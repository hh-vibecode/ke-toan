-- 10/11/2026: lịch kt-sao-ke — 13:30 và 01:30 giờ VN (sau kéo HĐ MISA 00:25 / 00:35 / 12:35 và ghép HĐ phiếu thu 00:45–00:55) gọi Edge kt-sao-ke
-- tự tính lại báo cáo Đối chiếu sao kê → link online luôn mới. Lệnh chép từ lịch kt-luu-luong (cùng header x-kt-cron) để khoá không nằm trong file này.
do $$ declare c text; begin
  select replace(replace(command, 'functions/v1/kt-luu-luong', 'functions/v1/kt-sao-ke'), 'timeout_milliseconds := 60000', 'timeout_milliseconds := 120000') into c
    from cron.job where jobname = 'kt-luu-luong';
  if c is null or c not like '%kt-sao-ke%' then raise exception 'Không chép được lệnh mẫu'; end if;
  perform cron.unschedule('kt-sao-ke') where exists (select 1 from cron.job where jobname = 'kt-sao-ke');
  perform cron.schedule('kt-sao-ke', '30 6,18 * * *', c);
  execute c;   -- chạy thử 1 lần ngay
end $$;
