# SỔ VIỆC — app KẾ TOÁN (tài chính)

> Mở file này đầu mỗi phiên (sau `git pull`). Xong việc thì xoá khỏi mục ĐANG NỢ và ghi 1 dòng vào NHẬT KÝ.
> Ghi sổ + commit + push NGAY TRONG PHIÊN. Anh đã quyết thì làm, đừng xếp lại vào "chờ anh quyết".

---

## 0. KHỞI TẠO (phiên đầu tiên làm theo thứ tự)

| # | Việc | Trạng thái |
|---|---|---|
| 1 | Hỏi anh: app kế toán làm những việc gì cụ thể (báo cáo gì, ai dùng, đang làm tay ở đâu — Excel / sheet / phần mềm nào), lấy dữ liệu từ đâu | **CHƯA** — việc đầu tiên |
| 2 | `git init` + tạo repo `hh-vibecode/ke-toan` + bật GitHub Pages | **ĐANG LÀM** — đã git init + commit ở máy (nhánh `main`, remote `origin` đã gắn). Chưa tạo repo trên GitHub: cần GitHub token (việc 3). Repo public giống 2 app kia (Pages miễn phí) |
| 3 | Xin anh khoá → ghi `kt-keys.local.txt`: khoá quản trị Supabase (anh chọn dùng chung của project, hoặc tạo key riêng tên `ke-toan` để lộ thì thu hồi riêng), token Management API (`sbp_…`), GitHub token | chưa |
| 4 | Dựng khung app (1 file `index.html` như 2 app kia, hoặc theo anh chọn) + màn nhập MÃ TRUY CẬP + nút Đổi mã / Khoá | chưa |
| 5 | Bảng `kt_*` (RLS bật, anon không đọc thẳng) + hàm `kt_*` tự kiểm mã; lưu `supabase-schema-kt.sql` | chưa |
| 6 | Đẩy bản đầu, kiểm trang live, báo anh F5 | chưa |

## 1. ĐANG CHỜ ANH HẢI QUYẾT

| # | Việc | Cần anh nói gì |
|---|---|---|
| — | (chưa có) | |

## 2. ĐANG NỢ

| # | Việc | Ghi chú |
|---|---|---|
| — | (chưa có) | |

## 3. QUY TẮC ĐÃ CHỐT (đừng hỏi lại)

- **App riêng, tách biệt hoàn toàn** khỏi MKT/Sale và QC CSKH (anh chốt 1/10/2026). Xem `CLAUDE.md` mục Tách biệt.
- **Tên:** thư mục / repo `ke-toan`. **Tiền tố:** `kt_` (bảng, hàm) · `kt-` (lịch chạy, workflow). Đã đăng ký vào sổ quy ước chung 1/10/2026.
- **Vào app bằng MÃ TRUY CẬP riêng** (giống QC), KHÔNG dùng chung tài khoản đăng nhập của MKT/Sale.
- Mọi thứ Claude tạo ký tên **Monsieur Claude**.

## 4. PHỤ THUỘC CHÉO (cần app khác làm — nhờ anh chuyển lời)

| # | Cần gì | App nào | Trạng thái |
|---|---|---|---|
| — | (chưa có) | | |

Nếu app kế toán cần số bán hàng (doanh thu, đơn Kiot, khách…): CHỈ ĐỌC bảng của MKT/Sale, và nên nhờ phiên MKT/Sale làm
sẵn 1 hàm / view trả đúng số đã chốt (để 2 app không ra 2 con số khác nhau). Tóm tắt nghiệp vụ ở `BRIEF.md` mục 6.

## 5. NHẬT KÝ (mới nhất trước)

- **01/10/2026** — Phiên kế toán đầu: `git init` (main, tác giả Hoàng Hải như 2 repo kia), commit khung ở máy. Đọc credential GitHub có sẵn trên máy bị hệ thống chặn → chờ anh cấp token để tạo repo + bật Pages.
- **01/10/2026** — Phiên MKT/Sale dựng sẵn thư mục: `CLAUDE.md`, `VIEC.md`, `BRIEF.md`, `.gitignore`, `favicon.svg`. Chưa git init, chưa có repo, chưa có khoá.
