-- 22/10/2026 (anh: "gắn link file để tìm cho dễ"): trả thêm số dòng trong sheet của từng khoản chi phí công ty. Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_ds_dcp_pnl(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not kt_co_quyen(u, 'he_thong') then raise exception 'Tài khoản chưa được cấp quyền xem trang này' using errcode = '42501'; end if;
  return jsonb_build_object(
    'chay_luc', (select max(chay_luc) from kt_dcp_dong),
    'phieu', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'so_tien', c.so_tien, 'nd', c.noi_dung, 'th', c.thu_huong_ten, 'tk', c.tai_khoan_id, 'loai', c.loai_id, 'khop', p.khop)
               order by coalesce(c.ngay_tt, c.ngay_de_nghi)), '[]') from kt_dcp_phieu p join kt_chi c on c.id = p.chi_id),
    'cp', (select coalesce(jsonb_agg(jsonb_build_object('thang', thang, 'ngay', ngay, 'sheet', sheet, 'nhom', danh_muc, 'nd', noi_dung, 'so_tien', so_tien, 'nguon_tt', nguon_tt, 'chi_id', chi_id, 'dong', dong)
               order by thang, ngay nulls last, id), '[]') from kt_dcp_dong),
    'pnl', (select coalesce(jsonb_agg(jsonb_build_object('nguon', nguon, 'thang', thang, 'ma', ma, 'ten', ten, 'target', target, 'th', thuc_hien, 'app', app, 'lech', lech) order by nguon, thang, dong), '[]')
               from kt_pnl_cu where ma is not null));
end $function$;
