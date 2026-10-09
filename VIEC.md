# SỔ VIỆC — app KẾ TOÁN (tài chính)

> Mở file này đầu mỗi phiên (sau `git pull`). Xong việc thì xoá khỏi mục ĐANG NỢ và ghi 1 dòng vào NHẬT KÝ.
> Ghi sổ + commit + push NGAY TRONG PHIÊN. Anh đã quyết thì làm, đừng xếp lại vào "chờ anh quyết".

---

## 0. KHỞI TẠO — XONG 05/10/2026

Repo + Pages · khoá (`kt-keys.local.txt`, anh nhờ phiên MKT chép sang 05/10) · `supabase-schema-kt.sql` đã chạy (14 bảng, 24 hàm,
RLS bật, 0 policy, 0 quyền bảng cho anon) · 3 tài khoản + danh mục (`scripts/khoi-tao.js`) · `scripts/kiem-thu.js` 32/32 đạt.
Script: `scripts/khoa.js` (đọc khoá, không in) · `scripts/sql.js` (chạy SQL qua Management API).

## 1. ĐANG CHỜ ANH HẢI QUYẾT / KẾ TOÁN XÁC NHẬN

**MỌI CÂU HỎI CHƯA TRẢ LỜI NẰM TRÊN APP: Cài đặt → Cần giải đáp** (bảng `kt_cau_hoi`, 30 câu / 20 chưa trả lời lúc 08/10 17:32, viết dễ hiểu cho người không
làm kế toán — anh chốt 05/10: "lưu lại hết, sau t đi hỏi 1 lượt"). **Đầu mỗi phiên Claude:** đọc câu đã trả lời
(`select tieu_de, tra_loi, tra_loi_boi from kt_cau_hoi where tra_loi is not null`) → làm theo → ghi nhật ký.
Câu hỏi mới: thêm vào `kt-cau-hoi.local.json` rồi chạy `scripts/nap-cau-hoi.js` (chỉ thêm câu chưa có).
Chi tiết số liệu đối chiếu T9: `doi-chieu-T9.local.md` (máy anh, KHÔNG lên GitHub).

Nhóm câu hỏi: Số dư đầu kỳ · Tiền mặt & Kiot · Chi · Cách tính · Vận hành · Luồng mới (08/10) · Kéo bù từ sheet (08/10) · Phân quyền (08/10) · Kiot.

## 1B. LUỒNG MỚI (anh gửi 08/10/2026 — sơ đồ GPT + ghi chú tay; KHÔNG dựa Google Sheet)

Nguồn: **Kiot** (doanh thu, khách hàng, NCC, hàng hoá, thu–chi 3 cơ sở **để khớp quỹ doanh thu cuối ngày**) ·
**meInvoice / 3TShop** (hoá đơn đầu ra / đầu vào; tồn kho sổ thuế 3 HKD) — anh lo API / khoá sau · **tự khai báo trên app** (vay & lãi vay, tài sản).
Báo cáo: 1 Tổng quan · 2 Dòng tiền · 3 Bán hàng · 4 Khách hàng · 5 NCC · 6 Hàng hoá / tồn kho (3–6 từ Kiot) · 7 P&L ·
8 Vay & lãi vay · 9 Tài sản · 10 Quản lý hoá đơn thuế · 11 Tồn kho sổ thuế. (Báo cáo "chi phí hoạt động" và "đầu tư & dự án" GPT thêm → anh bỏ.)
Bỏ bước thủ công: Zalo báo điều chuyển → app tự báo · form thu ngoài → nhập thẳng app · tạo phiếu Kiot 4A → xem Kiot API có cho ghi không (CHƯA thử POST — phải hỏi anh trước khi ghi lên Kiot).
Kiot API đọc được (08/10): customers 7.641 (có công nợ) · suppliers 353 (có công nợ) · products 7.568 (tồn kho từng chi nhánh) · invoices · orders · purchaseorders · returns · transfers.

| Giai đoạn | Việc | Trạng thái |
|---|---|---|
| A | Kéo Kiot mở rộng (bảng `kt_kiot_*`): khách, NCC, hàng hoá + tồn kho + giá vốn, hoá đơn + chi tiết, trả hàng, nhập hàng | **XONG 08/10** — nạp đầy đủ + 3 tiếng/lần chỉ phần sửa (`lastModifiedFrom`), ~26 giây/lần |
| B | Báo cáo Bán hàng / Khách hàng / NCC / Hàng hoá-tồn kho (công nợ khách + NCC lấy số Kiot) | **XONG 08/10** (`supabase-schema-kt-bao-cao.sql`) |
| C | Quỹ tiền mặt 3 cửa hàng (tab trong Dòng tiền) · P&L thực thu/thực chi · Vay & lãi vay · Tài sản | **XONG 08/10** — điều chuyển báo bằng **chuông trong app** (17:32, thay Zalo; anh không cần đẩy về điện thoại) |
| D | Hoá đơn thuế + tồn kho sổ thuế 3 HKD (chờ anh API meInvoice / 3TShop) | chờ anh — trang "Hoá đơn & thuế" đang là trang chờ |

