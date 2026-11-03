-- 03/11/2026 anh: "bấm vào 1 hoá đơn đang không ra cái gì, MISA nó xem được ảnh đây này" → xem bản hoá đơn (PDF) ngay trên app.
-- kt_hd_xem: kiểm phiên + quyền trang Hoá đơn & Thuế, trả thông tin + mã MISA (ma_ngoai) của 1 hoá đơn công ty.
-- Edge Function kt-meinvoice (HĐ ra) / kt-meinvoice-bot (HĐ vào) gọi hàm này trước khi tải PDF từ MISA,
-- lưu sẵn vào kt-chung-tu: hd/{ra|vao}/{mã MISA}.pdf (lần sau mở ngay, không gọi MISA lại). — Monsieur Claude
create or replace function public.kt_hd_xem(p_phien text, p_so_hd text, p_hkd text, p_ngay date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  select jsonb_build_object('chieu', h.chieu, 'nguon', split_part(h.nguon, ':', 1), 'ma', h.ma_ngoai, 'ky_hieu', h.ky_hieu, 'so_hd', h.so_hd, 'ngay', h.ngay,
           'nguoi_mua', h.nguoi_mua, 'mst', h.mst, 'thanh_tien', h.thanh_tien, 'tien_thue', h.tien_thue, 'tong', h.tong, 'ghi_chu', h.ghi_chu)
    into v from kt_thue_hd h
   where h.hkd = p_hkd and h.ngay = p_ngay and (h.so_hd = p_so_hd or ltrim(h.so_hd, '0') = ltrim(p_so_hd, '0'))
   order by (h.ma_ngoai is null), h.id limit 1;
  return v;
end $$;
revoke execute on function public.kt_hd_xem(text, text, text, date) from public;
grant execute on function public.kt_hd_xem(text, text, text, date) to anon, authenticated;
