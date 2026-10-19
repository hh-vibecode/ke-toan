-- Người đang trong app: KHÔNG báo danh / không hiện tài khoản tạm dùng để test (tam-…, tên "Thử giao diện") — 19/10/2026, anh hỏi "Thử giao diện là mày à". — Monsieur Claude
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_bao_danh'::regproc); n := length(d);
  d := replace(d, $a$  if coalesce(current_setting('kt.chi_xem', true), '') <> '1' then$a$, $a$  if coalesce(current_setting('kt.chi_xem', true), '') <> '1' and u.ten_dang_nhap not like 'tam-%' then$a$);
  if length(d) = n then raise exception 'kt_bao_danh: khong thay cho'; end if; execute d;
end $$;
delete from kt_dang_xem d where not exists (select 1 from kt_nguoi_dung n where n.id = d.nguoi_dung_id and n.ten_dang_nhap not like 'tam-%');
