-- 26/11/2026 kế toán: "P&L đang tính theo doanh thu nhưng trừ VAT lại đang theo dòng tiền => sai".
-- Trước: VAT = phiếu "Tiền khách trả" vào TK 599 TRONG THÁNG (ngày tiền về, gồm cọc chưa ra hoá đơn, trả nợ hoá đơn tháng trước) × tỷ lệ.
-- Nay (cùng mốc với dòng doanh thu = hoá đơn theo ngày hoá đơn): VAT tháng = Σ hoá đơn trong tháng × phần hoá đơn khách trả vào TK 599
-- (mọi ngày: tiền gắn hoá đơn + thu cục phân bổ + cọc TTDH của đơn đặt, tối đa 1) × tỷ lệ của chính hoá đơn (8%, phần đèn điện thờ / chuông mõ 10%)
-- − trả hàng trong tháng × phần 599 của hoá đơn gốc × tỷ lệ (dòng Trả hàng của P&L cũng theo ngày trả). Đúng công thức VAT của Hoa hồng (kt_bc_hoa_hong_dl.dt_sale).
-- Lưu ý: khách trả nợ vào 599 sau → VAT của tháng hoá đơn tăng theo (tháng cũ có thể đổi khi tiền về). — Monsieur Claude
create or replace function public.kt_vat_599(p_phien text, p_tu date, p_den date) returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'pl');
  return coalesce((select jsonb_agg(jsonb_build_object('thang', thang, 'cn', cn, 'tien', round(tien), 'vat', round(vat), 'so', so)) from (
    with ctt as materialized (select * from kt_coc_tt()),
         t599 as materialized (select ma from kt_kiot_so_quy where la_thu and trang_thai = '0' and tai_khoan = '1316100' and nhom = 'Tiền khách trả'),
         cuc2 as materialized (select c.* from kt_hd_thu_cuc2() c where c.ma not in (select ma from ctt)),
         v5h as materialized (select z.hd, sum(z.tien) t5 from (select c.hoa_don_id hd, c.ma, c.thu tien from cuc2 c where c.hoa_don_id is not null
                   union all select t.id, x->>'ma', (x->>'tien')::numeric from kt_kiot_hd_thu t cross join lateral jsonb_array_elements(t.ds) x
                    where coalesce(x->>'pt', '') <> 'Point' and x->>'ma' not like 'TTDH%') z join t599 on t599.ma = z.ma group by 1),
         v5d as materialized (select coalesce(ctt.dh, regexp_replace(substr(q.ma, 3), '-[0-9]+$', '')) dh, sum(q.so_tien) t5 from kt_kiot_so_quy q join t599 on t599.ma = q.ma
                   left join ctt on ctt.ma = q.ma where q.ma like 'TTDH%' or ctt.ma is not null group by 1),
         -- phần 599 + tỷ lệ của từng hoá đơn (chỉ hoá đơn có tiền về 599)
         p as (select h.id, least((coalesce(v5h.t5, 0) + coalesce(v5o.t5, 0)) / nullif(h.tong, 0), 1) phan, kt_vat_tl(h.chi_tiet) tl
                 from kt_kiot_hoa_don h left join v5h on v5h.hd = h.id
                 left join lateral (select v5d.t5 from kt_kiot_dat_hang o9 join v5d on v5d.dh = o9.ma where o9.id = h.dat_hang_id or (h.dat_hang_id is null and o9.ma = nullif(h.ma_dat_hang, '')) limit 1) v5o on true
                where h.trang_thai in (1, 3) and h.tong > 0 and (v5h.t5 is not null or v5o.t5 is not null)),
         x as (select to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, h.chi_nhanh cn, h.tong * p.phan tien, h.tong * p.phan * p.tl vat
                 from kt_kiot_hoa_don h join p on p.id = h.id
                where (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between greatest(p_tu, '2026-09-01') and p_den
               union all
               select to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM'), coalesce(t.chi_nhanh, h.chi_nhanh), -t.tong_tra * p.phan, -t.tong_tra * p.phan * p.tl
                 from kt_kiot_tra_hang t join kt_kiot_hoa_don h on h.id = t.hoa_don_id join p on p.id = h.id
                where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between greatest(p_tu, '2026-09-01') and p_den)
    select thang, cn, sum(tien) tien, sum(vat) vat, count(*) so from x where vat <> 0 group by 1, 2) y), '[]');
end $f$;
revoke all on function public.kt_vat_599(text, date, date) from public; grant execute on function public.kt_vat_599(text, date, date) to anon;