**CÒN THIẾU (cập nhật 09/10/2026)**: hoá đơn thuế (meInvoice) + tồn kho sổ thuế (3TShop) — chờ anh
· **chứng từ cũ trên Google Drive** (264 file / 133 phiếu; T9: 211 lượt file / 94 phiếu) — file Drive RIÊNG TƯ, cần anh mở quyền (mục 2 dòng 8)
· tạo phiếu Kiot tự động 4A: KHÔNG làm được (API Kiot không có lệnh ghi sổ quỹ) → 4A tạo tay trên Kiot
· tách gốc / lãi trong chi tài chính (cần kế toán nhập khoản vay) · giá vốn T9 gần đúng (câu hỏi trên app)
· tồn kho cuối kỳ: CHỤP TỪ 09/10/2026 (bảng kt_ton_kho_ngay / kt_ton_kho_thang) — trước đó không lấy lại được; báo cáo chưa có màn hình xem lịch sử tồn
· 18 câu Cần giải đáp (kế toán) · chưa thử chứng từ / chuông / duyệt 2 lượt trên trình duyệt THẬT bằng tay.

## 2. ĐANG NỢ

| # | Việc | Ghi chú |
|---|---|---|
| 1 | (B) 2 phiếu chi sheet ghi đã trả nhưng không có TK chi → đang "Chờ thanh toán" | kế toán bổ sung trên app |
| 2 | ~~Nhập bù phát sinh trên sheet từ 05/10~~ | **XONG 08/10** — 52 phiếu chi (tab 7.DATA CHI; Thu / Điều chuyển / công nợ không có dòng mới), nhãn "Kéo từ sheet cũ — cần bổ sung", kế toán sửa dần. Phiếu #370 (trả T8, lọt vì ngày dùng DV gõ 08/12/2026) đã ẩn. Số T9 tiền ra THAY ĐỔI vì có thêm phiếu đã trả trong T9 (số trong `doi-chieu-T9.local.md` cần đối chiếu lại) |
| 2b | ~~Quyền "chỉ được tạo đề nghị chi"~~ | **XONG 08/10** — quyền `chi_de_nghi` + `chi_duyet`; kiểm thử 16/16 (`scripts/kiem-thu-quyen-chi.js`). Chưa có tài khoản nhân viên thật nào (câu hỏi trên app) |
| 3 | Theo dõi job `kt-kiot` (nhật ký hanh_dong keo_kiot / keo_kiot_loi) | Lần tự động đầu 05/10 10:47 chạy OK |
| 4 | ~~Tải ảnh chứng từ thẳng lên app~~ | **XONG 08/10**, làm lại 17:32 cho gọn: kéo thả / Ctrl+V / chọn ngay lúc tạo phiếu, nén + tải ngầm có %, ghim giấy trên danh sách. Chưa thử chọn file thật trên trình duyệt bằng tay — anh thử giúp 1 phiếu |
| 5 | Kế toán bổ sung 50 phiếu kéo bù (người đề nghị, chứng từ) — 09/10 ẩn 2 phiếu trùng #376 #377 | trang Chi → lọc nguồn "Kéo từ sheet cũ — cần bổ sung" |
| 8 | Kéo chứng từ cũ từ Google Drive lên app (`scripts/keo-chung-tu-drive.js [T9|tat_ca] [ghi]`, chạy lại không trùng) | CHỜ ANH mở quyền thư mục Drive ("Bất kỳ ai có link" — tạm) → chạy T9 → kiểm → tất cả → anh khoá lại |
| 9 | Tồn kho: lịch `kt-kiot-hang-dem` 23:20 kéo đầy đủ hàng hoá + `kt-ton-kho` 23:40 chụp (`scripts/trien-khai-ton-kho.js`) | theo dõi nhật ký `chup_ton_kho`; làm màn hình xem tồn theo ngày khi cần |
| 6 | Theo dõi đề xuất chi kéo từ Kiot (kết quả trong `kt_dong_bo_kiot` → khoá `chi`: them / ghep_4a / huy / sua) | bắt đầu 08/10; 3 câu hỏi mới trên app (TT luôn, phiếu Kiot tự sinh, nghi trùng) |
| 7 | Mật khẩu `giamdoc` trong `kt-keys.local.txt` KHÔNG còn đúng (giám đốc có thể đã đổi) — test dùng tài khoản GĐ tạm | không đặt lại mật khẩu giám đốc |

## 3. QUY TẮC ĐÃ CHỐT (đừng hỏi lại)

