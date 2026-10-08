# SỔ VIỆC — app KẾ TOÁN (tài chính)

> Mở file này đầu mỗi phiên (sau `git pull`). Xong việc thì xoá khỏi mục ĐANG NỢ và ghi 1 dòng vào NHẬT KÝ.
> Ghi sổ + commit + push NGAY TRONG PHIÊN. Anh đã quyết thì làm, đừng xếp lại vào "chờ anh quyết".

---

## 0. KHỞI TẠO — XONG 05/10/2026

Repo + Pages · khoá (`kt-keys.local.txt`, anh nhờ phiên MKT chép sang 05/10) · `supabase-schema-kt.sql` đã chạy (14 bảng, 24 hàm,
RLS bật, 0 policy, 0 quyền bảng cho anon) · 3 tài khoản + danh mục (`scripts/khoi-tao.js`) · `scripts/kiem-thu.js` 32/32 đạt.
Script: `scripts/khoa.js` (đọc khoá, không in) · `scripts/sql.js` (chạy SQL qua Management API).

## 1. ĐANG CHỜ ANH HẢI QUYẾT / KẾ TOÁN XÁC NHẬN

**MỌI CÂU HỎI CHƯA TRẢ LỜI NẰM TRÊN APP: Cài đặt → Cần giải đáp** (bảng `kt_cau_hoi`, 19 câu, viết dễ hiểu cho người không
làm kế toán — anh chốt 05/10: "lưu lại hết, sau t đi hỏi 1 lượt"). **Đầu mỗi phiên Claude:** đọc câu đã trả lời
(`select tieu_de, tra_loi, tra_loi_boi from kt_cau_hoi where tra_loi is not null`) → làm theo → ghi nhật ký.
Câu hỏi mới: thêm vào `kt-cau-hoi.local.json` rồi chạy `scripts/nap-cau-hoi.js` (chỉ thêm câu chưa có).
Chi tiết số liệu đối chiếu T9: `doi-chieu-T9.local.md` (máy anh, KHÔNG lên GitHub).

Nhóm câu hỏi: Số dư đầu kỳ (4) · Tiền mặt & Kiot (7) · Chi (3) · Cách tính (2) · Vận hành (3).

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
| C | Quỹ tiền mặt 3 cửa hàng (tab trong Dòng tiền) · P&L thực thu/thực chi · Vay & lãi vay · Tài sản | **XONG 08/10** — điều chuyển báo trên app: hiện chỉ có số đếm "chưa xác nhận" trên menu, CHƯA có thông báo đẩy |
| D | Hoá đơn thuế + tồn kho sổ thuế 3 HKD (chờ anh API meInvoice / 3TShop) | chờ anh — trang "Hoá đơn & thuế" đang là trang chờ |

**CÒN THIẾU sau 08/10** (đã báo anh trong chat): hoá đơn thuế (meInvoice) + tồn kho sổ thuế (3TShop) · tạo phiếu Kiot tự động 4A (chưa thử GHI Kiot — cần anh cho phép)
· thông báo điều chuyển (thay Zalo) · ảnh chứng từ (anh chưa chọn Supabase / Drive) · quyền "chỉ tạo đề nghị chi" cho nhân viên (hiện quyền sửa Chi = được duyệt + thanh toán)
· tách gốc / lãi trong chi tài chính (cần nhập khoản vay) · tồn kho tại ngày cuối kỳ (mới có tồn hiện tại) · giá vốn T9 gần đúng (giá vốn bình quân ngày 08/10)
· công nợ nhập tay vs Kiot (chờ quyết) · phát sinh sau 5/10 trên sheet chưa vào app · 14 câu Cần giải đáp chưa trả lời (08/10 Claude đóng 8 câu đã có căn cứ: quyết định anh + sơ đồ mới).

## 2. ĐANG NỢ

