-- 30/10/2026 anh: Tổng quan mục 3 "Doanh thu theo nhóm hàng" — mỗi nhóm tách online / offline theo nguồn đơn Kiot. — Monsieur Claude
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
    'nhom', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'cn', cn, 'on', onl, 'dt', round(dt), 'gv', round(gv)) order by dt desc), '[]') from (
        select kt_nhom_cha(coalesce(d->>'nhom', '(không nhóm)')) nhom, h.chi_nhanh cn,
               -- 30/10/2026 anh: tách online / offline theo nguồn đơn Kiot (kênh bán trên hoá đơn, hoá đơn trống thì lấy kênh của đơn đặt hàng gắn) — như P&L: trực tiếp / Khác / trống = offline
               kt_kenh_ten(coalesce(kh.ten, ko.ten), h.chi_nhanh) not in ('Bán trực tiếp tại cửa hàng', 'Khác') onl,
               sum((d->>'tien')::numeric * h.tong / nullif(t.tien, 0)) dt,
               sum(coalesce(h.gia_von, 0) * coalesce(c.gv / nullif(t.gv, 0), (d->>'tien')::numeric / nullif(t.tien, 0))) gv
          from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
          left join kt_kiot_kenh kh on kh.id = h.kenh_id
          left join lateral (select k2.ten from kt_kiot_dat_hang o2 join kt_kiot_kenh k2 on k2.id = o2.kenh_id where h.kenh_id is null and h.dat_hang_id = o2.id limit 1) ko on true
          left join lateral (select (d->>'sl')::numeric * coalesce((select (e->>'gia_von')::numeric from kt_kiot_hang p, jsonb_array_elements(p.ton) e
                               where p.id = (d->>'sp')::bigint and e->>'cn' = h.chi_nhanh limit 1), 0) gv) c on true
          cross join lateral (select sum((x->>'tien')::numeric) tien,
                 sum((x->>'sl')::numeric * coalesce((select (e->>'gia_von')::numeric from kt_kiot_hang p, jsonb_array_elements(p.ton) e
                               where p.id = (x->>'sp')::bigint and e->>'cn' = h.chi_nhanh limit 1), 0)) gv from jsonb_array_elements(h.chi_tiet) x) t
         where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2, 3) x),
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
