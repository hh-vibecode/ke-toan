-- Huỷ "Đã chi tiền" (20/10/2026, kế toán: "1 khoản thủ quỹ đã chuyển sang đã thanh toán nhưng thực tế chị chưa duyệt lệnh, giờ muốn làm lại,
-- phiếu không có nút sửa lại bước, làm thế nào để không phải tạo phiếu lại từ đầu"). Người xác nhận (chi_duyet) / giám đốc đưa phiếu
-- Đã chi tiền → Chờ chi tiền; báo chuông người chi lại; nhật ký ghi lại. — Monsieur Claude
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_luu_chi'::regproc); n := length(d);
  d := replace(d, $a$    or (v_tu = 'cho_tt' and v_tt = 'da_tt' and (v_tq or v_gd))$a$,
                  $a$    or (v_tu = 'cho_tt' and v_tt = 'da_tt' and (v_tq or v_gd))
    or (v_tu = 'da_tt' and v_tt = 'cho_tt' and (v_duyet or v_gd))   -- 20/10: huỷ "Đã chi tiền" (chi nhầm / chưa duyệt lệnh)$a$);
  if length(d) = n then raise exception 'kt_luu_chi: khong thay cho'; end if; execute d;
end $$;
