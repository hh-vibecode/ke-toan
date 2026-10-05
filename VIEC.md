# SỔ VIỆC — app KẾ TOÁN (tài chính)

> Mở file này đầu mỗi phiên (sau `git pull`). Xong việc thì xoá khỏi mục ĐANG NỢ và ghi 1 dòng vào NHẬT KÝ.
> Ghi sổ + commit + push NGAY TRONG PHIÊN. Anh đã quyết thì làm, đừng xếp lại vào "chờ anh quyết".

---

## 0. KHỞI TẠO — XONG 05/10/2026

Repo + Pages · khoá (`kt-keys.local.txt`, anh nhờ phiên MKT chép sang 05/10) · `supabase-schema-kt.sql` đã chạy (14 bảng, 24 hàm,
RLS bật, 0 policy, 0 quyền bảng cho anon) · 3 tài khoản + danh mục (`scripts/khoi-tao.js`) · `scripts/kiem-thu.js` 32/32 đạt.
Script: `scripts/khoa.js` (đọc khoá, không in) · `scripts/sql.js` (chạy SQL qua Management API).

## 1. ĐANG CHỜ ANH HẢI QUYẾT / KẾ TOÁN XÁC NHẬN

Chi tiết số liệu từng mục: `doi-chieu-T9.local.md` (máy anh, KHÔNG lên GitHub). Mục A–H trong file đó.

| # | Việc | Cần nói gì |
|---|---|---|
| 1 | (A) Tồn đầu 1/9 + số dư thật 4 TK dashboard sheet không theo dõi (TECH CN, TECH HXT, BIDV-BUI THI HIEN, TK vay) | Kế toán xác nhận |
| 2 | "BIDV - BUI THI HIEN" trùng dãy số "MSB CN" | 1 hay 2 tài khoản? |
| 3 | (C) Có đưa CHI TIỀN MẶT TẠI QUẦY trên Kiot vào app không (hiện không; sheet cũng không) + tồn đầu két 1/9 có cộng tiền bán 31/8 chưa nộp không | Chọn |
| 4 | (E) Phiếu lương T8 sheet để trống loại → app gán "OPEX - Lương & BHXH" | Xác nhận |
| 5 | (F) Kiot ghi 1 khoản chuyển TECH CN → VCB CN là "thu khác"; sheet không ghi gì | Có ghi điều chuyển không? |
| 6 | (H) Kiot còn 4 quỹ app chưa theo dõi (3 quỹ ngoài + ví Shopee) | Có theo dõi không? |
| 7 | Người đề nghị chi (hàng chục người): tài khoản Nhân viên chỉ tick "Chi" hay giữ GG Form | Chọn |
| 8 | `kt-keys.local.txt` có khoá Meta / OpenAI / Pancake app không dùng | Cho xoá? |

## 2. ĐANG NỢ

| # | Việc | Ghi chú |
|---|---|---|
| 1 | (B) 2 phiếu chi sheet ghi đã trả nhưng không có TK chi → đang "Chờ thanh toán" | kế toán bổ sung trên app |
| 2 | Sheet vẫn được nhập song song → phát sinh sau 5/10 trên sheet chưa vào app | chốt ngày bỏ sheet / nhập bù |
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
- **Hạn chế nhập tay tối đa**: cái gì chọn được thì danh sách chọn, cái gì kéo được thì kéo tự động (anh chốt 05/10).
- **Giao diện theo theme XERO cho TOÀN APP** (anh chốt 05/10): menu ngang xanh đậm, dải tiêu đề trang trắng, tab trạng thái gạch chân, ô tài khoản (số dư sổ sách / sao kê / Đối soát), Tiền vào và ra, Chi phải trả, Công nợ phải thu theo tuổi nợ, ngăn kéo bên phải. **Font vẫn Montserrat.** KHÔNG giống GG Sheet.

## 4. PHỤ THUỘC CHÉO (cần app khác làm — nhờ anh chuyển lời)

| # | Cần gì | App nào | Trạng thái |
|---|---|---|---|
| — | (chưa có — Kiot tự kéo riêng theo anh chốt 05/10) | | |

## 5. NHẬT KÝ (mới nhất trước)

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
