// Triển khai chụp tồn kho cuối ngày: bảng + hàm (supabase-schema-kt-ton-kho.sql) + 2 lịch pg_cron:
//   'kt-kiot-hang-dem' 16:20 UTC (23:20 VN) kéo đầy đủ hàng hoá · 'kt-ton-kho' 16:40 UTC (23:40 VN) chụp tồn.
// Khoá KT_CRON_KEY đọc từ kt-keys.local.txt, KHÔNG in. Monsieur Claude 09/10/2026
const fs = require('fs'), path = require('path');
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const REF = 'bcrpxfvvjsjpvbksqzls', K = docKhoa();
(async () => {
  await sql(fs.readFileSync(path.join(__dirname, '..', 'supabase-schema-kt-ton-kho.sql'), 'utf8'));
  console.log('SQL tồn kho: OK');
  for (const j of ['kt-kiot-hang-dem', 'kt-ton-kho']) await sql(`select cron.unschedule('${j}') where exists (select 1 from cron.job where jobname = '${j}')`);
  await sql(`select cron.schedule('kt-kiot-hang-dem', '20 16 * * *', $c$select net.http_post(url := 'https://${REF}.supabase.co/functions/v1/kt-kiot',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-kt-cron', '${K.KT_CRON_KEY}'), body := '{"day_du":["hang"]}'::jsonb, timeout_milliseconds := 150000)$c$)`);
  await sql(`select cron.schedule('kt-ton-kho', '40 16 * * *', $c$select public.kt_chup_ton_kho()$c$)`);
  console.log('lịch:', JSON.stringify(await sql(`select jobname, schedule, active from cron.job where jobname like 'kt-%' order by jobname`)));
  console.log('chụp thử:', JSON.stringify(await sql(`select public.kt_chup_ton_kho() r`)));
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
