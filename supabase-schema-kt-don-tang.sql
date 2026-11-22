-- 22/10/2026: rà Hiệu suất đơn T1–T10 (anh: "rà lại hết các tháng cho chuẩn"): 99 đơn Kiot hoàn thành 0đ = hàng tặng / mẫu / khuyến mãi / hỗ trợ / xuất dùng
-- (ghi chú Kiot) đang tính là "đã đi hàng" → tách nhóm 'tang', không tính số đơn / giá trị / tỷ lệ đi hàng. — Monsieur Claude

CREATE OR REPLACE FUNCTION public.kt_bc_qt(p_phien text, p_loai text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; r jsonb;
begin
  perform kt_chan(p_phien, 'pl');
  if p_loai = 'don' then
    -- đơn đặt tạo trong kỳ: chia nhóm như Tổng quan (kt_tq_don) · hoá đơn hoàn thành trong kỳ (có / không qua đơn đặt)
    return jsonb_build_object(
      'don', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select to_char((o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, o.chi_nhanh cn, kt_kenh_ten(kn.ten, o.chi_nhanh) kenh,
               case when o.trang_thai = 4 and coalesce(o.da_tra, 0) > 0 then 'huy' when o.trang_thai = 4 then 'bg_dong' when coalesce(o.tong, 0) = 0 and o.trang_thai = 3 then 'tang' when exists (select 1 from kt_kiot_hoa_don h2 where (h2.dat_hang_id = o.id or h2.ma_dat_hang = o.ma) and h2.cod and h2.trang_thai = 2) and not exists (select 1 from kt_kiot_hoa_don h3 where (h3.dat_hang_id = o.id or h3.ma_dat_hang = o.ma) and h3.trang_thai in (1, 3)) then 'huy' when o.trang_thai = 3 then 'di_hang' when v.tinh_trang = 'da_hd' then 'di_hang' when v.tinh_trang = 'nghi_di' then 'nghi_di' when v.tinh_trang in ('cho', 'treo') then 'coc' else 'bao_gia' end nhom,
               count(*) so, sum(o.tong) tong,
               sum(case when o.trang_thai not in (3, 4) then coalesce(v.coc, 0) else 0 end) coc
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id left join kt_v_don_coc v on v.id = o.id left join kt_kiot_kenh kn on kn.id = o.kenh_id
         where (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2, 3, 4) x),
      'hd', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, h.chi_nhanh cn, h.dat_hang_id is not null qua_don, count(*) so, sum(h.tong) tong
          from kt_kiot_hoa_don h where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2, 3) x),
      -- đơn đã cọc chưa đi hàng (mọi thời điểm) — doanh số chờ ghi nhận
      'cho', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select o.chi_nhanh cn, to_char((o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, count(*) so, sum(o.tong) tong, sum(v.coc) da_tra
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id left join kt_v_don_coc v on v.id = o.id
         where v.tinh_trang in ('cho', 'treo') group by 1, 2) x));
  elsif p_loai = 'du_kien' then
    return jsonb_build_object('nay', v_nay,
      'so_du', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'ten', t.ten, 'loai', t.loai, 'so_du', kt_so_du_ngay(t.id, v_nay))), '[]')
                  from kt_tai_khoan t where t.hoat_dong and t.loai <> 'vay' and t.ngay_ton_dau <= v_nay),
      'chi_cho', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'noi_dung', c.noi_dung, 'so_tien', c.so_tien, 'han', c.han_tt, 'trang_thai', c.trang_thai,
                    'ngay', c.ngay_de_nghi) order by coalesce(c.han_tt, c.ngay_de_nghi)), '[]')
                  from kt_chi c where not c.da_xoa and c.trang_thai in ('cho_duyet', 'cho_gd', 'cho_tt')),
      'vay_tra', (select coalesce(jsonb_agg(jsonb_build_object('ngay', t.ngay, 'goc', t.goc, 'lai', t.lai, 'ten', v.ten) order by t.ngay), '[]')
                  from kt_vay_tra t join kt_vay v on v.id = t.vay_id where not t.da_xoa and not v.da_xoa and not t.da_tra),
      'no_kh', (select coalesce(sum(cong_no), 0) from kt_kiot_khach where cong_no > 0),
      'no_ncc', (select coalesce(sum(cong_no), 0) from kt_kiot_ncc where cong_no <> 0),
      'don_coc', (select coalesce(sum(o.tong - coalesce(v.coc, 0)), 0) from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id left join kt_v_don_coc v on v.id = o.id
                   where v.tinh_trang in ('cho', 'treo')),
      -- bình quân 8 tuần gần nhất (để ước tính tuần tới)
      'thu_tuan', (select coalesce(sum(so_tien), 0) / 8 from kt_thu where not da_xoa and trang_thai = 'da_duyet' and ngay > v_nay - 56 and ngay <= v_nay),
      'chi_tuan', (select coalesce(sum(so_tien), 0) / 8 from kt_chi where not da_xoa and trang_thai = 'da_tt' and ngay_tt > v_nay - 56 and ngay_tt <= v_nay));
  elsif p_loai = 'ngan_sach' then
    return jsonb_build_object(
      'loai', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'nhom_bc', nhom_bc) order by ten), '[]') from kt_loai where nhom = 'chi' and hoat_dong),
      'ns', (select coalesce(jsonb_agg(jsonb_build_object('thang', thang, 'loai_id', loai_id, 'so_tien', so_tien)), '[]') from kt_ngan_sach
               where thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM')),
      'thuc', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai_id', lid, 'tien', s)), '[]') from (
          select h.thang th, h.loai_id lid, sum(h.tien) s from kt_v_chi_ht h
           where h.thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM')
           group by 1, 2) x));
  elsif p_loai = 'ton' then
    with ban as (select d->>'ma' ma, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1),
         ban90 as (select distinct d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date > v_nay - 90),
         hg as (select p.ma, p.ten, kt_nhom_cha(coalesce(p.nhom, '(không nhóm)')) nhom, greatest(p.tong_ton, 0) ton, greatest(p.gia_tri_ton, 0) gt,
                       (select max((t->>'gia_von')::numeric) from jsonb_array_elements(p.ton) t where (t->>'gia_von')::numeric > 0) gv from kt_kiot_hang p where p.dv_goc_id is null)
    select jsonb_build_object('so_ngay', least(p_den, v_nay) - p_tu + 1,
      'gv_ky', (select coalesce(sum(gia_von), 0) from kt_kiot_hoa_don where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
      'ton_cn', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'sl', sl, 'gt', gt, 'so_ma', n) order by gt desc), '[]') from (
          select t->>'cn' cn, sum((t->>'ton')::numeric) sl, sum((t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0)) gt, count(*) n
            from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and (t->>'ton')::numeric > 0 group by 1) x),
      'nhom', (select coalesce(jsonb_agg(to_jsonb(x) order by x.gt desc), '[]') from (
          select hg.nhom, sum(hg.gt) gt, sum(hg.ton) ton, count(*) filter (where hg.ton > 0) so_ma, coalesce(sum(b.dt), 0) dt, coalesce(sum(b.sl * coalesce(hg.gv, 0)), 0) gv_ban,
                 sum(hg.gt) filter (where hg.ton > 0 and not exists (select 1 from ban90 z where z.ma = hg.ma)) gt_cham
            from hg left join ban b on b.ma = hg.ma group by 1 having sum(hg.gt) > 0 or coalesce(sum(b.dt), 0) > 0) x),
      'cham', (select coalesce(jsonb_agg(to_jsonb(x) order by x.gt desc), '[]') from (
          select hg.ma, hg.ten, hg.nhom, hg.ton, hg.gt from hg where hg.ton > 0 and not exists (select 1 from ban90 z where z.ma = hg.ma) order by hg.gt desc limit 50) x),
      'cham_tong', (select jsonb_build_object('so_ma', count(*), 'gt', coalesce(sum(gt), 0)) from hg where hg.ton > 0 and not exists (select 1 from ban90 z where z.ma = hg.ma)))
      into r;
    return r;
  elsif p_loai = 'vay' then
    return jsonb_build_object(
      'vay', (select coalesce(jsonb_agg(jsonb_build_object('ten', v.ten, 'ben', v.ben_cho_vay, 'so_tien', v.so_tien, 'lai_suat', v.lai_suat, 'dao_han', v.ngay_dao_han, 'xong', v.da_tat_toan, 'nhan', coalesce((select sum(n.so_tien) from kt_vay_nhan n where n.vay_id = v.id and not n.da_xoa), 0),
                'goc_tra', coalesce((select sum(goc) from kt_vay_tra t where t.vay_id = v.id and not t.da_xoa and t.da_tra), 0))), '[]') from kt_vay v where not v.da_xoa),
      'lai', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'goc', g, 'lai', l)), '[]') from (
          select to_char(ngay, 'YYYY-MM') th, sum(goc) g, sum(lai) l from kt_vay_tra where not da_xoa and da_tra and ngay between p_tu and p_den group by 1) x),
      'chi_tc', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', l, 'tien', s)), '[]') from (
          select h.thang th, lo.ten l, sum(h.tien) s from kt_v_chi_ht h join kt_loai lo on lo.id = h.loai_id
           where h.thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM') and (lo.nhom_bc = 'Chi tài chính' or lo.ten ~* '^FINANCE') group by 1, 2) x));
  elsif p_loai = 'cs' then
    return jsonb_build_object(
      'dt', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'dt', dt, 'gv', gv, 'so', so)), '[]') from (
          select to_char((ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, chi_nhanh cn, sum(tong) dt, sum(gia_von) gv, count(*) so from kt_kiot_hoa_don
           where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
      -- giá vốn hàng trả = tiền trả × (giá vốn / tổng) của hoá đơn gốc — như P&L (kt_bc_pl2)
      'tra', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'tra', s, 'gv', gv)), '[]') from (
          select to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, t.chi_nhanh cn, sum(t.tong_tra) s, round(sum(t.tong_tra * coalesce(h.gia_von / nullif(h.tong, 0), 0))) gv
            from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
           where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
      -- chi phí theo kỳ hạch toán (16/10/2026), chia theo đơn vị chịu chi phí (phan_bo) — tháng theo phân bổ tháng nếu có
      'cp', (select coalesce(jsonb_agg(jsonb_build_object('dv', dv, 'tien', s, 'nhom_bc', nb)), '[]') from (
          select h.don_vi_id dv, lo.nhom_bc nb, sum(h.tien) s
            from kt_v_chi_ht h join kt_loai lo on lo.id = h.loai_id
           where h.don_vi_id is not null and h.thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM')
           group by 1, 2) x),
      'cp_khong_pb', (select coalesce(sum(h.tien), 0) from kt_v_chi_ht h where h.don_vi_id is null
                       and h.thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM')),
      'kenh', (select coalesce(jsonb_agg(jsonb_build_object('kenh', ten, 'cn', cn, 'dt', dt, 'so', so)), '[]') from (
          select kt_kenh_ten(k.ten, h.chi_nhanh) ten, h.chi_nhanh cn, sum(h.tong) dt, count(*) so
            from kt_kiot_hoa_don h left join kt_kiot_kenh k on k.id = h.kenh_id
           where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x));
  end if;
  raise exception 'Loại báo cáo không hợp lệ';
end $function$;

CREATE OR REPLACE FUNCTION public.kt_tq_don(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'tong_quan');
  return jsonb_build_object(
    'kenh', (select coalesce(jsonb_agg(jsonb_build_object('ten', ten, 'cn', cn, 'dt', dt, 'so', so) order by dt desc), '[]') from (
        select kt_kenh_ten(k.ten, h.chi_nhanh) ten, h.chi_nhanh cn, sum(h.tong) dt, count(*) so
          from kt_kiot_hoa_don h left join kt_kiot_kenh k on k.id = h.kenh_id
         where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    -- nhóm CHA: doanh thu dòng hàng quy về tổng hoá đơn (đã trừ giảm giá HĐ); giá vốn HĐ chia cho các dòng theo tỷ lệ (SL × giá vốn hiện tại)
    'nhom', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'cn', cn, 'dt', round(dt), 'gv', round(gv)) order by dt desc), '[]') from (
        select kt_nhom_cha(coalesce(d->>'nhom', '(không nhóm)')) nhom, h.chi_nhanh cn,
               sum((d->>'tien')::numeric * h.tong / nullif(t.tien, 0)) dt,
               sum(coalesce(h.gia_von, 0) * coalesce(c.gv / nullif(t.gv, 0), (d->>'tien')::numeric / nullif(t.tien, 0))) gv
          from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
          left join lateral (select (d->>'sl')::numeric * coalesce((select (e->>'gia_von')::numeric from kt_kiot_hang p, jsonb_array_elements(p.ton) e
                               where p.id = (d->>'sp')::bigint and e->>'cn' = h.chi_nhanh limit 1), 0) gv) c on true
          cross join lateral (select sum((x->>'tien')::numeric) tien,
                 sum((x->>'sl')::numeric * coalesce((select (e->>'gia_von')::numeric from kt_kiot_hang p, jsonb_array_elements(p.ton) e
                               where p.id = (x->>'sp')::bigint and e->>'cn' = h.chi_nhanh limit 1), 0)) gv from jsonb_array_elements(h.chi_tiet) x) t
         where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    -- đơn đặt hàng tạo trong kỳ: đã đi hàng (Hoàn thành) / đã cọc chưa đi hàng / báo giá (không dấu vết tiền) / huỷ
    'don_ky', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'cn', cn, 'so', so, 'tong', tong, 'coc', coc)), '[]') from (
        select case when o.trang_thai = 4 and coalesce(o.da_tra, 0) > 0 then 'huy' when o.trang_thai = 4 then 'bg_dong' when coalesce(o.tong, 0) = 0 and o.trang_thai = 3 then 'tang' when exists (select 1 from kt_kiot_hoa_don h2 where (h2.dat_hang_id = o.id or h2.ma_dat_hang = o.ma) and h2.cod and h2.trang_thai = 2) and not exists (select 1 from kt_kiot_hoa_don h3 where (h3.dat_hang_id = o.id or h3.ma_dat_hang = o.ma) and h3.trang_thai in (1, 3)) then 'huy' when o.trang_thai = 3 then 'di_hang'
                    when v.tinh_trang = 'da_hd' then 'di_hang' when v.tinh_trang = 'nghi_di' then 'nghi_di' when v.tinh_trang in ('cho', 'treo') then 'coc' else 'bao_gia' end nhom, o.chi_nhanh cn,
               count(*) so, sum(o.tong) tong, sum(case when o.trang_thai not in (3, 4) then coalesce(v.coc, 0) else 0 end) coc
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id left join kt_v_don_coc v on v.id = o.id
         where (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    -- TẤT CẢ đơn đã cọc chưa đi hàng (không theo kỳ) — doanh thu dự kiến
    'coc_cho', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'ma', o.ma, 'ngay', (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', o.chi_nhanh,
                 'khach', o.khach_ten, 'nv', o.nv_ban, 'tong', o.tong, 'da_tra', o.da_tra, 'tra_truoc', coalesce(v.coc_tt, 0),
                 'ghi_chu', o.ghi_chu, 'coc', v.coc, 'tinh_trang', v.tinh_trang, 'ngay_hd', v.ngay_hd, 'hd_ma', v.hd_ma) order by o.ngay desc), '[]')
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id left join kt_v_don_coc v on v.id = o.id
         where v.tinh_trang in ('cho', 'treo')),
    -- 16/10/2026: đơn trước đây bị tính "đã cọc chưa đi hàng" nhưng thực ra đã có hoá đơn (gắn đơn / nghi đã đi hàng) — để kế toán soát
    'coc_loai', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'ma', o.ma, 'ngay', (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', o.chi_nhanh,
                 'khach', o.khach_ten, 'nv', o.nv_ban, 'tong', o.tong, 'da_tra', o.da_tra, 'ghi_chu', o.ghi_chu, 'tinh_trang', v.tinh_trang, 'ngay_hd', v.ngay_hd, 'hd_ma', v.hd_ma)
                 order by o.ngay desc), '[]')
          from kt_kiot_dat_hang o join kt_v_don_coc v on v.id = o.id where v.tinh_trang in ('da_hd', 'nghi_di')));
end $function$;
