-- 30/10/2026 anh: Tổng quan mục 3 — bấm Online / Offline của 1 nhóm hàng (hoặc Tổng cộng) → popup các hoá đơn cấu thành doanh số: ngày, khách, cơ sở, nguồn (kênh bán).
-- Cùng công thức nhóm hàng của kt_tq_don (dòng hàng quy về tổng hoá đơn, giá vốn chia theo SL × giá vốn). p_nhom null = mọi nhóm. — Monsieur Claude
create or replace function public.kt_tq_nhom_hd(p_phien text, p_tu date, p_den date, p_nhom text) returns jsonb
language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'tong_quan');
  return coalesce((select jsonb_agg(jsonb_build_object('ma', ma, 'ngay', ngay, 'cn', cn, 'khach', khach, 'kenh', kenh, 'trong', trong, 'on', onl,
                 'sl', sl, 'dt', round(dt), 'gv', round(gv)) order by ngay desc, ma desc) from (
    select h.ma, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, h.chi_nhanh cn, h.khach_ten khach,
           kt_kenh_ten(coalesce(kh.ten, ko.ten), h.chi_nhanh) kenh, coalesce(kh.ten, ko.ten) is null trong,
           kt_kenh_ten(coalesce(kh.ten, ko.ten), h.chi_nhanh) not in ('Bán trực tiếp tại cửa hàng', 'Khác') onl,
           sum((d->>'sl')::numeric) sl,
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
     where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
       and (p_nhom is null or kt_nhom_cha(coalesce(d->>'nhom', '(không nhóm)')) = p_nhom)
     group by h.id, h.ma, 2, 3, 4, 5, 6, 7) x), '[]');
end $f$;
revoke all on function public.kt_tq_nhom_hd(text, date, date, text) from public;
grant execute on function public.kt_tq_nhom_hd(text, date, date, text) to anon, authenticated;
