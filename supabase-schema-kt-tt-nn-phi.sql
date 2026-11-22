-- 16/11/2026 kế toán: "phí chuyển (thanh toán trung gian) từng lô tính luôn vào giá vốn". Phí mỗi lần chuyển (kt_tt_nn.phi, đ) chia theo tỷ lệ
-- nguyên tệ phân bổ cho từng PO / tổng nguyên tệ lần chuyển → PO thuộc hồ sơ nhập khẩu nào (kt_lo_nk_don.po_id; PO ở n hồ sơ thì chia đều) → dòng chi phí
-- tự động "Phí chuyển tiền thanh toán trung gian" (tính giá vốn) ở tab Chi phí + cột Chi phí danh sách hồ sơ. Phần chưa gắn PO (trả trước) chưa vào lô nào. — Monsieur Claude
create or replace function public.kt_lo_nk_phi_tt(p_lo bigint) returns jsonb
language sql stable security definer set search_path = public as $f$
  with lp as (select distinct d.po_id from kt_lo_nk_don d where d.lo_id = p_lo and not d.da_xoa and d.po_id is not null),
  nlo as (select d.po_id, count(distinct d.lo_id) n from kt_lo_nk_don d join kt_lo_nk l on l.id = d.lo_id and not l.da_xoa
           where not d.da_xoa and d.po_id in (select po_id from lp) group by 1),
  pb as (select t.id, t.ngay, t.ben_nhan, t.phi, t.so_tien_nt, (x->>'po_id')::bigint po_id, (x->>'so_tien_nt')::numeric nt
           from kt_tt_nn t cross join lateral jsonb_array_elements(t.phan_bo) x
          where not t.da_xoa and coalesce(t.phi, 0) > 0 and t.so_tien_nt > 0 and nullif(x->>'po_id', '') is not null),
  z as (select pb.id, pb.ngay, pb.ben_nhan, sum(pb.phi * pb.nt / pb.so_tien_nt / nlo.n) s from pb join nlo on nlo.po_id = pb.po_id group by 1, 2, 3)
  select coalesce(jsonb_agg(jsonb_build_object('id', null, 'ao', true, 'tt_id', z.id, 'loai', 'khac', 'ngay', z.ngay, 'tinh_gv', true, 'so_tien', round(z.s),
           'noi_dung', 'Phí chuyển tiền thanh toán trung gian' || coalesce(' · ' || z.ben_nhan, '')) order by z.ngay, z.id) filter (where round(z.s) > 0), '[]'::jsonb)
    from z
$f$;
revoke all on function public.kt_lo_nk_phi_tt(bigint) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.kt_lo_nk_ct(p_phien text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; l kt_lo_nk;
begin
  u := kt_chan(p_phien, 'ncc');
  select * into l from kt_lo_nk where id = p_id and not da_xoa;
  if l.id is null then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  return jsonb_build_object('lo', to_jsonb(l),
    'don', coalesce((select jsonb_agg(to_jsonb(d) || jsonb_build_object('gia_tri_vnd', kt_lo_nk_don_vnd(d, l),
        'ncc', jsonb_build_object('id', n.id, 'ma', n.ma, 'ten', n.ten, 'loai', n.loai, 'tien_te', n.them->>'tien_te', 'ty_gia', n.them->>'ty_gia'),
        'nhap', (select jsonb_build_object('id', h.id, 'ma', h.ma, 'ngay', h.ngay, 'tong', h.tong, 'chi_tiet', h.chi_tiet) from kt_kiot_nhap_hang h where h.id = d.nhap_id),
        'hs', (select jsonb_build_object('id', s.id, 'ten', s.ten, 'so_hd', s.so_hd) from kt_ho_so s where s.id = d.ho_so_id))
      order by d.ngay nulls last, d.id) from kt_lo_nk_don d join kt_ncc n on n.id = d.ncc_id where d.lo_id = p_id and not d.da_xoa), '[]'),
    'cp', coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object('chi', (select jsonb_build_object('id', k.id, 'ngay', coalesce(k.ngay_tt, k.ngay_de_nghi), 'noi_dung', k.noi_dung,
          'so_tien', k.so_tien, 'trang_thai', k.trang_thai, 'nguoi_nhan', coalesce(k.nguoi_nhan_tien, k.thu_huong_ten)) from kt_chi k where k.id = c.chi_id))
      order by c.ngay nulls last, c.id) from kt_lo_nk_cp c where c.lo_id = p_id and not c.da_xoa), '[]') || kt_lo_nk_phi_tt(p_id),
    'ct', coalesce((select jsonb_agg(jsonb_build_object('id', ct.id, 'ten', ct.ten_file, 'mime', ct.mime, 'tao_boi', ct.tao_boi, 'tao_luc', ct.tao_luc) order by ct.id)
      from kt_chung_tu ct where ct.bang = 'lo_nk' and ct.dong_id = p_id and not ct.da_xoa), '[]'));
end $function$
;

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
      'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'lo_nk' and ct.dong_id = l.id and not ct.da_xoa))
    order by coalesce(l.ngay_kh, l.tao_luc::date) desc, l.id desc) from kt_lo_nk l where not l.da_xoa), '[]');
end $function$
;