| # | Việc | Ghi chú |
|---|---|---|
| 1 | (B) 2 phiếu chi sheet ghi đã trả nhưng không có TK chi → đang "Chờ thanh toán" | kế toán bổ sung trên app |
| 2 | Bỏ Google Sheet (sơ đồ 08/10) — phát sinh trên sheet từ 05/10 chưa vào app | Claude nhập bù 1 lần khi anh gửi link sheet mới nhất |
| 2b | Quyền "chỉ được tạo đề nghị chi" (không duyệt / không xem số khác) để cấp tài khoản cho nhân viên | Claude làm — sơ đồ 08/10: người đề nghị nhập trên app |
| 3 | Theo dõi job `kt-kiot` (nhật ký hanh_dong keo_kiot / keo_kiot_loi) | Lần tự động đầu 05/10 10:47 chạy OK |
| 4 | Tải ảnh chứng từ thẳng lên app | giai đoạn sau |

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
- **Ảnh chứng từ:** app lưu được (Supabase Storage riêng tư, tự nén) hoặc đẩy sang Google Drive qua Apps Script — anh CHƯA chọn.
- **Hạn chế nhập tay tối đa**: cái gì chọn được thì danh sách chọn, cái gì kéo được thì kéo tự động (anh chốt 05/10).
- **Giao diện theo theme XERO cho TOÀN APP** (anh chốt 05/10): menu ngang xanh đậm, dải tiêu đề trang trắng, tab trạng thái gạch chân, ô tài khoản (số dư sổ sách / sao kê / Đối soát), Tiền vào và ra, Chi phải trả, Công nợ phải thu theo tuổi nợ, ngăn kéo bên phải. **Font vẫn Montserrat.** KHÔNG giống GG Sheet.

## 4. PHỤ THUỘC CHÉO (cần app khác làm — nhờ anh chuyển lời)

| # | Cần gì | App nào | Trạng thái |
|---|---|---|---|
| — | (chưa có — Kiot tự kéo riêng theo anh chốt 05/10) | | |

## 5. NHẬT KÝ (mới nhất trước)

- **08/10/2026 16:49** — Anh: tạm bỏ kiểm giao diện điện thoại; công nợ khách "kiot là đủ" → Tổng quan lấy số Kiot (khách còn nợ / trả trước / top nợ), ẩn trang công nợ nhập tay (giữ dữ liệu), sửa trang Logic, đóng câu hỏi (còn 14). Anh hỏi ảnh chứng từ "up lên app sau down về có tiện k" → đã trả lời trong chat, chờ anh gật.

- **08/10/2026 16:34** — Luồng mới (sơ đồ anh gửi, đã khớp ghi chú tay): kéo Kiot mở rộng (6 bảng `kt_kiot_*`, nạp đầy đủ: 353 NCC, 7.641 khách, 7.568 hàng, 669 HĐ, 38 trả, 57 nhập) + hàm `kt-kiot` chạy phần sửa 3 tiếng/lần. Báo cáo mới: Bán hàng, Khách hàng, NCC, Hàng hoá & tồn kho, P&L (thực thu/thực chi + tham chiếu Kiot), Quỹ tiền mặt 3 cửa hàng; nhập liệu Vay & lãi vay, Tài sản (khấu hao đường thẳng); trang chờ Hoá đơn & thuế. Menu: Tổng quan · Nghiệp vụ ▾ · Báo cáo ▾ · Cài đặt ▾; quyền theo module mới. Thêm 4 câu Cần giải đáp (23 câu). Lỗi tự sửa: nạp hàng hoá trùng dòng trong 1 lượt ghi (Kiot trả trùng khi phân trang) → bỏ trùng; nạp hoá đơn quá 150 giây vì thiếu "đến ngày" → thêm; bài kiểm thử cũ giả định ngày trống → đổi sang so trước/sau. Kiểm thử 32/32 + luồng mới 14/14.

- **05/10/2026 11:41** — Tổng quan dạng biểu đồ (anh: "hiện đại, bảng biểu kiểu sơ đồ, thoáng"): bỏ 16 ô tài khoản → biểu đồ thanh 2 chiều quanh trục 0, tự ẩn TK số dư 0 không giao dịch (nút hiện lại), bấm dòng sang đối soát, ĐẶT DƯỚI CÙNG (anh chốt); bảng theo cơ sở → thanh đôi Thu / Chi + chênh lệch; bố cục 2 cột.