- **App riêng, tách biệt hoàn toàn** khỏi MKT/Sale và QC CSKH (anh chốt 1/10/2026). Xem `CLAUDE.md` mục Tách biệt.
- **Tên:** thư mục / repo `ke-toan`. **Tiền tố:** `kt_` (bảng, hàm) · `kt-` (lịch chạy, workflow). Đã đăng ký vào sổ quy ước chung 1/10/2026.
- **Đăng nhập tài khoản + mật khẩu, phân quyền giống app MKT/Sale** (anh chốt 05/10): Supreme / Admin toàn quyền; vị trí khác tick từng trang Xem / Nhập-sửa. Tài khoản RIÊNG app kế toán. Hiện có: `hai` (Supreme), `giamdoc`, `ketoan` (Admin). Mật khẩu ban đầu trong `kt-keys.local.txt`.
- Mọi thứ Claude tạo ký tên **Monsieur Claude**.
- **Repo public** (anh chốt 2/10/2026) → tuyệt đối không có khoá quản trị / số liệu thật / số tài khoản thật trong code và sổ.
- **GitHub: tự xử lý bằng đăng nhập git có sẵn trên máy** (anh chốt 2/10/2026). Không in token ra.
- **Khung app** theo đề xuất 05/10 (anh đồng ý) + **trang Logic trong Cài đặt** để người khác đọc app tính thế nào. Sửa luật ở SQL thì sửa luôn trang Logic.
- **Phạm vi dữ liệu: từ 01/09/2026** (anh chốt 05/10: "làm trước T9, dữ liệu t gửi là T9, kết hợp kiot").
- **Kiot: luồng kéo RIÊNG** của app kế toán, KHÔNG dùng chung / nhờ MKT/Sale; **3 tiếng / lần** (anh chốt 05/10). Đã chạy: Edge Function `kt-kiot` + pg_cron `kt-kiot` (`47 */3 * * *` UTC), secrets `KT_*`. Luật Kiot → Thu ở `supabase-schema-kt-kiot.sql` + trang Logic.
- **Khoá Supabase: dùng chung** khoá của project (anh chốt 05/10).
- **Luồng mới 08/10 (mục 1B)** thay luồng cũ dựa Google Sheet. **3 nơi tồn kho sổ thuế = 3 hộ kinh doanh** Hiền Thủy · Chánh Tâm · Shidai.
  **P&L tính theo THỰC THU / THỰC CHI**; hoá đơn và giá vốn là phần chính trong đó. **Không làm** báo cáo chi phí hoạt động, đầu tư & dự án (anh chốt 08/10).
- **Ảnh chứng từ: lưu và xem ngay trên app** (anh chốt 08/10): bucket riêng tư `kt-chung-tu`, Edge Function `kt-chung-tu` cấp link 5 phút, ảnh nén trên máy, tải về từng file / cả phiếu / cả kỳ (.zip).
- **Luồng chi (anh chốt 08/10 tối):** nhân viên **đề xuất chi trên Kiot** (không dùng app) → app kéo về 3 tiếng/lần thành phiếu "Chờ kế toán kiểm"
  → **kế toán kiểm, xác nhận lượt 1** → **giám đốc xác nhận lại (lượt 2)** → kế toán thanh toán. Người kiểm lượt 1 không tự xác nhận lượt 2.
  Quyền `chi_duyet` = kế toán kiểm + thanh toán (Admin có); `chi_gd` = giám đốc xác nhận — KHÔNG đi theo Admin, chỉ Supreme cấp / bỏ và đặt lại mật khẩu
  tài khoản có `chi_gd`. `chi_de_nghi` (nhân viên tạo trên app) giữ nhưng KHÔNG dùng — anh: "nhân viên m quan tâm làm gì". SQL: `supabase-schema-kt-duyet-2-cap.sql`.
  Phiếu chi Kiot trước 08/10 KHÔNG kéo. Chống trùng: ghép phiếu app đánh dấu 4A cùng số tiền ±5 ngày; trùng khác → nhãn "Nghi trùng".
  Anh chốt 09/10: "Đã thanh toán luôn" KHÔNG cần giám đốc xác nhận · phiếu Kiot tự sinh (TTTH trả hàng, PCPN trả NCC) CÓ qua đủ 2 lượt.
- **File khoá `kt-keys.local.txt` chỉ chứa khoá app kế toán** (anh chốt 09/10, đã dọn: bỏ Pancake / Meta / OpenAI / mật khẩu CSDL / link app MKT).
  Sửa file khoá bằng script theo tên dòng, KHÔNG in nội dung kể cả đã che (sự cố 09/10).
- **Thông báo = chuông TRONG APP kiểu Facebook**, KHÔNG đẩy về điện thoại (anh chốt 08/10). Bảng `kt_thong_bao`, hàm lưu tự sinh (`supabase-schema-kt-thong-bao.sql`).
- **Ảnh chứng từ: gọn nhất cho người up** (anh 08/10): nén + tải ngầm, bấm lại xem ngay. Kiot KHÔNG cho ghi phiếu thu/chi qua API (đã thử 08/10) → 4A tạo tay.
- **Phát sinh còn trên sheet cũ: kéo tạm vào, gắn thẻ "Kéo từ sheet cũ"**, kế toán điền dần (anh chốt 08/10).
- **Hạn chế nhập tay tối đa**: cái gì chọn được thì danh sách chọn, cái gì kéo được thì kéo tự động (anh chốt 05/10).
- **Giao diện theo theme XERO cho TOÀN APP** (anh chốt 05/10): menu ngang xanh đậm, dải tiêu đề trang trắng, tab trạng thái gạch chân, ô tài khoản (số dư sổ sách / sao kê / Đối soát), Tiền vào và ra, Chi phải trả, Công nợ phải thu theo tuổi nợ, ngăn kéo bên phải. **Font vẫn Montserrat.** KHÔNG giống GG Sheet.

