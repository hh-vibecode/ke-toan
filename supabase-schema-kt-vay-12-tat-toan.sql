-- 26/10/2026 (anh: "Tổng dư nợ gốc sao không có số") — thẻ để "—" vì 2 khoản có lần trả nhưng chưa có lần nhận tiền.
-- #12 "VCB — vay ngắn hạn (hạn mức, nhiều khế ước TKV)" gom lần trả của các khế ước VCB cũ, KHÔNG có trong 12 khế ước còn dư nợ theo sao kê 09/10 → đã tất toán:
-- ghi lần nhận = tổng gốc đã trả (không gắn TK — không đổi số dư) để dư nợ về 0, đánh dấu tất toán. #10 chưa rõ thuộc khoản nào → giữ, chờ kế toán. — Monsieur Claude
insert into kt_vay_nhan (vay_id, ngay, so_tien, tai_khoan_id, ghi_chu, tao_boi)
select 12, coalesce((select min(ngay) from kt_vay_tra where vay_id = 12 and not da_xoa), '2026-05-11'),
       (select sum(goc) from kt_vay_tra where vay_id = 12 and not da_xoa and da_tra), null,
       'Giải ngân các khế ước VCB cũ (đã tất toán, không có số liệu giải ngân) — ghi bằng tổng gốc đã trả để dư nợ về 0, không qua TK', 'Hệ thống'
 where not exists (select 1 from kt_vay_nhan where vay_id = 12 and not da_xoa);
update kt_vay set da_tat_toan = true, sua_boi = 'Hệ thống', sua_luc = now(),
       ghi_chu = coalesce(ghi_chu, '') || ' · Các khế ước cũ đã tất toán trước 09/10/2026 (không có trong sao kê dư nợ) — 26/10'
 where id = 12 and not da_tat_toan;
