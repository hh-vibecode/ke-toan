-- GÓP Ý KẾ TOÁN 16/10/2026 (18:03, ảnh anh gửi) — Monsieur Claude
--  1. KQKD lấy NHẦM toàn bộ phiếu chi trả trong tháng làm chi phí tháng → tách:
--       · CHI PHÍ HẠCH TOÁN (báo cáo hiệu quả kinh doanh): theo KỲ HẠCH TOÁN của phiếu = tháng phân bổ (phan_bo_thang) nếu có,
--         nếu không = tháng kế toán ghi tay (kt_chi.thang_ht), nếu không = tháng NGÀY SỬ DỤNG DỊCH VỤ (thiếu thì ngày đề nghị).
--         Tính phiếu đã được xác nhận (chờ chi + đã chi), KHÔNG tính phiếu tạm ứng (tạm ứng chưa phải chi phí).
--       · DÒNG TIỀN (báo cáo dòng tiền / sổ quỹ): giữ nguyên theo ngày thanh toán, tiền thật ra khỏi tài khoản.
--     View kt_v_chi_ht + hàm kt_chi_phi_ht (Tổng quan) · kt_bc_pl2 / kt_bc_qt / kt_drill đổi sang kỳ hạch toán.
--  2. Công nợ phải thu: tách NỢ THẬT / COD CHƯA THU HỒI (hoá đơn dùng COD) / KHÁCH CHƯA LẤY HÀNG (ghi chú hoá đơn) —
--     kế toán sửa tay từng hoá đơn được (kt_no_phan_loai).
--  3. Phiếu đề nghị thanh toán: hoá đơn xuất về Công ty / HKD Hiền Thủy / HKD Chánh Tâm (kt_chi.hd_ve) ·
--     đề nghị TẠM ỨNG (kt_chi.la_tam_ung) → tự đẩy sang Tạm ứng & hoàn ứng (trigger), bị từ chối / xoá thì tự gỡ.
--  6. "Đã cọc · chưa đi hàng" cả năm nhiều bất thường. Luật cũ: đơn đặt chưa hoàn thành + (đơn có tiền trả HOẶC khách đang có
--     tiền trả trước trên Kiot) → (a) khách có 1 khoản trả trước thì MỌI đơn mở của khách đều thành "đã cọc" (đếm trùng),
--     (b) đơn đã xuất hoá đơn nhưng đơn không chuyển Hoàn thành vẫn bị tính. Luật mới (view kt_v_don_coc):
--       · tiền trả trước của khách chỉ chia 1 lần cho các đơn mở cũ nhất (FIFO), không nhân lên mọi đơn;
--       · đơn đã có hoá đơn gắn đơn (dat_hang_id / mã đặt hàng) → 'da_hd' = đã đi hàng, loại ra;
--       · khách có hoá đơn KHÔNG gắn đơn sau ngày đặt, giá trị ≥ 50% đơn → 'nghi_di' (nghi đã đi hàng), loại ra, liệt kê riêng để soát;
--       · còn lại: 'cho' (đang chờ) / 'treo' (đặt > 90 ngày — vẫn tính, gắn nhãn để sales kiểm huỷ).
--  5. Tài khoản ngừng dùng: dùng cờ kt_tai_khoan.hoat_dong (đã có) — giao diện ẩn khỏi số dư / lựa chọn, lịch sử phiếu giữ nguyên.
--     Danh sách gợi ý (CHỈ ĐỌC, chạy xem trước khi tắt):
--       select t.id, t.ten, t.ton_dau, t.ngay_ton_dau, max(b.ngay) phat_sinh_cuoi from kt_tai_khoan t
--         left join kt_v_bien_dong b on b.tai_khoan_id = t.id where t.hoat_dong group by 1 order by 5 nulls first;

alter table public.kt_chi add column if not exists thang_ht text,
  add column if not exists hd_ve text, add column if not exists la_tam_ung boolean not null default false;
alter table public.kt_chi drop constraint if exists kt_chi_thang_ht_check;
alter table public.kt_chi add constraint kt_chi_thang_ht_check check (thang_ht is null or thang_ht ~ '^20[0-9]{2}-(0[1-9]|1[0-2])$');
alter table public.kt_chi drop constraint if exists kt_chi_hd_ve_check;
alter table public.kt_chi add constraint kt_chi_hd_ve_check check (hd_ve is null or hd_ve in ('cong_ty', 'hkd_ht', 'hkd_ct'));

-- ── 1. CHI PHÍ HẠCH TOÁN: mỗi phiếu tách theo (tháng hạch toán × đơn vị chịu chi phí)
create or replace view public.kt_v_chi_ht as
  select c.id chi_id, c.loai_id,
         coalesce(pt->>'thang', c.thang_ht, to_char(coalesce(c.ngay_su_dung, c.ngay_de_nghi, c.ngay_tt), 'YYYY-MM')) thang,
         (pb->>'don_vi_id')::int don_vi_id,
         coalesce((pt->>'so_tien')::numeric, c.so_tien) * coalesce((pb->>'so_tien')::numeric / nullif(c.so_tien, 0), 1) tien
    from kt_chi c
    left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' and jsonb_array_length(c.phan_bo_thang) > 0 then c.phan_bo_thang end) pt on true
    left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' and jsonb_array_length(c.phan_bo) > 0 then c.phan_bo end) pb on true
   where not c.da_xoa and c.trang_thai in ('cho_tt', 'da_tt') and not c.la_tam_ung;
revoke all on public.kt_v_chi_ht from anon, authenticated;