## 4. PHỤ THUỘC CHÉO (cần app khác làm — nhờ anh chuyển lời)

| # | Cần gì | App nào | Trạng thái |
|---|---|---|---|
| — | (chưa có — Kiot tự kéo riêng theo anh chốt 05/10) | | |

## 5. NHẬT KÝ (mới nhất trước)

- **09/10/2026 tối (3)** — **Hoá đơn & thuế từ 3TShop** (giai đoạn D — 3TShop không API, anh xuất Sheet): `supabase-schema-kt-thue.sql` (kt_thue_xnt, kt_thue_hd, kt_bc_thue),
  `scripts/keo-3tshop.js` + `scripts/doc-xlsx.js` (nguồn trong `nguon-3tshop.local.json` — gitignore). Đã kéo HT Q1–Q3, CT Q1, Shidai (hoá đơn). Hoá đơn đọc theo TÊN cột
  (HT quý 3 mẫu bảng kê khác — lần đầu đọc ra 0 đồng, phát hiện khi chạy thử, sửa trước khi ghi). Trang Hoá đơn & thuế: tồn kho sổ thuế hộ × kỳ (bấm xem từng mã),
  hoá đơn bán / doanh thu Kiot theo tháng. Đối soát lỗi thêm nhóm "Hoá đơn 3TShop ngày sai năm" (Shidai 145 dòng).
  Chờ: link CT Q2/Q3 dạng chữ · tab tồn kho Shidai. Câu hỏi chia 4 chủ đề lớn (A Thu & Kiot · B Chi · C P&L & vay · D Tồn kho sổ thuế & hoá đơn).
  Anh trả lời "cân bằng quỹ" = không tính thu → luật Kiot bỏ 7 phiếu (1 phiếu T10).

- **09/10/2026 tối (2)** — (1) **Luật loại chi** (anh: "m tự quyết, người hay nhầm"): `scripts/chot-loai-chi.js` 8 luật theo bản chất (phí NH → Vận hành; CTNN / vận chuyển TQ → Giá vốn;
  trả thẻ tín dụng → Tài chính — ban đầu định đổi sang Marketing, xem dữ liệu thấy là trả nợ thẻ nên giữ Tài chính); sửa 37 phiếu cũ. Bảng `kt_luat_loai_chi`
  + cờ "nghi sai loại" bật từ ngày áp dụng app (`kt_cai_dat.ngay_ap_dung_app` — CHỜ anh báo ngày) — test 5/5 (`scripts/kiem-thu-luat-loai.js`).
  (2) **Trang Đối soát lỗi** (Nghiệp vụ → Theo dõi; kiểu Daily Task app MKT) — `supabase-schema-kt-doi-soat.sql`: 9 nhóm việc kế toán + lỗi hệ thống (job Kiot, ghép TK, tồn kho).
  (3) Câu hỏi còn 4 (cân bằng quỹ, cọc Phương Hương, gốc vay T9, đã đóng câu chốt loại). Sao kê: anh tự gửi hằng tuần (thư mục Drive — chờ tên).
  (4) 3TShop = tồn kho sổ thuế: file Shidai (link xuất bản đầu tiên) + HT Q1–Q3 + CT Q1 đọc được qua rclone; CT Q2/Q3 chờ link dạng chữ.

- **09/10/2026 tối** — Anh chốt: **luồng CHUẨN từ 01/09; trước T9 phiên phiến** (đóng tạm việc / câu hỏi chỉ dính trước T9).
  (1) Chi T1–T4: `scripts/nhap-chi-t1-4.js` (tab NĂM 2025 + THÁNG 1..5 + tab chính, cột nhận theo TÊN tiêu đề) — 418 phiếu; thêm 5 TK cũ (ngừng dùng) VCB HT/CT/SD, BIDV HT, TECH Cá Nhân;
      3 TK Kiot đã xoá ghép vào VCB HT/CT/SD theo 4 số cuối phiếu gốc → thu Kiot T1–T4 đủ (820 phiếu bị bỏ lần đầu đã vào lại).
  (2) Loại chi T1–T4 TỰ GÁN (`scripts/gan-loai-chi.js` — chấm thử T8–T9: 78%, tin cao 93%): luật từ khoá học từ mẫu (lương, cước, NCC, điện nước) xét trước,
      bỏ người thụ hưởng là nhân viên (nhận tiền đi trả hộ). Lần đầu bộ gán lệch về "Vận hành" (50%) và gán sai phiếu lương → phát hiện khi soát, sửa, gán lại (`regan ghi`).
  (3) Câu hỏi soạn lại 3 nhóm (Số dư đầu T9 · Phiếu cần xác nhận · Cách tính), đóng 4 câu trước T9, thêm yêu cầu sao kê từ 01/09; 12 phiếu trước T9 thiếu TK/loại ẩn tạm;
      HĐ đỏ chưa nhận chỉ đếm từ 01/09. Ảnh chứng từ: trung bình ~450 KB/ảnh, PDF UNC ~1,6 MB — không cần nén thêm.

