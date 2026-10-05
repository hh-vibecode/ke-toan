# App KẾ TOÁN (tài chính) — luật làm việc cho Claude

Làm việc bằng tiếng Việt, gọi người dùng là **anh** (anh Hải). Mọi thứ Claude tạo ký tên **Monsieur Claude**.
**Đầu mỗi phiên: `git pull` rồi đọc `VIEC.md`** (sổ việc: đang nợ, chờ anh quyết, quy tắc đã chốt, nhật ký).
Xong việc thì cập nhật sổ ngay trong phiên, commit + push trước khi kết thúc. Anh đã quyết rồi thì LÀM, đừng hỏi lại.
Bối cảnh đầy đủ lúc khởi tạo: `BRIEF.md` (đọc 1 lần ở phiên đầu).

## Tách biệt (anh chốt 1/10/2026: "3 app không liên quan tới nhau")
- App này là app RIÊNG: thư mục `C:\Users\HP\Desktop\ke-toan`, repo `hh-vibecode/ke-toan`, GitHub Pages riêng.
- KHÔNG sửa / commit / ghi sổ vào repo khác: `mkt-sale-app` (MKT/Sale), `qc-cskh` (QC CSKH), `1.Dashboard-Meta` (chỉ đọc).
  Không đọc file khoá của app khác. Phiên Claude của các app KHÔNG đọc được hội thoại của nhau.
- Cần gì từ app khác (cột mới trên bảng dùng chung, một hàm RPC, số liệu đã tính sẵn) → ghi `VIEC.md` mục "Phụ thuộc chéo",
  báo anh chuyển lời cho phiên app đó. Không tự sửa sang.
- **Tiền tố riêng: `kt_`** (bảng, view, hàm) và **`kt-`** (lịch pg_cron, Edge Function, workflow, khoá trong `job_moc`).
  Đã đăng ký trong `QUY-UOC-DUNG-CHUNG-SUPABASE.md` (repo mkt-sale-app) ngày 1/10/2026.
- **Đăng nhập bằng TÀI KHOẢN + MẬT KHẨU riêng của app kế toán** (bảng `kt_nguoi_dung`), phân quyền KIỂU app MKT/Sale
  (Supreme / Admin toàn quyền, vị trí khác tick từng trang xem / sửa) — anh chốt 05/10/2026. KHÔNG dùng chung
  `sales_users` / `dang-nhap` của MKT.

## Supabase dùng chung (`bcrpxfvvjsjpvbksqzls`)
- Quy ước đầy đủ: https://github.com/hh-vibecode/mkt-sale-app/blob/main/QUY-UOC-DUNG-CHUNG-SUPABASE.md
- Chỉ ĐỌC bảng app khác; bảng dùng chung chỉ được THÊM; không đụng khoá legacy (anon, service_role), JWT secret,
  cài đặt Auth, Edge Function `dang-nhap`, hàm `la_quan_tri()`, cấu trúc `sales_users`.
- Dữ liệu tài chính là nhạy cảm: bảng `kt_*` bật RLS, KHÔNG cho anon đọc thẳng. Trình duyệt chỉ gọi hàm `kt_*`
  (security definer, `set search_path=public`) và hàm tự kiểm phiên đăng nhập + quyền theo trang (`kt_chan`; mật khẩu băm bcrypt, có Đổi mật khẩu). Không bao giờ
  đặt khoá quản trị trong trang web.
- Đọc phải phân trang (tối đa 1000 dòng / lần), chỉ chọn cột cần, chỉ đọc phần mới; ghi hàng loạt gộp 1 lệnh, `return=minimal`;
  job nặng chỉ chạy khi dữ liệu đổi. Mọi thay đổi CSDL lưu file `supabase-schema-*.sql`.

## Cách làm việc
- **Minh bạch, không giấu:** anh không trách khi làm sai. Mỗi báo cáo kể đủ việc làm sai (kể cả đã tự sửa), phần CHƯA kiểm
  được, rủi ro tiềm tàng (dữ liệu, quyền, bảo mật, job, số liệu). Không chắc thì nói không chắc. Cùng nhau giải quyết.
- **Tự làm, không giao việc cho anh:** SQL, deploy, cấu hình làm được thì tự làm rồi báo. Chỉ nhờ anh khi thật sự bị chặn.
- **Commit:** pull → `git diff --cached --stat` (chỉ đúng file mình sửa) → commit → push. Push bị từ chối → `git pull --rebase`,
  xung đột giải TAY từng chỗ, kiểm 0 dấu `<<<<<<<` và cú pháp OK rồi mới push — mỗi bước 1 lệnh, không nối `&&` sau bước kiểm.
- **Đóng dấu `APP_VERSION` bằng giờ máy thật** (`date` / `Get-Date`), không tự ước. Đẩy xong đợi trang live hiện đúng bản mới
  rồi **báo anh F5**.
- **Khoá / token / mật khẩu:** không in ra màn hình, không dán vào chat, không commit. Máy: `kt-keys.local.txt` (gitignore).
  Soát file khoá CHỈ in tên dòng (`grep -o '^[A-Z_]*'`) — giá trị nằm dòng dưới vẫn có thể bị in lộ (sự cố 30/9).
- Thao tác ra ngoài khó gỡ (ghi / xoá hàng loạt trên phần mềm khác): chạy thử trước, báo số trước.
- Số liệu tài chính: đối chiếu với nguồn gốc trước khi trình; thiếu dữ liệu KHÔNG phải là khớp.

## Giao diện (anh đã chốt cho mọi app)
- Không icon emoji trang trí (chỉ icon SVG + ký hiệu nút ✏ ✓ ✕ ▶ ☰). Không đoạn chú thích dài dưới tiêu đề thẻ — dùng badge gọn.
- Bảng: số căn phải thẳng cột, tiêu đề cùng phía dữ liệu. Thẻ chỉ số: 3 thẻ / hàng, hàng 1 tiền, hàng 2 số lượng.
- Thêm trạng thái / lựa chọn mới thì bộ lọc, thẻ, màu phải nhận ngay.

## Máy anh (Windows)
- Không có `node` / `gh`: chạy script bằng `ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" file.js`.
- SQL qua Supabase Management API (token `sbp_…` trong `kt-keys.local.txt`). GitHub API bằng token trong cùng file.
