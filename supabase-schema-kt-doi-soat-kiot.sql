-- Kiot chỉ để đối soát (16/10/2026, anh Hải: "kiot tách riêng ra cho vào phần báo lỗi") — Monsieur Claude
-- Phiếu chi không còn cột / thẻ / ô chọn Kiot. Phiếu đã thanh toán mà chưa thấy phiếu chi khớp trên Kiot chỉ hiện ở trang Đối soát lỗi.
-- Vá trên định nghĩa đang chạy (không chép đè cả hàm).
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_doi_soat'::regproc);
  n := length(d);
  d := replace(d, $a$'ten','Phiếu chi chưa tạo trên KiotViet (4A)','ai','ke_toan','huong_dan','Tạo phiếu chi tương ứng trên Kiot — app tự nhận ở lần kéo Kiot sau (15 phút). Không cần tạo thì mở phiếu → "Không tạo phiếu Kiot (4B)" + lý do'$a$,
                  $a$'ten','Phiếu chi đã thanh toán chưa thấy trên Kiot','ai','ke_toan','huong_dan','Ghi phiếu chi tương ứng trên Kiot (cùng số tiền, cùng tài khoản, lệch ≤ 5 ngày) — hệ thống tự khớp ở lần kéo Kiot sau (15 phút). Khoản không cần ghi Kiot thì bấm "Không cần ghi Kiot" trên dòng'$a$);
  if length(d) = n then raise exception 'khong thay nhom kiot_4a'; end if;
  execute d;
end $$;
