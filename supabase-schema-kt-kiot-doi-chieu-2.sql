-- SO KHỚP THÊM VỚI KIOT (14/10/2026, anh: "so khớp thêm sổ quỹ từng quỹ, tổng công nợ, phiếu nhập, đơn đặt, đếm số dòng"). Monsieur Claude
-- Chạy thử chỉ đọc 14/10 trước khi làm: sổ quỹ T9 app thiếu 4 phiếu Kiot ghi lùi ngày + 1 phiếu huỷ muộn (lần kéo 15 phút chỉ lấy 10 ngày gần nhất);
-- phiếu nhập T9 / T10 thiếu 1 + 1 (phiếu chưa từng sửa → lọc "ngày sửa" của Kiot không trả); đơn đặt, công nợ KH / NCC khớp.
-- Edge Function kt-kiot (doiChieuThang) dùng 2 hàm dưới; kết quả ghi kt_kiot_doi_chieu (thêm loại 'cong_no').

-- dữ liệu app 1 tháng: sổ quỹ · phiếu nhập · đơn đặt — mỗi dòng [id, trạng thái, tiền, ..., mã] (mã luôn ở cuối)
create or replace function public.kt_kiot_dc_db2(p_tu date, p_den date) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'sq', (select coalesce(jsonb_agg(jsonb_build_array(id, trang_thai, so_tien, la_thu, chi_nhanh, ma)), '[]')
             from kt_kiot_so_quy where ngay >= (p_tu::timestamp at time zone 'Asia/Ho_Chi_Minh') and ngay < (p_den::timestamp at time zone 'Asia/Ho_Chi_Minh')),
    'nh', (select coalesce(jsonb_agg(jsonb_build_array(id, trang_thai, tong, chi_nhanh, ma)), '[]')
             from kt_kiot_nhap_hang where ngay >= (p_tu::timestamp at time zone 'Asia/Ho_Chi_Minh') and ngay < (p_den::timestamp at time zone 'Asia/Ho_Chi_Minh')),
    'dh', (select coalesce(jsonb_agg(jsonb_build_array(id, trang_thai, tong, chi_nhanh, ma)), '[]')
             from kt_kiot_dat_hang where ngay >= (p_tu::timestamp at time zone 'Asia/Ho_Chi_Minh') and ngay < (p_den::timestamp at time zone 'Asia/Ho_Chi_Minh')));
$$;
-- công nợ hiện tại trên app: [id, công nợ, mã]
create or replace function public.kt_kiot_cn_db() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'kh', (select coalesce(jsonb_agg(jsonb_build_array(id, coalesce(cong_no, 0), ma)), '[]') from kt_kiot_khach),
    'ncc', (select coalesce(jsonb_agg(jsonb_build_array(id, coalesce(cong_no, 0), ma)), '[]') from kt_kiot_ncc));
$$;
revoke execute on function public.kt_kiot_dc_db2(date, date) from public, anon, authenticated;
revoke execute on function public.kt_kiot_cn_db() from public, anon, authenticated;
-- dọn quyền thừa (14/10): hàm nội bộ không cho trình duyệt gọi thẳng
revoke execute on function public.kt_so_du_ngay(int, date) from public, anon, authenticated;
revoke execute on function public.kt_tg_khoa_ky() from public, anon, authenticated;

alter table public.kt_kiot_doi_chieu drop constraint if exists kt_kiot_doi_chieu_loai_check;
alter table public.kt_kiot_doi_chieu add constraint kt_kiot_doi_chieu_loai_check check (loai = any (array['thang', 'ton', 'cong_no']));

-- trang Nhật ký kéo & so khớp Kiot (bản đang chạy 14/10) + 10 lần so công nợ gần nhất
CREATE OR REPLACE FUNCTION public.kt_ds_keo_kiot(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'nhat_ky');
  return jsonb_build_object(
    'lich', (select coalesce(jsonb_agg(jsonb_build_object('ten', jobname, 'lich', schedule, 'bat', active, 'than', command ~ 'x-kt-cron') order by jobname), '[]')
               from (select jobname, schedule, active, command::text command from cron.job where jobname like 'kt-%') j),
    'chay', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'luc', luc, 'nguoi', nguoi, 'viec', hanh_dong, 'kq', du_lieu) order by id desc), '[]')
               from (select * from kt_nhat_ky where hanh_dong in ('keo_kiot', 'keo_kiot_loi', 'doi_chieu_kiot', 'chup_ton_kho', 'keo_meinvoice')
                     order by id desc limit 150) n),
    'thang', (select coalesce(jsonb_agg(to_jsonb(d) order by d.thang desc), '[]')
               from (select distinct on (thang) * from kt_kiot_doi_chieu where loai = 'thang' order by thang, luc desc) d),
    'ton', (select coalesce(jsonb_agg(to_jsonb(d) order by d.luc desc), '[]')
               from (select * from kt_kiot_doi_chieu where loai = 'ton' order by luc desc limit 30) d),
    'cong_no', (select coalesce(jsonb_agg(to_jsonb(d) order by d.luc desc), '[]')
               from (select * from kt_kiot_doi_chieu where loai = 'cong_no' order by luc desc limit 10) d));
end $function$;
