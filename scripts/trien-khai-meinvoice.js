// Triển khai kéo HOÁ ĐƠN CÔNG TY TỔNG (MISA meInvoice): SQL + secrets KT_MEINVOICE_* + Edge Function kt-meinvoice + lịch pg_cron 'kt-meinvoice'
// (mỗi đêm 00:25 giờ VN). Khoá đọc từ kt-keys.local.txt, KHÔNG in ra. Chạy: Code.exe scripts/trien-khai-meinvoice.js [nap_lai_tu YYYY-MM]
// Có "nap_lai_tu" → sau khi triển khai gọi function nạp lại từ tháng đó tới nay. Monsieur Claude
const fs = require('fs'), path = require('path');
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const REF = 'bcrpxfvvjsjpvbksqzls', K = docKhoa(), API = `https://api.supabase.com/v1/projects/${REF}`;
const H = { Authorization: 'Bearer ' + K.SUPABASE_ACCESS_TOKEN };
(async () => {
  for (const k of ['MEINVOICE_CLIENT_ID', 'MEINVOICE_CLIENT_SECRET', 'MEINVOICE_MST', 'MEINVOICE_USER', 'MEINVOICE_PASS', 'KT_CRON_KEY'])
    if (!K[k]) throw new Error('thiếu ' + k + ' trong kt-keys.local.txt');
  await sql(fs.readFileSync(path.join(__dirname, '..', 'supabase-schema-kt-meinvoice.sql'), 'utf8'));
  console.log('SQL: ok');
  const s = await fetch(API + '/secrets', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' }, body: JSON.stringify(
    ['MEINVOICE_CLIENT_ID', 'MEINVOICE_CLIENT_SECRET', 'MEINVOICE_MST', 'MEINVOICE_USER', 'MEINVOICE_PASS'].map(k => ({ name: 'KT_' + k, value: K[k] }))) });
  console.log('secrets KT_MEINVOICE_*:', s.status);
  const fd = new FormData();
  fd.append('metadata', JSON.stringify({ entrypoint_path: 'index.ts', name: 'kt-meinvoice', verify_jwt: false }));
  fd.append('file', new Blob([fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'kt-meinvoice', 'index.ts'))], { type: 'application/typescript' }), 'index.ts');
  const d = await fetch(API + '/functions/deploy?slug=kt-meinvoice', { method: 'POST', headers: H, body: fd });
  console.log('deploy kt-meinvoice:', d.status, d.ok ? '' : (await d.text()).slice(0, 300));
  // 17:25 UTC = 00:25 giờ VN, lệch khỏi kt-kiot-hang-dem (16:20) và kt-ton-kho (16:40)
  await sql(`select cron.unschedule('kt-meinvoice') where exists (select 1 from cron.job where jobname = 'kt-meinvoice')`);
  await sql(`select cron.schedule('kt-meinvoice', '25 17 * * *', $c$select net.http_post(url := 'https://${REF}.supabase.co/functions/v1/kt-meinvoice',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-kt-cron', '${K.KT_CRON_KEY}'), body := '{}'::jsonb, timeout_milliseconds := 150000)$c$)`);
  console.log('lịch:', JSON.stringify(await sql(`select jobname, schedule, active from cron.job where jobname = 'kt-meinvoice'`)));
  const i = process.argv.indexOf('nap_lai_tu');
  if (i > 0) {
    const r = await fetch(`https://${REF}.supabase.co/functions/v1/kt-meinvoice`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-kt-cron': K.KT_CRON_KEY },
      body: JSON.stringify({ tu: process.argv[i + 1] }) });
    const j = await r.json(); console.log('nạp lại:', r.status, JSON.stringify({ thang: j.thang, ky_hieu: j.ky_hieu, giay: j.giay, loi: j.loi }));
  }
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
