-- 09/11/2026 anh: "đơn bị xoá mà khách đã cọc chưa — khách cọc hay trả rồi xoá mới quan tâm, nếu chỉ là báo giá thì không cần báo".
-- Đơn đặt app có mà Kiot không còn: chỉ tính lệch / báo khi đơn CÓ TIỀN — đã trả trên phiếu (da_tra > 0) hoặc có phiếu thu cọc TTDH… còn hiệu lực.
-- Edge kt-kiot gọi khi so tháng; đơn không tiền ghi riêng (thua_bo), không vào số lệch, không lên chuông. — Monsieur Claude
create or replace function public.kt_kiot_dh_co_tien(p_ma text[]) returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(d.ma), '{}') from kt_kiot_dat_hang d
   where d.ma = any(p_ma) and (coalesce(d.da_tra, 0) > 0
      or exists (select 1 from kt_kiot_so_quy q where q.la_thu and q.trang_thai = '0' and q.ma like 'TT%'
                   and regexp_replace(substr(q.ma, 3), '-[0-9]+$', '') = d.ma));
$$;
revoke all on function public.kt_kiot_dh_co_tien(text[]) from public, anon, authenticated;
grant execute on function public.kt_kiot_dh_co_tien(text[]) to service_role;
