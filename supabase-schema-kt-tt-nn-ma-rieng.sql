-- THANH TOÁN TRUNG GIAN: MÃ PHIẾU RIÊNG PCTG, KHÔNG NỐI PHIẾU CHI — 19/11/2026. Monsieur Claude
-- Anh: "tách riêng rồi thì tự tạo mã phiếu chi riêng, không nối với phiếu chi ở Thu chi & Ngân quỹ; chỉ mã thôi". Mã = PCTG + số lần (giao diện).
-- Lần chuyển tự trừ số dư TRỪ KHI còn phiếu chi ĐANG HIỆU LỰC (đã chi, không xoá) cho cùng khoản (lần cũ có chi_id) — kế toán xoá phiếu chi đó trên app
-- thì lần chuyển tự trừ thay, không trừ 2 lần, không mất số. (Lần 6 ↔ PC002040: chờ kế toán xoá PC002040 — hệ thống không tự xoá phiếu kế toán lập.)
create or replace view public.kt_v_bien_dong as
 SELECT t.tai_khoan_id, t.ngay, 'thu'::text AS kieu, t.so_tien AS vao, 0::numeric AS ra
   FROM kt_thu t WHERE NOT t.da_xoa AND t.trang_thai = 'da_duyet'::text
UNION ALL
 SELECT c.tai_khoan_id, c.ngay_tt AS ngay, 'chi'::text AS kieu, 0 AS vao, c.so_tien AS ra
   FROM kt_chi c WHERE NOT c.da_xoa AND c.trang_thai = 'da_tt'::text
UNION ALL
 SELECT d.tk_di_id AS tai_khoan_id, d.ngay, 'dc'::text AS kieu, 0 AS vao, d.so_tien AS ra
   FROM kt_dieu_chuyen d WHERE NOT d.da_xoa AND NOT kt_dc_cho_nhan(d.tk_nhan_id, d.tq_nhan_luc, d.tao_luc)
UNION ALL
 SELECT d.tk_nhan_id AS tai_khoan_id, d.ngay, 'dc'::text AS kieu, d.so_tien AS vao, 0 AS ra
   FROM kt_dieu_chuyen d WHERE NOT d.da_xoa AND NOT kt_dc_cho_nhan(d.tk_nhan_id, d.tq_nhan_luc, d.tao_luc)
UNION ALL
 SELECT n.tai_khoan_id, n.ngay, 'vay'::text AS kieu, n.so_tien AS vao, 0 AS ra
   FROM kt_vay_nhan n WHERE NOT n.da_xoa AND n.tai_khoan_id IS NOT NULL
UNION ALL
 SELECT r.tai_khoan_id, r.ngay, 'vay'::text AS kieu, 0 AS vao, r.goc + r.lai AS ra
   FROM kt_vay_tra r WHERE NOT r.da_xoa AND r.da_tra AND r.tai_khoan_id IS NOT NULL
UNION ALL
 SELECT tt.tk_id::integer AS tai_khoan_id, tt.ngay, 'chi'::text AS kieu, 0 AS vao, kt_tt_nn_ra(tt) AS ra
   FROM kt_tt_nn tt WHERE NOT tt.da_xoa AND tt.tk_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM kt_chi c WHERE c.id = tt.chi_id AND NOT c.da_xoa AND c.trang_thai = 'da_tt') AND kt_tt_nn_ra(tt) > 0;

create or replace function public.kt_so_quy_ngay(p_phien text, p_tk integer, p_ngay date)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'tong_quan') or kt_co_quyen(u, 'so_du') or kt_co_quyen(u, 'so_quy')) then raise exception 'Tài khoản chưa được cấp quyền xem dòng tiền' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'kieu', (x->>'id')::bigint) from (
    select jsonb_build_object('kieu', 'thu', 'id', t.id, 'nd', t.noi_dung, 'vao', t.so_tien, 'ra', 0, 'ca_nhan', t.khong_hach_toan) x
      from kt_thu t where not t.da_xoa and t.trang_thai = 'da_duyet' and t.tai_khoan_id = p_tk and t.ngay = p_ngay and not kt_an_thu(u, t.noi_dung)
    union all select jsonb_build_object('kieu', 'chi', 'id', c.id, 'nd', c.noi_dung, 'vao', 0, 'ra', c.so_tien, 'ca_nhan', c.khong_hach_toan, 'doi', c.thu_huong_ten)
      from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.tai_khoan_id = p_tk and c.ngay_tt = p_ngay and not kt_an_thu(u, c.noi_dung)
    union all select jsonb_build_object('kieu', 'dc', 'id', d.id, 'nd', d.noi_dung, 'vao', 0, 'ra', d.so_tien, 'ca_nhan', d.khong_hach_toan, 'doi', 'sang ' || (select ten from kt_tai_khoan where id = d.tk_nhan_id))
      from kt_dieu_chuyen d where not d.da_xoa and d.tk_di_id = p_tk and d.ngay = p_ngay and not kt_an_thu(u, d.noi_dung) and not kt_dc_cho_nhan(d.tk_nhan_id, d.tq_nhan_luc, d.tao_luc)
    union all select jsonb_build_object('kieu', 'dc', 'id', d.id, 'nd', d.noi_dung, 'vao', d.so_tien, 'ra', 0, 'ca_nhan', d.khong_hach_toan, 'doi', 'từ ' || (select ten from kt_tai_khoan where id = d.tk_di_id))
      from kt_dieu_chuyen d where not d.da_xoa and d.tk_nhan_id = p_tk and d.ngay = p_ngay and not kt_an_thu(u, d.noi_dung) and not kt_dc_cho_nhan(d.tk_nhan_id, d.tq_nhan_luc, d.tao_luc)
    union all select jsonb_build_object('kieu', 'vay', 'id', n.id, 'nd', 'Nhận tiền vay · ' || v.ten, 'vao', n.so_tien, 'ra', 0)
      from kt_vay_nhan n join kt_vay v on v.id = n.vay_id where not n.da_xoa and n.tai_khoan_id = p_tk and n.ngay = p_ngay
    union all select jsonb_build_object('kieu', 'vay', 'id', r.id, 'nd', 'Trả nợ vay · ' || v.ten, 'vao', 0, 'ra', r.goc + r.lai)
      from kt_vay_tra r join kt_vay v on v.id = r.vay_id where not r.da_xoa and r.da_tra and r.tai_khoan_id = p_tk and r.ngay = p_ngay
    union all select jsonb_build_object('kieu', 'tt', 'id', tt.id, 'nd', 'Thanh toán trung gian · ' || tt.so_tien_nt || ' ' || tt.tien_te
             || case when tt.tien_te <> 'VND' then ' × ' || tt.ty_gia else '' end || case when coalesce(tt.phi, 0) > 0 then ' + phí ' || tt.phi else '' end
             || coalesce(' · ' || (select string_agg(distinct e->>'ncc_ten', ', ') from jsonb_array_elements(tt.phan_bo) e), ''),
             'vao', 0, 'ra', kt_tt_nn_ra(tt), 'doi', tt.ben_nhan)
      from kt_tt_nn tt where not tt.da_xoa and tt.tk_id = p_tk and tt.ngay = p_ngay and not exists (select 1 from kt_chi c where c.id = tt.chi_id and not c.da_xoa and c.trang_thai = 'da_tt') and kt_tt_nn_ra(tt) > 0) s), '[]');
end $function$;

