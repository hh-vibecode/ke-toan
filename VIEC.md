# SỔ VIỆC — app KẾ TOÁN (tài chính)

> Mở file này đầu mỗi phiên (sau `git pull`). Xong việc thì xoá khỏi mục ĐANG NỢ và ghi 1 dòng vào NHẬT KÝ.
> Ghi sổ + commit + push NGAY TRONG PHIÊN. Anh đã quyết thì làm, đừng xếp lại vào "chờ anh quyết".

---

## 0. KHỞI TẠO — XONG 05/10/2026

Repo + Pages · khoá (`kt-keys.local.txt`, anh nhờ phiên MKT chép sang 05/10) · `supabase-schema-kt.sql` đã chạy (14 bảng, 24 hàm,
RLS bật, 0 policy, 0 quyền bảng cho anon) · 3 tài khoản + danh mục (`scripts/khoi-tao.js`) · `scripts/kiem-thu.js` 32/32 đạt.
Script: `scripts/khoa.js` (đọc khoá, không in) · `scripts/sql.js` (chạy SQL qua Management API).

## 1. ĐANG CHỜ ANH HẢI QUYẾT

| # | Việc | Cần anh nói gì |
|---|---|---|
| 1 | Tồn đầu từng tài khoản ngày 01/08/2026 (sao kê / két) | Số dư 31/07 từng TK (nhập ở Cài đặt > Tài khoản) |
| 2 | Tài khoản "BIDV - BUI THI HIEN" trùng dãy số với "MSB CN" | Kế toán xác nhận là 1 hay 2 tài khoản |
| 3 | Người đề nghị chi (hàng chục người): cấp tài khoản vị trí Nhân viên chỉ tick "Chi" hay giữ GG Form | Chọn 1 (chưa gấp) |
| 4 | `kt-keys.local.txt` đang chứa cả khoá Meta / OpenAI / Pancake (app kế toán không dùng) | Đồng ý để Claude xoá các dòng đó cho gọn, an toàn? |

## 2. ĐANG NỢ

| # | Việc | Ghi chú |
|---|---|---|
| 1 | Chuyển dữ liệu cũ TỪ 01/08/2026: chi (sheet đề nghị), điều chuyển, công nợ, thu "Thu khác" | DATA THU của sheet chỉ có tháng 9 và phần lớn là thu Kiot → thu bán hàng lấy từ Kiot, tránh cộng 2 lần |
| 2 | Luồng kéo Kiot RIÊNG (workflow `kt-kiot`, 3 tiếng / lần, tránh phút trùng job khác): sổ quỹ → `kt_kiot_so_quy` → phiếu thu sang `kt_thu` | Chưa chắc API Kiot có trả sổ quỹ — kiểm bằng khoá thật; dự phòng: hoá đơn / đơn đặt kèm thanh toán. Cần secrets repo |
| 3 | Ghép tài khoản / chi nhánh Kiot ↔ danh mục app | sau khi kéo được Kiot |
| 4 | Tải ảnh chứng từ thẳng lên app (Supabase Storage riêng tư) — hiện mới dán link | giai đoạn sau |

## 3. QUY TẮC ĐÃ CHỐT (đừng hỏi lại)

- **App riêng, tách biệt hoàn toàn** khỏi MKT/Sale và QC CSKH (anh chốt 1/10/2026). Xem `CLAUDE.md` mục Tách biệt.
- **Tên:** thư mục / repo `ke-toan`. **Tiền tố:** `kt_` (bảng, hàm) · `kt-` (lịch chạy, workflow). Đã đăng ký vào sổ quy ước chung 1/10/2026.
- **Đăng nhập tài khoản + mật khẩu, phân quyền giống app MKT/Sale** (anh chốt 05/10): Supreme / Admin toàn quyền; vị trí khác tick từng trang Xem / Nhập-sửa. Tài khoản RIÊNG app kế toán. Hiện có: `hai` (Supreme), `giamdoc`, `ketoan` (Admin). Mật khẩu ban đầu trong `kt-keys.local.txt`.
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

