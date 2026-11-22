-- 27/10/2026 (anh, kế toán phản hồi): "tiền từ phiếu điều chuyển chuyển vào két khi thủ quỹ CHƯA ấn nhận tiền thì chưa đếm vào đâu,
-- bên kế toán đang phản hồi chưa ấn mà đã thêm vào rồi làm cuối ngày toàn bị lệch".
-- Trước (quy tắc 20/10): chưa bấm nhận vẫn tính vào số dư két (bấm nhận chỉ dời ngày phiếu sang ngày nhận — 22/10).
-- Nay: điều chuyển VÀO KÉT (tài khoản tiền mặt thủ quỹ chi) chưa bấm "Đã nhận" → KHÔNG tính cả 2 bên (không trừ TK đi, không cộng két)
-- trong số dư (kt_v_bien_dong → kt_so_du_ngay, kiểm két, Tổng quan, Sổ quỹ) và sổ quỹ theo ngày. Bấm nhận → tính cả 2 bên, ngày = ngày nhận.
-- Chỉ áp phiếu tạo từ 20/10/2026 (ngày có nút nhận); phiếu trước đó chưa từng có bước nhận → tính như cũ. — Monsieur Claude
create or replace function public.kt_dc_cho_nhan(p_tk_nhan int, p_tq_nhan timestamptz, p_tao timestamptz) returns boolean
 language sql stable set search_path to 'public' as $$
  select p_tq_nhan is null and p_tao >= timestamptz '2026-10-20 00:00:00+07'
     and exists (select 1 from kt_tai_khoan t where t.id = p_tk_nhan and t.loai = 'tien_mat' and t.thu_quy_chi);
$$;
revoke all on function public.kt_dc_cho_nhan(int, timestamptz, timestamptz) from public, anon, authenticated;

create or replace view public.kt_v_bien_dong as
 SELECT t.tai_khoan_id, t.ngay, 'thu'::text AS kieu, t.so_tien AS vao, 0::numeric AS ra FROM kt_thu t WHERE NOT t.da_xoa AND t.trang_thai = 'da_duyet'::text
UNION ALL
 SELECT c.tai_khoan_id, c.ngay_tt AS ngay, 'chi'::text AS kieu, 0 AS vao, c.so_tien AS ra FROM kt_chi c WHERE NOT c.da_xoa AND c.trang_thai = 'da_tt'::text
UNION ALL
 SELECT d.tk_di_id AS tai_khoan_id, d.ngay, 'dc'::text AS kieu, 0 AS vao, d.so_tien AS ra FROM kt_dieu_chuyen d
  WHERE NOT d.da_xoa AND NOT kt_dc_cho_nhan(d.tk_nhan_id, d.tq_nhan_luc, d.tao_luc)
UNION ALL
 SELECT d.tk_nhan_id AS tai_khoan_id, d.ngay, 'dc'::text AS kieu, d.so_tien AS vao, 0 AS ra FROM kt_dieu_chuyen d
  WHERE NOT d.da_xoa AND NOT kt_dc_cho_nhan(d.tk_nhan_id, d.tq_nhan_luc, d.tao_luc)
UNION ALL
 SELECT n.tai_khoan_id, n.ngay, 'vay'::text AS kieu, n.so_tien AS vao, 0 AS ra FROM kt_vay_nhan n WHERE NOT n.da_xoa AND n.tai_khoan_id IS NOT NULL
UNION ALL
 SELECT r.tai_khoan_id, r.ngay, 'vay'::text AS kieu, 0 AS vao, r.goc + r.lai AS ra FROM kt_vay_tra r WHERE NOT r.da_xoa AND r.da_tra AND r.tai_khoan_id IS NOT NULL;

-- Sổ quỹ theo ngày: bỏ điều chuyển vào két chưa nhận (như số dư)
CREATE OR REPLACE FUNCTION public.kt_so_quy_ngay(p_phien text, p_tk integer, p_ngay date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      from kt_vay_tra r join kt_vay v on v.id = r.vay_id where not r.da_xoa and r.da_tra and r.tai_khoan_id = p_tk and r.ngay = p_ngay) s), '[]');
end $function$;
