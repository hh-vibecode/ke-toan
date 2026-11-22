-- 03/11/2026 anh: "set lịch kéo định kỳ 2 lần/ngày" — MISA meInvoice (HĐ đầu ra công ty) + MISA Bot (HĐ đầu vào) thêm lượt trưa,
-- cùng lệnh với lượt đêm (00:25 / 00:35 giờ VN) → thêm 12:25 / 12:35 giờ VN. Lệnh chép từ lịch cũ (không ghi khoá vào file). — Monsieur Claude
do $$ declare c text; begin
  select command into c from cron.job where jobname = 'kt-meinvoice';
  if c is null then raise exception 'khong thay kt-meinvoice'; end if;
  perform cron.schedule('kt-meinvoice-trua', '25 5 * * *', c);
  select command into c from cron.job where jobname = 'kt-meinvoice-bot';
  if c is null then raise exception 'khong thay kt-meinvoice-bot'; end if;
  perform cron.schedule('kt-meinvoice-bot-trua', '35 5 * * *', c);
end $$;
select jobname, schedule, active from cron.job where jobname like 'kt-meinvoice%' order by 1;
