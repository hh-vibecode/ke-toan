-- 24/10/2026 kế toán (anh chuyển file "Tân Hưng Thịnh.xlsx" = sao kê dư nợ VCB 01/01–09/10/2026 + ảnh app VCB 3 khoản cá nhân): "cập nhật trước khoản vay công ty từ đầu năm".
-- Anh chọn: giải ngân KHÔNG gắn tài khoản (không đổi số dư; không thấy khoản nào vào TK 599 qua phiếu thu / điều chuyển) · mỗi khế ước 1 khoản vay.
-- ĐÃ CHẠY 24/10/2026 (Supabase MCP). File này ghi lại để tra cứu — chạy lại sẽ tạo trùng. Monsieur Claude
--
-- 1) 12 khế ước VCB hạn mức (APPL00556841 · APPL00929362 .HDCTD.mSME, LS 8,7%, trả gốc cuối kỳ, lãi hàng tháng) — tổng 4.436.620.968 = "TỔNG DƯ NỢ" sao kê:
--    khế ước 001068092536 dùng lại khoản #17 (chị Thu Trang tạo 22/10, đã có lần trả gốc 500.000.000); 11 khế ước còn lại tạo mới (#18–#28).
--    Mỗi khoản: 1 lần nhận tiền (ngày giải ngân, tai_khoan_id null). Lần trả ở khoản hạn mức #12 có ghi số khế ước → chuyển sang khoản riêng;
--    các lần trả hằng tháng (26–27) là LÃI (khớp dư nợ × 8,7% × số ngày) → goc → lai (22 lần, ~39,4 triệu). 13/10 607.878.669 → gốc 605.713.037 + lãi 2.165.632.
--    #18 (001067746221) tất toán 13/10.
-- 2) 3 khoản cá nhân VCB (CN Nam Hải Phòng, trả gốc đều): #29 001061721514 (3 tỷ, 29/10/2025, 7,2%), #30 001072967560 (1 tỷ, 23/10/2026, 9,5%),
--    #31 001043756534 (700 triệu, 04/01/2024, 11,9%). Lần nhận tiền chưa gắn tài khoản. Lần trả có ghi số TK vay chuyển từ #12 (12 + 9 lần), giữ nguyên số
--    (đang gộp gốc + lãi — chưa có lịch trả nợ để tách).
-- Số dư tài khoản không đổi (chỉ chuyển lần trả giữa các khoản + đổi gốc ↔ lãi, tổng mỗi lần giữ nguyên).
do $d$
declare r record; v_id bigint; n int;
begin
  for r in select * from (values
    ('1067746221',605713037,'2026-05-20'::date,'2026-10-13'::date,'APPL00556841'),('1068092536',998703731,'2026-06-01','2026-10-26','APPL00556841'),
    ('1068338985',231367596,'2026-06-09','2026-11-02','APPL00556841'),('1068597215',284787716,'2026-06-16','2026-11-09','APPL00556841'),
    ('1068649969',209190000,'2026-06-18','2026-11-11','APPL00556841'),('1068761735',673459231,'2026-06-22','2026-11-16','APPL00556841'),
    ('1069358872',198335037,'2026-07-10','2026-12-03','APPL00556841'),('1069713287',82332713,'2026-07-21','2026-12-14','APPL00556841'),
    ('1069780634',165850530,'2026-07-23','2026-12-16','APPL00556841'),('1070674839',284644631,'2026-08-18','2027-01-11','APPL00929362'),
    ('1071393415',372871560,'2026-09-09','2027-02-02','APPL00929362'),('1071448008',329365186,'2026-09-10','2027-02-03','APPL00929362')) t(kv,tien,ngay,han,hd)
  loop
    if r.kv = '1068092536' then
      v_id := 17;
      update kt_vay set ten = 'VCB — khế ước 00' || r.kv, ben_cho_vay = 'Vietcombank', so_tien = r.tien, ngay_vay = r.ngay, ngay_dao_han = r.han, lai_suat = 8.7,
        hinh_thuc = 'goc_cuoi_ky', ma_vay = '00' || r.kv, ghi_chu = 'HĐ hạn mức ' || r.hd || '.HDCTD.mSME · theo sao kê dư nợ VCB 01/01–09/10/2026', sua_boi = 'Hệ thống', sua_luc = now() where id = 17;
    else
      insert into kt_vay (ten, ben_cho_vay, so_tien, ngay_vay, ngay_dao_han, lai_suat, hinh_thuc, ma_vay, ghi_chu, tao_boi)
      values ('VCB — khế ước 00' || r.kv, 'Vietcombank', r.tien, r.ngay, r.han, 8.7, 'goc_cuoi_ky', '00' || r.kv,
        'HĐ hạn mức ' || r.hd || '.HDCTD.mSME · theo sao kê dư nợ VCB 01/01–09/10/2026', 'Hệ thống') returning id into v_id;
    end if;
    insert into kt_vay_nhan (vay_id, ngay, so_tien, tai_khoan_id, ghi_chu, tao_boi)
    values (v_id, r.ngay, r.tien, null, 'Giải ngân khế ước 00' || r.kv || ' — không qua tài khoản (anh 24/10)', 'Hệ thống');
    update kt_vay_tra set vay_id = v_id,
      goc = case when ngay = '2026-10-13' and goc = 607878669 then 605713037 else 0 end,
      lai = case when ngay = '2026-10-13' and goc = 607878669 then 2165632 else goc end
     where vay_id = 12 and not da_xoa and ghi_chu like '%' || r.kv || '%';
  end loop;
