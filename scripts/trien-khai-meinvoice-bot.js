// Triển khai Edge Function kt-meinvoice-bot (HĐ ĐẦU VÀO công ty THT từ MISA Xử lý hóa đơn) + chạy thử 1 khoảng tháng (CHỈ ĐẾM, không ghi).
// Khoá cron lấy từ lịch pg_cron 'kt-meinvoice' (không cần file khoá có KT_CRON_KEY), KHÔNG in ra. Chạy: node scripts/trien-khai-meinvoice-bot.js [thu YYYY-MM YYYY-MM] [ham]
// "ham" = chỉ deploy. Monsieur Claude 14/10/2026
const fs = require('fs'), path = require('path');
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const REF = 'bcrpxfvvjsjpvbksqzls', K = docKhoa(), API = `https://api.supabase.com/v1/projects/${REF}`;
(async () => {
  const fd = new FormData();
  fd.append('metadata', JSON.stringify({ entrypoint_path: 'index.ts', name: 'kt-meinvoice-bot', verify_jwt: false }));
  fd.append('file', new Blob([fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'kt-meinvoice-bot', 'index.ts'))], { type: 'application/typescript' }), 'index.ts');
  const d = await fetch(API + '/functions/deploy?slug=kt-meinvoice-bot', { method: 'POST', headers: { Authorization: 'Bearer ' + K.SUPABASE_ACCESS_TOKEN }, body: fd });
  console.log('deploy kt-meinvoice-bot:', d.status, d.ok ? '' : (await d.text()).slice(0, 300));
  const i = process.argv.indexOf('thu');
  if (i < 0) return;
  const cmd = (await sql(`select command from cron.job where jobname = 'kt-meinvoice'`))[0].command;
  const khoa = (cmd.match(/'x-kt-cron',\s*'([^']+)'/) || [])[1];
  if (!khoa) throw new Error('không đọc được khoá cron từ lịch kt-meinvoice');
  const r = await fetch(`https://${REF}.supabase.co/functions/v1/kt-meinvoice-bot`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-kt-cron': khoa },
    body: JSON.stringify({ thu: true, tu: process.argv[i + 1], den: process.argv[i + 2] || process.argv[i + 1] }) });
  const t = await r.text(); console.log('chạy thử:', r.status, t.split(khoa).join('[KHOA]').slice(0, 6000));
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
