-- 23/10/2026 (anh, theo kế toán): "tất cả khoản tiền chuyển về tài khoản công ty 599 đều trừ đi 8% VAT, riêng nhóm đèn điện 10%, chuông mõ 10%";
-- "trừ đi 8% nghĩa là bán 100 nhận được 92"; "áp toàn bộ tiền chuyển về liên quan tới các nhóm sản phẩm".
-- Tiền về TK VCB CTY …599 = sổ quỹ Kiot, tài khoản Kiot 1316100, nhóm "Tiền khách trả" (bỏ chuyển rút nội bộ, nộp tiền vào TK, lãi NH, BHXH hoàn).
-- Khách trả công nợ không gắn hoá đơn → tỷ lệ 10% theo phần hàng ĐÈN ĐIỆN THỜ + CHUÔNG MÕ / PHÁP KHÍ trong hoá đơn của khách đó 90 ngày trước ngày trả.
-- VAT = tiền × (8% + 2% × phần hàng 10%). Dùng ở Báo cáo → P&L từ T9 (dòng "Trừ VAT tiền về TK công ty 599"). — Monsieur Claude
create or replace function public.kt_vat_599(p_phien text, p_tu date, p_den date) returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'pl');
  return coalesce((select jsonb_agg(jsonb_build_object('thang', thang, 'cn', chi_nhanh, 'tien', tien, 'vat', vat, 'so', so)) from (
    select to_char(t.ngay, 'YYYY-MM') thang, t.chi_nhanh, sum(t.so_tien) tien, round(sum(t.so_tien * (0.08 + 0.02 * coalesce(p.phan, 0)))) vat, count(*) so
      from (select s.ma, (s.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, s.chi_nhanh, s.doi_tac, s.so_tien from kt_kiot_so_quy s
             where s.la_thu and s.tai_khoan = '1316100' and s.trang_thai = '0' and s.nhom = 'Tiền khách trả'
               and (s.ngay at time zone 'Asia/Ho_Chi_Minh')::date between greatest(p_tu, '2026-09-01') and p_den) t
      left join lateral (select sum((i->>'tien')::numeric) filter (where i->>'nhom' in ('ĐÈN ĐIỆN THỜ', 'CHUÔNG MÕ / PHÁP KHÍ')) / nullif(sum((i->>'tien')::numeric), 0) phan
                           from kt_kiot_hoa_don h cross join jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) i
                          where h.khach_ten = t.doi_tac and h.trang_thai in (1, 3)
                            and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between t.ngay - 90 and t.ngay) p on true
     group by 1, 2) x), '[]');
end $f$;
revoke all on function public.kt_vat_599(text, date, date) from public; grant execute on function public.kt_vat_599(text, date, date) to anon;
