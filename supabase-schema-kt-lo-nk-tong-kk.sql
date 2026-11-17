-- HỒ SƠ NHẬP KHẨU — Ô TỔNG QUAN THUẾ NHẬP KHẨU (VNĐ) + GIÁ TRỊ HÀNG KÊ KHAI (17/11/2026, kế toán: "phần hồ sơ nhập khẩu bổ sung ở các ô tổng quan phần thuế nhập khẩu (vnđ) và giá trị hàng kê khai"). Monsieur Claude
-- kt_lo_nk_kk_tong: số tổng kê khai của 1 lô — dùng cho trang danh sách (kt_ds_lo_nk trả thêm 'kk'); cửa sổ từng hồ sơ tính cùng công thức trên trình duyệt (lnkKk).
--   giá khai trên đơn hàng (gia_tri_kk × tỷ giá tờ khai / tỷ giá đơn / tỷ giá lô) · dòng tờ khai kt_lo_nk_kk (trị giá nguyên tệ, thuế NK, thuế GTGT — đồng)
--   · chi phí đã ghi loại thue_nk / vat_nk (dự phòng khi chưa nhập tờ khai). Chỉ đọc, không đổi dữ liệu.
create or replace function public.kt_lo_nk_kk_tong(l kt_lo_nk) returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'don_n', (select count(*) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa and d.gia_tri_kk is not null),
    'don_vnd', (select sum(case when coalesce(d.tien_te, l.tien_te) = 'VND' then d.gia_tri_kk else d.gia_tri_kk * coalesce(d.ty_gia_kk, d.ty_gia, l.ty_gia) end)
                  from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa and d.gia_tri_kk is not null),
    'don_thieu_ty', (select count(*) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa and d.gia_tri_kk is not null and coalesce(d.tien_te, l.tien_te) <> 'VND' and coalesce(d.ty_gia_kk, d.ty_gia, l.ty_gia) is null),
    'kk_n', (select count(*) from kt_lo_nk_kk k where k.lo_id = l.id),
    'kk_tg', (select sum(k.tri_gia) from kt_lo_nk_kk k where k.lo_id = l.id),
    'kk_te', (select case when count(distinct coalesce(k.tien_te, 'USD')) = 1 then max(coalesce(k.tien_te, 'USD')) end from kt_lo_nk_kk k where k.lo_id = l.id),
    'kk_nk', (select sum(k.thue_nk) from kt_lo_nk_kk k where k.lo_id = l.id),
    'kk_vat', (select sum(k.thue_vat) from kt_lo_nk_kk k where k.lo_id = l.id),
    'cp_nk', (select sum(c.so_tien) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and c.loai = 'thue_nk'),
    'cp_vat', (select sum(c.so_tien) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and c.loai = 'vat_nk'))
$$;
revoke all on function public.kt_lo_nk_kk_tong(kt_lo_nk) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.kt_ds_lo_nk(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(to_jsonb(l) || jsonb_build_object(
      'so_don', (select count(*) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa),
      'ncc', (select coalesce(jsonb_agg(distinct n.ten), '[]') from kt_lo_nk_don d join kt_ncc n on n.id = d.ncc_id where d.lo_id = l.id and not d.da_xoa),
      'gia_tri', (select coalesce(sum(kt_lo_nk_don_vnd(d, l)), 0) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa),
      'gia_tri_te', (select sum(d.gia_tri) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa and coalesce(d.tien_te, l.tien_te) = l.tien_te),
      'chi_phi', (select coalesce(sum(c.so_tien), 0) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and c.tinh_gv)
                   + coalesce((select sum((x->>'so_tien')::numeric) from jsonb_array_elements(kt_lo_nk_phi_tt(l.id)) x), 0),
      'chi_phi_khac', (select coalesce(sum(c.so_tien), 0) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and not c.tinh_gv),
      'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'lo_nk' and ct.dong_id = l.id and not ct.da_xoa),
      'kk', kt_lo_nk_kk_tong(l))
    order by coalesce(l.ngay_kh, l.tao_luc::date) desc, l.id desc) from kt_lo_nk l where not l.da_xoa), '[]');
end $function$;
