-- ĐỀ XUẤT MUA HÀNG / ĐƠN KHÁCH ĐẶT RIÊNG — FORM CÔNG KHAI (12/11/2026). Kế toán (anh chuyển): "Đề xuất mua hàng và đơn khách đặt riêng do Sale nhập:
-- làm form công khai giống đề nghị thanh toán". Cùng cách form đề nghị: không cần tài khoản, gửi xong nhận MÃ BÍ MẬT (lưu băm sha256) để tải ảnh mẫu
-- (3 giờ, tối đa 30 file, kho chứng từ bang 'de_xuat') và xem trạng thái (#dx=<mã>). Chặn gửi ồ ạt: 10 lần / giờ / IP, 60 lần / giờ toàn hệ thống.
-- Kế toán / người mua hàng (quyền trang 'ncc') xem ở Đơn đặt hàng (PO) → tab Đề xuất mua hàng: tồn Kiot từng cơ sở, duyệt / từ chối, tạo PO từ đề xuất. — Monsieur Claude
create table if not exists public.kt_de_xuat_mua (
  id bigserial primary key, loai text not null check (loai in ('bo_sung', 'khach_dat')),
  nguoi text not null, bo_phan_id int references kt_don_vi(id), ngay_can date, uu_tien text not null default 'thuong' check (uu_tien in ('thuong', 'gap')),
  dong jsonb not null default '[]',      -- [{ma, ten, quy_cach, sl, ghi_chu}]
  khach jsonb,                            -- {ten, sdt, ma_don, coc, hen_giao}
  ghi_chu text, trang_thai text not null default 'cho_duyet' check (trang_thai in ('cho_duyet', 'da_duyet', 'da_dat', 'tu_choi')),
  ly_do text, xu_ly_boi text, xu_ly_luc timestamptz, po_id bigint references kt_po(id),
  ma_hash text unique, so_file int not null default 0, ip text, tao_luc timestamptz not null default now(), da_xoa boolean not null default false);
alter table public.kt_de_xuat_mua enable row level security;
revoke all on public.kt_de_xuat_mua from anon, authenticated;

create or replace function public.kt_dx_theo_ma(p_ma text, p_tai_len boolean) returns kt_de_xuat_mua
language plpgsql stable security definer set search_path = public, extensions as $$
declare d kt_de_xuat_mua;
begin
  select * into d from kt_de_xuat_mua where ma_hash = encode(digest(coalesce(p_ma, ''), 'sha256'), 'hex') and not da_xoa;
  if d.id is null then raise exception 'Mã đề xuất không đúng'; end if;
  if p_tai_len and d.tao_luc < now() - interval '3 hours' then raise exception 'Đã quá 3 giờ sau khi gửi — gửi ảnh bổ sung cho người mua hàng'; end if;
  if p_tai_len and d.so_file >= 30 then raise exception 'Mỗi đề xuất tối đa 30 ảnh / file'; end if;
  return d;
end $$;

create or replace function public.kt_gui_de_xuat(p_dong jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_ip text := kt_ip_goi(); v_nguoi text := btrim(regexp_replace(coalesce(p_dong->>'nguoi', ''), '\s+', ' ', 'g'));
  v_dong jsonb; v_id bigint; v_ma text; v_loai text := coalesce(p_dong->>'loai', 'bo_sung'); nhan int[];
begin
  if (select count(*) from kt_de_xuat_mua where ip = v_ip and tao_luc > now() - interval '1 hour') >= 10 then raise exception 'Gửi quá nhiều trong 1 giờ — thử lại sau'; end if;
  if (select count(*) from kt_de_xuat_mua where tao_luc > now() - interval '1 hour') >= 60 then raise exception 'Hệ thống đang nhận quá nhiều đề xuất — thử lại sau'; end if;
  if length(v_nguoi) < 2 then raise exception 'Nhập họ tên người đề xuất'; end if;
  if v_loai not in ('bo_sung', 'khach_dat') then raise exception 'Loại đề xuất không hợp lệ'; end if;
  if not exists (select 1 from kt_don_vi where id = nullif(p_dong->>'bo_phan_id', '')::int and hoat_dong) then raise exception 'Chọn cơ sở / bộ phận'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('ma', left(btrim(coalesce(e->>'ma', '')), 40), 'ten', left(btrim(coalesce(e->>'ten', '')), 200),
           'quy_cach', left(btrim(coalesce(e->>'quy_cach', '')), 200), 'sl', greatest(0, coalesce(nullif(e->>'sl', '')::numeric, 0)), 'ghi_chu', left(btrim(coalesce(e->>'ghi_chu', '')), 300))), '[]')
    into v_dong from jsonb_array_elements(case when jsonb_typeof(p_dong->'dong') = 'array' then p_dong->'dong' else '[]' end) e
   where btrim(coalesce(e->>'ma', '') || coalesce(e->>'ten', '')) <> '';
  if jsonb_array_length(v_dong) = 0 then raise exception 'Nhập ít nhất 1 mặt hàng'; end if;
  if jsonb_array_length(v_dong) > 50 then raise exception 'Tối đa 50 mặt hàng / đề xuất'; end if;
  if exists (select 1 from jsonb_array_elements(v_dong) e where (e->>'sl')::numeric <= 0) then raise exception 'Nhập số lượng cho từng mặt hàng'; end if;
  if v_loai = 'khach_dat' and coalesce(btrim(p_dong->'khach'->>'ten'), '') = '' then raise exception 'Nhập tên khách đặt'; end if;
  insert into kt_de_xuat_mua (loai, nguoi, bo_phan_id, ngay_can, uu_tien, dong, khach, ghi_chu, ip)
  values (v_loai, left(v_nguoi, 100), (p_dong->>'bo_phan_id')::int, nullif(p_dong->>'ngay_can', '')::date, case when p_dong->>'uu_tien' = 'gap' then 'gap' else 'thuong' end,
    v_dong, case when v_loai = 'khach_dat' then jsonb_build_object('ten', left(btrim(p_dong->'khach'->>'ten'), 120), 'sdt', left(btrim(coalesce(p_dong->'khach'->>'sdt', '')), 30),
      'ma_don', left(btrim(coalesce(p_dong->'khach'->>'ma_don', '')), 40), 'coc', nullif(p_dong->'khach'->>'coc', '')::numeric, 'hen_giao', nullif(p_dong->'khach'->>'hen_giao', '')) end,
    left(nullif(btrim(p_dong->>'ghi_chu'), ''), 1000), v_ip) returning id into v_id;
  v_ma := encode(gen_random_bytes(18), 'hex');
  update kt_de_xuat_mua set ma_hash = encode(digest(v_ma, 'sha256'), 'hex') where id = v_id;
  select array_agg(id) into nhan from kt_nguoi_dung where hoat_dong and (vi_tri in ('supreme', 'admin') or 'ncc:ghi' = any(quyen));
  perform kt_bao(nhan, v_nguoi, 'de_xuat_mua', case when v_loai = 'khach_dat' then 'Đơn khách đặt riêng mới' else 'Đề xuất mua hàng mới' end,
    'DX' || lpad(v_id::text, 5, '0') || ' · ' || v_nguoi || ' · ' || jsonb_array_length(v_dong) || ' mặt hàng' || case when p_dong->>'uu_tien' = 'gap' then ' · GẤP' else '' end, 'de_xuat', v_id);
  perform kt_ghi_nhat_ky(v_nguoi, 'kt_de_xuat_mua', v_id, 'them', jsonb_build_object('loai', v_loai, 'so_dong', jsonb_array_length(v_dong)));
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

