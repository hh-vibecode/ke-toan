# SỔ VIỆC — app KẾ TOÁN (tài chính)

> Mở file này đầu mỗi phiên (sau `git pull`). Xong việc thì xoá khỏi mục ĐANG NỢ và ghi 1 dòng vào NHẬT KÝ.
> Ghi sổ + commit + push NGAY TRONG PHIÊN. Anh đã quyết thì làm, đừng xếp lại vào "chờ anh quyết".

---

## 0. KHỞI TẠO

| # | Việc | Trạng thái |
|---|---|---|
| 1 | Hỏi anh app làm gì | **XONG 05/10** — thay 2 GG Sheet (Quản lý dòng tiền + Đề nghị thanh toán) bằng app 4 phần Thu · Chi · Điều chuyển · Công nợ + báo cáo |
| 2 | Repo + GitHub Pages | **XONG 02/10** — https://hh-vibecode.github.io/ke-toan/ |
| 3 | Khoá → `kt-keys.local.txt` | **CHỜ ANH** — xem mục 1 |
| 4 | Khung app `index.html` + mã truy cập + Đổi mã / Khoá + trang Logic | **XONG 05/10** (soát giao diện bằng dữ liệu giả; CHƯA chạy với CSDL thật) |
| 5 | `supabase-schema-kt.sql` (bảng + hàm kt_*, RLS bật, không policy) | **ĐÃ VIẾT, CHƯA CHẠY** — cần token `sbp_…` |
| 6 | Đẩy bản đầu, kiểm live, báo anh F5 | XONG 05/10 (trang hiện màn nhập mã; đăng nhập chưa được tới khi chạy SQL + tạo mã) |

## 1. ĐANG CHỜ ANH HẢI QUYẾT

| # | Việc | Cần anh nói gì |
|---|---|---|
| 1 | Khoá dùng chung (anh chốt 05/10 "dùng chung khóa"): khoá quản trị Supabase + token `sbp_…` + khoá API Kiot. Luật CLAUDE.md cấm Claude đọc file khoá app khác | Anh tự dán vào `kt-keys.local.txt`, HOẶC cho phép Claude chép (không in ra) từ file khoá của mkt-sale-app |
| 2 | Tồn đầu từng tài khoản ngày 01/08/2026 (sao kê / két) | Số dư 31/07 từng TK — hoặc cho Claude lấy tạm từ sheet rồi kế toán soát |
| 3 | Gộp tên tài khoản (sheet có ~20 cách ghi cho ~13 TK) | Duyệt bảng gộp Claude gửi trong chat |
| 4 | Người đề nghị chi (hàng chục người): mã chung "đề nghị" hay giữ GG Form | Chọn 1 (giai đoạn 1 tạm chỉ 3 người dùng nên chưa gấp) |

## 2. ĐANG NỢ

| # | Việc | Ghi chú |
|---|---|---|
| 1 | Chạy `supabase-schema-kt.sql` + tạo 3 mã (anh Hải, giám đốc, kế toán — quản trị) ghi vào `kt-keys.local.txt` | chờ khoá |
| 2 | Danh mục ban đầu (TK, cơ sở / bộ phận, loại thu / chi + cách chia) từ 2 sheet | `scripts/khoi-tao.js` |
| 3 | Chuyển dữ liệu cũ TỪ 01/08/2026: chi (sheet đề nghị), điều chuyển, công nợ, thu ngoài | Lưu ý: tab DATA THU của sheet chỉ có tháng 9 → thu tháng 8 lấy từ Kiot |
| 4 | Luồng kéo Kiot RIÊNG (workflow `kt-kiot`, 3 tiếng / lần, tránh phút trùng job khác): sổ quỹ → `kt_kiot_so_quy` → phiếu thu sang `kt_thu` | Chưa chắc API Kiot có trả sổ quỹ — kiểm bằng khoá thật; dự phòng: hoá đơn / đơn đặt kèm thanh toán |
| 5 | Ghép tài khoản / chi nhánh Kiot ↔ danh mục app | sau khi kéo được Kiot |
| 6 | Tải ảnh chứng từ thẳng lên app (Supabase Storage riêng tư) — hiện mới dán link | giai đoạn sau |

## 3. QUY TẮC ĐÃ CHỐT (đừng hỏi lại)