-- Tổng quan: chi phí theo kỳ hạch toán, cùng dạng chi_theo_dv / chi_theo_loai của kt_bao_cao (chi phí chung chia theo tỉ lệ thu như cũ)
create or replace function public.kt_chi_phi_ht(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb; v_t0 text := to_char(p_tu, 'YYYY-MM'); v_t1 text := to_char(p_den, 'YYYY-MM');
begin
  perform kt_chan(p_phien, 'tong_quan');
  with
  ht as (select h.*, l.ten loai_ten, l.nhom_bc, l.cach_chia from kt_v_chi_ht h join kt_loai l on l.id = h.loai_id where h.thang between v_t0 and v_t1),
  thu_dv as (select don_vi_id, sum(so_tien) thu from kt_thu where not da_xoa and trang_thai = 'da_duyet' and ngay between p_tu and p_den and don_vi_id is not null group by 1),
  tong_thu as (select nullif(sum(thu), 0) tong from thu_dv),
  chi_dv as (
    select h.don_vi_id, h.loai_ten, h.tien so_tien from ht h where h.cach_chia = 'rieng'
    union all
    select d.don_vi_id, h.loai_ten, round(h.tien * d.thu / tt.tong) from ht h cross join thu_dv d cross join tong_thu tt where h.cach_chia = 'ty_le_thu' and tt.tong is not null
    union all
    select null, h.loai_ten, h.tien from ht h, tong_thu tt where h.cach_chia = 'ty_le_thu' and tt.tong is null)
  select jsonb_build_object('chi_theo', 'hach_toan',
    'chi_theo_dv', (select coalesce(jsonb_agg(jsonb_build_object('don_vi_id', don_vi_id, 'loai', loai_ten, 'so_tien', s)), '[]')
                     from (select don_vi_id, loai_ten, round(sum(so_tien)) s from chi_dv group by 1, 2) x),
    'chi_theo_loai', (select coalesce(jsonb_agg(jsonb_build_object('loai', loai_ten, 'nhom_bc', nhom_bc, 'cach_chia', cach_chia, 'so_tien', s, 'so_phieu', n) order by s desc), '[]')
                       from (select loai_ten, nhom_bc, cach_chia, round(sum(tien)) s, count(distinct chi_id) n from ht group by 1, 2, 3) x),
    -- phiếu đã xác nhận nhưng chưa gán loại chi → chưa vào được chi phí (kế toán cần gán)
    'chua_loai', (select jsonb_build_object('so', count(*), 'tien', coalesce(sum(c.so_tien), 0)) from kt_chi c
                   where not c.da_xoa and c.trang_thai in ('cho_tt', 'da_tt') and not c.la_tam_ung and c.loai_id is null
                     and coalesce(c.thang_ht, to_char(coalesce(c.ngay_su_dung, c.ngay_de_nghi), 'YYYY-MM')) between v_t0 and v_t1)) into r;
  return r;
end $$;
revoke execute on function public.kt_chi_phi_ht(text, date, date) from public;
grant execute on function public.kt_chi_phi_ht(text, date, date) to anon, authenticated;

-- ── 6. ĐƠN ĐÃ CỌC · CHƯA ĐI HÀNG (luật mới)
create index if not exists kt_kiot_hoa_don_dat_hang_idx on public.kt_kiot_hoa_don (dat_hang_id) where dat_hang_id is not null;
create index if not exists kt_kiot_hoa_don_ma_dh_idx on public.kt_kiot_hoa_don (ma_dat_hang) where ma_dat_hang is not null;
create index if not exists kt_kiot_hoa_don_khach_idx on public.kt_kiot_hoa_don (khach_id, ngay);
create or replace view public.kt_v_don_coc as
  with o as (
    select o.id, o.ma, o.ngay, o.khach_id, o.tong, coalesce(o.da_tra, 0) da_tra, (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date nd,
           case when coalesce(k.cong_no, 0) < 0 then -k.cong_no else 0 end tra_truoc
      from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id
     where o.trang_thai not in (3, 4) and coalesce(o.tong, 0) > 0),
  -- hoá đơn gắn đơn (đơn đã đi hàng nhưng Kiot chưa chuyển đơn sang Hoàn thành)
  hd as (select o.id, min((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date) ngay_hd, min(h.ma) hd_ma from o
           join kt_kiot_hoa_don h on h.trang_thai in (1, 3) and (h.dat_hang_id = o.id or (coalesce(h.ma_dat_hang, '') <> '' and h.ma_dat_hang = o.ma)) group by 1),
  -- khách có hoá đơn KHÔNG gắn đơn đặt từ ngày đặt trở đi, giá trị ≥ 50% đơn → nghi đã đi hàng bằng hoá đơn bán thẳng
  nghi as (select o.id, min((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date) ngay_hd, min(h.ma) hd_ma from o
           join kt_kiot_hoa_don h on h.khach_id = o.khach_id and h.ngay >= o.ngay and h.trang_thai in (1, 3)
            and h.dat_hang_id is null and coalesce(h.ma_dat_hang, '') = '' and h.tong >= o.tong * 0.5
          where o.id not in (select id from hd) group by 1),
  -- tiền trả trước của khách chia 1 LẦN cho các đơn còn chờ cũ nhất (FIFO)
  cho as (select o.*, o.tong - least(o.tong, o.da_tra) con,
                 sum(o.tong - least(o.tong, o.da_tra)) over (partition by o.khach_id order by o.ngay, o.id) cum
            from o where o.id not in (select id from hd) and o.id not in (select id from nghi)),
  coc as (select c.id, least(c.tong, c.da_tra) coc_don,
                 case when c.khach_id is null then 0 else greatest(0, least(c.con, c.tra_truoc - (c.cum - c.con))) end coc_tt from cho c)
  select o.id, o.nd ngay,
         case when hd.id is not null then 'da_hd' when nghi.id is not null then 'nghi_di'
              when o.nd < (now() at time zone 'Asia/Ho_Chi_Minh')::date - 90 then 'treo' else 'cho' end tinh_trang,
         coalesce(c.coc_don + c.coc_tt, least(o.tong, o.da_tra)) coc, coalesce(c.coc_tt, 0) coc_tt,
         coalesce(hd.ngay_hd, nghi.ngay_hd) ngay_hd, coalesce(hd.hd_ma, nghi.hd_ma) hd_ma
    from o left join hd on hd.id = o.id left join nghi on nghi.id = o.id left join coc c on c.id = o.id
   where (hd.id is not null or nghi.id is not null) and (o.da_tra > 0 or o.tra_truoc > 0)   -- trước đây bị tính cọc
      or (c.coc_don + c.coc_tt) > 0;
revoke all on public.kt_v_don_coc from anon, authenticated;

-- ── 2. CÔNG NỢ: loại nợ của 1 hoá đơn
create table if not exists public.kt_no_phan_loai (
  hoa_don_id bigint primary key, loai text not null check (loai in ('that', 'cod', 'chua_lay')), ghi_chu text,
  sua_boi text, sua_luc timestamptz not null default now());
alter table public.kt_no_phan_loai enable row level security;
revoke all on public.kt_no_phan_loai from anon, authenticated;
-- kế toán sửa tay > ô COD trên hoá đơn Kiot > ghi chú hoá đơn có "chưa lấy / gửi lại / giữ hàng…" > nợ thật
create or replace function public.kt_loai_no(p_hd bigint, p_cod boolean, p_ghi_chu text) returns text
language sql stable set search_path = public as $$
  select coalesce((select loai from kt_no_phan_loai where hoa_don_id = p_hd),
    case when coalesce(p_cod, false) then 'cod'
         when p_ghi_chu ~* '(chưa|chua)\s*(lấy|lay|nhận|nhan|giao|lây)|gửi lại|gui lai|giữ hàng|giu hang|để lại|de lai|hẹn lấy|hen lay|chưa đi hàng|chua di hang' then 'chua_lay'
         else 'that' end);
$$;
create or replace function public.kt_luu_loai_no(p_phien text, p_hd bigint, p_loai text) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'khach_hang', true);
  if not exists (select 1 from kt_kiot_hoa_don where id = p_hd) then raise exception 'Không tìm thấy hoá đơn'; end if;
  if coalesce(p_loai, '') = '' then delete from kt_no_phan_loai where hoa_don_id = p_hd;
  elsif p_loai not in ('that', 'cod', 'chua_lay') then raise exception 'Loại nợ không hợp lệ';
  else insert into kt_no_phan_loai (hoa_don_id, loai, sua_boi) values (p_hd, p_loai, u.ho_ten)
       on conflict (hoa_don_id) do update set loai = excluded.loai, sua_boi = excluded.sua_boi, sua_luc = now(); end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_no_phan_loai', p_hd, 'sua', jsonb_build_object('loai', p_loai));
end $$;
revoke execute on function public.kt_luu_loai_no(text, bigint, text) from public;
grant execute on function public.kt_luu_loai_no(text, bigint, text) to anon, authenticated;

-- ── 3 + 1. Bổ sung trên phiếu chi: hoá đơn về đâu · tạm ứng · tháng hạch toán (gọi sau kt_luu_chi; cùng quyền sửa phiếu)
create or replace function public.kt_chi_bo_sung(p_phien text, p_id bigint, p_dong jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_cu kt_chi;
begin
  u := kt_chan_dong(p_phien, 'chi', array[p_id], true);
  select * into v_cu from kt_chi where id = p_id and not da_xoa;
  if v_cu.id is null then raise exception 'Không tìm thấy phiếu chi %', p_id; end if;
  if p_dong ? 'thang_ht' and nullif(p_dong->>'thang_ht', '') !~ '^20[0-9]{2}-(0[1-9]|1[0-2])$' then raise exception 'Tháng hạch toán phải dạng YYYY-MM'; end if;
  if p_dong ? 'hd_ve' and nullif(p_dong->>'hd_ve', '') not in ('cong_ty', 'hkd_ht', 'hkd_ct') then raise exception 'Hoá đơn về: chọn Công ty / HKD Hiền Thủy / HKD Chánh Tâm'; end if;
  update kt_chi set
    thang_ht   = case when p_dong ? 'thang_ht' then nullif(p_dong->>'thang_ht', '') else thang_ht end,
    hd_ve      = case when p_dong ? 'hd_ve' then nullif(p_dong->>'hd_ve', '') else hd_ve end,
    la_tam_ung = case when p_dong ? 'la_tam_ung' then coalesce((p_dong->>'la_tam_ung')::boolean, false) else la_tam_ung end
   where id = p_id;
  if (p_dong ? 'thang_ht' and nullif(p_dong->>'thang_ht', '') is distinct from v_cu.thang_ht)
     or (p_dong ? 'hd_ve' and nullif(p_dong->>'hd_ve', '') is distinct from v_cu.hd_ve)
     or (p_dong ? 'la_tam_ung' and coalesce((p_dong->>'la_tam_ung')::boolean, false) is distinct from v_cu.la_tam_ung) then
    perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'sua', p_dong);
  end if;
end $$;
revoke execute on function public.kt_chi_bo_sung(text, bigint, jsonb) from public;
grant execute on function public.kt_chi_bo_sung(text, bigint, jsonb) to anon, authenticated;

-- Đề nghị tạm ứng → tự có dòng trong Tạm ứng & hoàn ứng (ngày = ngày chi, chưa chi thì ngày đề nghị); từ chối / xoá / bỏ tick → gỡ nếu chưa hoàn
create or replace function public.kt_chi_tam_ung_tg() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_tu bigint;
begin
  select id into v_tu from kt_tam_ung where chi_id = new.id and not da_xoa;
  if new.la_tam_ung and not new.da_xoa and new.trang_thai not in ('tu_choi', 'tu_choi_tt') then
    if v_tu is null then
      insert into kt_tam_ung (ngay, nguoi_nhan, bo_phan_id, so_tien, ly_do, chi_id, ghi_chu, tao_boi)
      values (coalesce(new.ngay_tt, new.ngay_de_nghi), coalesce(nullif(btrim(new.thu_huong_ten), ''), new.nguoi_de_nghi), new.bo_phan_id, new.so_tien,
              left(new.noi_dung, 500), new.id, 'Tự tạo từ phiếu đề nghị tạm ứng', 'Hệ thống');
    else
      update kt_tam_ung set ngay = coalesce(new.ngay_tt, new.ngay_de_nghi),
             so_tien = greatest(new.so_tien, coalesce((select sum(so_tien) from kt_tam_ung_hoan where tam_ung_id = v_tu and not da_xoa), 0))
       where id = v_tu and tao_boi = 'Hệ thống';
    end if;
  elsif v_tu is not null and not exists (select 1 from kt_tam_ung_hoan where tam_ung_id = v_tu and not da_xoa) then
    update kt_tam_ung set da_xoa = true, sua_boi = 'Hệ thống', sua_luc = now() where id = v_tu and tao_boi = 'Hệ thống';
  end if;
  return null;
end $$;
drop trigger if exists kt_chi_tam_ung on public.kt_chi;
create trigger kt_chi_tam_ung after insert or update of la_tam_ung, trang_thai, da_xoa, so_tien, ngay_tt on public.kt_chi
  for each row execute function public.kt_chi_tam_ung_tg();

-- Phiếu đề nghị công khai (#de-nghi): thêm hd_ve + la_tam_ung (định nghĩa đầy đủ, thay bản ở supabase-schema-kt-de-nghi-cong-khai.sql)
create or replace function public.kt_gui_de_nghi(p_dong jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_ip text := kt_ip_goi(); v_nguoi text := btrim(regexp_replace(coalesce(p_dong->>'nguoi_de_nghi', ''), '\s+', ' ', 'g'));
  v_nd text := btrim(coalesce(p_dong->>'noi_dung', '')); v_tien numeric; v_sd date; v_han date; v_bp int; v_ck boolean;
  v_th text := btrim(coalesce(p_dong->>'thu_huong_ten', '')); v_nh text := btrim(coalesce(p_dong->>'thu_huong_nh', ''));
  v_stk text := regexp_replace(coalesce(p_dong->>'thu_huong_stk', ''), '[\s.\-]', '', 'g'); v_gc text := nullif(btrim(coalesce(p_dong->>'ghi_chu', '')), '');
  v_pb jsonb := coalesce(p_dong->'phan_bo', '[]'::jsonb); v_tong numeric; v_hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_id bigint; v_ma text; v_cu bigint; v_tom text;
  v_tu boolean := coalesce(p_dong->>'la_tam_ung', '') = 'true'; v_hdve text := nullif(p_dong->>'hd_ve', '');
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
  if v_tu then p_dong := p_dong || jsonb_build_object('co_hd_do', coalesce(p_dong->>'co_hd_do', 'false')); end if;   -- tạm ứng: hoá đơn nộp khi hoàn ứng
  if p_dong->>'co_hd_do' is null or p_dong->>'co_hd_do' not in ('true', 'false') then raise exception 'Chọn có / không có hoá đơn đỏ'; end if;
  -- 16/10/2026 (kế toán): có hoá đơn thì chọn hoá đơn xuất về Công ty hay hộ kinh doanh nào
  if p_dong->>'co_hd_do' = 'true' and coalesce(v_hdve, '') not in ('cong_ty', 'hkd_ht', 'hkd_ct') then
    raise exception 'Chọn hoá đơn xuất về: Công ty / HKD Hiền Thủy / HKD Chánh Tâm'; end if;
  if p_dong->>'co_hd_do' = 'false' then v_hdve := null; end if;
  if length(coalesce(v_gc, '')) > 500 then raise exception 'Ghi chú tối đa 500 ký tự'; end if;
  -- đơn vị chịu chi phí: 1–6 đơn vị đang dùng, không trùng, tổng = số tiền
  if jsonb_typeof(v_pb) <> 'array' or (jsonb_array_length(v_pb) = 0 and not v_tu) then raise exception 'Chọn đơn vị chịu chi phí'; end if;
  if jsonb_array_length(v_pb) > 6 then raise exception 'Tối đa 6 đơn vị chịu chi phí'; end if;
  if exists (select 1 from jsonb_array_elements(v_pb) x where not exists (select 1 from kt_don_vi d where d.id = (x->>'don_vi_id')::int and d.hoat_dong and d.la_co_so)
             or (x->>'so_tien')::numeric <= 0 or (x->>'so_tien')::numeric <> round((x->>'so_tien')::numeric)) then
    raise exception 'Đơn vị chịu chi phí không hợp lệ'; end if;
  if (select count(distinct x->>'don_vi_id') from jsonb_array_elements(v_pb) x) <> jsonb_array_length(v_pb) then raise exception 'Đơn vị chịu chi phí bị chọn trùng'; end if;
  select sum((x->>'so_tien')::numeric) into v_tong from jsonb_array_elements(v_pb) x;
  if jsonb_array_length(v_pb) > 0 and v_tong <> v_tien then raise exception 'Tổng tiền chia cho các đơn vị (%) phải bằng số tiền đề nghị (%)', v_tong, v_tien; end if;
  v_pb := (select coalesce(jsonb_agg(jsonb_build_object('don_vi_id', (x->>'don_vi_id')::int, 'so_tien', (x->>'so_tien')::numeric)), '[]') from jsonb_array_elements(v_pb) x);
  -- bấm gửi 2 lần
  select c.id into v_cu from kt_chi c join kt_chi_phieu p on p.chi_id = c.id
   where not c.da_xoa and lower(c.nguoi_de_nghi) = lower(v_nguoi) and c.so_tien = v_tien and lower(c.noi_dung) = lower(v_nd) and p.tao_luc > now() - interval '30 minutes' limit 1;
  if v_cu is not null then raise exception 'Phiếu này vừa được gửi (mã #%) — không gửi lại', v_cu; end if;

  insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, thu_huong_nh, thu_huong_stk,
    phan_bo, han_tt, co_hd_do, ghi_chu, trang_thai, nguon, tao_boi, hd_ve, la_tam_ung)
  values (v_hom, v_nguoi, v_bp, v_nd, v_sd, v_tien, v_th, v_nh, nullif(v_stk, ''), v_pb, v_han, (p_dong->>'co_hd_do')::boolean, v_gc,
    'cho_duyet', 'phieu', 'Phiếu đề nghị', v_hdve, v_tu)
  returning id into v_id;
  v_ma := encode(gen_random_bytes(18), 'hex');
  insert into kt_chi_phieu (chi_id, ma_hash, ip) values (v_id, encode(digest(v_ma, 'sha256'), 'hex'), v_ip);
  perform kt_ghi_nhat_ky('Phiếu đề nghị: ' || v_nguoi, 'kt_chi', v_id, 'them', (p_dong - 'web') || jsonb_build_object('nguon', 'phieu'));
  v_tom := left(v_nd, 120) || ' · ' || replace(to_char(v_tien, 'FM999G999G999G999'), ',', '.') || ' đ';
  perform kt_bao(kt_ai_ke_toan(null), v_nguoi, 'chi_moi', case when v_tu then 'Phiếu đề nghị TẠM ỨNG mới — chờ kế toán kiểm' else 'Phiếu đề nghị thanh toán mới — chờ kế toán kiểm' end, v_tom, 'chi', v_id);
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $$;

-- ═════ Các hàm báo cáo: định nghĩa đầy đủ (lấy từ bản đang chạy, chỉ sửa phần chi phí / cọc / công nợ) ═════

-- kt_bc_pl2 — chi phí + lãi vay qua phiếu chi theo kỳ hạch toán
CREATE OR REPLACE FUNCTION public.kt_bc_pl2(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_t0 text := to_char(p_tu, 'YYYY-MM'); v_t1 text := to_char(p_den, 'YYYY-MM');
begin
  perform kt_chan(p_phien, 'pl');
  return jsonb_build_object(
    'dt', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'dt', dt, 'gv', gv)), '[]') from (
        select to_char((ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, chi_nhanh cn, sum(tong) dt, sum(coalesce(gia_von, 0)) gv
          from kt_kiot_hoa_don where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    -- trả hàng: trừ doanh thu theo ngày trả; giá vốn hàng trả = tiền trả × (giá vốn / tổng) của hoá đơn gốc (như trang Bán hàng)
    'tra', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'tra', tra, 'gv', gv)), '[]') from (
        select to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, t.chi_nhanh cn, sum(t.tong_tra) tra,
               round(sum(t.tong_tra * coalesce(h.gia_von / nullif(h.tong, 0), 0))) gv
          from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
         where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    'cp', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai_id, 'dv', dv, 'tien', tien)), '[]') from (
        select th, loai_id, dv, round(sum(tien)) tien from (
          -- 16/10/2026 (kế toán): chi phí theo KỲ HẠCH TOÁN (kt_v_chi_ht), không theo ngày thanh toán
          select h.thang th, h.loai_id, h.don_vi_id dv, h.tien
            from kt_v_chi_ht h join kt_loai l on l.id = h.loai_id
           where l.nhom_bc = 'Chi vận hành & quản lí' and h.thang between v_t0 and v_t1) z
         group by 1, 2, 3) x),
    'lai_vay', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'lai', s)), '[]') from (
        select th, sum(s) s from (
          select to_char(ngay, 'YYYY-MM') th, lai s from kt_vay_tra where not da_xoa and da_tra and lai <> 0 and ngay between p_tu and p_den
          union all   -- 15/10/2026: lãi vay & phí tài chính trả qua phiếu chi
          select h.thang, h.tien from kt_v_chi_ht h join kt_loai l on l.id = h.loai_id
           where l.ten = 'FINANCE - Lãi vay & phí tài chính' and h.thang between v_t0 and v_t1) z group by 1) x),
    'loai', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'nhom_bc', nhom_bc, 'thu_tu', thu_tu, 'hoat_dong', hoat_dong) order by thu_tu, id), '[]') from kt_loai where nhom = 'chi'));
