-- 20/10/2026 (anh: "phiếu test để ngầm hết, đừng cho hiện ra"): phiếu kiểm thử (nội dung bắt đầu "THỬ HỆ THỐNG") chỉ TK tạm (tam-...) thấy,
-- người thật không thấy trong danh sách và không nhận thông báo. Monsieur Claude
create or replace function kt_an_thu(u kt_nguoi_dung, p_nd text) returns boolean language sql stable set search_path = public as $$
  select coalesce(p_nd, '') like 'THỬ HỆ THỐNG%' and coalesce(u.ten_dang_nhap, '') not like 'tam-%' $$;
revoke all on function kt_an_thu(kt_nguoi_dung, text) from public, anon;
CREATE OR REPLACE FUNCTION public.kt_ds(p_phien text, p_bang text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_tat boolean;
begin
  if p_bang = 'chi' then
    u := kt_chan(p_phien);
    v_tat := kt_co_quyen(u, 'chi');
    if not v_tat and not kt_co_quyen(u, 'chi_de_nghi') and not kt_co_quyen(u, 'chi_tt') then
      raise exception 'Tài khoản chưa được cấp quyền xem trang này' using errcode = '42501';
    end if;
    return coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object('so_ct', (select count(*) from kt_chung_tu k
        where k.bang = 'chi' and k.dong_id = c.id and not k.da_xoa), 'nghi_loai', kt_nghi_loai(c), 'thieu_unc', kt_thieu_unc(c), 'nhac_mo', kt_nhac_mo('chi', c.id)) order by coalesce(c.ngay_tt, c.ngay_de_nghi) desc, c.id desc) from kt_chi c
      where not da_xoa and not kt_an_thu(u, c.noi_dung) and (v_tat or c.tao_boi = u.ho_ten
          or (kt_co_quyen(u, 'chi_tt') and c.trang_thai in ('cho_tt','da_tt') and exists (select 1 from kt_tai_khoan t where t.id = c.tai_khoan_id and t.thu_quy_chi))
          or (kt_co_quyen(u, 'chi_tt') and c.trang_thai = 'da_tt' and c.co_hd_do)) and (ngay_de_nghi between p_tu and p_den or ngay_tt between p_tu and p_den
        or trang_thai in ('cho_duyet','cho_gd','cho_tt'))), '[]');
  end if;
  u := kt_chan(p_phien, p_bang);
  if p_bang = 'thu' then
    return coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('so_ct', (select count(*) from kt_chung_tu k
        where k.bang = 'thu' and k.dong_id = t.id and not k.da_xoa), 'nhac_mo', kt_nhac_mo('thu', t.id)) order by t.ngay desc, t.id desc) from kt_thu t
      where not da_xoa and not kt_an_thu(u, t.noi_dung) and ngay between p_tu and p_den), '[]');
  elsif p_bang = 'dieu_chuyen' then
    return coalesce((select jsonb_agg(to_jsonb(d) || jsonb_build_object('so_ct', (select count(*) from kt_chung_tu k
        where k.bang = 'dieu_chuyen' and k.dong_id = d.id and not k.da_xoa)) order by d.ngay desc, d.id desc) from kt_dieu_chuyen d
      where not da_xoa and not kt_an_thu(u, d.noi_dung) and ngay between p_tu and p_den), '[]');
  elsif p_bang = 'cong_no' then
    return coalesce((select jsonb_agg(x order by x->>'ngay' desc) from (
      select to_jsonb(n) || jsonb_build_object('da_thu', coalesce(t.da_thu, 0), 'lan_thu', coalesce(t.lan, '[]'::jsonb),
        'con_no', n.so_tien - n.tra_hang - coalesce(t.da_thu, 0)) x
      from kt_cong_no n
      left join lateral (select sum(so_tien) da_thu, jsonb_agg(jsonb_build_object('id', id, 'ngay', ngay, 'so_tien', so_tien,
          'ghi_chu', ghi_chu) order by ngay) lan from kt_cong_no_thu where cong_no_id = n.id and not da_xoa) t on true
      where not n.da_xoa and (n.ngay between p_tu and p_den or n.so_tien - n.tra_hang - coalesce(t.da_thu, 0) <> 0)) s), '[]');
  elsif p_bang = 'sap_tra' then
    return coalesce((select jsonb_agg(to_jsonb(s) order by s.da_tra, s.han nulls last) from kt_sap_tra s where not da_xoa), '[]');
  end if;
  raise exception 'Bảng không hợp lệ';
end $function$;
create or replace function public.kt_bao(p_nguoi integer[], p_tu text, p_loai text, p_tieu_de text, p_noi_dung text, p_bang text, p_dong_id bigint)
 returns void language sql security definer set search_path to 'public' as $function$
  insert into kt_thong_bao (nguoi_dung_id, tu, loai, tieu_de, noi_dung, bang, dong_id)
  select distinct x, p_tu, p_loai, p_tieu_de, p_noi_dung, p_bang, p_dong_id from unnest(p_nguoi) x
   where x is not null
     and (not (coalesce(p_noi_dung, '') like 'THỬ HỆ THỐNG%' or coalesce(p_tieu_de, '') like 'THỬ HỆ THỐNG%'
           or (p_bang = 'chi' and exists (select 1 from kt_chi c where c.id = p_dong_id and c.noi_dung like 'THỬ HỆ THỐNG%'))
           or (p_bang = 'thu' and exists (select 1 from kt_thu t where t.id = p_dong_id and t.noi_dung like 'THỬ HỆ THỐNG%'))
           or (p_bang = 'dieu_chuyen' and exists (select 1 from kt_dieu_chuyen d where d.id = p_dong_id and d.noi_dung like 'THỬ HỆ THỐNG%')))
          or exists (select 1 from kt_nguoi_dung n where n.id = x and n.ten_dang_nhap like 'tam-%'));
$function$;
