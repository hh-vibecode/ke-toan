-- 26/10/2026 xử lý báo lỗi kế toán #9 #10 #11 (phiếu sheet cũ ghi đã thanh toán nhưng thiếu TK chi; CSDL bắt phiếu Đã thanh toán phải có TK). — Monsieur Claude
--  #75 gia hạn phần mềm MISA: trả bằng thẻ Visa Nguyễn Thị Chuyện. Theo cách làm thẻ tín dụng 24/10 (VIEC 128): tiêu bằng thẻ = phiếu chi từ TK thẻ
--      (số dư âm = dư nợ thẻ). Trả nợ thẻ trước nay ghi phiếu "FINANCE - Trả thẻ tín dụng" (nhóm Chi tài chính, không vào P&L) → #75 vẫn tính P&L.
--  #90 in tem CCTV: trả từ quỹ ngoài kho Shidai → đã gồm trong phiếu hoàn quỹ #89 (quỹ ngoài 08.09–16.09, đã hạch toán P&L)
--      → chi từ TK "Quỹ ngoài cơ sở" (NGỪNG dùng: quỹ ngoài không theo dõi số dư — anh chốt), KHÔNG hạch toán (tránh đếm 2 lần).
insert into kt_tai_khoan (ten, loai, hoat_dong, thu_tu)
select 'Thẻ Visa Nguyễn Thị Chuyện', 'the_tin_dung', true, 90 where not exists (select 1 from kt_tai_khoan where ten = 'Thẻ Visa Nguyễn Thị Chuyện');
insert into kt_tai_khoan (ten, loai, hoat_dong, thu_tu)
select 'Quỹ ngoài cơ sở (chi lẻ đã gồm trong phiếu hoàn quỹ)', 'khac', false, 200 where not exists (select 1 from kt_tai_khoan where ten like 'Quỹ ngoài cơ sở%');
update kt_chi set trang_thai = 'da_tt', ngay_tt = coalesce(ngay_tt, ngay_de_nghi),
       tai_khoan_id = (select id from kt_tai_khoan where ten = 'Thẻ Visa Nguyễn Thị Chuyện'),
       ghi_chu = replace(coalesce(ghi_chu, ''), '[Sheet cũ ghi Đã thanh toán nhưng thiếu TK chi — kế toán bổ sung]', '[Trả bằng thẻ Visa Nguyễn Thị Chuyện — kế toán báo 24/10]'),
       sua_boi = 'Hệ thống', sua_luc = now()
 where id = 75 and trang_thai = 'cho_tt';
update kt_chi set trang_thai = 'da_tt', ngay_tt = coalesce(ngay_tt, ngay_de_nghi), khong_hach_toan = true,
       tai_khoan_id = (select id from kt_tai_khoan where ten like 'Quỹ ngoài cơ sở%'),
       ghi_chu = replace(coalesce(ghi_chu, ''), '[Sheet cũ ghi Đã thanh toán nhưng thiếu TK chi — kế toán bổ sung]', '[Trả từ quỹ ngoài kho Shidai, đã gồm trong phiếu hoàn quỹ PC000089 — không hạch toán]'),
       sua_boi = 'Hệ thống', sua_luc = now()
 where id = 90 and trang_thai = 'cho_tt';
update kt_bao_loi set da_xu_ly = true, xu_ly_boi = 'Hệ thống', xu_ly_luc = now(),
       xu_ly_ghi = case id when 9 then 'Đã chuyển Đã thanh toán từ TK mới "Thẻ Visa Nguyễn Thị Chuyện" (thẻ tín dụng) — vẫn tính P&L'
                           else 'Đã chuyển Đã thanh toán từ TK "Quỹ ngoài cơ sở" — không hạch toán vì đã gồm trong phiếu hoàn quỹ PC000089' end
 where id in (9, 10, 11) and not da_xu_ly;
insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu)
values ('Hệ thống', 'kt_chi', 'xu_ly_bao_loi', jsonb_build_object('bao_loi', array[9, 10, 11], 'chi', array[75, 90]));
-- #14 (Oanh 25/10: phiếu chi Tổng công ty chọn phân bổ cho từng cơ sở, vào lại không lưu): nút Chia nhanh (Đều HT/CT/SD, % doanh số, Cả về Tổng công ty)
-- điền số bằng code → không bật cờ "đã đổi" → bấm Lưu bỏ qua phân bổ. Sửa ở index.html (pbChia bật cờ). 10 phiếu chị sửa 25/10 vẫn ở Tổng công ty — chị chia lại.
update kt_bao_loi set da_xu_ly = true, xu_ly_boi = 'Hệ thống', xu_ly_luc = now(),
       xu_ly_ghi = 'Lỗi nút Chia nhanh không lưu phân bổ — đã sửa bản v1.210. Các phiếu sửa 25/10 (PC000397, 398, 399, 401, 1588, 1595, 1614, 1635, 1673, 1782) chưa lưu phân bổ, cần chia lại.'
 where id = 14 and not da_xu_ly;
