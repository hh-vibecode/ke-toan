-- 24/10/2026 kế toán (anh chuyển): phiếu thu kéo tự động từ Kiot (vd TNH000719) muốn bỏ khỏi luồng → cần nút Xoá; anh: "phiếu nào cũng phải có nút xoá".
-- Trước: phiếu thu Kiot không có nút Xoá, và kt_dong_bo_kiot đặt lại da_xoa = false → xoá xong lần kéo Kiot sau hồi sinh.
-- Sửa: cờ xoa_tay (người dùng xoá) — kt_xoa bật cờ, đồng bộ Kiot không ghi đè phiếu có cờ. Monsieur Claude
alter table public.kt_thu add column if not exists xoa_tay boolean not null default false;

create or replace function public.kt_xoa(p_phien text, p_bang text, p_id bigint)
 returns void language plpgsql security definer set search_path to 'public' as $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, case when p_bang = 'cong_no_thu' then 'cong_no' when p_bang in ('vay_tra', 'vay_nhan') then 'vay' when p_bang = 'tam_ung_hoan' then 'tam_ung' else p_bang end, true);
  if p_bang not in ('thu','chi','dieu_chuyen','cong_no','cong_no_thu','sap_tra','vay','vay_tra','vay_nhan','tai_san','tam_ung','tam_ung_hoan') then raise exception 'Bảng không hợp lệ'; end if;
  execute format('update public.%I set da_xoa = true where id = $1', 'kt_' || p_bang) using p_id;
  if p_bang = 'thu' then update kt_thu set xoa_tay = true where id = p_id; end if;   -- 24/10: đồng bộ Kiot không hồi sinh phiếu người dùng đã xoá
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, 'xoa', null);
end $function$;

-- kt_dong_bo_kiot: bỏ qua phiếu thu người dùng đã xoá (vá tại chỗ)
do $d$ declare d text := pg_get_functiondef('kt_dong_bo_kiot(date)'::regprocedure); n int := length(d);
begin
  if position('kt_thu.xoa_tay' in d) > 0 then return; end if;
  d := replace(d, 'where (kt_thu.ngay, kt_thu.noi_dung, kt_thu.so_tien,', 'where not kt_thu.xoa_tay and (kt_thu.ngay, kt_thu.noi_dung, kt_thu.so_tien,');
  if length(d) = n then raise exception 'Vá kt_dong_bo_kiot không khớp mẫu'; end if;
  execute d;
end $d$;
