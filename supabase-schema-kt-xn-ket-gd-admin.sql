-- 09/11/2026 anh (ảnh trang Điều chuyển tiền): "giám đốc và tài khoản admin đều nhìn được phần này và có thể ấn xác nhận".
-- Thay luật 20/10 ("tiền vào két chỉ thủ quỹ xác nhận, admin kế toán không bấm được"): bước "Đã nhận tiền" vào két (điều chuyển + phiếu thu tiền mặt chờ nhận)
-- cho thủ quỹ (chi_tt) + Supreme + Admin + giám đốc (quyền chi_gd). Người bấm ghi vào tq_nhan_boi / xac_nhan_boi như cũ. — Monsieur Claude
create or replace function public.kt_xn_ket(u kt_nguoi_dung) returns boolean language sql immutable set search_path = public as $$
  select kt_la_thu_quy(u) or u.vi_tri in ('supreme', 'admin') or 'chi_gd' = any(coalesce(u.quyen, '{}'));
$$;
do $$ declare d text; begin
  d := pg_get_functiondef('public.kt_tq_nhan(text, text, bigint, boolean)'::regprocedure);
  if position('if not kt_la_thu_quy(u) then' in d) > 0 then
    d := replace(d, 'if not kt_la_thu_quy(u) then raise exception ''Thủ quỹ xác nhận đã nhận tiền''', 'if not kt_xn_ket(u) then raise exception ''Chỉ thủ quỹ, giám đốc hoặc admin xác nhận đã nhận tiền''');
    if position('kt_xn_ket(u)' in d) = 0 then raise exception 'kt_tq_nhan đổi cấu trúc — soát tay'; end if;
    execute d;
  end if;
  d := pg_get_functiondef('public.kt_luu_dieu_chuyen(text, jsonb)'::regprocedure);
  if position('and not kt_la_thu_quy(u)' in d) > 0 then
    d := replace(d, 'and not kt_la_thu_quy(u)', 'and not kt_xn_ket(u)');
    d := replace(d, 'Tiền vào két: thủ quỹ bấm "Đã nhận tiền" để xác nhận', 'Tiền vào két: thủ quỹ, giám đốc hoặc admin bấm "Đã nhận tiền" để xác nhận');
    execute d;
  end if;
end $$;
