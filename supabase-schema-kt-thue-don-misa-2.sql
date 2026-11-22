-- 10/11/2026 anh: "bịt hẳn vào" (kẽ hở: kế toán phát hành nháp trên MISA → lần kéo HĐ 00:25 / 12:25 trừ tồn theo HĐ MISA, mà đơn app vẫn "Nháp"
-- cho tới khi có người mở trang Lập hoá đơn → tồn bị trừ 2 lần). → Edge kt-meinvoice cuối mỗi lượt kéo gọi kt-meinvoice-nhap {viec:'kiem'} bằng
-- khoá lịch: lấy số HĐ các nháp đã phát hành, đơn chuyển "Đã xuất HĐ" ngay trong cùng lượt. Hàm dưới chỉ service_role. — Monsieur Claude
create or replace function public.kt_thue_don_misa_cho() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'ref', d.misa_ref)), '[]') from kt_thue_don d
   where d.misa_ref is not null and coalesce(d.so_hd, '') = ''
$$;
revoke execute on function public.kt_thue_don_misa_cho() from public, anon, authenticated;
grant execute on function public.kt_thue_don_misa_cho() to service_role;
