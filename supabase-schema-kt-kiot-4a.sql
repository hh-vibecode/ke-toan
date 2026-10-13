-- TỰ KIỂM PHIẾU CHI ĐÃ CÓ TRÊN KIOT CHƯA (4A) — 13/10/2026. Monsieur Claude
-- Anh 13/10: "Chưa cập nhật KiotViet cần làm, để bắt kế toán nhớ phải tạo" + "m kéo được phiếu chi Kiot mà, tự check tự gán".
-- Phiếu chi ĐÃ THANH TOÁN từ tài khoản có gắn quỹ Kiot (kt_tai_khoan.kiot_ma), không phải đề xuất từ Kiot, đang "không ảnh hưởng" (kiot = 'khong'):
--   → tìm phiếu CHI trên sổ quỹ Kiot cùng quỹ, cùng số tiền, lệch ≤ 5 ngày, CHƯA gắn với phiếu app nào (1 phiếu Kiot ↔ 1 phiếu app)
--   → thấy: tự gán kiot = 'da_tao' (4A) + mã / id phiếu Kiot. Không thấy: phiếu hiện "Chưa cập nhật KiotViet" (trang Chi + Đối soát lỗi).
-- Chạy sau mỗi lần kéo Kiot (gọi trong kt_dong_bo_kiot, 3 tiếng / lần) — phiếu kế toán tạo trên Kiot muộn sẽ tự được nhận.
-- Chỉ xét từ 01/09/2026 (luồng chuẩn); thanh toán trước đó là số tham khảo.
create or replace function public.kt_dong_bo_kiot_4a() returns int
language plpgsql security definer set search_path = public as $$
declare r_c record; q record; n int := 0;
begin
  for r_c in select c.id, c.so_tien, c.ngay_tt, t.kiot_ma from kt_chi c join kt_tai_khoan t on t.id = c.tai_khoan_id
            where not c.da_xoa and c.trang_thai = 'da_tt' and c.nguon <> 'kiot' and c.kiot = 'khong' and c.ngay_tt >= date '2026-09-01'
              and coalesce(array_length(t.kiot_ma, 1), 0) > 0 order by c.ngay_tt, c.id loop
    select s.id, s.ma into q from kt_kiot_so_quy s
     where not s.la_thu and s.trang_thai = '0' and s.so_tien = r_c.so_tien and s.tai_khoan = any(r_c.kiot_ma)
       and abs((s.ngay at time zone 'Asia/Ho_Chi_Minh')::date - r_c.ngay_tt) <= 5
       and not exists (select 1 from kt_chi x where x.kiot_so_quy_id = s.id and not x.da_xoa)
     order by abs((s.ngay at time zone 'Asia/Ho_Chi_Minh')::date - r_c.ngay_tt), s.id limit 1;
    if q.id is not null then
      update kt_chi set kiot = 'da_tao', kiot_so_quy_id = q.id, kiot_ma = q.ma, sua_luc = now(), sua_boi = 'Hệ thống (tự khớp phiếu chi Kiot)' where id = r_c.id;
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke execute on function public.kt_dong_bo_kiot_4a() from public, anon, authenticated;
grant execute on function public.kt_dong_bo_kiot_4a() to service_role;

-- Phiếu "chưa cập nhật KiotViet" (để trang Chi / Đối soát / Tổng quan dùng chung 1 điều kiện)
create or replace function public.kt_chua_kiot(c kt_chi) returns boolean language sql stable set search_path = public as $$
  select not c.da_xoa and c.trang_thai = 'da_tt' and c.nguon <> 'kiot' and c.kiot = 'khong' and c.ngay_tt >= date '2026-09-01'
     and exists (select 1 from kt_tai_khoan t where t.id = c.tai_khoan_id and coalesce(array_length(t.kiot_ma, 1), 0) > 0);
$$;