end $function$
;

-- kt_bc_qt — ngân sách / cơ sở / tài chính theo kỳ hạch toán; luật cọc mới
CREATE OR REPLACE FUNCTION public.kt_bc_qt(p_phien text, p_loai text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; r jsonb;
begin
  perform kt_chan(p_phien, 'pl');
  if p_loai = 'don' then
    -- đơn đặt tạo trong kỳ: chia nhóm như Tổng quan (kt_tq_don) · hoá đơn hoàn thành trong kỳ (có / không qua đơn đặt)
    return jsonb_build_object(
      'don', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select to_char((o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, o.chi_nhanh cn, kt_kenh_ten(kn.ten, o.chi_nhanh) kenh,
               case when o.trang_thai = 4 then 'huy' when o.trang_thai = 3 then 'di_hang' when v.tinh_trang = 'da_hd' then 'di_hang' when v.tinh_trang = 'nghi_di' then 'nghi_di' when v.tinh_trang in ('cho', 'treo') then 'coc' else 'bao_gia' end nhom,
               count(*) so, sum(o.tong) tong,
               sum(case when o.trang_thai not in (3, 4) then coalesce(v.coc, 0) else 0 end) coc
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id left join kt_v_don_coc v on v.id = o.id left join kt_kiot_kenh kn on kn.id = o.kenh_id
         where (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2, 3, 4) x),
      'hd', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, h.chi_nhanh cn, h.dat_hang_id is not null qua_don, count(*) so, sum(h.tong) tong
          from kt_kiot_hoa_don h where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2, 3) x),
      -- đơn đã cọc chưa đi hàng (mọi thời điểm) — doanh số chờ ghi nhận
      'cho', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select o.chi_nhanh cn, to_char((o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, count(*) so, sum(o.tong) tong, sum(v.coc) da_tra
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id left join kt_v_don_coc v on v.id = o.id
         where v.tinh_trang in ('cho', 'treo') group by 1, 2) x));
  elsif p_loai = 'du_kien' then
    return jsonb_build_object('nay', v_nay,
      'so_du', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'ten', t.ten, 'loai', t.loai, 'so_du', kt_so_du_ngay(t.id, v_nay))), '[]')
                  from kt_tai_khoan t where t.hoat_dong and t.loai <> 'vay' and t.ngay_ton_dau <= v_nay),
      'chi_cho', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'noi_dung', c.noi_dung, 'so_tien', c.so_tien, 'han', c.han_tt, 'trang_thai', c.trang_thai,
                    'ngay', c.ngay_de_nghi) order by coalesce(c.han_tt, c.ngay_de_nghi)), '[]')
                  from kt_chi c where not c.da_xoa and c.trang_thai in ('cho_duyet', 'cho_gd', 'cho_tt')),
      'vay_tra', (select coalesce(jsonb_agg(jsonb_build_object('ngay', t.ngay, 'goc', t.goc, 'lai', t.lai, 'ten', v.ten) order by t.ngay), '[]')
                  from kt_vay_tra t join kt_vay v on v.id = t.vay_id where not t.da_xoa and not v.da_xoa and not t.da_tra),
      'no_kh', (select coalesce(sum(cong_no), 0) from kt_kiot_khach where cong_no > 0),
      'no_ncc', (select coalesce(sum(cong_no), 0) from kt_kiot_ncc where cong_no <> 0),
      'don_coc', (select coalesce(sum(o.tong - coalesce(v.coc, 0)), 0) from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id left join kt_v_don_coc v on v.id = o.id
                   where v.tinh_trang in ('cho', 'treo')),
      -- bình quân 8 tuần gần nhất (để ước tính tuần tới)
      'thu_tuan', (select coalesce(sum(so_tien), 0) / 8 from kt_thu where not da_xoa and trang_thai = 'da_duyet' and ngay > v_nay - 56 and ngay <= v_nay),
      'chi_tuan', (select coalesce(sum(so_tien), 0) / 8 from kt_chi where not da_xoa and trang_thai = 'da_tt' and ngay_tt > v_nay - 56 and ngay_tt <= v_nay));
  elsif p_loai = 'ngan_sach' then
    return jsonb_build_object(
      'loai', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'nhom_bc', nhom_bc) order by ten), '[]') from kt_loai where nhom = 'chi' and hoat_dong),
      'ns', (select coalesce(jsonb_agg(jsonb_build_object('thang', thang, 'loai_id', loai_id, 'so_tien', so_tien)), '[]') from kt_ngan_sach
               where thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM')),
      'thuc', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai_id', lid, 'tien', s)), '[]') from (
          select h.thang th, h.loai_id lid, sum(h.tien) s from kt_v_chi_ht h
           where h.thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM')
           group by 1, 2) x));
  elsif p_loai = 'ton' then
    with ban as (select d->>'ma' ma, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1),
         ban90 as (select distinct d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date > v_nay - 90),
         hg as (select p.ma, p.ten, kt_nhom_cha(coalesce(p.nhom, '(không nhóm)')) nhom, greatest(p.tong_ton, 0) ton, greatest(p.gia_tri_ton, 0) gt,
                       (select max((t->>'gia_von')::numeric) from jsonb_array_elements(p.ton) t where (t->>'gia_von')::numeric > 0) gv from kt_kiot_hang p where p.dv_goc_id is null)
    select jsonb_build_object('so_ngay', least(p_den, v_nay) - p_tu + 1,
      'gv_ky', (select coalesce(sum(gia_von), 0) from kt_kiot_hoa_don where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
      'ton_cn', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'sl', sl, 'gt', gt, 'so_ma', n) order by gt desc), '[]') from (
          select t->>'cn' cn, sum((t->>'ton')::numeric) sl, sum((t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0)) gt, count(*) n
            from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and (t->>'ton')::numeric > 0 group by 1) x),
      'nhom', (select coalesce(jsonb_agg(to_jsonb(x) order by x.gt desc), '[]') from (
          select hg.nhom, sum(hg.gt) gt, sum(hg.ton) ton, count(*) filter (where hg.ton > 0) so_ma, coalesce(sum(b.dt), 0) dt, coalesce(sum(b.sl * coalesce(hg.gv, 0)), 0) gv_ban,
                 sum(hg.gt) filter (where hg.ton > 0 and not exists (select 1 from ban90 z where z.ma = hg.ma)) gt_cham
            from hg left join ban b on b.ma = hg.ma group by 1 having sum(hg.gt) > 0 or coalesce(sum(b.dt), 0) > 0) x),
      'cham', (select coalesce(jsonb_agg(to_jsonb(x) order by x.gt desc), '[]') from (
          select hg.ma, hg.ten, hg.nhom, hg.ton, hg.gt from hg where hg.ton > 0 and not exists (select 1 from ban90 z where z.ma = hg.ma) order by hg.gt desc limit 50) x),
      'cham_tong', (select jsonb_build_object('so_ma', count(*), 'gt', coalesce(sum(gt), 0)) from hg where hg.ton > 0 and not exists (select 1 from ban90 z where z.ma = hg.ma)))
      into r;
    return r;
  elsif p_loai = 'vay' then
    return jsonb_build_object(
      'vay', (select coalesce(jsonb_agg(jsonb_build_object('ten', v.ten, 'ben', v.ben_cho_vay, 'so_tien', v.so_tien, 'lai_suat', v.lai_suat, 'dao_han', v.ngay_dao_han, 'xong', v.da_tat_toan, 'nhan', coalesce((select sum(n.so_tien) from kt_vay_nhan n where n.vay_id = v.id and not n.da_xoa), 0),
                'goc_tra', coalesce((select sum(goc) from kt_vay_tra t where t.vay_id = v.id and not t.da_xoa and t.da_tra), 0))), '[]') from kt_vay v where not v.da_xoa),
      'lai', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'goc', g, 'lai', l)), '[]') from (
          select to_char(ngay, 'YYYY-MM') th, sum(goc) g, sum(lai) l from kt_vay_tra where not da_xoa and da_tra and ngay between p_tu and p_den group by 1) x),
      'chi_tc', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', l, 'tien', s)), '[]') from (
          select h.thang th, lo.ten l, sum(h.tien) s from kt_v_chi_ht h join kt_loai lo on lo.id = h.loai_id
           where h.thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM') and (lo.nhom_bc = 'Chi tài chính' or lo.ten ~* '^FINANCE') group by 1, 2) x));
  elsif p_loai = 'cs' then
    return jsonb_build_object(
      'dt', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'dt', dt, 'gv', gv, 'so', so)), '[]') from (
          select to_char((ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, chi_nhanh cn, sum(tong) dt, sum(gia_von) gv, count(*) so from kt_kiot_hoa_don
           where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
      -- giá vốn hàng trả = tiền trả × (giá vốn / tổng) của hoá đơn gốc — như P&L (kt_bc_pl2)
      'tra', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'tra', s, 'gv', gv)), '[]') from (
          select to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, t.chi_nhanh cn, sum(t.tong_tra) s, round(sum(t.tong_tra * coalesce(h.gia_von / nullif(h.tong, 0), 0))) gv
            from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
           where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
      -- chi phí theo kỳ hạch toán (16/10/2026), chia theo đơn vị chịu chi phí (phan_bo) — tháng theo phân bổ tháng nếu có
      'cp', (select coalesce(jsonb_agg(jsonb_build_object('dv', dv, 'tien', s, 'nhom_bc', nb)), '[]') from (
          select h.don_vi_id dv, lo.nhom_bc nb, sum(h.tien) s
            from kt_v_chi_ht h join kt_loai lo on lo.id = h.loai_id
           where h.don_vi_id is not null and h.thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM')
           group by 1, 2) x),
      'cp_khong_pb', (select coalesce(sum(h.tien), 0) from kt_v_chi_ht h where h.don_vi_id is null
                       and h.thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM')),
      'kenh', (select coalesce(jsonb_agg(jsonb_build_object('kenh', ten, 'cn', cn, 'dt', dt, 'so', so)), '[]') from (
          select kt_kenh_ten(k.ten, h.chi_nhanh) ten, h.chi_nhanh cn, sum(h.tong) dt, count(*) so
            from kt_kiot_hoa_don h left join kt_kiot_kenh k on k.id = h.kenh_id
           where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x));
  end if;
  raise exception 'Loại báo cáo không hợp lệ';
end $function$
;

-- kt_drill — ô chi phí HĐ theo kỳ hạch toán
CREATE OR REPLACE FUNCTION public.kt_drill(p_phien text, p_loai text, p_khoa text, p_tu date, p_den date, p_cn text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  -- quyền theo trang tương ứng: chi phí → Chi · khách / hoá đơn → Khách hàng · tồn → Hàng hoá · nhóm / mặt hàng → Bán hàng
  perform kt_chan(p_phien, case p_loai when 'cp' then 'chi' when 'kh' then 'khach_hang' when 'hd' then 'khach_hang' when 'ton_lau' then 'hang_hoa' else 'ban_hang' end);
  if p_loai = 'nhom' then
    with ct as (select h.chi_nhanh, d from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                 where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
                   and coalesce(d->>'nhom', '(không nhóm)') = p_khoa and (p_cn is null or h.chi_nhanh = p_cn))
    select coalesce(jsonb_agg(jsonb_build_object('ma', g.ma, 'ten', g.ten, 'sl', g.sl, 'dt', g.dt, 'ton', (select tong_ton from kt_kiot_hang p where p.ma = g.ma limit 1)) order by g.dt desc), '[]') into r
      from (select ct.d->>'ma' ma, max(ct.d->>'ten') ten, sum((ct.d->>'sl')::numeric) sl, sum((ct.d->>'tien')::numeric) dt from ct group by 1 order by 4 desc limit 200) g;
  elsif p_loai = 'sp' then
    select jsonb_build_object(
      'sp', (select jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'dvt', don_vi, 'gia_ban', gia_ban, 'tong_ton', tong_ton, 'gia_tri_ton', gia_tri_ton, 'ton', ton) from kt_kiot_hang where ma = p_khoa limit 1),
      'ban_cs', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'sl', sl, 'dt', dt) order by dt desc), '[]') from (
          select h.chi_nhanh cn, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
           where h.trang_thai in (1, 3) and d->>'ma' = p_khoa and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1) x),
      'hd', (select coalesce(jsonb_agg(x order by x->>'ngay' desc), '[]') from (
          select jsonb_build_object('ma', h.ma, 'ngay', (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', h.chi_nhanh, 'khach', h.khach_ten, 'sl', (d->>'sl')::numeric, 'tien', (d->>'tien')::numeric) x
            from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d where h.trang_thai in (1, 3) and d->>'ma' = p_khoa order by h.ngay desc limit 15) t)) into r;
  elsif p_loai = 'kh' then
    select jsonb_build_object(
      'kh', (select jsonb_build_object('id', id, 'ma', ma, 'ten', ten, 'sdt', sdt, 'cong_no', cong_no, 'tong_mua', tong_mua) from kt_kiot_khach where id = p_khoa::bigint),
      'hd', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'tong', tong, 'da_tra', da_tra, 'nv', nv_ban,
          'so_mh', jsonb_array_length(chi_tiet)) order by ngay desc), '[]') from kt_kiot_hoa_don
         where khach_id = p_khoa::bigint and trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den)) into r;
  elsif p_loai = 'hd' then
    select jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'khach', khach_ten, 'khach_id', khach_id, 'nv', nv_ban,
      'tong', tong, 'da_tra', da_tra, 'gia_von', gia_von, 'trang_thai', trang_thai_ten, 'dong', chi_tiet) into r from kt_kiot_hoa_don where ma = p_khoa limit 1;
  elsif p_loai = 'ton_lau' then
    with ban as (select distinct d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai in (1, 3) and h.chi_nhanh = p_cn and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_den - 180 and p_den),
    ton as (select p.ma, p.ten, p.nhom, (t->>'ton')::numeric sl, (t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0) gt
              from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and t->>'cn' = p_cn and (t->>'ton')::numeric > 0)
    select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'sl', sl, 'gt', gt,
        'ban_cuoi', (select max((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date) from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                      where h.trang_thai in (1, 3) and h.chi_nhanh = p_cn and d->>'ma' = ton.ma)) order by gt desc), '[]') into r
      from (select * from ton where ma not in (select ma from ban where ma is not null) order by gt desc limit 100) ton;
  elsif p_loai = 'cp' then
    select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ngay', coalesce(c.ngay_su_dung, c.ngay_de_nghi), 'thang', pb.thang, 'tt', c.trang_thai, 'nd', c.noi_dung, 'th', c.thu_huong_ten, 'loai', l.ten, 'tien', coalesce(pb.tien, c.so_tien), 'dv', dv.ten)
        order by coalesce(pb.tien, c.so_tien) desc), '[]') into r
      from kt_chi c join kt_loai l on l.id = c.loai_id
      join lateral (select h.don_vi_id dv_id, sum(h.tien) tien, min(h.thang) thang from kt_v_chi_ht h
                    where h.chi_id = c.id and h.thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM') group by 1) pb on true
      left join kt_don_vi dv on dv.id = pb.dv_id
     where l.nhom_bc = 'Chi vận hành & quản lí'
       and (coalesce(p_khoa, '') = '' or l.ten = p_khoa)
       and (p_cn is null or (p_cn = '_chung' and coalesce(array_length(dv.kiot_chi_nhanh, 1), 0) = 0) or p_cn = any(dv.kiot_chi_nhanh));
  end if;
  return coalesce(r, 'null'::jsonb);
end $function$
;

-- kt_tq_don — luật cọc chưa đi hàng mới
CREATE OR REPLACE FUNCTION public.kt_tq_don(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'tong_quan');
  return jsonb_build_object(
    'kenh', (select coalesce(jsonb_agg(jsonb_build_object('ten', ten, 'cn', cn, 'dt', dt, 'so', so) order by dt desc), '[]') from (
        select kt_kenh_ten(k.ten, h.chi_nhanh) ten, h.chi_nhanh cn, sum(h.tong) dt, count(*) so
          from kt_kiot_hoa_don h left join kt_kiot_kenh k on k.id = h.kenh_id
         where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    -- nhóm CHA: doanh thu dòng hàng quy về tổng hoá đơn (đã trừ giảm giá HĐ); giá vốn HĐ chia cho các dòng theo tỷ lệ (SL × giá vốn hiện tại)
    'nhom', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'cn', cn, 'dt', round(dt), 'gv', round(gv)) order by dt desc), '[]') from (
        select kt_nhom_cha(coalesce(d->>'nhom', '(không nhóm)')) nhom, h.chi_nhanh cn,
               sum((d->>'tien')::numeric * h.tong / nullif(t.tien, 0)) dt,
               sum(coalesce(h.gia_von, 0) * coalesce(c.gv / nullif(t.gv, 0), (d->>'tien')::numeric / nullif(t.tien, 0))) gv
          from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
          left join lateral (select (d->>'sl')::numeric * coalesce((select (e->>'gia_von')::numeric from kt_kiot_hang p, jsonb_array_elements(p.ton) e
                               where p.id = (d->>'sp')::bigint and e->>'cn' = h.chi_nhanh limit 1), 0) gv) c on true
          cross join lateral (select sum((x->>'tien')::numeric) tien,
                 sum((x->>'sl')::numeric * coalesce((select (e->>'gia_von')::numeric from kt_kiot_hang p, jsonb_array_elements(p.ton) e
                               where p.id = (x->>'sp')::bigint and e->>'cn' = h.chi_nhanh limit 1), 0)) gv from jsonb_array_elements(h.chi_tiet) x) t
         where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    -- đơn đặt hàng tạo trong kỳ: đã đi hàng (Hoàn thành) / đã cọc chưa đi hàng / báo giá (không dấu vết tiền) / huỷ
    'don_ky', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'cn', cn, 'so', so, 'tong', tong, 'coc', coc)), '[]') from (
        select case when o.trang_thai = 4 then 'huy' when o.trang_thai = 3 then 'di_hang'
                    when v.tinh_trang = 'da_hd' then 'di_hang' when v.tinh_trang = 'nghi_di' then 'nghi_di' when v.tinh_trang in ('cho', 'treo') then 'coc' else 'bao_gia' end nhom, o.chi_nhanh cn,
               count(*) so, sum(o.tong) tong, sum(case when o.trang_thai not in (3, 4) then coalesce(v.coc, 0) else 0 end) coc
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id left join kt_v_don_coc v on v.id = o.id
         where (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    -- TẤT CẢ đơn đã cọc chưa đi hàng (không theo kỳ) — doanh thu dự kiến
    'coc_cho', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'ma', o.ma, 'ngay', (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', o.chi_nhanh,
                 'khach', o.khach_ten, 'nv', o.nv_ban, 'tong', o.tong, 'da_tra', o.da_tra, 'tra_truoc', coalesce(v.coc_tt, 0),
                 'ghi_chu', o.ghi_chu, 'coc', v.coc, 'tinh_trang', v.tinh_trang, 'ngay_hd', v.ngay_hd, 'hd_ma', v.hd_ma) order by o.ngay desc), '[]')
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id left join kt_v_don_coc v on v.id = o.id
         where v.tinh_trang in ('cho', 'treo')),
    -- 16/10/2026: đơn trước đây bị tính "đã cọc chưa đi hàng" nhưng thực ra đã có hoá đơn (gắn đơn / nghi đã đi hàng) — để kế toán soát
    'coc_loai', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'ma', o.ma, 'ngay', (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', o.chi_nhanh,
                 'khach', o.khach_ten, 'nv', o.nv_ban, 'tong', o.tong, 'da_tra', o.da_tra, 'ghi_chu', o.ghi_chu, 'tinh_trang', v.tinh_trang, 'ngay_hd', v.ngay_hd, 'hd_ma', v.hd_ma)
                 order by o.ngay desc), '[]')
          from kt_kiot_dat_hang o join kt_v_don_coc v on v.id = o.id where v.tinh_trang in ('da_hd', 'nghi_di')));
