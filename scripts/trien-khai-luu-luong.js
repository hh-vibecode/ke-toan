// Triển khai Edge Function kt-luu-luong + secret KT_SB_PAT + lịch kt-luu-luong (23:55 VN). Dùng: trien-khai-luu-luong.js [secret] [lich] [chay]
// Không in khoá ra màn hình. Monsieur Claude 22/10/2026
const fs = require('fs'), path = require('path');
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const REF = 'bcrpxfvvjsjpvbksqzls', K = docKhoa(), API = `https://api.supabase.com/v1/projects/${REF}`, A = process.argv.slice(2);
const H = { Authorization: 'Bearer ' + K.SUPABASE_ACCESS_TOKEN };
(async () => {
  if (A.includes('secret')) {
    const r = await fetch(API + '/secrets', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' }, body: JSON.stringify([{ name: 'KT_SB_PAT', value: K.SUPABASE_ACCESS_TOKEN }]) });
    console.log('secret KT_SB_PAT:', r.status);
  }
  const fd = new FormData();
  fd.append('metadata', JSON.stringify({ entrypoint_path: 'index.ts', name: 'kt-luu-luong', verify_jwt: false }));
  fd.append('file', new Blob([fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'kt-luu-luong', 'index.ts'))], { type: 'application/typescript' }), 'index.ts');
  const d = await fetch(API + '/functions/deploy?slug=kt-luu-luong', { method: 'POST', headers: H, body: fd });
  console.log('deploy kt-luu-luong:', d.status, d.ok ? '' : (await d.text()).slice(0, 300));
  const cmd = (await sql(`select command from cron.job where jobname = 'kt-meinvoice'`))[0].command;
  const khoa = (cmd.match(/'x-kt-cron',\s*'([^']+)'/) || [])[1];
  if (!khoa) throw new Error('không đọc được khoá cron');
  if (A.includes('lich')) {   // 16:55 UTC = 23:55 giờ VN
    await sql(`select cron.unschedule('kt-luu-luong') where exists (select 1 from cron.job where jobname = 'kt-luu-luong')`);
    await sql(`select cron.schedule('kt-luu-luong', '55 16 * * *', $c$select net.http_post(url := 'https://${REF}.supabase.co/functions/v1/kt-luu-luong',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-kt-cron', '${khoa}'), body := '{}'::jsonb, timeout_milliseconds := 60000)$c$)`);
    console.log('lịch:', JSON.stringify(await sql(`select jobname, schedule, active from cron.job where jobname = 'kt-luu-luong'`)));
  }
  if (A.includes('chay')) {
    const r = await fetch(`https://${REF}.supabase.co/functions/v1/kt-luu-luong`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-kt-cron': khoa }, body: '{}' });
    console.log('chạy:', r.status, (await r.text()).split(khoa).join('[KHOA]').slice(0, 600));
  }
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
