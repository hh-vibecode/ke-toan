-- PHIẾU CHI CHỈ GỒM LUỒNG ĐỀ NGHỊ THANH TOÁN (16/10/2026, kế toán: "các luồng phiếu trên Kiot chỉ dùng để đối chiếu, không đẩy vô đây";
-- anh: "làm gọn lại luồng dữ liệu, trên đề nghị thanh toán làm gì có Kiot"). Monsieur Claude
-- Phiếu Kiot = chi két quầy (CTM), trả tiền khách (TTTH), ngân hàng tự trích nợ… → chỉ xem ở Sổ quỹ / đối chiếu, không vào danh sách duyệt.
-- Ẩn mọi phiếu chi nguồn Kiot CHƯA thanh toán (không đổi số dư). Phiếu Kiot đã ghép làm xác nhận cho phiếu đề nghị vẫn giữ trên phiếu đề nghị (kiot_ma).
with an as (
  update kt_chi set da_xoa = true, ghi_chu = concat_ws(' ', ghi_chu, '[Phiếu Kiot chỉ để đối chiếu — không thuộc luồng đề nghị thanh toán, ẩn 16/10/2026]')
   where nguon = 'kiot' and not da_xoa and trang_thai <> 'da_tt' returning id)
insert into kt_nhat_ky (nguoi, bang, dong_id, hanh_dong, du_lieu) select 'Hệ thống', 'kt_chi', id, 'an_kiot_doi_chieu', null from an;
