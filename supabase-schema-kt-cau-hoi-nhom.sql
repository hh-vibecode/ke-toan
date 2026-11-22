-- Cần giải đáp: nhóm câu hỏi theo MỤC CHÍNH CỦA APP (menu) — 19/10/2026, anh: "chia theo hạng mục chính; tự nhóm, liên quan phần nghiệp vụ
-- hay phần báo cáo nào thì nhóm chung lại". Trước có 19 nhóm lẻ đặt theo đợt hỏi. Câu hỏi mới từ nay đặt nhom = tên mục menu. — Monsieur Claude
update kt_cau_hoi set nhom = case
  when id in (49, 50) or tieu_de ilike 'Công nợ%' or tieu_de ilike '%công nợ%Kiot%' then 'Công nợ & Thanh toán'
  when nhom in ('1. Số dư đầu tháng 9 (quan trọng nhất)', 'Số dư đầu kỳ', 'Khớp sổ quỹ & tài khoản (19/10)', 'Tiền mặt & Kiot', 'A. Thu tiền & Kiot',
                '2. Phiếu cần xác nhận', 'Chi', 'Luồng mới (08/10)', 'B. Chi & đề nghị chi', 'Kéo bù từ sheet (08/10)', 'Duyệt chi 2 lượt (08/10)',
                'A. Số dư & khớp tài khoản', 'B. Thu tiền & Kiot', 'C. Chi & đề nghị thanh toán', 'D. Công nợ & vay') then 'Thu chi & Ngân quỹ'
  when nhom in ('3. Cách tính số', 'Cách tính', 'C. Lãi lỗ (P&L) & vay', 'Số liệu cả năm 2026', 'E. Lãi lỗ & cách tính số liệu') then 'Báo cáo quản trị & Chốt kỳ'
  when nhom in ('D. Tồn kho sổ thuế & hoá đơn (3TShop)', 'E. Hoá đơn công ty tổng (meInvoice)', 'F. Thuế, hoá đơn & tồn kho') then 'Hóa đơn & Thuế'
  when nhom in ('Vận hành', 'Phân quyền (08/10)', 'G. Vận hành & phân quyền') then 'Hệ thống & Cài đặt'
  else nhom end;
select nhom, count(*) n, count(*) filter (where tra_loi is null) cho from kt_cau_hoi group by nhom order by nhom;
