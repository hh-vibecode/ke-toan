-- ════════════════════════════════════════════════════════════════════════════
-- PHIẾU ĐỀ NGHỊ THANH TOÁN CÔNG KHAI (14/10/2026)
-- Kế toán (chị Jaycie) muốn bỏ link Google Form đề nghị thanh toán bên ngoài → anh: "tách màn ra 1 phần phiếu vs 1 phần để đăng nhập,
-- phần phiếu đề nghị thanh toán đẩy dữ liệu về để duyệt chi, xử lý cẩn thận đảm bảo dữ liệu đầy đủ".
-- Cùng 1 link app: màn đầu có 2 phần — "Đề nghị thanh toán" (AI CŨNG ĐIỀN ĐƯỢC, không cần tài khoản) và "Đăng nhập".
-- Phiếu gửi → kt_chi trạng thái 'cho_duyet' (Chờ kế toán kiểm), nguon = 'phieu' → đi tiếp luồng 2 lượt sẵn có
-- (kế toán kiểm → giám đốc xác nhận → kế toán thanh toán). Chuông báo kế toán như đề nghị tạo trong app.
-- Trường giống form cũ (12 mục + hồ sơ đính kèm): người đề nghị, bộ phận, nội dung, ngày sử dụng, số tiền, người thụ hưởng,
-- ngân hàng, STK, đơn vị chịu chi phí, mong muốn TT trước, hoá đơn đỏ, ghi chú, hồ sơ (ảnh / PDF lên kho chứng từ riêng tư).
-- An toàn (trang không đăng nhập): mọi kiểm tra ở hàm SQL (không tin trình duyệt) · bảng vẫn khoá RLS, anon chỉ gọi 4 hàm dưới ·
-- chống gửi ồ ạt (10 phiếu / giờ / địa chỉ IP, 60 phiếu / giờ toàn hệ thống) · chống bấm gửi 2 lần (trùng người + số tiền + nội dung trong 30 phút) ·
-- ô bẫy máy tự điền · mã phiếu bí mật (băm sha256) cho người gửi: tải hồ sơ trong 3 giờ (tối đa 15 file) + xem trạng thái phiếu.
-- Monsieur Claude
-- ════════════════════════════════════════════════════════════════════════════

alter table public.kt_chi drop constraint if exists kt_chi_nguon_check;
alter table public.kt_chi add constraint kt_chi_nguon_check check (nguon = any (array['app', 'sheet_cu', 'kiot', 'phieu']));

create table if not exists public.kt_chi_phieu (
  chi_id   bigint primary key references public.kt_chi(id) on delete cascade,
  ma_hash  text not null unique,
  ip       text,
  so_file  int not null default 0,
  tao_luc  timestamptz not null default now()
);
create index if not exists kt_chi_phieu_ip on public.kt_chi_phieu (ip, tao_luc desc);
alter table public.kt_chi_phieu enable row level security;
revoke all on public.kt_chi_phieu from anon, authenticated;