create or replace function public.kt_quyen_ct_dx(p_ma text) returns bigint
language sql stable security definer set search_path = public as $$ select (kt_dx_theo_ma(p_ma, true)).id; $$;

create or replace function public.kt_them_ct_dx(p_ma text, p_duong_dan text, p_ten text, p_mime text, p_kich_thuoc bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare d kt_de_xuat_mua := kt_dx_theo_ma(p_ma, true); v_id bigint;
begin
  if p_duong_dan !~ ('^de_xuat/' || d.id || '/[0-9]+_[A-Za-z0-9._-]+$') then raise exception 'Đường dẫn ảnh không hợp lệ'; end if;
  if coalesce(p_mime, '') !~ '^(image/(jpeg|png|webp|heic|heif)|application/pdf)$' then raise exception 'Chỉ nhận ảnh hoặc PDF'; end if;
  if coalesce(p_kich_thuoc, 0) <= 0 or p_kich_thuoc > 15 * 1024 * 1024 then raise exception 'File tối đa 15 MB'; end if;
  if exists (select 1 from kt_chung_tu where duong_dan = p_duong_dan) then raise exception 'Ảnh này đã ghi'; end if;
  insert into kt_chung_tu (bang, dong_id, duong_dan, ten_file, mime, kich_thuoc, tao_boi)
  values ('de_xuat', d.id, p_duong_dan, left(coalesce(p_ten, 'anh'), 200), p_mime, p_kich_thuoc, 'Đề xuất mua hàng: ' || d.nguoi) returning id into v_id;
  update kt_de_xuat_mua set so_file = so_file + 1 where id = d.id;
  return v_id;
end $$;

-- người gửi xem trạng thái (không lộ đề xuất người khác)
create or replace function public.kt_xem_de_xuat(p_ma text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d kt_de_xuat_mua := kt_dx_theo_ma(p_ma, false);
begin
  return jsonb_build_object('id', d.id, 'loai', d.loai, 'nguoi', d.nguoi, 'tao_luc', d.tao_luc, 'ngay_can', d.ngay_can, 'uu_tien', d.uu_tien, 'dong', d.dong, 'khach', d.khach,
    'trang_thai', d.trang_thai, 'ly_do', d.ly_do, 'xu_ly_luc', d.xu_ly_luc, 'so_file', d.so_file, 'tai_them', d.tao_luc > now() - interval '3 hours',
    'po', (select so from kt_po where id = d.po_id));
end $$;

-- người mua hàng: danh sách + tồn Kiot từng cơ sở của từng mã + ảnh
create or replace function public.kt_dx_ds(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'loai', d.loai, 'nguoi', d.nguoi, 'bo_phan', (select ten from kt_don_vi where id = d.bo_phan_id), 'ngay_can', d.ngay_can,
      'uu_tien', d.uu_tien, 'khach', d.khach, 'ghi_chu', d.ghi_chu, 'trang_thai', d.trang_thai, 'ly_do', d.ly_do, 'xu_ly_boi', d.xu_ly_boi, 'xu_ly_luc', d.xu_ly_luc, 'tao_luc', d.tao_luc,
      'po_id', d.po_id, 'po', (select so from kt_po where id = d.po_id),
      'anh', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ten', c.ten_file, 'mime', c.mime) order by c.id), '[]') from kt_chung_tu c where c.bang = 'de_xuat' and c.dong_id = d.id and not c.da_xoa),
      'dong', (select coalesce(jsonb_agg(e || jsonb_build_object('ton', (select h.ton from kt_kiot_hang h where h.ma = e->>'ma' limit 1), 'ten_kiot', (select h.ten from kt_kiot_hang h where h.ma = e->>'ma' limit 1))), '[]')
               from jsonb_array_elements(d.dong) e)) order by (d.trang_thai = 'cho_duyet') desc, (d.uu_tien = 'gap') desc, d.id desc)
    from kt_de_xuat_mua d where not d.da_xoa and (d.trang_thai = 'cho_duyet' or d.tao_luc > now() - interval '120 days')), '[]');