end $function$
;

-- kt_cong_no_dt — tách nợ thật / COD / chưa lấy hàng
CREATE OR REPLACE FUNCTION public.kt_cong_no_dt(p_phien text, p_loai text DEFAULT 'kh'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; r jsonb; han int;
begin
  perform kt_chan(p_phien, case when p_loai = 'ncc' then 'ncc' else 'khach_hang' end);
  select coalesce(nullif(gia_tri, '')::int, 30) into han from kt_cai_dat where khoa = case when p_loai = 'ncc' then 'han_no_ncc_ngay' else 'han_no_kh_ngay' end;
  han := coalesce(han, 30);
  with dt as (
    select id, ma, ten, sdt, cong_no no, tong_mua tong from kt_kiot_khach where p_loai = 'kh' and cong_no <> 0
    union all select id, ma, ten, sdt, cong_no, tong_nhap from kt_kiot_ncc where p_loai = 'ncc' and cong_no <> 0),
  ct as (   -- hoá đơn bán (khách) / phiếu nhập (NCC) đã hoàn thành
    select khach_id dt_id, id, ngay, chi_nhanh, tong, nv_ban nv, kt_loai_no(id, cod, ghi_chu) lno from kt_kiot_hoa_don where p_loai = 'kh' and trang_thai in (1, 3) and tong > 0
    union all select ncc_id, id, ngay, chi_nhanh, tong, null, 'that' from kt_kiot_nhap_hang where p_loai = 'ncc' and trang_thai = 3 and tong > 0),
  lk as (select ct.*, d.no, sum(ct.tong) over (partition by ct.dt_id order by ct.ngay desc, ct.id desc) cum
           from ct join dt d on d.id = ct.dt_id where d.no > 0),
  pb as (select dt_id, chi_nhanh, (ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, tong, least(tong, no - (cum - tong)) phan, lno from lk where cum - tong < no),
  g as (select dt_id, sum(phan) da_gan, sum(tong) tong_ct, min(ngay) cu_nhat, count(*) so_ct, (array_agg(chi_nhanh order by ngay desc))[1] cn,
          sum(phan) filter (where hom - ngay <= 30) b1, sum(phan) filter (where hom - ngay between 31 and 60) b2,
          sum(phan) filter (where hom - ngay between 61 and 90) b3, sum(phan) filter (where hom - ngay > 90) b4,
          sum(phan) filter (where lno = 'cod') n_cod, sum(phan) filter (where lno = 'chua_lay') n_cl
          from pb group by 1),
  cn_cuoi as (select distinct on (dt_id) dt_id, chi_nhanh, nv from ct order by dt_id, ngay desc),
  -- người phụ trách (14/10/2026): gán tay (kt_cong_no_pt) > NV bán phiếu gần nhất quy về tên trong Nhân sự (tên hoặc tên trên Kiot) > tên Kiot thô
  ns as (select id, ten, bo_phan_id, array(select lower(btrim(x)) from unnest(ten_kiot || ten) x) ten_kt from kt_nhan_su)
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'ma', d.ma, 'ten', d.ten, 'sdt', d.sdt, 'no', d.no, 'tong', d.tong,
      'cn', coalesce(g.cn, c.chi_nhanh), 'so_ct', coalesce(g.so_ct, 0), 'cu_nhat', g.cu_nhat, 'tuoi', hom - g.cu_nhat,
      'b1', coalesce(g.b1, 0), 'b2', coalesce(g.b2, 0), 'b3', coalesce(g.b3, 0), 'b4', coalesce(g.b4, 0),
      'truoc_2026', greatest(d.no - coalesce(g.da_gan, 0), 0), 'nv', coalesce(ng.ten, nk.ten, c.nv), 'nv_id', coalesce(ng.id, nk.id), 'nv_gan', pt.nhan_su_id is not null, 'nv_kiot', c.nv, 'han', han,
      -- 16/10/2026 (kế toán): tách nợ thật / COD chưa thu hồi / khách chưa lấy hàng (theo hoá đơn đang tính nợ)
      'no_cod', coalesce(g.n_cod, 0), 'no_chua_lay', coalesce(g.n_cl, 0), 'no_that', d.no - coalesce(g.n_cod, 0) - coalesce(g.n_cl, 0),
      -- tổng các chứng từ đang tính nợ (+ phần nợ trước 2026) · đã thanh toán = tổng − còn nợ · đến hạn = chứng từ nợ cũ nhất + số ngày được nợ
      'tong_ct', coalesce(g.tong_ct, 0) + greatest(d.no - coalesce(g.da_gan, 0), 0), 'den_han', g.cu_nhat + han,
      'qua_han', case when d.no > 0 and g.cu_nhat is not null then greatest(hom - (g.cu_nhat + han), 0) end) order by d.no desc), '[]') into r
    from dt d left join g on g.dt_id = d.id left join cn_cuoi c on c.dt_id = d.id
    left join kt_cong_no_pt pt on pt.loai = p_loai and pt.dt_id = d.id left join ns ng on ng.id = pt.nhan_su_id
    left join lateral (select n.id, n.ten from ns n where c.nv is not null and lower(btrim(c.nv)) = any(n.ten_kt) limit 1) nk on true;
  return r;
