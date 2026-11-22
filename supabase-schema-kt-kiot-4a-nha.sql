-- =========================================================================
-- 20/11/2026 — Sửa tự khớp 4A làm tắc cả lượt chép thu Kiot (Monsieur Claude)
-- Sự cố: phiếu chi #2085 (trùng, đã xoá 18/11) vẫn giữ kiot_so_quy_id của phiếu Kiot CNH009410 → khi phiếu gốc #2081
-- (cùng số tiền) đủ điều kiện, update vi phạm unique kt_chi_kiot_sq_uq → kt_dong_bo_kiot() lỗi toàn bộ
-- → từ 19/11 18:32 không phiếu thu Kiot nào vào app.
-- Sửa: (1) phiếu chi ĐÃ XOÁ nhả liên kết phiếu Kiot trước khi gán cho phiếu còn sống;
--      (2) mỗi phiếu gán trong khối exception riêng → 1 phiếu lỗi chỉ bị bỏ qua, không làm hỏng lượt kéo.
-- =========================================================================
create or replace function public.kt_dong_bo_kiot_4a() returns integer
language plpgsql security definer set search_path = public as $$
declare r_c record; q record; n int := 0;
begin
  for r_c in select c.id, c.so_tien, c.ngay_tt, t.kiot_ma from kt_chi c join kt_tai_khoan t on t.id = c.tai_khoan_id
            where not c.da_xoa and c.trang_thai = 'da_tt' and c.nguon <> 'kiot' and c.kiot = 'khong' and c.ngay_tt >= date '2026-09-01'
              and coalesce(array_length(t.kiot_ma, 1), 0) > 0 order by c.ngay_tt, c.id loop
    q := null;
    select s.id, s.ma into q from kt_kiot_so_quy s
     where not s.la_thu and s.trang_thai = '0' and s.so_tien = r_c.so_tien and s.tai_khoan = any(r_c.kiot_ma)
       and abs((s.ngay at time zone 'Asia/Ho_Chi_Minh')::date - r_c.ngay_tt) <= 5
       and not exists (select 1 from kt_chi x where x.kiot_so_quy_id = s.id and not x.da_xoa)
     order by abs((s.ngay at time zone 'Asia/Ho_Chi_Minh')::date - r_c.ngay_tt), s.id limit 1;
    if q.id is not null then
      begin
        update kt_chi set kiot_so_quy_id = null where kiot_so_quy_id = q.id and da_xoa;   -- phiếu đã xoá nhả liên kết
        update kt_chi set kiot = 'da_tao', kiot_so_quy_id = q.id, kiot_ma = q.ma, sua_luc = now(),
               sua_boi = 'Hệ thống (tự khớp phiếu chi Kiot)' where id = r_c.id;
        n := n + 1;
      exception when others then
        raise warning 'kt_dong_bo_kiot_4a bỏ qua phiếu chi %: %', r_c.id, sqlerrm;
      end;
    end if;
  end loop;
  return n;
end $$;
revoke execute on function public.kt_dong_bo_kiot_4a() from public, anon, authenticated;
