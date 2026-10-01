# BRIEF TRIỂN KHAI APP MỚI — đọc hết trước khi làm bất cứ việc gì

Soạn 01/10/2026 bởi phiên MKT/Sale (Monsieur Claude). Đây là app thứ 3 của anh Hải, sau **MKT/Sale** và **QC CSKH**.
Yêu cầu số 1 của anh: **3 app TÁCH BIỆT, không liên quan tới nhau** — như cách QC CSKH đã tách khỏi MKT/Sale.

---

## 0. Đã chốt khi dựng thư mục (1/10/2026) — chỉ còn hỏi anh điều 1

1. **App làm gì: app tài chính cho KẾ TOÁN.** Việc cụ thể (báo cáo gì, ai dùng, đang làm tay ở đâu, lấy dữ liệu từ đâu) → **HỎI ANH NGAY ĐẦU PHIÊN.**
2. Tên thư mục / repo: **`ke-toan`** (`C:\Users\HP\Desktop\ke-toan`, `hh-vibecode/ke-toan`).
3. Tiền tố: **`kt_`** (bảng, hàm) · **`kt-`** (lịch chạy, workflow) — đã kiểm CSDL chưa có gì mang tiền tố này, đã đăng ký vào sổ quy ước chung.
4. Vào app: **MÃ TRUY CẬP riêng** (giống QC). KHÔNG dùng chung tài khoản / `dang-nhap` / `sales_users`.

---

## 1. Tách biệt — luật cứng

| Thứ | App mới phải có RIÊNG | Tuyệt đối không |
|---|---|---|
| Thư mục | `C:\Users\HP\Desktop\<ten-app>` | làm việc trong `mkt-sale-app`, `qc-cskh`, `1.Dashboard-Meta` |
| Repo / web | `hh-vibecode/<ten-app>` + GitHub Pages riêng | commit / push vào repo app khác |
| Sổ việc | `CLAUDE.md` + `VIEC.md` riêng ở gốc repo | ghi vào sổ của app khác |
| Bộ nhớ Claude | bộ nhớ theo thư mục `ke-toan` (đã có sẵn vài mục về CÁCH LÀM VIỆC với anh) | chép bộ nhớ nghiệp vụ của MKT/QC sang |
| Khoá | `kt-keys.local.txt` (gitignore). Khoá Supabase: anh chọn **dùng chung** khoá quản trị của project hoặc **tạo key riêng** cho app (key riêng chỉ có lợi khi lộ: thu hồi riêng, 2 app kia không dừng) + secrets GitHub của repo này | đọc file khoá của app khác |
| Bảng, hàm, lịch chạy, Edge Function, workflow | đều mang tiền tố của app | tạo thứ không tiền tố |

- Các phiên Claude **không đọc được hội thoại của nhau**. Cần gì từ app khác (thêm cột vào bảng dùng chung, một hàm RPC…) → ghi vào `VIEC.md` mục **"Phụ thuộc chéo"** rồi báo anh chuyển lời. Không tự sửa sang.
- Đăng ký tiền tố: báo anh để phiên MKT/Sale thêm 1 dòng vào sổ đăng ký trong `QUY-UOC-DUNG-CHUNG-SUPABASE.md` (repo mkt-sale-app).

---

## 2. Supabase dùng chung (project `bcrpxfvvjsjpvbksqzls`, gói Pro, máy Micro)

Đọc đủ quy ước: https://github.com/hh-vibecode/mkt-sale-app/blob/main/QUY-UOC-DUNG-CHUNG-SUPABASE.md — tóm tắt:

- **Chỉ ĐỌC** bảng của app khác. Cần ghi → app chủ làm hàm RPC có kiểm tra, app mới gọi hàm đó.
- Bảng dùng chung chỉ được **THÊM** (cột / bảng / hàm), không đổi tên, xoá, đổi kiểu, không đổi RLS / trigger của app khác.
- **Không đụng:** khoá legacy (`anon`, `service_role`), JWT secret, cài đặt Auth (chỉ được THÊM domain của mình vào redirect), Edge Function `dang-nhap`, hàm `la_quan_tri()`, cấu trúc `sales_users`.
- Bảng mới: bật RLS; hàm `security definer` luôn `set search_path=public`, `revoke ... from public, anon`, chỉ `grant` đúng vai.
- Mọi thay đổi CSDL lưu file `supabase-schema-*.sql` trong repo app mới.
- Tài nguyên chung cả 3 app: đọc PHẢI phân trang (PostgREST tối đa 1000 dòng / lần), chỉ chọn cột cần, chỉ đọc phần mới; ghi hàng loạt gộp 1 lệnh + `Prefer: return=minimal`; job nặng chỉ chạy khi dữ liệu đổi. (Egress từng vượt quota gói free ngày 29/9/2026.)
- Lịch chạy app khác đang dùng (giờ VN) — tránh trùng giờ nặng: Pancake mỗi 10 phút + quét toàn bộ 7h05 · 12h30 · 18h00; Kiot phút 5/20/35/50 + 7h20; Meta Ads 7h · 12h · 15h; chốt mốc số liệu 0h · 8h · 16h; sao lưu 1h; QC kéo mỗi giờ phút :25.

---

## 3. Cách làm việc với anh Hải (giống 2 app kia)

