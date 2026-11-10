-- 10/11/2026 anh (ảnh trang So khớp Kiot ↔ App của app MKT: "Bên Kế toán lệch Kiot 6 mã — kế toán còn giữ mã Kiot đã xoá"):
-- DH002432 · DH002643 · DH002684 · DH002782 · DH002782.01 · DH002954 đã bị XOÁ trên Kiot (hoá đơn bán của chúng vẫn còn) nhưng app kế toán vẫn giữ
-- (lần so khớp chỉ báo "app thừa", không đánh dấu) → đánh dấu trạng thái "Đã xoá trên Kiot" (đơn đặt = 4 như huỷ, hoá đơn = 2), KHÔNG xoá dòng
-- (giữ liên kết hoá đơn); lần so khớp bỏ phiếu đã đánh dấu; Edge kt-kiot từ nay tự đánh dấu phiếu Kiot xác nhận đã xoá + báo giá đã xoá. — Monsieur Claude
create or replace function public.kt_kiot_danh_dau_xoa(p_loai text, p_ma text[]) returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0;
begin
  if coalesce(array_length(p_ma, 1), 0) = 0 then return 0; end if;
  if p_loai = 'dh' then
    update kt_kiot_dat_hang set trang_thai = 4, trang_thai_ten = 'Đã xoá trên Kiot' where ma = any(p_ma) and coalesce(trang_thai_ten, '') <> 'Đã xoá trên Kiot';
  elsif p_loai = 'hd' then
    update kt_kiot_hoa_don set trang_thai = 2, trang_thai_ten = 'Đã xoá trên Kiot' where ma = any(p_ma) and coalesce(trang_thai_ten, '') <> 'Đã xoá trên Kiot';
  else raise exception 'Loại không hợp lệ'; end if;
  get diagnostics n = row_count;
  if n > 0 then perform kt_ghi_nhat_ky('Hệ thống', case p_loai when 'dh' then 'kt_kiot_dat_hang' else 'kt_kiot_hoa_don' end, null, 'danh_dau_xoa_kiot', jsonb_build_object('ma', p_ma, 'so', n)); end if;
  return n;
end $$;
revoke execute on function public.kt_kiot_danh_dau_xoa(text, text[]) from public, anon, authenticated;
grant execute on function public.kt_kiot_danh_dau_xoa(text, text[]) to service_role;

-- lần so khớp (Edge): bỏ phiếu đã đánh dấu xoá trên Kiot
CREATE OR REPLACE FUNCTION public.kt_kiot_dc_db(p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
  select jsonb_build_object(
    'hd', (select coalesce(jsonb_agg(jsonb_build_array(id, trang_thai, tong,
              (select coalesce(sum((d->>'tien')::numeric), 0) from jsonb_array_elements(chi_tiet) d), chi_nhanh, ma)), '[]')
             from kt_kiot_hoa_don where coalesce(trang_thai_ten, '') <> 'Đã xoá trên Kiot' and ngay >= (p_tu::timestamp at time zone 'Asia/Ho_Chi_Minh') and ngay < (p_den::timestamp at time zone 'Asia/Ho_Chi_Minh')),
    'th', (select coalesce(jsonb_agg(jsonb_build_array(id, trang_thai, tong_tra, chi_nhanh, ma)), '[]')
             from kt_kiot_tra_hang where ngay >= (p_tu::timestamp at time zone 'Asia/Ho_Chi_Minh') and ngay < (p_den::timestamp at time zone 'Asia/Ho_Chi_Minh')));
$$;

CREATE OR REPLACE FUNCTION public.kt_kiot_dc_db2(p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
  select jsonb_build_object(
    'sq', (select coalesce(jsonb_agg(jsonb_build_array(id, trang_thai, so_tien, la_thu, chi_nhanh, ma)), '[]')
             from kt_kiot_so_quy where ngay >= (p_tu::timestamp at time zone 'Asia/Ho_Chi_Minh') and ngay < (p_den::timestamp at time zone 'Asia/Ho_Chi_Minh')),
    'nh', (select coalesce(jsonb_agg(jsonb_build_array(id, trang_thai, tong, chi_nhanh, ma)), '[]')
             from kt_kiot_nhap_hang where ngay >= (p_tu::timestamp at time zone 'Asia/Ho_Chi_Minh') and ngay < (p_den::timestamp at time zone 'Asia/Ho_Chi_Minh')),
    'dh', (select coalesce(jsonb_agg(jsonb_build_array(id, trang_thai, tong, chi_nhanh, ma)), '[]')
             from kt_kiot_dat_hang where coalesce(trang_thai_ten, '') <> 'Đã xoá trên Kiot' and ngay >= (p_tu::timestamp at time zone 'Asia/Ho_Chi_Minh') and ngay < (p_den::timestamp at time zone 'Asia/Ho_Chi_Minh')));
$$;

-- đánh dấu 6 đơn đặt app MKT báo (đã kiểm: Kiot không còn; hoá đơn HD059385 · HD059544 · HD059835 · HD060358 vẫn còn)
select public.kt_kiot_danh_dau_xoa('dh', array['DH002432','DH002643','DH002684','DH002782','DH002782.01','DH002954']);
