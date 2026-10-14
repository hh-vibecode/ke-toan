// Triển khai Nhật ký kéo + So khớp Kiot (14/10/2026): SQL supabase-schema-kt-kiot-doi-chieu.sql · Edge Function kt-kiot (bản có so khớp)
// · lịch pg_cron 'kt-kiot-doi-chieu' 16:50 UTC (23:50 VN) so tháng này + tháng trước.
// Khoá KT_CRON_KEY: lấy từ kt-keys.local.txt, không có thì đọc từ lịch 'kt-kiot' đang chạy — KHÔNG in ra. Monsieur Claude
const fs = require('fs'), path = require('path');
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const REF = 'bcrpxfvvjsjpvbksqzls', K = docKhoa(), API = `https://api.supabase.com/v1/projects/${REF}`;
const H = { Authorization: 'Bearer ' + K.SUPABASE_ACCESS_TOKEN };
(async () => {
  const chi = process.argv[2];   // 'ham' = chỉ deploy Edge Function
  if (chi !== 'ham') { await sql(fs.readFileSync(path.join(__dirname, '..', 'supabase-schema-kt-kiot-doi-chieu.sql'), 'utf8')); console.log('SQL: OK'); }
  const fd = new FormData();
  fd.append('metadata', JSON.stringify({ entrypoint_path: 'index.ts', name: 'kt-kiot', verify_jwt: false }));
  fd.append('file', new Blob([fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'kt-kiot', 'index.ts'))], { type: 'application/typescript' }), 'index.ts');
  const d = await fetch(API + '/functions/deploy?slug=kt-kiot', { method: 'POST', headers: H, body: fd });
  const t = await d.text(); console.log('deploy kt-kiot:', d.status, d.ok ? JSON.parse(t).version : t.slice(0, 500));
  if (!d.ok || chi === 'ham') return;
  let cron = K.KT_CRON_KEY;
  if (!cron) { const j = await sql(`select command from cron.job where jobname = 'kt-kiot'`); const m = String(j[0].command).match(/'x-kt-cron',\s*'([0-9a-f]+)'/); cron = m && m[1]; }
  if (!cron) throw new Error('không tìm thấy KT_CRON_KEY');
  await sql(`select cron.unschedule('kt-kiot-doi-chieu') where exists (select 1 from cron.job where jobname = 'kt-kiot-doi-chieu')`);
  await sql(`select cron.schedule('kt-kiot-doi-chieu', '50 16 * * *', $c$select net.http_post(url := 'https://${REF}.supabase.co/functions/v1/kt-kiot',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-kt-cron', '${cron}'), body := '{"doi_chieu":{}}'::jsonb, timeout_milliseconds := 150000)$c$)`);
  console.log('lịch:', JSON.stringify(await sql(`select jobname, schedule, active from cron.job where jobname like 'kt-%' order by jobname`)));
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