- **09/10/2026 chiều muộn** — **Dữ liệu năm 2026** (anh: "auke, làm nốt"):
  (1) Edge Function `kt-kiot` nhận khoảng ngày (`tu/den/thu_tu`) → `scripts/keo-kiot-cu.js` kéo Kiot T1–T8 (sổ quỹ, hoá đơn, trả hàng, nhập hàng; giá vốn tính theo giá vốn hiện tại — gần đúng);
      phiếu thu Kiot chép sang app từ 01/05 (T5–T8: 2.260 phiếu). Tiền vào T9 không đổi.
  (2) `scripts/nhap-sheet-khoang.js` nhập chi + điều chuyển 01/05–31/08: nguồn chính tab 7.DATA CHI (có khoản ghi thẳng từ sao kê mà file Đề nghị không có),
      thêm người đề nghị / UNC từ file Đề nghị (ghép 586/587). 587 phiếu (11 thiếu TK/loại → Chờ TT cho kế toán bổ sung) + 74 điều chuyển (5 dòng sheet trống TK → bỏ).
      Đối chiếu với 5.TH THU-CHI: T6/T7/T8 khớp đúng từng đồng (trừ 11 phiếu chờ bổ sung); T5 app hơn sheet đúng 1 phiếu đã trả nhưng sheet để trống ngày DV nên tổng sheet bỏ sót.
      Lần chạy thử đầu dùng file Đề nghị làm nguồn → đối chiếu thấy thiếu khoản sao kê → đổi nguồn TRƯỚC khi ghi.
  (3) KHÔNG tính ngược số dư 01/05: ra 7 tài khoản âm (sheet không theo dõi chi của chúng) → số dư vẫn từ mốc 01/09; giao diện ghi rõ. Thu ngoài Kiot T5–T8 sheet không ghi → câu hỏi trên app đổi thành T1–T8.
  (4) Bộ lọc kỳ thêm "Năm nay" (anh yêu cầu), bỏ "Từ 1/9"; mốc chọn ngày 01/01; biểu đồ Tổng quan dùng tổng theo ngày (`kt_dong_tien.theo_ngay`, file `supabase-schema-kt-nam-2026.sql`).
  (5) Chứng từ Drive tất cả các tháng đang kéo nền (`keo-chung-tu-drive.js tat_ca ghi`, chạy lại không trùng).

- **09/10/2026 tối** — (1) Đăng nhập Drive anh qua **rclone** (chỉ đọc, `%USERPROFILE%\tools\rclone`, remote `ktdrive:` — anh cho phép; lưu ý: client_id dùng chung của rclone sẽ bị Google dừng trong 2026 → khi lỗi thì tạo client_id riêng).
  Kéo chứng từ T9: 194 file / 93 phiếu (169 MB, 80 UNC, 53 PDF); 14 file không phải ảnh/PDF + 2 lỗi → giữ link gốc. Tháng khác: chạy `keo-chung-tu-drive.js tat_ca ghi`.
  (2) Bỏ nút "Chứng từ kỳ (.zip)" (anh: cần file nào vào phiếu tải). (3) Anh trả lời 6 câu trên app: két: cộng tiền bán 31/8 vào tồn đầu 01/09 (số ở doi-chieu-T9.local.md);
  công nợ NCC Kiot DƯƠNG = mình nợ NCC (trang NCC tách 2 chiều); **mục Nghi trùng** (tab Chi + Việc cần làm + chuông `chi_trung` + hàm `kt_xu_ly_trung` gộp / khác nhau) — test 25/25.
  (4) Kiểm dữ liệu cả năm 2026 (anh muốn xử lý full 2026): sheet đề nghị có tab T1–T8 (đủ ngày TT + TK chi; T1–T4 KHÔNG có loại chi);
  file dòng tiền: DATA THU chỉ T9, DATA CHI/ĐIỀU CHUYỂN + TH THU-CHI (thu ngoài Kiot) từ T5. Thiếu: số dư 01/01, thu ngoài Kiot T1–4, điều chuyển T1–4 → 4 câu trên app.
  Chờ anh đồng ý để nhập T5–T8 (Kiot từ 01/01 + chi + thu ngoài Kiot + điều chuyển) rồi đối chiếu từng tháng. Hỏi MISA AppID cho API meInvoice (anh lo).

- **09/10/2026 chiều** — Làm các việc tự làm được:
  (1) Nhật ký job Kiot ĐÃ ghi kết quả đề xuất chi (`du_lieu.so_quy.dong_bo.chi`) — hôm trước Claude tra sai chỗ, báo nhầm "chưa ghi".
  (2) **Phát hiện tồn kho trên app CŨ**: Kiot không đổi "ngày sửa" sản phẩm khi bán / nhập → kéo 3 tiếng (chỉ phần sửa) bỏ sót; kiểm 7/15 mặt hàng lệch.
      Kéo đầy đủ (68 giây) → 15/15 khớp. Thêm lịch kéo đầy đủ mỗi tối + chụp tồn kho cuối ngày / cuối tháng. Báo cáo Hàng hoá & giá vốn hoá đơn trước 09/10 có thể đã dùng số tồn / giá vốn cũ.
  (3) Đối chiếu lại T9 (chi tiết `doi-chieu-T9.local.md` mục 6): tiền ra khớp sheet trừ 830.000 (2 phiếu thiếu TK chi). **Lỗi kéo bù 08/10: tạo trùng #376/#377**
      (phí QLTK, ghép không xét ngày) → đã ẩn, sửa script. (4) Kiểm thử chuyển sang tài khoản TẠM (`scripts/tk-tam.js`), bỏ lệnh xoá phiên theo giờ: 33/14/12/16/20 đạt.
  (5) Chứng từ cũ trên Drive: viết `scripts/keo-chung-tu-drive.js`, chạy thử T9 → 211/211 file đòi đăng nhập Google (riêng tư) → chờ anh mở quyền.

