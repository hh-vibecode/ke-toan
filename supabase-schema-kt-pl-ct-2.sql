-- 23/10/2026 (anh): "click vào các khoản sẽ phân chi tiết ra các phiếu trong đó, để thể hiện sự liên kết" (T9, T10).
-- kt_pl_ct trước lọc theo NGÀY THANH TOÁN + chỉ phiếu đã chi → danh sách lệch số P&L (P&L tính theo tháng hạch toán / ngày sử dụng,
-- gồm cả phiếu chờ chi, bỏ tạm ứng). Nay đọc thẳng view kt_v_chi_ht (nguồn của kt_bc_pl2) → tổng danh sách = đúng ô P&L. — Monsieur Claude
create or replace function public.kt_pl_ct(p_phien text, p_loai integer[], p_tu date, p_den date) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
declare v_t0 text := to_char(p_tu, 'YYYY-MM'); v_t1 text := to_char(p_den, 'YYYY-MM');
begin
  perform kt_chan(p_phien, 'pl');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ngay', ngay, 'so', so, 'nd', noi_dung, 'th', thu_huong_ten, 'loai', loai_id,
           'dv', dv, 'tien', tien, 'thang', thang, 'tt', trang_thai) order by ngay desc nulls last, id desc), '[]') from (
    select c.id, coalesce(c.ngay_tt, c.ngay_de_nghi) ngay, coalesce(c.kiot_ma, 'PC' || lpad(c.id::text, 6, '0')) so, c.noi_dung, c.thu_huong_ten, h.loai_id,
           h.don_vi_id dv, h.thang, c.trang_thai, round(sum(h.tien)) tien
      from kt_v_chi_ht h join kt_chi c on c.id = h.chi_id
     where h.loai_id = any(p_loai) and h.thang between v_t0 and v_t1
     group by 1, 2, 3, 4, 5, 6, 7, 8, 9 limit 3000) x);
end $f$;
