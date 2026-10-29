-- POPUP CHI TIẾT PHIẾU NHẬP (29/10/2026 ảnh mẫu): kt_ncc_ct trả thêm giảm giá + chi tiết hàng hoá (mã, tên, SL, giá) của phiếu nhập Kiot. Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_ncc_ct(p_phien text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; n kt_ncc; v_chi bigint[]; v_hs bigint[];
begin
  u := kt_chan(p_phien, 'ncc');
  select * into n from kt_ncc where id = p_id and not da_xoa;
  if n.id is null then raise exception 'Không thấy nhà cung cấp'; end if;
  select coalesce(array_agg(dong_id), '{}') into v_chi from kt_v_ncc_phieu where ncc_id = p_id and bang = 'chi';
  select coalesce(array_agg(id), '{}') into v_hs from kt_ho_so where ncc_id = p_id and not da_xoa;
  return jsonb_build_object(
    'ncc', to_jsonb(n) || jsonb_build_object('nguon', case when n.kiot_id is null then 'app' else 'kiot' end)
           || coalesce((select jsonb_build_object('cong_no', k.cong_no, 'tong_nhap', k.tong_nhap, 'tong_nhap_tru_tra', k.tong_nhap_tru_tra) from kt_kiot_ncc k where k.id = n.kiot_id), '{}'),
    'so', kt_ncc_so(p_id),
    'ho_so', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'ten', h.ten, 'loai', h.loai, 'so_hd', h.so_hd, 'ngay', h.ngay, 'gia_tri', h.gia_tri,
        'trang_thai', h.trang_thai, 'ghi_chu', h.ghi_chu, 'tao_boi', h.tao_boi,
        'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'ho_so' and ct.dong_id = h.id and not ct.da_xoa)) order by coalesce(h.ngay, h.tao_luc::date) desc, h.id desc)
      from kt_ho_so h where h.ncc_id = p_id and not h.da_xoa), '[]'),
    'phieu', coalesce((select jsonb_agg(x order by x->>'ngay' desc nulls last, (x->>'id')::bigint desc) from (
        select jsonb_build_object('bang', 'chi', 'id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'noi_dung', c.noi_dung, 'so_tien', c.so_tien,
          'trang_thai', c.trang_thai, 'nguoi_nhan', c.thu_huong_ten, 'stk', c.thu_huong_stk, 'tai_khoan_id', c.tai_khoan_id, 'loai_id', c.loai_id,
          'ho_so_id', p.ho_so_id, 'cach', p.cach, 'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'chi' and ct.dong_id = c.id and not ct.da_xoa)) x
          from kt_v_ncc_phieu p join kt_chi c on c.id = p.dong_id where p.bang = 'chi' and p.ncc_id = p_id
        union all
        select jsonb_build_object('bang', 'thu', 'id', t.id, 'ngay', t.ngay, 'noi_dung', t.noi_dung, 'so_tien', t.so_tien, 'trang_thai', t.trang_thai,
          'tai_khoan_id', t.tai_khoan_id, 'loai_id', t.loai_id, 'ho_so_id', p.ho_so_id, 'cach', p.cach,
          'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'thu' and ct.dong_id = t.id and not ct.da_xoa))
          from kt_v_ncc_phieu p join kt_thu t on t.id = p.dong_id where p.bang = 'thu' and p.ncc_id = p_id) z), '[]'),
    'tl', coalesce((select jsonb_object_agg(t.ct_id, jsonb_build_object('thu_muc', t.thu_muc, 'so_hieu', t.so_hieu, 'ngay_bh', t.ngay_bh, 'hl_tu', t.hl_tu, 'hl_den', t.hl_den, 'mo_ta', t.mo_ta, 'ho_so_id', t.ho_so_id, 'sua_boi', t.sua_boi, 'sua_luc', t.sua_luc))
        from kt_tai_lieu t where t.ncc_id = p_id), '{}'),
    'pb', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'chi_id', b.chi_id, 'nhap_id', b.nhap_id, 'so_tien', b.so_tien, 'tao_boi', b.tao_boi)) from kt_ncc_phan_bo b where b.ncc_id = p_id), '[]'),
    'dm', (select nullif(gia_tri, '')::jsonb from kt_cai_dat where khoa = 'tl_danh_muc'),
    'thu_muc', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'ten', m.ten, 'cha', m.cha) order by m.id) from kt_ncc_thu_muc m where m.ncc_id = p_id and not m.da_xoa), '[]'),
    'han', coalesce((select nullif(gia_tri, '')::int from kt_cai_dat where khoa = 'han_no_ncc_ngay'), 30),
    'no', case when n.kiot_id is not null then kt_cong_no_dt_ct(p_phien, 'ncc', n.kiot_id) end,
    'nhap', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'ngay', h.ngay, 'chi_nhanh', h.chi_nhanh, 'tong', h.tong, 'da_tra', h.da_tra, 'trang_thai', h.trang_thai, 'mo_ta', h.mo_ta,
          'ho_so_id', (select g.ho_so_id from kt_ncc_gan g where g.bang = 'nhap' and g.dong_id = h.id), 'giam_gia', h.giam_gia, 'chi_tiet', h.chi_tiet)
        order by h.ngay desc) from kt_kiot_nhap_hang h where n.kiot_id is not null and h.ncc_id = n.kiot_id), '[]'),
    'ct', coalesce((select jsonb_agg(jsonb_build_object('id', ct.id, 'bang', ct.bang, 'dong_id', ct.dong_id, 'ten', ct.ten_file, 'mime', ct.mime, 'tao_boi', ct.tao_boi, 'tao_luc', ct.tao_luc) order by ct.tao_luc desc)
        from kt_chung_tu ct where not ct.da_xoa and ((ct.bang = 'chi' and ct.dong_id = any (v_chi)) or (ct.bang = 'ho_so' and ct.dong_id = any (v_hs)) or (ct.bang = 'ncc' and ct.dong_id = p_id)
          or (ct.bang = 'thu' and ct.dong_id in (select dong_id from kt_v_ncc_phieu where ncc_id = p_id and bang = 'thu')))), '[]'));
end $function$;