- **App riêng, tách biệt hoàn toàn** khỏi MKT/Sale và QC CSKH (anh chốt 1/10/2026). Xem `CLAUDE.md` mục Tách biệt.
- **Tên:** thư mục / repo `ke-toan`. **Tiền tố:** `kt_` (bảng, hàm) · `kt-` (lịch chạy, workflow). Đã đăng ký vào sổ quy ước chung 1/10/2026.
- **Vào app bằng MÃ TRUY CẬP riêng**, mỗi người 1 mã (để nhật ký biết ai làm). Hiện chỉ **anh Hải, giám đốc, kế toán — đều quản trị full** (anh chốt 05/10).
- Mọi thứ Claude tạo ký tên **Monsieur Claude**.
- **Repo public** (anh chốt 2/10/2026) → tuyệt đối không có khoá quản trị / số liệu thật / số tài khoản thật trong code và sổ.
- **GitHub: tự xử lý bằng đăng nhập git có sẵn trên máy** (anh chốt 2/10/2026). Không in token ra.
- **Khung app** theo đề xuất 05/10 (anh đồng ý) + **trang Logic trong Cài đặt** để người khác đọc app tính thế nào. Sửa luật ở SQL thì sửa luôn trang Logic.
- **Phạm vi dữ liệu: từ 01/08/2026** (anh chốt 05/10).
- **Kiot: luồng kéo RIÊNG** của app kế toán, KHÔNG dùng chung / nhờ MKT/Sale; **3 tiếng / lần** (anh chốt 05/10).
- **Khoá Supabase: dùng chung** khoá của project (anh chốt 05/10).
- **Hạn chế nhập tay tối đa**: cái gì chọn được thì danh sách chọn, cái gì kéo được thì kéo tự động (anh chốt 05/10).
- **Giao diện kiểu phần mềm kế toán** (MISA AMIS / Xero / QuickBooks), KHÔNG giống GG Sheet: tổng quan thẻ + biểu đồ, danh sách 2 dòng, sổ quỹ gom theo ngày, xem phiếu bằng ngăn kéo bên phải (anh chốt 05/10).

## 4. PHỤ THUỘC CHÉO (cần app khác làm — nhờ anh chuyển lời)

| # | Cần gì | App nào | Trạng thái |
|---|---|---|---|
| — | (chưa có — Kiot tự kéo riêng theo anh chốt 05/10) | | |

## 5. NHẬT KÝ (mới nhất trước)

- **05/10/2026 09:23** — Anh chốt: khung OK + trang Logic; 3 người quản trị; Kiot kéo riêng 3h/lần; dữ liệu từ 1/8; dùng chung khoá; hạn chế nhập tay; giao diện kiểu phần mềm kế toán. Viết `supabase-schema-kt.sql` (chưa chạy — chưa có khoá) + `index.html` (Tổng quan thẻ + biểu đồ, Dòng tiền & đối soát, Thu dạng sổ quỹ, Chi đề nghị → duyệt → thanh toán + 4A/4B + HĐ đỏ, Điều chuyển, Công nợ, Sắp phải trả, Cài đặt: danh mục / người dùng / Logic / nhật ký / đổi mã). Soát giao diện bằng dữ liệu giả + Chrome headless (máy tính + điện thoại 375px). Sự cố nhỏ tự sửa: 1 lệnh treo vì `cat` chờ stdin (đã dừng, không ghi gì); chạy nhầm script ghép có thể xoá phần Tổng quan (script lỗi trước khi ghi — đã kiểm file còn nguyên); trang Logic lỡ ghi 1 con số thật từ sheet → đã xoá trước khi đẩy.

- **05/10/2026 09:00** — Anh gửi link xuất bản file Đề nghị thanh toán → đã đọc (tab chính + tab lưu theo tháng). Bổ sung đề xuất phần Chi trong chat.
- **05/10/2026 08:44** — Đọc luồng Thu–Chi–Điều chuyển (ảnh anh gửi) + file GG Sheet quản lý dòng tiền (bản xuất bản, 10 tab). File đề nghị thanh toán để riêng tư, chưa đọc được. Phát hiện lỗi số liệu trên sheet (đã báo anh trong chat; KHÔNG ghi số vào repo vì repo public). Gửi đề xuất app, chờ anh duyệt.
- **02/10/2026 14:38** — Tạo repo `hh-vibecode/ke-toan` (public, anh chốt) bằng đăng nhập git có sẵn trên máy, đẩy commit đầu, bật Pages (`main` /). Auto mode chặn 2 lần (đọc credential, tạo repo public) → anh tắt auto mode và duyệt tay.
- **01/10/2026** — Phiên kế toán đầu: `git init` (main, tác giả Hoàng Hải như 2 repo kia), commit khung ở máy. Đọc credential GitHub có sẵn trên máy bị hệ thống chặn → chờ anh cấp token để tạo repo + bật Pages.
- **01/10/2026** — Phiên MKT/Sale dựng sẵn thư mục: `CLAUDE.md`, `VIEC.md`, `BRIEF.md`, `.gitignore`, `favicon.svg`. Chưa git init, chưa có repo, chưa có khoá.
