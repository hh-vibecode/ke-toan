-- HOÁ ĐƠN CÔNG TY TỔNG từ MISA meInvoice (12/10/2026) — Monsieur Claude
-- Anh chốt 12/10: meInvoice = hoá đơn CÔNG TY TỔNG (đi theo dòng tiền tài khoản công ty); Kiot / 3TShop = các HỘ.
-- Ký hiệu máy tính tiền *MHH ("Hong Kong Center") và *MSH ("Saikung Hot Pot") = dịch vụ khác → KHÔNG tính (Edge Function bỏ qua).
-- GIỮ (tính vào app) toàn bộ ký hiệu còn lại: THT / TYY = hoá đơn giá trị gia tăng · TTV = nến · TCK = chuyển khoản.
-- Lưu vào kt_thue_hd với hkd = 'CTY', chieu = 'ra', MỖI HOÁ ĐƠN 1 DÒNG (API danh sách chỉ có tổng hoá đơn, không có từng dòng hàng).
-- Nguồn 'meinvoice:YYYY-MM': mỗi lần nạp thay nguyên tháng đó (chạy lại không trùng; hoá đơn điều chỉnh / thay thế cập nhật theo).
-- Anh chốt 12/10/2026 (tối): SHIDAI = CÔNG TY THT. Hoá đơn bán Shidai trong file 3TShop trùng ~96% hoá đơn meInvoice (số + ngày) → bỏ bản 3TShop,
--   hoá đơn mua Shidai (NHẬP HT, mua từ Hiền Thủy) chuyển sang hkd 'CTY'. Cột công ty so với doanh thu Kiot "Tổng kho sỉ Shidai".
delete from kt_thue_hd where hkd = 'SD' and chieu = 'ra' and nguon like 'SD:%THONG_TIN_XUAT';
update kt_thue_hd set hkd = 'CTY' where hkd = 'SD' and nguon like 'SD:%NHAP_HT';

-- Edge Function kt-meinvoice (CHỈ ĐỌC MISA: token · templates · paging) gọi hàm dưới bằng service_role; pg_cron 'kt-meinvoice' mỗi đêm.

create or replace function public.kt_nap_meinvoice(p_thang text, p_ds jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_thang !~ '^\d{4}-\d{2}$' then raise exception 'tháng sai: %', p_thang; end if;
  delete from kt_thue_hd where nguon = 'meinvoice:' || p_thang;
  insert into kt_thue_hd (hkd, chieu, so_hd, mau, ky_hieu, ngay, mst, nguoi_mua, ten, thanh_tien, tien_thue, tong, ghi_chu, nguon)
  select 'CTY', 'ra', x->>'so_hd', x->>'mau', x->>'ky_hieu', (x->>'ngay')::date, nullif(x->>'mst', ''), x->>'nguoi_mua', x->>'ten',
         (x->>'thanh_tien')::numeric, (x->>'tien_thue')::numeric, (x->>'tong')::numeric, nullif(x->>'ghi_chu', ''), 'meinvoice:' || p_thang
    from jsonb_array_elements(p_ds) x;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.kt_nap_meinvoice(text, jsonb) from public, anon, authenticated;
grant execute on function public.kt_nap_meinvoice(text, jsonb) to service_role;

create or replace function public.kt_hkd_chi_nhanh(p text) returns text language sql immutable as $$
  select case p when 'HT' then 'Đồ thờ Hiền Thủy' when 'CT' then 'Đồ Thờ Chánh Tâm' when 'CTY' then 'Tổng kho sỉ Shidai' when 'SD' then 'Tổng kho sỉ Shidai' end;   -- 12/10: Shidai = công ty THT
$$;