end $$;

create or replace function public.kt_dx_xu_ly(p_phien text, p_id bigint, p_tt text, p_ly_do text, p_po bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if p_tt not in ('cho_duyet', 'da_duyet', 'da_dat', 'tu_choi') then raise exception 'Trạng thái không hợp lệ'; end if;
  if p_tt = 'tu_choi' and coalesce(btrim(p_ly_do), '') = '' then raise exception 'Ghi lý do từ chối'; end if;
  update kt_de_xuat_mua set trang_thai = p_tt, ly_do = nullif(btrim(p_ly_do), ''), po_id = coalesce(p_po, case when p_tt = 'da_dat' then po_id end),
    xu_ly_boi = coalesce(u.ho_ten, u.ten_dang_nhap), xu_ly_luc = now() where id = p_id and not da_xoa;
  if not found then raise exception 'Không tìm thấy đề xuất'; end if;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_de_xuat_mua', p_id, p_tt, jsonb_build_object('ly_do', p_ly_do, 'po', p_po));
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_gui_de_xuat(jsonb)', 'kt_them_ct_dx(text, text, text, text, bigint)', 'kt_xem_de_xuat(text)', 'kt_dx_ds(text)', 'kt_dx_xu_ly(text, bigint, text, text, bigint)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
  execute 'revoke all on function public.kt_quyen_ct_dx(text) from public, anon, authenticated';   -- chỉ Edge kt-chung-tu (service_role) gọi
  execute 'revoke all on function public.kt_dx_theo_ma(text, boolean) from public, anon, authenticated';
end $$;
