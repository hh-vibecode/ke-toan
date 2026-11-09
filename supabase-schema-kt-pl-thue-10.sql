-- 09/11/2026 kế toán (mục 7): "đã bổ sung nhóm chi phí thuế nhưng không thấy trong P&L, lại có 1 nhóm ngoài". Nhóm kế toán tạo 03/11 ("10. Chi phí thuế",
-- đổi tên 05/11 "Thuế VAT đã khấu trừ") KHÔNG có mã mục → P&L xếp ngoài khung 1–9, form phiếu chi không hiện. Gán mã 10, xếp sau nhóm 9.
-- P&L / Tổng quan / Hiệu quả cơ sở: nhóm mã 10 (cả mục con) = THUẾ — dòng sau lợi nhuận trước thuế, cộng chung thuế T1–T8 theo file (plThueIds). — Monsieur Claude
update kt_loai set ma = '10', thu_tu = 2000 where id = 124;