- **05/10/2026 11:20** — Anh: "dropdown vs tìm kiếm cho hết lên trên cùng, cách dữ liệu 1 khoảng nhỏ" → hàng bộ lọc (ô chọn + tìm kiếm + nhãn tổng) chuyển lên dải tiêu đề trắng (class `fbar`, tự áp cho mọi trang danh sách trong render()); khung dữ liệu chỉ còn tab + danh sách, cách 14px.

- **05/10/2026 11:15** — Ô lọc mỗi loại 1 màu (loại = tím, cơ sở = xanh ngọc, bộ phận = cam, tài khoản = xanh dương, khác = hồng); tab trạng thái Chi theo màu trạng thái. Trang "Cần giải đáp" (bảng kt_cau_hoi, 19 câu) trong Cài đặt. Cài đặt chia module như app MKT/Sale (menu xổ: Hỏi đáp · Quản trị · Danh mục · Hệ thống, mỗi module 1 trang). Phân quyền: bỏ ô Vị trí (anh: "bỏ phần bộ phận"), chỉ tick Toàn quyền hoặc từng trang theo module Báo cáo / Nghiệp vụ / Quản trị; bảng tài khoản kiểu MKT (Sửa · Đặt lại mật khẩu · Khoá / Mở lại).

- **05/10/2026 10:57** — Anh góp ý giao diện (màu chuẩn, đừng dính nhau): gộp tab + bộ lọc + danh sách vào 1 khung trắng (mọi trang danh sách), dải tiêu đề kéo hết bề ngang, ô / nút cao đều 34px, ô lọc dài đều, nhãn tổng bên phải. Nội dung thu Kiot gọn: tên khách · mô tả · mã phiếu. Job kt-kiot chạy tự động lần đầu 10:47 OK.

