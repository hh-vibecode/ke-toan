-- DỌN NHÀ HÀNG ĐỢT 3 (23/10/2026) — Monsieur Claude
-- Anh 23/10: "T1–T5 soát và gỡ các giao dịch liên quan tới nhà hàng ra, đừng để lẫn vào các nhãn đồ thờ".
-- Soát phiếu chi / thu / điều chuyển T1–T5 theo NỘI DUNG (từ khoá thực phẩm, NCC thực phẩm, tháo dỡ HKC / SKH, thuê nhà HN): 33 dòng khớp → ẩn 14 dòng chắc chắn của nhà hàng,
-- giữ đồ thờ (hộp mực máy in kho Shidai, trả thẻ Visa, khách mua đồ thờ kể cả "Nhà hàng chay Phúc Nguyên Hưng"); hỏi anh #1263 "4 mâm cỗ Hải Mai".
-- Cùng cách đợt 1, 2: ẨN (da_xoa), không xoá cứng; đều trước 01/09/2026 → không đổi số dư. Phiếu thu Kiot thêm vào kt_bo_qua_nguon để lần kéo sau không chép lại.
update kt_chi set da_xoa = true, sua_luc = now(), sua_boi = 'Hệ thống (dọn nhà hàng — anh 23/10)',
       ghi_chu = concat_ws(' · ', nullif(ghi_chu, ''), 'Ẩn 23/10/2026: nhà hàng, không thuộc app')
 where id in (1113, 1144, 1151, 1266, 1248, 1314, 1315, 1063, 1059, 1398) and not da_xoa;   -- 1398 nước hoa đỏ (cùng loại #1098 anh cho ẩn 22/10)
insert into kt_bo_qua_nguon (ma_nguon, ly_do)
select ma_nguon, 'Nhà hàng — NCC thực phẩm hoàn tiền hàng trả (anh 23/10/2026)' from kt_thu where id in (23524, 23421, 23362, 23155, 23150) and ma_nguon is not null
on conflict (ma_nguon) do nothing;
update kt_thu set da_xoa = true, sua_luc = now(), sua_boi = 'Hệ thống (dọn nhà hàng — anh 23/10)'
 where id in (23524, 23421, 23362, 23155, 23150) and not da_xoa;
delete from kt_dcp_phieu where chi_id in (1113, 1144, 1151, 1266, 1248, 1314, 1315, 1063, 1059, 1398);
