-- THANH TOÁN TRUNG GIAN: TRẢ TỪ TÀI KHOẢN VAY → HIỆN "GHI VÀO KHOẢN VAY" — 20/11/2026. Monsieur Claude
-- Anh: "tk vay thì phải trừ vào khoản vay chứ đúng không" — đúng (giải ngân vào khoản vay, TK vay vào = ra), nhưng nhãn "Đã trừ số dư" gây hiểu nhầm → kt_tt_nn_ds trả thêm vay_ten để trang ghi "Ghi vào khoản vay …".
CREATE OR REPLACE FUNCTION public.kt_tt_nn_ds(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(to_jsonb(t) - 'da_xoa' || jsonb_build_object('tk', (select ten from kt_tai_khoan where id = t.tk_id), 'tk_loai', (select loai from kt_tai_khoan where id = t.tk_id), 'vay_ten', (select ten from kt_vay where id = t.vay_id and not da_xoa),
      'ra', kt_tt_nn_ra(t),
      'chi', (select jsonb_build_object('id', c.id, 'so_tien', c.so_tien, 'tt', c.trang_thai, 'ngay', c.ngay_tt) from kt_chi c where c.id = t.chi_id and not c.da_xoa),
      'nghi_trung', case when t.chi_id is null and t.tk_id is not null and kt_tt_nn_ra(t) > 0 then (select jsonb_agg(jsonb_build_object('id', c.id, 'ngay', c.ngay_tt, 'nd', left(c.noi_dung, 80)) order by abs(c.ngay_tt - t.ngay))
          from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.tai_khoan_id = t.tk_id and c.ngay_tt between t.ngay - 10 and t.ngay + 10
           and abs(c.so_tien - kt_tt_nn_ra(t)) < 1 and not exists (select 1 from kt_tt_nn o where o.chi_id = c.id and not o.da_xoa)) end) order by t.ngay desc, t.id desc)
    from kt_tt_nn t where not t.da_xoa), '[]');
end $function$
;