-- IP người gửi (PostgREST chuyển header vào request.headers)
create or replace function public.kt_ip_goi() returns text
language sql stable as $$
  select coalesce(nullif(split_part(coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for', ''), ',', 1), ''),
                  current_setting('request.headers', true)::json->>'cf-connecting-ip', 'khong_ro');
$$;

-- Danh mục cho phiếu: bộ phận đề nghị + đơn vị chịu chi phí (chỉ id + tên đang dùng — không có số liệu)
create or replace function public.kt_dm_de_nghi() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'bo_phan', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ten', ten) order by thu_tu, ten), '[]') from kt_don_vi where hoat_dong and la_bo_phan),
    'don_vi', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ten', ten) order by thu_tu, ten), '[]') from kt_don_vi where hoat_dong and la_co_so));
$$;

-- Gửi phiếu. p_dong: {nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, hinh_thuc ('ck'|'tien_mat'), thu_huong_ten, thu_huong_nh,
--   thu_huong_stk, phan_bo:[{don_vi_id, so_tien}], han_tt, co_hd_do, ghi_chu, web (ô bẫy — phải trống)} → {id, ma}
create or replace function public.kt_gui_de_nghi(p_dong jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_ip text := kt_ip_goi(); v_nguoi text := btrim(regexp_replace(coalesce(p_dong->>'nguoi_de_nghi', ''), '\s+', ' ', 'g'));
  v_nd text := btrim(coalesce(p_dong->>'noi_dung', '')); v_tien numeric; v_sd date; v_han date; v_bp int; v_ck boolean;
  v_th text := btrim(coalesce(p_dong->>'thu_huong_ten', '')); v_nh text := btrim(coalesce(p_dong->>'thu_huong_nh', ''));
  v_stk text := regexp_replace(coalesce(p_dong->>'thu_huong_stk', ''), '[\s.\-]', '', 'g'); v_gc text := nullif(btrim(coalesce(p_dong->>'ghi_chu', '')), '');
  v_pb jsonb := coalesce(p_dong->'phan_bo', '[]'::jsonb); v_tong numeric; v_hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_id bigint; v_ma text; v_cu bigint; v_tom text;
begin
  if coalesce(p_dong->>'web', '') <> '' then raise exception 'Không gửi được phiếu'; end if;   -- ô bẫy máy tự điền
  -- chống gửi ồ ạt
  if (select count(*) from kt_chi_phieu where ip = v_ip and tao_luc > now() - interval '1 hour') >= 10 then
    raise exception 'Máy này đã gửi 10 phiếu trong 1 giờ — đợi một lúc rồi gửi tiếp, hoặc báo kế toán'; end if;
  if (select count(*) from kt_chi_phieu where tao_luc > now() - interval '1 hour') >= 60 then
    raise exception 'Hệ thống đang nhận quá nhiều phiếu — thử lại sau ít phút'; end if;
  -- kiểm từng ô
  if length(v_nguoi) < 2 or length(v_nguoi) > 80 then raise exception 'Nhập họ và tên người đề nghị'; end if;
  v_bp := nullif(p_dong->>'bo_phan_id', '')::int;
  if v_bp is null or not exists (select 1 from kt_don_vi where id = v_bp and hoat_dong and la_bo_phan) then raise exception 'Chọn bộ phận'; end if;
  if length(v_nd) < 5 then raise exception 'Nhập nội dung chi (hạng mục, lý do)'; end if;
  if length(v_nd) > 1000 then raise exception 'Nội dung chi tối đa 1.000 ký tự'; end if;
  begin v_tien := (p_dong->>'so_tien')::numeric; exception when others then v_tien := null; end;
  if v_tien is null or v_tien < 1000 or v_tien > 100000000000 or v_tien <> round(v_tien) then raise exception 'Số tiền không hợp lệ (từ 1.000 đ, số nguyên)'; end if;
  begin v_sd := (p_dong->>'ngay_su_dung')::date; exception when others then v_sd := null; end;
  if v_sd is null then raise exception 'Nhập ngày sử dụng dịch vụ / nhận hàng'; end if;
  if v_sd < v_hom - 400 or v_sd > v_hom + 365 then raise exception 'Ngày sử dụng dịch vụ không hợp lệ'; end if;
  begin v_han := nullif(p_dong->>'han_tt', '')::date; exception when others then raise exception 'Ngày mong muốn thanh toán không hợp lệ'; end;
  if v_han is not null and (v_han < v_hom - 1 or v_han > v_hom + 365) then raise exception 'Ngày mong muốn thanh toán phải từ hôm nay trở đi'; end if;
  if length(v_th) < 2 or length(v_th) > 150 then raise exception 'Nhập tên người / đơn vị thụ hưởng'; end if;
  v_ck := coalesce(p_dong->>'hinh_thuc', 'ck') <> 'tien_mat';
  if v_ck then
    if length(v_nh) < 2 or length(v_nh) > 100 then raise exception 'Nhập ngân hàng thụ hưởng'; end if;
    if v_stk !~ '^[0-9A-Za-z]{4,25}$' then raise exception 'Số tài khoản thụ hưởng không hợp lệ'; end if;
  else v_nh := 'Tiền mặt'; v_stk := null; end if;
  if p_dong->>'co_hd_do' is null or p_dong->>'co_hd_do' not in ('true', 'false') then raise exception 'Chọn có / không có hoá đơn đỏ'; end if;
  if length(coalesce(v_gc, '')) > 500 then raise exception 'Ghi chú tối đa 500 ký tự'; end if;
  -- đơn vị chịu chi phí: 1–6 đơn vị đang dùng, không trùng, tổng = số tiền
  if jsonb_typeof(v_pb) <> 'array' or jsonb_array_length(v_pb) = 0 then raise exception 'Chọn đơn vị chịu chi phí'; end if;
  if jsonb_array_length(v_pb) > 6 then raise exception 'Tối đa 6 đơn vị chịu chi phí'; end if;
  if exists (select 1 from jsonb_array_elements(v_pb) x where not exists (select 1 from kt_don_vi d where d.id = (x->>'don_vi_id')::int and d.hoat_dong and d.la_co_so)
             or (x->>'so_tien')::numeric <= 0 or (x->>'so_tien')::numeric <> round((x->>'so_tien')::numeric)) then
    raise exception 'Đơn vị chịu chi phí không hợp lệ'; end if;
  if (select count(distinct x->>'don_vi_id') from jsonb_array_elements(v_pb) x) <> jsonb_array_length(v_pb) then raise exception 'Đơn vị chịu chi phí bị chọn trùng'; end if;
  select sum((x->>'so_tien')::numeric) into v_tong from jsonb_array_elements(v_pb) x;
  if v_tong <> v_tien then raise exception 'Tổng tiền chia cho các đơn vị (%) phải bằng số tiền đề nghị (%)', v_tong, v_tien; end if;
  v_pb := (select jsonb_agg(jsonb_build_object('don_vi_id', (x->>'don_vi_id')::int, 'so_tien', (x->>'so_tien')::numeric)) from jsonb_array_elements(v_pb) x);
  -- bấm gửi 2 lần
  select c.id into v_cu from kt_chi c join kt_chi_phieu p on p.chi_id = c.id
   where not c.da_xoa and lower(c.nguoi_de_nghi) = lower(v_nguoi) and c.so_tien = v_tien and lower(c.noi_dung) = lower(v_nd) and p.tao_luc > now() - interval '30 minutes' limit 1;
  if v_cu is not null then raise exception 'Phiếu này vừa được gửi (mã #%) — không gửi lại', v_cu; end if;

  insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, thu_huong_nh, thu_huong_stk,
    phan_bo, han_tt, co_hd_do, ghi_chu, trang_thai, nguon, tao_boi)
  values (v_hom, v_nguoi, v_bp, v_nd, v_sd, v_tien, v_th, v_nh, nullif(v_stk, ''), v_pb, v_han, (p_dong->>'co_hd_do')::boolean, v_gc,
    'cho_duyet', 'phieu', 'Phiếu đề nghị')
  returning id into v_id;
  v_ma := encode(gen_random_bytes(18), 'hex');
  insert into kt_chi_phieu (chi_id, ma_hash, ip) values (v_id, encode(digest(v_ma, 'sha256'), 'hex'), v_ip);
  perform kt_ghi_nhat_ky('Phiếu đề nghị: ' || v_nguoi, 'kt_chi', v_id, 'them', (p_dong - 'web') || jsonb_build_object('nguon', 'phieu'));
  v_tom := left(v_nd, 120) || ' · ' || replace(to_char(v_tien, 'FM999G999G999G999'), ',', '.') || ' đ';
  perform kt_bao(kt_ai_ke_toan(null), v_nguoi, 'chi_moi', 'Phiếu đề nghị thanh toán mới — chờ kế toán kiểm', v_tom, 'chi', v_id);
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

-- mã phiếu → id (còn hiệu lực tải hồ sơ: 3 giờ, tối đa 15 file, phiếu chưa xoá)
create or replace function public.kt_phieu_theo_ma(p_ma text, p_tai_len boolean) returns kt_chi_phieu
language plpgsql stable security definer set search_path = public, extensions as $$
declare p kt_chi_phieu;
begin
  select * into p from kt_chi_phieu where ma_hash = encode(digest(coalesce(p_ma, ''), 'sha256'), 'hex');
  if p.chi_id is null or exists (select 1 from kt_chi where id = p.chi_id and da_xoa) then raise exception 'Mã phiếu không đúng'; end if;
  if p_tai_len and p.tao_luc < now() - interval '3 hours' then raise exception 'Đã quá 3 giờ sau khi gửi — gửi hồ sơ bổ sung cho kế toán'; end if;
  if p_tai_len and p.so_file >= 15 then raise exception 'Mỗi phiếu tối đa 15 file hồ sơ'; end if;
  return p;
end $$;
-- Edge Function kt-chung-tu gọi trước khi ký link tải lên (chỉ service_role)
create or replace function public.kt_quyen_ct_phieu(p_ma text) returns bigint
language sql stable security definer set search_path = public as $$ select (kt_phieu_theo_ma(p_ma, true)).chi_id; $$;

-- Ghi hồ sơ đã tải lên vào phiếu
create or replace function public.kt_them_ct_phieu(p_ma text, p_duong_dan text, p_ten text, p_mime text, p_kich_thuoc bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare p kt_chi_phieu := kt_phieu_theo_ma(p_ma, true); v_id bigint; v_ten text;
begin
  if p_duong_dan !~ ('^chi/' || p.chi_id || '/[0-9]+_[A-Za-z0-9._-]+$') then raise exception 'Đường dẫn hồ sơ không hợp lệ'; end if;
  if coalesce(p_mime, '') !~ '^(image/(jpeg|png|webp|heic|heif)|application/pdf)$' then raise exception 'Chỉ nhận ảnh hoặc PDF'; end if;
  if coalesce(p_kich_thuoc, 0) <= 0 or p_kich_thuoc > 15 * 1024 * 1024 then raise exception 'File tối đa 15 MB'; end if;
  if exists (select 1 from kt_chung_tu where duong_dan = p_duong_dan) then raise exception 'Hồ sơ này đã ghi'; end if;
  select nguoi_de_nghi into v_ten from kt_chi where id = p.chi_id;
  insert into kt_chung_tu (bang, dong_id, duong_dan, ten_file, mime, kich_thuoc, tao_boi)
  values ('chi', p.chi_id, p_duong_dan, left(coalesce(p_ten, 'tep'), 200), p_mime, p_kich_thuoc, 'Phiếu đề nghị: ' || v_ten) returning id into v_id;
  update kt_chi_phieu set so_file = so_file + 1 where chi_id = p.chi_id;
  return v_id;
end $$;

-- Người gửi xem lại phiếu của mình bằng mã (link theo dõi) — chỉ những gì họ đã nhập + trạng thái
create or replace function public.kt_xem_de_nghi(p_ma text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p kt_chi_phieu := kt_phieu_theo_ma(p_ma, false); c kt_chi;
begin
  select * into c from kt_chi where id = p.chi_id;
  return jsonb_build_object('id', c.id, 'ngay_de_nghi', c.ngay_de_nghi, 'nguoi_de_nghi', c.nguoi_de_nghi,
    'bo_phan', (select ten from kt_don_vi where id = c.bo_phan_id), 'noi_dung', c.noi_dung, 'so_tien', c.so_tien,
    'thu_huong_ten', c.thu_huong_ten, 'trang_thai', c.trang_thai, 'ngay_tt', c.ngay_tt,
    'so_file', (select count(*) from kt_chung_tu where bang = 'chi' and dong_id = c.id and not da_xoa),
    'con_tai_len', p.tao_luc > now() - interval '3 hours' and p.so_file < 15);
end $$;

revoke execute on function public.kt_ip_goi(), public.kt_phieu_theo_ma(text, boolean), public.kt_quyen_ct_phieu(text) from public, anon, authenticated;
grant execute on function public.kt_quyen_ct_phieu(text) to service_role;
revoke execute on function public.kt_dm_de_nghi(), public.kt_gui_de_nghi(jsonb), public.kt_them_ct_phieu(text, text, text, text, bigint), public.kt_xem_de_nghi(text) from public;
grant execute on function public.kt_dm_de_nghi(), public.kt_gui_de_nghi(jsonb), public.kt_them_ct_phieu(text, text, text, text, bigint), public.kt_xem_de_nghi(text) to anon, authenticated;
