-- 26/11/2026 kế toán (sau bản theo hoá đơn Kiot sáng nay): "mục 3 lấy đúng theo hoá đơn đã xuất trên meInvoice trong tháng sẽ chuẩn hơn".
-- Dòng P&L "Trừ VAT ... 599" từ T9: VAT tháng = Σ tiền thuế các hoá đơn ra của CÔNG TY (meInvoice, 2 mẫu GTGT 1 + GTGT nến) có NGÀY HOÁ ĐƠN trong tháng.
--   Bỏ (khi MISA có trả trạng thái): HĐ bị huỷ (EInvoiceStatus 2), HĐ bị thay thế (RefInvoiceStatus 3 + EInvoiceStatus 1). Lưu ý: lệnh /invoice/paging hiện
--   KHÔNG trả các trường này (thử 26/11: chỉ có Org* + PaymentMethodType) → đang tính mọi HĐ MISA trả về; cần đối chiếu bảng kê MISA nếu có HĐ huỷ.
--   HĐ điều chỉnh tăng / giảm: MISA trả số chênh (âm khi giảm) → cộng vào tháng của HĐ điều chỉnh.
-- Chia cơ sở (để lọc cơ sở / Tổng quan): (1) phiếu thu đã gắn HĐ (kt_thu_hd) → đơn vị của phiếu → chi nhánh Kiot, nhiều phiếu lấy đơn vị có tiền lớn nhất;
--   (2) HĐ điều chỉnh / thay thế → cơ sở của HĐ gốc; (3) cùng MST người mua → cơ sở của HĐ gần nhất đã biết;
--   (4) còn lại chia theo tỷ lệ doanh thu hoá đơn Kiot của tháng (gắn phiếu thu cho HĐ là tự chia lại đúng).
-- Thay bản supabase-schema-kt-vat-599-theo-hd.sql (cùng tên hàm, cùng dạng trả {thang, cn, tien, vat, so}; tien = tiền hàng chưa thuế). — Monsieur Claude
create or replace function public.kt_vat_599(p_phien text, p_tu date, p_den date) returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'pl');
  return coalesce((select jsonb_agg(jsonb_build_object('thang', thang, 'cn', cn, 'tien', round(tien), 'vat', round(vat), 'so', so) order by thang, cn) from (
    with h as materialized (
           select x.id, x.ky_hieu || '-' || x.so_hd k, x.ngay, x.mst, x.thanh_tien, x.tien_thue, x.misa,
                  -- HĐ gốc của HĐ điều chỉnh / thay thế: ưu tiên trường MISA, không có thì đọc ghi chú "Điều chỉnh / thay thế HĐ C26TTV 00000027"
                  coalesce(case when x.misa ? 'OrgInvNo' then coalesce(x.mau, '1') || coalesce(x.misa->>'OrgInvSeries', '') || '-' || lpad(x.misa->>'OrgInvNo', 8, '0') end,
                           (select coalesce(x.mau, '1') || m[1] || '-' || m[2] from regexp_match(coalesce(x.ghi_chu, ''), 'HĐ\s+(\S+)\s+(\d+)') m)) goc
             from kt_thue_hd x where x.hkd = 'CTY' and x.chieu = 'ra' and x.nguon like 'meinvoice:%' and x.so_hd is not null),
         -- (1) cơ sở theo phiếu thu đã gắn
         c1 as (select distinct on (th.hd_ma) th.hd_ma k, dv.kiot_chi_nhanh[1] cn
                  from kt_thu_hd th join kt_thu t on t.id = th.thu_id join kt_don_vi dv on dv.id = t.don_vi_id
                 where cardinality(dv.kiot_chi_nhanh) > 0
                 group by th.hd_ma, dv.kiot_chi_nhanh[1] order by th.hd_ma, sum(t.so_tien) desc),
         h1 as (select h.*, c1.cn cn1 from h left join c1 on c1.k = h.k),
         -- (2) theo HĐ gốc, (3) theo MST
         h2 as (select h1.*, coalesce(h1.cn1, g.cn1,
                  (select z.cn1 from h1 z where z.mst = h1.mst and h1.mst is not null and z.cn1 is not null order by abs(z.ngay - h1.ngay) limit 1)) cn
                  from h1 left join h1 g on g.k = h1.goc),
         h3 as (select to_char(ngay, 'YYYY-MM') thang, cn, thanh_tien, tien_thue from h2
                 where ngay between greatest(p_tu, '2026-09-01') and p_den
                   and coalesce((misa->>'EInvoiceStatus')::int, 1) <> 2
                   and not (coalesce((misa->>'RefInvoiceStatus')::int, 0) = 3 and coalesce((misa->>'EInvoiceStatus')::int, 1) = 1)),
         -- (4) HĐ chưa biết cơ sở: chia theo tỷ lệ doanh thu hoá đơn Kiot của tháng (như lãi vay) → tổng VAT giữ đúng số meInvoice, Tổng quan = P&L
         dtk as (select to_char((k.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, k.chi_nhanh cn, sum(k.tong) dt from kt_kiot_hoa_don k
                  where k.trang_thai in (1, 3) and k.tong > 0 and (k.ngay at time zone 'Asia/Ho_Chi_Minh')::date between greatest(p_tu, '2026-09-01') and p_den group by 1, 2),
         tl as (select thang, cn, dt / nullif(sum(dt) over (partition by thang), 0) p from dtk),
         u as (select thang, sum(thanh_tien) tien, sum(tien_thue) vat, count(*) so from h3 where cn is null group by 1),
         z as (select thang, cn, thanh_tien tien, tien_thue vat, 1 so from h3 where cn is not null
               union all select u.thang, tl.cn, u.tien * tl.p, u.vat * tl.p, 0 from u join tl on tl.thang = u.thang
               union all select u.thang, null, u.tien, u.vat, u.so from u where not exists (select 1 from tl where tl.thang = u.thang and tl.p is not null))
    select thang, cn, sum(tien) tien, sum(vat) vat, sum(so) so from z group by 1, 2 having round(sum(vat)) <> 0) y), '[]');
end $f$;
revoke all on function public.kt_vat_599(text, date, date) from public; grant execute on function public.kt_vat_599(text, date, date) to anon;
