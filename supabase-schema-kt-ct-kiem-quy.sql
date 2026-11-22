-- 24/10/2026 HOTFIX (anh: "lỗi ảnh hotfix" — Kiểm két: ảnh chụp sổ tải lên báo LỖI): kt_quyen_chung_tu (Edge Function kt-chung-tu gọi để ký link tải lên / xem)
-- chỉ nhận bao_loi / thu / chi / dieu_chuyen / vay / tai_san → thiếu 'kiem_quy' (ảnh kiểm két) và 'tam_ung' → "Bảng chứng từ không hợp lệ".
-- kt_chan_dong đã lo quyền (kiem_quy → trang kiem_ket; tam_ung → trang tam_ung). Monsieur Claude
create or replace function public.kt_quyen_chung_tu(p_phien text, p_bang text, p_ghi boolean, p_ids bigint[])
 returns text language plpgsql security definer set search_path to 'public' as $function$
declare u kt_nguoi_dung;
begin
  if p_bang not in ('bao_loi','thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung') then raise exception 'Bảng chứng từ không hợp lệ'; end if;
  u := kt_chan_dong(p_phien, p_bang, p_ids, p_ghi);
  return u.ho_ten;
end $function$;
revoke execute on function public.kt_quyen_chung_tu(text, text, boolean, bigint[]) from public, anon, authenticated;
grant execute on function public.kt_quyen_chung_tu(text, text, boolean, bigint[]) to service_role;
