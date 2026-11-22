-- HOA HỒNG: phiếu thu sổ quỹ (không gắn đơn) → PHIẾU ĐẶT HÀNG MỚI NHẤT của khách — 17/11/2026. Monsieur Claude
-- Anh: "trước t bảo nối với cả sổ quỹ rồi mà, vì nhiều khi đơn hàng trước đấy báo giá không có mã sp nên vẫn cần vào sổ quỹ lập phiếu thu,
-- phiếu thu m cứ gắn với phiếu đặt hàng mới nhất của khách đấy là xong". Thay bản coc-tt (17/11 sáng: chỉ ghép khi đơn tạo trong 3 ngày trước → 1 ngày sau phiếu,
-- đơn chưa có cọc khác). Giờ: phiếu "Tiền khách trả" mã TT + số, Kiot chưa chia vào hoá đơn nào → đơn đặt MỚI NHẤT của đúng khách (chưa huỷ) tạo trước ngày phiếu
-- (cho phép đơn tạo trễ tối đa 3 ngày sau phiếu: thu cọc xong mới lên đơn). Không có đơn nào → giữ luồng cũ (phiếu cục / hoá đơn gần nhất).
-- Vẫn chỉ áp đơn tạo từ 01/11/2026 (T9–T10 đã trả hoa hồng, không đổi số cũ).
create or replace function public.kt_coc_tt() returns table(ma text, dh text, dat_id bigint)
language sql stable security definer set search_path = public as $$
  with chia as (select distinct x->>'ma' ma from kt_kiot_hd_thu t, jsonb_array_elements(t.ds) x),
       q as (select q.ma, (q.goc->>'partnerId')::bigint kh, q.ngay from kt_kiot_so_quy q
              where q.la_thu and q.trang_thai = '0' and q.nhom = 'Tiền khách trả' and q.ma ~ '^TT[0-9]' and q.goc->>'partnerType' = 'C' and q.goc->>'partnerId' ~ '^[0-9]+$'
                and q.ngay >= timestamptz '2026-10-29 00:00+07' and q.ma not in (select ma from chia)),
       m as (select distinct on (q.ma) q.ma, o.ma dh, o.id dat_id
               from q join kt_kiot_dat_hang o on o.khach_id = q.kh and o.trang_thai is distinct from 4
                and o.ngay >= timestamptz '2026-11-01 00:00+07' and o.ngay <= q.ngay + interval '3 days'
              order by q.ma, o.ngay desc)
  select ma, dh, dat_id from m;
$$;
revoke all on function public.kt_coc_tt() from public, anon, authenticated;
