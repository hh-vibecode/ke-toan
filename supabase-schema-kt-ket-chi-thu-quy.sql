-- 20/10/2026 (anh): "Đóng quyền admin được ấn xác nhận điều chuyển tiền từ quỹ cửa hàng sang két tiền mặt — xử lý chưa?"
-- Bản trước (kt-dc-vao-ket.sql) kiểm kt_co_quyen(u, 'chi_tt') → vị trí Admin / Supreme / '*' coi như có MỌI quyền nên tài khoản Admin (ketoan, giamdoc)
-- vẫn bấm được; chỉ chặn được TK nhân viên (admin.ketoan). Sửa: tiền vào KÉT chỉ người được tick vai THỦ QUỸ ('chi_tt' trong quyen) xác nhận;
-- Supreme (chủ app) giữ quyền để gỡ khi cần. Monsieur Claude
create or replace function public.kt_la_thu_quy(u kt_nguoi_dung) returns boolean language sql immutable as $$
  select u.vi_tri = 'supreme' or 'chi_tt' = any(coalesce(u.quyen, '{}'));
$$;

do $$
declare d text;
begin
  -- 2 hàm đang chạy: thay đúng chỗ kiểm quyền thủ quỹ (giữ nguyên phần còn lại của hàm)
  d := pg_get_functiondef('public.kt_luu_dieu_chuyen(text, jsonb)'::regprocedure);
  if position('not kt_co_quyen(u, ''chi_tt'')' in d) = 0 then raise exception 'kt_luu_dieu_chuyen: không thấy chỗ kiểm chi_tt'; end if;
  execute replace(d, 'not kt_co_quyen(u, ''chi_tt'')', 'not kt_la_thu_quy(u)');
  d := pg_get_functiondef('public.kt_tq_nhan(text, text, bigint, boolean)'::regprocedure);
  if position('not kt_co_quyen(u, ''chi_tt'')' in d) = 0 then raise exception 'kt_tq_nhan: không thấy chỗ kiểm chi_tt'; end if;
  execute replace(d, 'not kt_co_quyen(u, ''chi_tt'')', 'not kt_la_thu_quy(u)');
end $$;
