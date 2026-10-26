-- 26/10/2026 (kế toán, anh chuyển): "tồn kho nội bộ chia theo nhóm cha" — Tổng quan mục 6 đang lấy 3 nhóm tồn nhiều nhất theo nhóm CON.
-- kt_tq_bo_sung: nhóm tồn → kt_nhom_cha(…) (như mục doanh thu theo nhóm cha); kt_drill 'nhom': khớp nhóm con HOẶC nhóm cha (bấm nhóm cha ra đủ hàng).
-- Định nghĩa lấy từ CSDL 26/10, chỉ thay 2 chỗ trên. — Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_tq_bo_sung(p_phien text, p_tu date, p_den date, p_tu0 date, p_den0 date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'tong_quan');
  with hd as (select * from kt_kiot_hoa_don where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
  hd0 as (select khach_id, sum(tong) dt from kt_kiot_hoa_don where trang_thai in (1, 3) and khach_id is not null
            and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu0 and p_den0 group by 1),
  kh as (select khach_id, max(khach_ma) ma, max(khach_ten) ten, sum(tong) dt, count(*) so, mode() within group (order by chi_nhanh) cn
           from hd where khach_id is not null group by 1 order by sum(tong) desc limit 5),
  ct as (select hd.chi_nhanh, d from hd cross join lateral jsonb_array_elements(hd.chi_tiet) d),
  sp as (select d->>'ma' ma, max(d->>'ten') ten, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt, mode() within group (order by chi_nhanh) cn
           from ct group by 1 order by sum((d->>'tien')::numeric) desc limit 5),
  ban180 as (select distinct h.chi_nhanh cn, d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
               where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_den - 180 and p_den),
  ton as (select t->>'cn' cn, p.ma, kt_nhom_cha(coalesce(p.nhom, '(không nhóm)')) nhom, (t->>'ton')::numeric sl, (t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0) gt
            from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and (t->>'ton')::numeric > 0)
  select jsonb_build_object(
    'top_kh', (select coalesce(jsonb_agg(jsonb_build_object('id', kh.khach_id, 'ma', kh.ma, 'ten', kh.ten, 'dt', kh.dt, 'so', kh.so, 'cn', kh.cn, 'dt0', coalesce(hd0.dt, 0)) order by kh.dt desc), '[]')
                 from kh left join hd0 on hd0.khach_id = kh.khach_id),
    'top_sp', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'sl', sl, 'dt', dt, 'cn', cn) order by dt desc), '[]') from sp),
    -- 14/10 (kế toán): thêm 3 nhóm hàng tồn nhiều tiền nhất ở từng kho
    'ton_cs', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'gt', gt, 'so_ma', so_ma, 'lau_so', lau_so, 'lau_gt', lau_gt,
        'nhom_top', (select coalesce(jsonb_agg(jsonb_build_object('nhom', n.nhom, 'gt', n.gt) order by n.gt desc), '[]') from (select nhom, sum(gt) gt from ton t2 where t2.cn = x.cn group by 1 order by 2 desc limit 3) n)) order by gt desc), '[]') from (
                 select t.cn, sum(t.gt) gt, count(*) so_ma, count(*) filter (where b.ma is null) lau_so, coalesce(sum(t.gt) filter (where b.ma is null), 0) lau_gt
                   from ton t left join ban180 b on b.cn = t.cn and b.ma = t.ma group by 1) x)) into r;
  return r;
end $function$
;