- Tiếng Việt, gọi **"anh"**, ký **Monsieur Claude**.
- **Minh bạch, không giấu:** anh không trách khi làm sai. Mỗi báo cáo kể đủ: đã làm sai gì (kể cả đã tự sửa), phần **chưa kiểm** được, **rủi ro tiềm tàng** (dữ liệu, quyền, bảo mật, job, số liệu). Không chắc thì nói không chắc.
- **Tự làm, không giao việc cho anh:** SQL, deploy, cấu hình làm được thì tự làm rồi báo. Anh đã quyết thì làm, đừng hỏi lại.
- **Commit:** tự pull → `git diff --cached --stat` (chỉ đúng file mình sửa) → commit → push. Push bị từ chối → `git pull --rebase`, xung đột giải TAY từng chỗ, kiểm 0 dấu `<<<<<<<` rồi mới push; mỗi bước 1 lệnh, không nối `&&` sau bước kiểm.
- **Đóng dấu phiên bản** (`APP_VERSION`) bằng **giờ máy thật** (`date` / `Get-Date`), không tự ước giờ. Đẩy xong đợi trang live hiện đúng bản mới rồi **báo anh F5**.
- **Ghi sổ ngay trong phiên** (`VIEC.md`: đang nợ · chờ anh quyết · quy tắc đã chốt · nhật ký), commit + push trước khi kết thúc phiên.
- **Khoá / token:** không in ra màn hình, không dán vào chat, không commit. Soát file khoá thì CHỈ in tên dòng (`grep -o '^[A-Z_]*'`) — 30/9 một lệnh che chỉ được giá trị cùng dòng nên làm lộ token nằm dòng dưới.
- Thao tác ra ngoài khó gỡ (ghi / xoá hàng loạt trên Pancake, Kiot, gửi tin khách): chạy thử `KHO=1`, báo số trước.
- Thẻ khách Pancake nằm ở `data.customer.shop_customer.tags`; `PUT` thẻ là ghi đè cả bộ — gửi đủ thẻ cũ + mới.

## 4. Giao diện (anh đã chốt)

- Không icon emoji trang trí (chỉ icon SVG + ký hiệu nút ✏ ✓ ✕ ▶ ☰). Không đoạn chú thích dài dưới tiêu đề thẻ — dùng badge gọn.
- Bảng: số căn phải thẳng cột, tiêu đề cùng phía dữ liệu. Thẻ chỉ số: 3 thẻ / hàng, hàng 1 tiền, hàng 2 số lượng.
- Thêm trạng thái / lựa chọn mới thì bộ lọc, thẻ, màu phải nhận ngay.

## 5. Máy anh (Windows)

- Không có `node` / `gh` cài sẵn: chạy script bằng `ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" file.js`.
- Chạy SQL qua Supabase Management API (token `sbp_…` trong file khoá riêng của app mới — xin anh); mẫu script: `scripts/sql.js` trong repo mkt-sale-app (CHỈ ĐỌC để tham khảo, chép sang repo mới).
- Chụp màn hình app: Chrome headless + cổng debug (đã dùng được 30/9).

## 6. Nếu app mới cần dữ liệu bán hàng (đọc từ bảng của MKT/Sale)

Chỉ đọc, và nhớ các luật nghiệp vụ đã chốt để số khớp 2 app kia:
- Doanh thu Sale = **đơn đặt hàng Kiot** (`kiot_orders`), không phải hoá đơn; ngày chốt = ngày tạo đơn; chỉ tính đơn có **dấu vết tiền** (đã trả / hoá đơn hoàn thành / cọc) từ 1/6/2026.
- Pancake ↔ Kiot nối **chỉ** bằng Mã KH Sale ghi trong ghi chú đơn Pancake. Trùng SĐT = 1 khách.
- Sỉ / Lẻ: chi nhánh Kiot "Tổng kho sỉ Shidai" = Sỉ; thẻ Pancake KH SỈ / KH LẺ.
- Tên Sale chuẩn = tên trong bảng `sale_nhan_su`.
- Muốn số khớp tuyệt đối thì nhờ phiên MKT/Sale làm hàm / view có sẵn số (qua anh), đừng tự tính lại theo cách riêng.

---

## 7. Checklist khởi động

Thư mục, `CLAUDE.md`, `VIEC.md`, `.gitignore`, `favicon.svg` đã dựng sẵn; tiền tố đã đăng ký. Còn lại làm theo `VIEC.md` mục 0:
hỏi anh app làm gì → `git init` + repo + GitHub Pages → xin khoá ghi `kt-keys.local.txt` → dựng khung + màn mã truy cập →
bảng / hàm `kt_*` (RLS bật) + `supabase-schema-kt.sql` → đẩy bản đầu, kiểm trang live, báo anh F5.

---

## Câu mở phiên (anh dán vào phiên Claude mới, mở ở thư mục `C:\Users\HP\Desktop\ke-toan`)

> Đọc `CLAUDE.md`, `VIEC.md` và `BRIEF.md` trong thư mục này rồi làm theo. Đây là app kế toán riêng, tách biệt hoàn toàn khỏi app MKT/Sale và app QC CSKH. Bắt đầu bằng việc hỏi anh app cần làm những gì.
