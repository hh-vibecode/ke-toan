// Triển khai Edge Function kt-meinvoice-bot (HĐ ĐẦU VÀO công ty THT từ MISA Xử lý hóa đơn → kt_thue_hd + tự ghép phiếu chi chưa nhận HĐ).
// Chạy: node scripts/trien-khai-meinvoice-bot.js [sql] [lich] [thu|nap YYYY-MM [YYYY-MM]]
//   sql = chạy supabase-schema-kt-hd-vao.sql · lich = đặt pg_cron 'kt-meinvoice-bot' 00:35 giờ VN · thu = CHỈ ĐẾM · nap = ghi + ghép (thêm khong_ghep = ghi HĐ, chỉ đếm số phiếu sẽ ghép).
// Khoá cron lấy từ lịch pg_cron 'kt-meinvoice' (phiên cloud không có KT_CRON_KEY trong file khoá), KHÔNG in ra. Monsieur Claude 14/10/2026
const fs = require('fs'), path = require('path');
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const REF = 'bcrpxfvvjsjpvbksqzls', K = docKhoa(), API = `https://api.supabase.com/v1/projects/${REF}`, A = process.argv.slice(2);
(async () => {
  if (A.includes('sql')) { await sql(fs.readFileSync(path.join(__dirname, '..', 'supabase-schema-kt-hd-vao.sql'), 'utf8')); console.log('SQL: ok'); }
  const fd = new FormData();
  fd.append('metadata', JSON.stringify({ entrypoint_path: 'index.ts', name: 'kt-meinvoice-bot', verify_jwt: false }));
  fd.append('file', new Blob([fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'kt-meinvoice-bot', 'index.ts'))], { type: 'application/typescript' }), 'index.ts');
  const d = await fetch(API + '/functions/deploy?slug=kt-meinvoice-bot', { method: 'POST', headers: { Authorization: 'Bearer ' + K.SUPABASE_ACCESS_TOKEN }, body: fd });
  console.log('deploy kt-meinvoice-bot:', d.status, d.ok ? '' : (await d.text()).slice(0, 300));
  const cmd = (await sql(`select command from cron.job where jobname = 'kt-meinvoice'`))[0].command;
  const khoa = (cmd.match(/'x-kt-cron',\s*'([^']+)'/) || [])[1];
  if (!khoa) throw new Error('không đọc được khoá cron từ lịch kt-meinvoice');
  if (A.includes('lich')) {   // 17:35 UTC = 00:35 giờ VN, sau kt-meinvoice (00:25)
    await sql(`select cron.unschedule('kt-meinvoice-bot') where exists (select 1 from cron.job where jobname = 'kt-meinvoice-bot')`);
    await sql(`select cron.schedule('kt-meinvoice-bot', '35 17 * * *', $c$select net.http_post(url := 'https://${REF}.supabase.co/functions/v1/kt-meinvoice-bot',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-kt-cron', '${khoa}'), body := '{}'::jsonb, timeout_milliseconds := 150000)$c$)`);
    console.log('lịch:', JSON.stringify(await sql(`select jobname, schedule, active from cron.job where jobname = 'kt-meinvoice-bot'`)));
  }
  const i = A.findIndex(x => x === 'thu' || x === 'nap');
  if (i < 0) return;
  const r = await fetch(`https://${REF}.supabase.co/functions/v1/kt-meinvoice-bot`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-kt-cron': khoa },
    body: JSON.stringify({ thu: A[i] === 'thu', ghep: !A.includes('khong_ghep'), tu: A[i + 1], den: A[i + 2] || A[i + 1] }) });
  const t = await r.text(); console.log(A[i] === 'thu' ? 'chạy thử:' : 'nạp:', r.status, t.split(khoa).join('[KHOA]').slice(0, 6000));
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
