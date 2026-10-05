# SỔ VIỆC — app KẾ TOÁN (tài chính)

> Mở file này đầu mỗi phiên (sau `git pull`). Xong việc thì xoá khỏi mục ĐANG NỢ và ghi 1 dòng vào NHẬT KÝ.
> Ghi sổ + commit + push NGAY TRONG PHIÊN. Anh đã quyết thì làm, đừng xếp lại vào "chờ anh quyết".

---

## 0. KHỞI TẠO (phiên đầu tiên làm theo thứ tự)

| # | Việc | Trạng thái |
|---|---|---|
| 1 | Hỏi anh: app kế toán làm những việc gì cụ thể (báo cáo gì, ai dùng, đang làm tay ở đâu — Excel / sheet / phần mềm nào), lấy dữ liệu từ đâu | **ĐÃ HỎI 1/10, CHỜ ANH TRẢ LỜI** |
| 2 | `git init` + tạo repo `hh-vibecode/ke-toan` + bật GitHub Pages | **XONG 2/10** — repo public, Pages nhánh `main` thư mục gốc (giống 2 app kia): https://hh-vibecode.github.io/ke-toan/ (404 tới khi có `index.html`) |
| 3 | Xin anh khoá → ghi `kt-keys.local.txt`: khoá quản trị Supabase (anh chọn dùng chung của project, hoặc tạo key riêng tên `ke-toan` để lộ thì thu hồi riêng), token Management API (`sbp_…`) | chưa — GitHub KHÔNG cần token riêng: dùng đăng nhập git có sẵn trên máy (anh chốt 2/10) |
| 4 | Dựng khung app (1 file `index.html` như 2 app kia, hoặc theo anh chọn) + màn nhập MÃ TRUY CẬP + nút Đổi mã / Khoá | chưa |
| 5 | Bảng `kt_*` (RLS bật, anon không đọc thẳng) + hàm `kt_*` tự kiểm mã; lưu `supabase-schema-kt.sql` | chưa |
| 6 | Đẩy bản đầu, kiểm trang live, báo anh F5 | chưa |

## 1. ĐANG CHỜ ANH HẢI QUYẾT

| # | Việc | Cần anh nói gì |
|---|---|---|
| 1 | Duyệt đề xuất app (gửi trong chat 05/10): 4 module Thu · Chi · Điều chuyển · Công nợ + báo cáo; chia giai đoạn | Đồng ý / sửa |
| 2 | Ai dùng app, mỗi người 1 mã hay 1 mã / vai trò; người đề nghị chi có vào app không | Danh sách người + vai trò |
| 3 | File 1 (đề nghị thanh toán) đang để riêng tư → em không đọc được | Mở quyền xem bằng link |
| 4 | Thu Kiot tự động: nhờ phiên MKT/Sale đồng bộ sổ quỹ Kiot (phụ thuộc chéo) hay app kế toán tự kéo | Chọn 1 |
| 5 | Khoá Supabase: dùng chung hay tạo key riêng `ke-toan` | Chọn 1 |

## 2. ĐANG NỢ

| # | Việc | Ghi chú |
|---|---|---|
| — | (chưa có) | |

## 3. QUY TẮC ĐÃ CHỐT (đừng hỏi lại)

- **App riêng, tách biệt hoàn toàn** khỏi MKT/Sale và QC CSKH (anh chốt 1/10/2026). Xem `CLAUDE.md` mục Tách biệt.
- **Tên:** thư mục / repo `ke-toan`. **Tiền tố:** `kt_` (bảng, hàm) · `kt-` (lịch chạy, workflow). Đã đăng ký vào sổ quy ước chung 1/10/2026.
- **Vào app bằng MÃ TRUY CẬP riêng** (giống QC), KHÔNG dùng chung tài khoản đăng nhập của MKT/Sale.
- Mọi thứ Claude tạo ký tên **Monsieur Claude**.
- **Repo public** (anh chốt 2/10/2026, để Pages miễn phí như 2 app kia) → tuyệt đối không có khoá quản trị / số liệu trong code.
- **GitHub: tự xử lý bằng đăng nhập git có sẵn trên máy** (anh chốt 2/10/2026), không xin anh tạo token. Không in token ra.

## 4. PHỤ THUỘC CHÉO (cần app khác làm — nhờ anh chuyển lời)

| # | Cần gì | App nào | Trạng thái |
|---|---|---|---|
| — | (chưa có) | | |

Nếu app kế toán cần số bán hàng (doanh thu, đơn Kiot, khách…): CHỈ ĐỌC bảng của MKT/Sale, và nên nhờ phiên MKT/Sale làm
sẵn 1 hàm / view trả đúng số đã chốt (để 2 app không ra 2 con số khác nhau). Tóm tắt nghiệp vụ ở `BRIEF.md` mục 6.

## 5. NHẬT KÝ (mới nhất trước)

- **05/10/2026 08:44** — Đọc luồng Thu–Chi–Điều chuyển (ảnh anh gửi) + file GG Sheet quản lý dòng tiền (bản xuất bản, 10 tab). File đề nghị thanh toán để riêng tư, chưa đọc được. Phát hiện lỗi số liệu trên sheet (đã báo anh trong chat; KHÔNG ghi số vào repo vì repo public). Gửi đề xuất app, chờ anh duyệt.
- **02/10/2026 14:38** — Tạo repo `hh-vibecode/ke-toan` (public, anh chốt) bằng đăng nhập git có sẵn trên máy, đẩy commit đầu, bật Pages (`main` /). Auto mode chặn 2 lần (đọc credential, tạo repo public) → anh tắt auto mode và duyệt tay.
- **01/10/2026** — Phiên kế toán đầu: `git init` (main, tác giả Hoàng Hải như 2 repo kia), commit khung ở máy. Đọc credential GitHub có sẵn trên máy bị hệ thống chặn → chờ anh cấp token để tạo repo + bật Pages.
- **01/10/2026** — Phiên MKT/Sale dựng sẵn thư mục: `CLAUDE.md`, `VIEC.md`, `BRIEF.md`, `.gitignore`, `favicon.svg`. Chưa git init, chưa có repo, chưa có khoá.