CREATE OR REPLACE FUNCTION public.kt_drill(p_phien text, p_loai text, p_khoa text, p_tu date, p_den date, p_cn text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  -- quyền theo trang tương ứng: chi phí → Chi · khách / hoá đơn → Khách hàng · tồn → Hàng hoá · nhóm / mặt hàng → Bán hàng
  perform kt_chan(p_phien, case p_loai when 'cp' then 'chi' when 'kh' then 'khach_hang' when 'hd' then 'khach_hang' when 'ton_lau' then 'hang_hoa' else 'ban_hang' end);
  if p_loai = 'nhom' then
    with ct as (select h.chi_nhanh, d from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                 where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
                   and (coalesce(d->>'nhom', '(không nhóm)') = p_khoa or kt_nhom_cha(coalesce(d->>'nhom', '(không nhóm)')) = p_khoa) and (p_cn is null or h.chi_nhanh = p_cn))
    select coalesce(jsonb_agg(jsonb_build_object('ma', g.ma, 'ten', g.ten, 'sl', g.sl, 'dt', g.dt, 'ton', (select tong_ton from kt_kiot_hang p where p.ma = g.ma limit 1)) order by g.dt desc), '[]') into r
      from (select ct.d->>'ma' ma, max(ct.d->>'ten') ten, sum((ct.d->>'sl')::numeric) sl, sum((ct.d->>'tien')::numeric) dt from ct group by 1 order by 4 desc limit 200) g;
  elsif p_loai = 'sp' then
    select jsonb_build_object(
      'sp', (select jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'dvt', don_vi, 'gia_ban', gia_ban, 'tong_ton', tong_ton, 'gia_tri_ton', gia_tri_ton, 'ton', ton) from kt_kiot_hang where ma = p_khoa limit 1),
      'ban_cs', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'sl', sl, 'dt', dt) order by dt desc), '[]') from (
          select h.chi_nhanh cn, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
           where h.trang_thai in (1, 3) and d->>'ma' = p_khoa and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1) x),
      'hd', (select coalesce(jsonb_agg(x order by x->>'ngay' desc), '[]') from (
          select jsonb_build_object('ma', h.ma, 'ngay', (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', h.chi_nhanh, 'khach', h.khach_ten, 'sl', (d->>'sl')::numeric, 'tien', (d->>'tien')::numeric) x
            from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d where h.trang_thai in (1, 3) and d->>'ma' = p_khoa order by h.ngay desc limit 15) t)) into r;
  elsif p_loai = 'kh' then
    select jsonb_build_object(
      'kh', (select jsonb_build_object('id', id, 'ma', ma, 'ten', ten, 'sdt', sdt, 'cong_no', cong_no, 'tong_mua', tong_mua) from kt_kiot_khach where id = p_khoa::bigint),
      'hd', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'tong', tong, 'da_tra', da_tra, 'nv', nv_ban,
          'so_mh', jsonb_array_length(chi_tiet)) order by ngay desc), '[]') from kt_kiot_hoa_don
         where khach_id = p_khoa::bigint and trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den)) into r;
  elsif p_loai = 'hd' then
    select jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'khach', khach_ten, 'khach_id', khach_id, 'nv', nv_ban,
      'tong', tong, 'da_tra', da_tra, 'gia_von', gia_von, 'trang_thai', trang_thai_ten, 'dong', chi_tiet) into r from kt_kiot_hoa_don where ma = p_khoa limit 1;
  elsif p_loai = 'ton_lau' then
    with ban as (select distinct d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai in (1, 3) and h.chi_nhanh = p_cn and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_den - 180 and p_den),
    ton as (select p.ma, p.ten, p.nhom, (t->>'ton')::numeric sl, (t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0) gt
              from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and t->>'cn' = p_cn and (t->>'ton')::numeric > 0)
    select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'sl', sl, 'gt', gt,
        'ban_cuoi', (select max((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date) from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                      where h.trang_thai in (1, 3) and h.chi_nhanh = p_cn and d->>'ma' = ton.ma)) order by gt desc), '[]') into r
      from (select * from ton where ma not in (select ma from ban where ma is not null) order by gt desc limit 100) ton;
  elsif p_loai = 'cp' then
    select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ngay', coalesce(c.ngay_su_dung, c.ngay_de_nghi), 'thang', pb.thang, 'tt', c.trang_thai, 'nd', c.noi_dung, 'th', c.thu_huong_ten, 'loai', l.ten, 'tien', coalesce(pb.tien, c.so_tien), 'dv', dv.ten)
        order by coalesce(pb.tien, c.so_tien) desc), '[]') into r
      from kt_chi c join kt_loai l on l.id = c.loai_id
      join lateral (select h.don_vi_id dv_id, sum(h.tien) tien, min(h.thang) thang from kt_v_chi_ht h
                    where h.chi_id = c.id and h.thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM') group by 1) pb on true
      left join kt_don_vi dv on dv.id = pb.dv_id
     where l.nhom_bc = 'Chi vận hành & quản lí'
       and (coalesce(p_khoa, '') = '' or l.ten = p_khoa)
       and (p_cn is null or (p_cn = '_chung' and coalesce(array_length(dv.kiot_chi_nhanh, 1), 0) = 0) or p_cn = any(dv.kiot_chi_nhanh));
  end if;
  return coalesce(r, 'null'::jsonb);
end $function$
;