- **05/10/2026 10:08** — Đối chiếu T9 app vs sheet tới từng tài khoản: 11/12 TK khớp tuyệt đối; tiền vào và két lệch nhỏ đã giải thích đủ (Kiot tiền mặt theo ngày bán + chi tại quầy, sheet theo ngày nộp két); tiền ra khớp khi tính theo ngày dùng DV (trừ 2 phiếu sheet thiếu TK). Sửa luật Kiot: Cash → két; TTD_/CTD_ và phiếu chứa số TK công ty = chuyển nội bộ. Sửa nhập chi: lấy cả dòng gõ tay không có dấu thời gian, gán loại cho phiếu lương sheet để trống. Thêm nút "Chi theo ngày trả / ngày dùng DV" ở Tổng quan (kt_bao_cao thêm p_chi_theo). Ghi chú đối chiếu: doi-chieu-T9.local.md. Lỗi tự sửa: mất ký tự `\` trong regex SQL (luật nội bộ chưa chạy) → sửa ngay.

- **05/10/2026 09:59** — Anh đổi mốc sang 1/9, làm T9 + Kiot; theme Xero toàn app (font Montserrat); nút con mắt mật khẩu. Kiot API có sổ quỹ (/cashflow) → `kt_dong_bo_kiot()` (thu khách TTHD/TTDH/TT + thu khác, bỏ "Chuyển rút" + phiếu huỷ; tiền mặt quầy → Két). Nhập T9: 914 phiếu Kiot (→ 505 thu), 5 thu ngoài Kiot từ sheet (12 dòng sheet trùng Kiot đã bỏ), 181 chi (đề nghị TT), 14 điều chuyển, 121 công nợ (khớp sheet 681,72 tr), tồn đầu 1/9 khớp sheet. Edge Function + pg_cron `kt-kiot` chạy thử OK. Lỗi tự sửa: đọc số mũ Excel sai (bắt được ở chạy thử, chưa ghi); mảng kiot_ma 2 chiều (ghi đè lại); endDate Kiot không gồm ngày cuối → T9 thiếu 30/9 → job tự bù, rồi 1 khoản BHXH 42,15 tr bị tính 2 lần (sheet + Kiot) → đã ẩn dòng sheet.

- **05/10/2026 09:40** — Anh cho chép khoá (auto mode chặn Claude đọc file khoá MKT → anh nhờ phiên MKT chép sang `kt-keys.local.txt`). Anh đổi đăng nhập sang tài khoản + mật khẩu, phân quyền kiểu MKT. Viết lại phần đăng nhập (phiên băm sha256, sai 5 lần khoá 15 phút, quyền kiểm ở `kt_chan`). Chạy `supabase-schema-kt.sql` lần đầu: lỗi `$` do Claude ghép mã (JS biến `$$` thành `$`) → sửa, chạy lại OK. Tự phát hiện + sửa trước khi chạy: khoá sai mật khẩu không ghi được (raise huỷ lệnh đếm), ô trống gửi chuỗi rỗng, tên CTE `no`. Tạo 3 tài khoản + danh mục (16 TK, 13 đơn vị, 13 loại). Kiểm thử đầu-cuối 32/32, xoá dữ liệu thử, đăng xuất phiên thử. Bỏ chế độ xem thử dữ liệu mẫu (không cần nữa).

- **05/10/2026 09:23** — Anh chốt: khung OK + trang Logic; 3 người quản trị; Kiot kéo riêng 3h/lần; dữ liệu từ 1/8; dùng chung khoá; hạn chế nhập tay; giao diện kiểu phần mềm kế toán. Viết `supabase-schema-kt.sql` (chưa chạy — chưa có khoá) + `index.html` (Tổng quan thẻ + biểu đồ, Dòng tiền & đối soát, Thu dạng sổ quỹ, Chi đề nghị → duyệt → thanh toán + 4A/4B + HĐ đỏ, Điều chuyển, Công nợ, Sắp phải trả, Cài đặt: danh mục / người dùng / Logic / nhật ký / đổi mã). Soát giao diện bằng dữ liệu giả + Chrome headless (máy tính + điện thoại 375px). Sự cố nhỏ tự sửa: 1 lệnh treo vì `cat` chờ stdin (đã dừng, không ghi gì); chạy nhầm script ghép có thể xoá phần Tổng quan (script lỗi trước khi ghi — đã kiểm file còn nguyên); trang Logic lỡ ghi 1 con số thật từ sheet → đã xoá trước khi đẩy.

- **05/10/2026 09:00** — Anh gửi link xuất bản file Đề nghị thanh toán → đã đọc (tab chính + tab lưu theo tháng). Bổ sung đề xuất phần Chi trong chat.
- **05/10/2026 08:44** — Đọc luồng Thu–Chi–Điều chuyển (ảnh anh gửi) + file GG Sheet quản lý dòng tiền (bản xuất bản, 10 tab). File đề nghị thanh toán để riêng tư, chưa đọc được. Phát hiện lỗi số liệu trên sheet (đã báo anh trong chat; KHÔNG ghi số vào repo vì repo public). Gửi đề xuất app, chờ anh duyệt.
- **02/10/2026 14:38** — Tạo repo `hh-vibecode/ke-toan` (public, anh chốt) bằng đăng nhập git có sẵn trên máy, đẩy commit đầu, bật Pages (`main` /). Auto mode chặn 2 lần (đọc credential, tạo repo public) → anh tắt auto mode và duyệt tay.
- **01/10/2026** — Phiên kế toán đầu: `git init` (main, tác giả Hoàng Hải như 2 repo kia), commit khung ở máy. Đọc credential GitHub có sẵn trên máy bị hệ thống chặn → chờ anh cấp token để tạo repo + bật Pages.
- **01/10/2026** — Phiên MKT/Sale dựng sẵn thư mục: `CLAUDE.md`, `VIEC.md`, `BRIEF.md`, `.gitignore`, `favicon.svg`. Chưa git init, chưa có repo, chưa có khoá.
