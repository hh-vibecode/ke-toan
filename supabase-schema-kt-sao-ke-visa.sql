-- ĐỐI CHIẾU SAO KÊ — THÊM 2 THẺ VISA CÔNG TY (12/11/2026). Monsieur Claude
-- Kế toán (anh chuyển): "thêm thông tin 2 thẻ visa vào đối chiếu sao kê để Trang tạm thời note tay số hoá đơn để kịp deadline tháng này".
-- Sao kê thẻ phải gắn 1 tài khoản trên app → tạo 2 tài khoản loại Thẻ tín dụng, NGỪNG dùng (hoat_dong = false) để KHÔNG hiện ở form phiếu,
-- số dư / Sổ quỹ (số dư 0, không phiếu) và Đối soát giao dịch (chỉ lấy TK ngân hàng đang dùng). Tên chứa số tài khoản thẻ VCB để màn Nạp sao kê
-- tự nhận đúng thẻ các tháng sau. Kế toán muốn ghi phiếu chi từ thẻ thì bật "đang dùng" ở Cài đặt → Tài khoản tiền.
-- Dữ liệu sao kê T10 (HXT, DTMO) nạp riêng: supabase-schema-kt-sao-ke-visa-t10.local.sql (không commit — số tiền, số thẻ).
insert into kt_tai_khoan (ten, loai, ton_dau, ngay_ton_dau, thu_tu, hoat_dong, thu_quy_chi)
select v.ten, 'the_tin_dung', 0, date '2026-09-01', 90, false, false
from (values ('Thẻ Visa Hồ Xuân Thịnh - VB1030000004'), ('Thẻ Visa Đặng Thị Minh Oanh - VB1030000005')) v(ten)
where not exists (select 1 from kt_tai_khoan t where t.ten = v.ten);