- **09/10/2026** — Ghi 3 câu anh trả lời (TT luôn không cần GĐ · phiếu Kiot tự sinh qua 2 lượt · dọn file khoá), sửa trang Logic. Tài khoản anh hiển thị "Admin".
  **SỰ CỐ KHOÁ:** lúc soát cấu trúc file khoá, lệnh "che giá trị" (chỉ che chuỗi ≥14 ký tự) để lọt DB_PASSWORD (mật khẩu CSDL dùng chung) và 3 mật khẩu
  app hai / giamdoc / ketoan ra kết quả lệnh trên máy (nhật ký phiên Claude) — KHÔNG dán vào chat, không commit. Đã báo anh; đề nghị đổi mật khẩu hai + ketoan
  trong app; mật khẩu CSDL là cài đặt dùng chung → anh quyết (đổi sẽ ảnh hưởng app MKT nếu app đó dùng).

- **08/10/2026 tối** — (1) **Sự cố màn hình đen** ở Tổng quan từ bản 17:02: khung xem ảnh chứng từ đặt tên lớp `.lb` trùng nhãn biểu đồ số dư
  → mỗi nhãn thành lớp đen phủ màn hình. Em chỉ chụp kiểm trang Chi nên không bắt được. Sửa 17:50 (đổi `.ct-lb`). Bài học: chụp kiểm cả Tổng quan sau mỗi lần đổi CSS.
  (2) Duyệt chi 2 lượt + đề xuất chi từ Kiot (xem mục 3). Kiểm thử mới `scripts/kiem-thu-duyet-2-cap.js` 20/20; test cũ sửa theo luồng 2 lượt: 33/33 · 14/14 · 12/12 · 16/16.
  Lỗi tự bắt trước khi chạy: phép trừ mảng int[] cần extension không có; thông báo kế toán tự tạo phiếu rơi sang anh/GĐ; Admin tự cấp quyền GĐ / đặt lại mật khẩu GĐ → chặn ở SQL.
  4 phiếu chi Kiot ngày 08/10 đã vào app (1 nghi trùng). Ghi 2 câu anh trả lời, sửa câu "nhân viên gửi đề nghị" (trước Claude tự điền sai), thêm 3 câu mới.

- **08/10/2026 17:32** — Làm 5 việc anh giao: (1) thử GHI phiếu Kiot (anh cho phép): API trả 404, không có lệnh ghi → 4A tạo tay, đóng câu 23.
  (2) Chuông thông báo trong app (bảng `kt_thong_bao`; đề nghị chi mới / duyệt / đã TT / từ chối; điều chuyển mới / đã xác nhận; đếm mỗi phút).
  (3) Chứng từ gọn hơn: kéo thả, Ctrl+V, chọn ảnh ngay lúc tạo phiếu, nén + tải ngầm có %, thử lại khi lỗi, ghim giấy + số chứng từ trên danh sách Thu / Chi / Điều chuyển bấm mở thẳng.
  (4) Quyền `chi_de_nghi` / `chi_duyet` (SQL + giao diện + Edge Function `kt-chung-tu` kiểm quyền theo dòng, deploy v2).
  (5) Kéo bù sheet: 52 phiếu chi, nhãn tím + bộ lọc nguồn. Thêm 7 câu hỏi lên app (tổng 20 chưa trả lời). Trang Logic thêm mục Chuông, Kéo bù, quyền Chi.
  **Lỗi đã tự sửa:** kéo bù lần đầu ghép theo SỐ DÒNG nhưng tab DATA CHI bị xếp lại → phát hiện ở chạy thử, đổi sang ghép theo nội dung + số tiền trước khi ghi;
  lọt phiếu #370 (trả T8) → ẩn; lệnh `cat >` treo (lặp lỗi cũ) → dừng; câu hỏi nhập hàng Kiot mô tả sai cách tính → sửa lại; bộ test cũ không dọn thông báo → thêm bước dọn,
  và 1 ca test cũ trượt do chi chia chung (dữ liệu mới) → test so đúng loại chi riêng. Kiểm thử: 32/32 · 14/14 · 12/12 · 16/16 (mới).

- **08/10/2026 17:02** — Chứng từ ảnh / PDF trên app (anh chốt "dùng app xem chứng từ"): bucket riêng tư kt-chung-tu, bảng kt_chung_tu, Edge Function kt-chung-tu (kiểm phiên + quyền, link 5 phút), ô chứng từ trong Thu / Chi / Điều chuyển / Vay / Tài sản (nén ảnh, xem to, tải về, xoá = ẩn), tải cả kỳ .zip; tạo phiếu mới xong tự mở lại để thêm ảnh. Kiểm thử phần nền 12/12 (scripts/kiem-thu-chung-tu.js) + chụp giao diện với file thử (đã xoá).

