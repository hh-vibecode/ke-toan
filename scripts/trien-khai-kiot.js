// Triển khai luồng kéo Kiot RIÊNG: secrets KT_* + Edge Function kt-kiot + lịch pg_cron 'kt-kiot' (phút 47, 3 tiếng / lần).
// Khoá đọc từ kt-keys.local.txt, KHÔNG in ra. KT_CRON_KEY sinh ngẫu nhiên, ghi thêm vào kt-keys.local.txt. Monsieur Claude
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const REF = 'bcrpxfvvjsjpvbksqzls', K = docKhoa(), API = `https://api.supabase.com/v1/projects/${REF}`;
const H = { Authorization: 'Bearer ' + K.SUPABASE_ACCESS_TOKEN };
(async () => {
  let cron = K.KT_CRON_KEY;
  if (!cron) { cron = crypto.randomBytes(24).toString('hex');
    fs.appendFileSync(path.join(__dirname, '..', 'kt-keys.local.txt'), `\nKT_CRON_KEY (khoá pg_cron gọi Edge Function kt-kiot): ${cron}\n`); }
  // 1. secrets (dùng chung project → bắt buộc tiền tố KT_)
  const s = await fetch(API + '/secrets', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' }, body: JSON.stringify([
    { name: 'KT_KIOT_CLIENT_ID', value: K.KIOT_CLIENT_ID }, { name: 'KT_KIOT_CLIENT_SECRET', value: K.KIOT_CLIENT_SECRET },
    { name: 'KT_KIOT_RETAILER', value: K.KIOT_RETAILER }, { name: 'KT_CRON_KEY', value: cron }]) });
  console.log('secrets KT_*:', s.status);
  // 2. Edge Function
  const fd = new FormData();
  fd.append('metadata', JSON.stringify({ entrypoint_path: 'index.ts', name: 'kt-kiot', verify_jwt: false }));
  fd.append('file', new Blob([fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'kt-kiot', 'index.ts'))], { type: 'application/typescript' }), 'index.ts');
  const d = await fetch(API + '/functions/deploy?slug=kt-kiot', { method: 'POST', headers: H, body: fd });
  console.log('deploy kt-kiot:', d.status, (await d.text()).slice(0, 300));
  // 3. quyền: job chạy bằng service_role
  await sql(`grant execute on function public.kt_dong_bo_kiot(date) to service_role`);
  // 4. lịch pg_cron — phút 47 mỗi 3 tiếng (UTC */3 → giờ VN 1:47, 4:47, 7:47, 10:47, 13:47, 16:47, 19:47, 22:47)
  await sql(`select cron.unschedule('kt-kiot') where exists (select 1 from cron.job where jobname = 'kt-kiot')`);
  await sql(`select cron.schedule('kt-kiot', '47 */3 * * *', $c$select net.http_post(url := 'https://${REF}.supabase.co/functions/v1/kt-kiot',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-kt-cron', '${cron}'), body := '{}'::jsonb, timeout_milliseconds := 150000)$c$)`);
  console.log('lịch:', JSON.stringify(await sql(`select jobname, schedule, active from cron.job where jobname = 'kt-kiot'`)));
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
