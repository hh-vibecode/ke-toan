// Triển khai Edge Function kt-so-hh (chia sẻ hoa hồng + quy tắc sang app MKT, so đơn hằng đêm). Dùng: trien-khai-so-hh.js [chay]
// chay = gọi thử 1 lần (khoá cron đọc từ lịch, không in). Monsieur Claude 16/11/2026
const fs = require('fs'), path = require('path');
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const REF = 'bcrpxfvvjsjpvbksqzls', K = docKhoa(), API = `https://api.supabase.com/v1/projects/${REF}`, A = process.argv.slice(2);
const H = { Authorization: 'Bearer ' + K.SUPABASE_ACCESS_TOKEN };
(async () => {
  const fd = new FormData();
  fd.append('metadata', JSON.stringify({ entrypoint_path: 'index.ts', name: 'kt-so-hh', verify_jwt: false }));
  fd.append('file', new Blob([fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'kt-so-hh', 'index.ts'))], { type: 'application/typescript' }), 'index.ts');
  const d = await fetch(API + '/functions/deploy?slug=kt-so-hh', { method: 'POST', headers: H, body: fd });
  console.log('deploy kt-so-hh:', d.status, d.ok ? '' : (await d.text()).slice(0, 300));
  if (A.includes('chay')) {
    const cmd = (await sql(`select command from cron.job where jobname = 'kt-sao-ke'`))[0].command;
    const khoa = (cmd.match(/'x-kt-cron',\s*'([^']+)'/) || [])[1];
    if (!khoa) throw new Error('không đọc được khoá cron');
    const t0 = Date.now(), r = await fetch(`https://${REF}.supabase.co/functions/v1/kt-so-hh`, { method: 'POST', headers: { 'x-kt-cron': khoa, 'Content-Type': 'application/json' }, body: '{}' });
    console.log('chạy:', r.status, (await r.text()).slice(0, 500), (Date.now() - t0) + ' ms');
  }
})().catch(e => { console.error(e.message); process.exit(1); });