- **08/10/2026 16:49** — Anh: tạm bỏ kiểm giao diện điện thoại; công nợ khách "kiot là đủ" → Tổng quan lấy số Kiot (khách còn nợ / trả trước / top nợ), ẩn trang công nợ nhập tay (giữ dữ liệu), sửa trang Logic, đóng câu hỏi (còn 14). Anh hỏi ảnh chứng từ "up lên app sau down về có tiện k" → đã trả lời trong chat, chờ anh gật.

- **08/10/2026 16:34** — Luồng mới (sơ đồ anh gửi, đã khớp ghi chú tay): kéo Kiot mở rộng (6 bảng `kt_kiot_*`, nạp đầy đủ: 353 NCC, 7.641 khách, 7.568 hàng, 669 HĐ, 38 trả, 57 nhập) + hàm `kt-kiot` chạy phần sửa 3 tiếng/lần. Báo cáo mới: Bán hàng, Khách hàng, NCC, Hàng hoá & tồn kho, P&L (thực thu/thực chi + tham chiếu Kiot), Quỹ tiền mặt 3 cửa hàng; nhập liệu Vay & lãi vay, Tài sản (khấu hao đường thẳng); trang chờ Hoá đơn & thuế. Menu: Tổng quan · Nghiệp vụ ▾ · Báo cáo ▾ · Cài đặt ▾; quyền theo module mới. Thêm 4 câu Cần giải đáp (23 câu). Lỗi tự sửa: nạp hàng hoá trùng dòng trong 1 lượt ghi (Kiot trả trùng khi phân trang) → bỏ trùng; nạp hoá đơn quá 150 giây vì thiếu "đến ngày" → thêm; bài kiểm thử cũ giả định ngày trống → đổi sang so trước/sau. Kiểm thử 32/32 + luồng mới 14/14.

- **05/10/2026 11:41** — Tổng quan dạng biểu đồ (anh: "hiện đại, bảng biểu kiểu sơ đồ, thoáng"): bỏ 16 ô tài khoản → biểu đồ thanh 2 chiều quanh trục 0, tự ẩn TK số dư 0 không giao dịch (nút hiện lại), bấm dòng sang đối soát, ĐẶT DƯỚI CÙNG (anh chốt); bảng theo cơ sở → thanh đôi Thu / Chi + chênh lệch; bố cục 2 cột.

- **05/10/2026 11:20** — Anh: "dropdown vs tìm kiếm cho hết lên trên cùng, cách dữ liệu 1 khoảng nhỏ" → hàng bộ lọc (ô chọn + tìm kiếm + nhãn tổng) chuyển lên dải tiêu đề trắng (class `fbar`, tự áp cho mọi trang danh sách trong render()); khung dữ liệu chỉ còn tab + danh sách, cách 14px.

- **05/10/2026 11:15** — Ô lọc mỗi loại 1 màu (loại = tím, cơ sở = xanh ngọc, bộ phận = cam, tài khoản = xanh dương, khác = hồng); tab trạng thái Chi theo màu trạng thái. Trang "Cần giải đáp" (bảng kt_cau_hoi, 19 câu) trong Cài đặt. Cài đặt chia module như app MKT/Sale (menu xổ: Hỏi đáp · Quản trị · Danh mục · Hệ thống, mỗi module 1 trang). Phân quyền: bỏ ô Vị trí (anh: "bỏ phần bộ phận"), chỉ tick Toàn quyền hoặc từng trang theo module Báo cáo / Nghiệp vụ / Quản trị; bảng tài khoản kiểu MKT (Sửa · Đặt lại mật khẩu · Khoá / Mở lại).

- **05/10/2026 10:57** — Anh góp ý giao diện (màu chuẩn, đừng dính nhau): gộp tab + bộ lọc + danh sách vào 1 khung trắng (mọi trang danh sách), dải tiêu đề kéo hết bề ngang, ô / nút cao đều 34px, ô lọc dài đều, nhãn tổng bên phải. Nội dung thu Kiot gọn: tên khách · mô tả · mã phiếu. Job kt-kiot chạy tự động lần đầu 10:47 OK.

