-- CHIA SẺ HOA HỒNG + QUY TẮC CHO APP MKT (so đơn hằng đêm) — 17/11/2026. Monsieur Claude
-- Anh (qua phiên MKT/SALE, 17/11): "không so khớp với kế toán ở doanh thu nữa, cái cần so khớp là số lượng đơn onl off xem đã chuẩn dữ liệu ghi nhận giữa 2 bên chưa,
-- và sale đã được ghi nhận đủ đơn chưa", "bắt đầu so từ tháng 11", "bảo kế toán share phần hoa hồng, hỗ trợ check cuối mỗi ngày xem các đơn đã được ghi nhận
-- đúng đủ cho các sale chưa, share cả phần quy tắc hoa hồng xem hoa hồng của sale đã đúng chưa".
-- Edge kt-so-hh (lịch kt-so-hh 21:40 VN, sau kt-so-dt-2app 21:30, trước lượt MKT 22:20): tính bằng ĐÚNG hhTinh của trang Hoa hồng (đoạn <hh-tinh-chung>
-- trong index.html đang chạy) → cột hh / hh_ly của dòng ben='kt' trong so_dt_2app + bảng so_dt_2app_quy_tac (ben='kt'). Ngoại lệ bảng so chung: CLAUDE.md.

-- ghi hoa hồng từng mã (phần vai "Bán" của sale) — CHỈ service_role
create or replace function public.kt_so_dt_2app_hh(p_thang text, p_ds jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update so_dt_2app s set hh = coalesce((x->>'hh')::numeric, 0), hh_ly = x->>'hh_ly'
    from jsonb_array_elements(p_ds) x
   where s.ben = 'kt' and s.thang = p_thang and s.ma = x->>'ma';
  get diagnostics n = row_count;
  update so_dt_2app s set hh = 0, hh_ly = 'Không có hoa hồng bán theo đơn trong tháng: chưa có tiền về trong tháng, hoặc nhân viên cửa hàng — hưởng theo quỹ cửa hàng (quy tắc kt:logic_4), hoặc người bán chưa có trong cấu hình hoa hồng'
   where s.ben = 'kt' and s.thang = p_thang and not exists (select 1 from jsonb_array_elements(p_ds) x where x->>'ma' = s.ma);
  return n;
end $$;
revoke all on function public.kt_so_dt_2app_hh(text, jsonb) from public, anon, authenticated;
grant execute on function public.kt_so_dt_2app_hh(text, jsonb) to service_role;

-- ghi lại toàn bộ quy tắc hoa hồng bên kế toán (xoá + ghi dòng ben='kt') — CHỈ service_role
create or replace function public.kt_so_dt_2app_quy_tac_ghi(p_ds jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from so_dt_2app_quy_tac where ben = 'kt';
  insert into so_dt_2app_quy_tac (khoa, ben, noi_dung, ap_tu, ap_den, luc)
  select 'kt:' || regexp_replace(x->>'khoa', '^kt:', ''), 'kt', x->>'noi_dung', nullif(x->>'ap_tu', '')::date, nullif(x->>'ap_den', '')::date, now()
    from jsonb_array_elements(p_ds) x where coalesce(x->>'khoa', '') <> '';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.kt_so_dt_2app_quy_tac_ghi(jsonb) from public, anon, authenticated;
grant execute on function public.kt_so_dt_2app_quy_tac_ghi(jsonb) to service_role;

-- lịch kt-so-hh 21:40 VN (14:40 UTC): lệnh chép từ lịch kt-sao-ke (khoá không nằm trong file này)
do $$ declare c text; begin
  select replace(command, 'functions/v1/kt-sao-ke''', 'functions/v1/kt-so-hh''') into c from cron.job where jobname = 'kt-sao-ke';
  if c is null or c not like '%kt-so-hh%' then raise exception 'Không chép được lệnh mẫu'; end if;
  perform cron.unschedule('kt-so-hh') where exists (select 1 from cron.job where jobname = 'kt-so-hh');
  perform cron.schedule('kt-so-hh', '40 14 * * *', c);
end $$;