end $d$;
update kt_vay set da_tat_toan = true, sua_boi = 'Hệ thống', sua_luc = now() where ma_vay = '001067746221';
-- (3 khoản cá nhân: xem nhật ký kt_nhat_ky hanh_dong = 'cap_nhat_khoan_vay' 24/10/2026)

-- 24/10/2026 cùng đợt (mục con loại chi — kế toán: "không cần tự nhặt nữa, bổ sung nhóm chi con lúc duyệt"):
-- (a) trigger kt_chi_loai_cha ghi người chọn mục con = phiên đăng nhập (trước luôn 'Ghi trực tiếp') — đã áp:
do $d$ declare d text := pg_get_functiondef('kt_chi_loai_cha()'::regprocedure); n int := length(d);
begin
  if position('kt.nguoi' in d) > 0 then return; end if;
  d := replace(d, $s$new.loai_con_boi := coalesce(new.loai_con_boi, 'Ghi trực tiếp');$s$, $s$new.loai_con_boi := coalesce(nullif(current_setting('kt.nguoi', true), ''), 'Ghi trực tiếp');$s$);
  if length(d) = n then raise exception 'không khớp mẫu'; end if;
  execute d;
end $d$;
-- (b) phân loại tay 102 phiếu còn trống mục con (97 theo nội dung + 5 phiếu YEP 1095/1165/1166/1185/1199 → 4.8 Truyền thông nội bộ), loai_con_boi 'Hệ thống';
--     69 phiếu khó / không phải chi phí để lại KXĐ — xem kt_nhat_ky hanh_dong = 'phan_loai_con_tay'.
-- (c) CHƯA tắt lịch kt-phan-loai-con (lệnh cron.unschedule bị chặn quyền ở phiên Mac) — lịch chỉ chấm phiếu còn trống, không ghi đè mục con kế toán chọn.

-- 24/10/2026 (2) anh gửi ảnh app VCB "BỔ SUNG THÊM 1 KHOẢN VAY CÁ NHÂN": APPL00181769.HDCTD.KHCN · TK vay 001048351314 · giải ngân 2.000.000.000 ngày 27/06/2024 ·
-- đáo hạn 29/06/2054 · 360 tháng · 11,9% · hạn mức 3.700.000.000 · CN Đông Hà Nội · dư nợ 1.844.460.000. = khoản #11 "VCB — vay dài hạn (HN)" (1 lần trả 06/01 "khoản dài hạn VCB HN")
-- → cập nhật #11 thay vì tạo trùng; lần nhận tiền chưa gắn tài khoản. ĐÃ CHẠY.
update kt_vay set ten = 'VCB cá nhân — vay dài hạn HN 001048351314', ben_cho_vay = 'Vietcombank', so_tien = 2000000000, ngay_vay = '2024-06-27', ngay_dao_han = '2054-06-29',
  lai_suat = 11.9, hinh_thuc = 'goc_deu', ma_vay = '001048351314',
  ghi_chu = 'HĐ APPL00181769.HDCTD.KHCN · 360 tháng · hạn mức 3.700.000.000 · CN Đông Hà Nội · dư nợ ngân hàng 24/10/2026: 1.844.460.000 · các lần trả đang gộp gốc + lãi (chưa có lịch trả nợ để tách)',
  sua_boi = 'Hệ thống', sua_luc = now() where id = 11 and coalesce(ma_vay, '') <> '001048351314';
insert into kt_vay_nhan (vay_id, ngay, so_tien, tai_khoan_id, ghi_chu, tao_boi)
select 11, '2024-06-27', 2000000000, null, 'Giải ngân 2.000.000.000 — chưa gắn tài khoản (theo app ngân hàng anh gửi 24/10)', 'Hệ thống'
where not exists (select 1 from kt_vay_nhan where vay_id = 11 and not da_xoa);
insert into kt_nhat_ky (nguoi, bang, dong_id, hanh_dong, du_lieu)
values ('Hệ thống', 'kt_vay', 11, 'cap_nhat_khoan_vay', '{"tk_vay":"001048351314","giai_ngan":2000000000,"ngay":"2024-06-27","du_no_ngan_hang":1844460000}');