end $function$
;

-- kt_cong_no_dt_ct — loại nợ từng hoá đơn
CREATE OR REPLACE FUNCTION public.kt_cong_no_dt_ct(p_phien text, p_loai text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; d record; r jsonb;
begin
  perform kt_chan(p_phien, case when p_loai = 'ncc' then 'ncc' else 'khach_hang' end);
  if p_loai = 'ncc' then select id, ma, ten, sdt, cong_no no, tong_nhap tong, null::text loai into d from kt_kiot_ncc where id = p_id;
  else select id, ma, ten, sdt, cong_no no, tong_mua tong, loai::text loai into d from kt_kiot_khach where id = p_id; end if;
  if d.id is null then return null; end if;
  with ct as (
    select id, ma, ngay, chi_nhanh, tong, da_tra, kt_loai_no(id, cod, ghi_chu) lno, ghi_chu, cod, (select p.loai from kt_no_phan_loai p where p.hoa_don_id = kt_kiot_hoa_don.id) lno_tay from kt_kiot_hoa_don where p_loai <> 'ncc' and khach_id = p_id and trang_thai in (1, 3)
    union all select id, ma, ngay, chi_nhanh, tong, da_tra, 'that', null, null, null from kt_kiot_nhap_hang where p_loai = 'ncc' and ncc_id = p_id and trang_thai = 3),
  lk as (select ct.*, sum(tong) over (order by ngay desc, id desc) cum from ct where tong > 0)
  select jsonb_build_object(
    'dt', jsonb_build_object('id', d.id, 'ma', d.ma, 'ten', d.ten, 'sdt', d.sdt, 'no', d.no, 'tong', d.tong, 'loai', d.loai),
    'dang_no', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'tong', tong,
        'id', id, 'loai_no', lno, 'loai_tay', lno_tay is not null, 'ghi_chu', ghi_chu, 'cod', cod, 'con_no', least(tong, d.no - (cum - tong)), 'tuoi', hom - (ngay at time zone 'Asia/Ho_Chi_Minh')::date) order by ngay desc), '[]')
        from lk where d.no > 0 and cum - tong < d.no),
    'gan_day', (select coalesce(jsonb_agg(x order by x->>'ngay' desc), '[]') from (select jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date,
        'cn', chi_nhanh, 'tong', tong, 'da_tra', da_tra) x from ct order by ngay desc limit 15) t),
    'tra_tien', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'so_tien', so_tien,
        'pt', phuong_thuc, 'nd', noi_dung) order by ngay desc), '[]') from (select * from kt_kiot_so_quy
        where la_thu = (p_loai <> 'ncc') and trang_thai = '0' and lower(trim(doi_tac)) = lower(trim(d.ten)) order by ngay desc limit 15) q)) into r;
  return r;
end $function$
;