- **05/10/2026 09:40** — Anh cho chép khoá (auto mode chặn Claude đọc file khoá MKT → anh nhờ phiên MKT chép sang `kt-keys.local.txt`). Anh đổi đăng nhập sang tài khoản + mật khẩu, phân quyền kiểu MKT. Viết lại phần đăng nhập (phiên băm sha256, sai 5 lần khoá 15 phút, quyền kiểm ở `kt_chan`). Chạy `supabase-schema-kt.sql` lần đầu: lỗi `$` do Claude ghép mã (JS biến `$$` thành `$`) → sửa, chạy lại OK. Tự phát hiện + sửa trước khi chạy: khoá sai mật khẩu không ghi được (raise huỷ lệnh đếm), ô trống gửi chuỗi rỗng, tên CTE `no`. Tạo 3 tài khoản + danh mục (16 TK, 13 đơn vị, 13 loại). Kiểm thử đầu-cuối 32/32, xoá dữ liệu thử, đăng xuất phiên thử. Bỏ chế độ xem thử dữ liệu mẫu (không cần nữa).

- **05/10/2026 09:23** — Anh chốt: khung OK + trang Logic; 3 người quản trị; Kiot kéo riêng 3h/lần; dữ liệu từ 1/8; dùng chung khoá; hạn chế nhập tay; giao diện kiểu phần mềm kế toán. Viết `supabase-schema-kt.sql` (chưa chạy — chưa có khoá) + `index.html` (Tổng quan thẻ + biểu đồ, Dòng tiền & đối soát, Thu dạng sổ quỹ, Chi đề nghị → duyệt → thanh toán + 4A/4B + HĐ đỏ, Điều chuyển, Công nợ, Sắp phải trả, Cài đặt: danh mục / người dùng / Logic / nhật ký / đổi mã). Soát giao diện bằng dữ liệu giả + Chrome headless (máy tính + điện thoại 375px). Sự cố nhỏ tự sửa: 1 lệnh treo vì `cat` chờ stdin (đã dừng, không ghi gì); chạy nhầm script ghép có thể xoá phần Tổng quan (script lỗi trước khi ghi — đã kiểm file còn nguyên); trang Logic lỡ ghi 1 con số thật từ sheet → đã xoá trước khi đẩy.

- **05/10/2026 09:00** — Anh gửi link xuất bản file Đề nghị thanh toán → đã đọc (tab chính + tab lưu theo tháng). Bổ sung đề xuất phần Chi trong chat.
- **05/10/2026 08:44** — Đọc luồng Thu–Chi–Điều chuyển (ảnh anh gửi) + file GG Sheet quản lý dòng tiền (bản xuất bản, 10 tab). File đề nghị thanh toán để riêng tư, chưa đọc được. Phát hiện lỗi số liệu trên sheet (đã báo anh trong chat; KHÔNG ghi số vào repo vì repo public). Gửi đề xuất app, chờ anh duyệt.
- **02/10/2026 14:38** — Tạo repo `hh-vibecode/ke-toan` (public, anh chốt) bằng đăng nhập git có sẵn trên máy, đẩy commit đầu, bật Pages (`main` /). Auto mode chặn 2 lần (đọc credential, tạo repo public) → anh tắt auto mode và duyệt tay.
- **01/10/2026** — Phiên kế toán đầu: `git init` (main, tác giả Hoàng Hải như 2 repo kia), commit khung ở máy. Đọc credential GitHub có sẵn trên máy bị hệ thống chặn → chờ anh cấp token để tạo repo + bật Pages.
- **01/10/2026** — Phiên MKT/Sale dựng sẵn thư mục: `CLAUDE.md`, `VIEC.md`, `BRIEF.md`, `.gitignore`, `favicon.svg`. Chưa git init, chưa có repo, chưa có khoá.