- **05/10/2026 10:08** — Đối chiếu T9 app vs sheet tới từng tài khoản: 11/12 TK khớp tuyệt đối; tiền vào và két lệch nhỏ đã giải thích đủ (Kiot tiền mặt theo ngày bán + chi tại quầy, sheet theo ngày nộp két); tiền ra khớp khi tính theo ngày dùng DV (trừ 2 phiếu sheet thiếu TK). Sửa luật Kiot: Cash → két; TTD_/CTD_ và phiếu chứa số TK công ty = chuyển nội bộ. Sửa nhập chi: lấy cả dòng gõ tay không có dấu thời gian, gán loại cho phiếu lương sheet để trống. Thêm nút "Chi theo ngày trả / ngày dùng DV" ở Tổng quan (kt_bao_cao thêm p_chi_theo). Ghi chú đối chiếu: doi-chieu-T9.local.md. Lỗi tự sửa: mất ký tự `\` trong regex SQL (luật nội bộ chưa chạy) → sửa ngay.

- **05/10/2026 09:59** — Anh đổi mốc sang 1/9, làm T9 + Kiot; theme Xero toàn app (font Montserrat); nút con mắt mật khẩu. Kiot API có sổ quỹ (/cashflow) → `kt_dong_bo_kiot()` (thu khách TTHD/TTDH/TT + thu khác, bỏ "Chuyển rút" + phiếu huỷ; tiền mặt quầy → Két). Nhập T9: 914 phiếu Kiot (→ 505 thu), 5 thu ngoài Kiot từ sheet (12 dòng sheet trùng Kiot đã bỏ), 181 chi (đề nghị TT), 14 điều chuyển, 121 công nợ (khớp sheet <số>), tồn đầu 1/9 khớp sheet. Edge Function + pg_cron `kt-kiot` chạy thử OK. Lỗi tự sửa: đọc số mũ Excel sai (bắt được ở chạy thử, chưa ghi); mảng kiot_ma 2 chiều (ghi đè lại); endDate Kiot không gồm ngày cuối → T9 thiếu 30/9 → job tự bù, rồi 1 khoản BHXH <số> bị tính 2 lần (sheet + Kiot) → đã ẩn dòng sheet.

- **05/10/2026 09:40** — Anh cho chép khoá (auto mode chặn Claude đọc file khoá MKT → anh nhờ phiên MKT chép sang `kt-keys.local.txt`). Anh đổi đăng nhập sang tài khoản + mật khẩu, phân quyền kiểu MKT. Viết lại phần đăng nhập (phiên băm sha256, sai 5 lần khoá 15 phút, quyền kiểm ở `kt_chan`). Chạy `supabase-schema-kt.sql` lần đầu: lỗi `$` do Claude ghép mã (JS biến `$$` thành `$`) → sửa, chạy lại OK. Tự phát hiện + sửa trước khi chạy: khoá sai mật khẩu không ghi được (raise huỷ lệnh đếm), ô trống gửi chuỗi rỗng, tên CTE `no`. Tạo 3 tài khoản + danh mục (16 TK, 13 đơn vị, 13 loại). Kiểm thử đầu-cuối 32/32, xoá dữ liệu thử, đăng xuất phiên thử. Bỏ chế độ xem thử dữ liệu mẫu (không cần nữa).

- **05/10/2026 09:23** — Anh chốt: khung OK + trang Logic; 3 người quản trị; Kiot kéo riêng 3h/lần; dữ liệu từ 1/8; dùng chung khoá; hạn chế nhập tay; giao diện kiểu phần mềm kế toán. Viết `supabase-schema-kt.sql` (chưa chạy — chưa có khoá) + `index.html` (Tổng quan thẻ + biểu đồ, Dòng tiền & đối soát, Thu dạng sổ quỹ, Chi đề nghị → duyệt → thanh toán + 4A/4B + HĐ đỏ, Điều chuyển, Công nợ, Sắp phải trả, Cài đặt: danh mục / người dùng / Logic / nhật ký / đổi mã). Soát giao diện bằng dữ liệu giả + Chrome headless (máy tính + điện thoại 375px). Sự cố nhỏ tự sửa: 1 lệnh treo vì `cat` chờ stdin (đã dừng, không ghi gì); chạy nhầm script ghép có thể xoá phần Tổng quan (script lỗi trước khi ghi — đã kiểm file còn nguyên); trang Logic lỡ ghi 1 con số thật từ sheet → đã xoá trước khi đẩy.

- **05/10/2026 09:00** — Anh gửi link xuất bản file Đề nghị thanh toán → đã đọc (tab chính + tab lưu theo tháng). Bổ sung đề xuất phần Chi trong chat.
- **05/10/2026 08:44** — Đọc luồng Thu–Chi–Điều chuyển (ảnh anh gửi) + file GG Sheet quản lý dòng tiền (bản xuất bản, 10 tab). File đề nghị thanh toán để riêng tư, chưa đọc được. Phát hiện lỗi số liệu trên sheet (đã báo anh trong chat; KHÔNG ghi số vào repo vì repo public). Gửi đề xuất app, chờ anh duyệt.
- **02/10/2026 14:38** — Tạo repo `hh-vibecode/ke-toan` (public, anh chốt) bằng đăng nhập git có sẵn trên máy, đẩy commit đầu, bật Pages (`main` /). Auto mode chặn 2 lần (đọc credential, tạo repo public) → anh tắt auto mode và duyệt tay.
- **01/10/2026** — Phiên kế toán đầu: `git init` (main, tác giả Hoàng Hải như 2 repo kia), commit khung ở máy. Đọc credential GitHub có sẵn trên máy bị hệ thống chặn → chờ anh cấp token để tạo repo + bật Pages.
- **01/10/2026** — Phiên MKT/Sale dựng sẵn thư mục: `CLAUDE.md`, `VIEC.md`, `BRIEF.md`, `.gitignore`, `favicon.svg`. Chưa git init, chưa có repo, chưa có khoá.
