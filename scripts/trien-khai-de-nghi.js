// Triển khai phiếu đề nghị thanh toán công khai (14/10/2026): SQL supabase-schema-kt-de-nghi-cong-khai.sql + Edge Function kt-chung-tu
// (thêm việc 'tai_len_phieu'). Khoá đọc từ kt-keys.local.txt, không in. Monsieur Claude
const fs = require('fs'), path = require('path');
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const REF = 'bcrpxfvvjsjpvbksqzls', K = docKhoa();
(async () => {
  await sql(fs.readFileSync(path.join(__dirname, '..', 'supabase-schema-kt-de-nghi-cong-khai.sql'), 'utf8')); console.log('SQL: OK');
  const fd = new FormData();
  fd.append('metadata', JSON.stringify({ entrypoint_path: 'index.ts', name: 'kt-chung-tu', verify_jwt: false }));
  fd.append('file', new Blob([fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'kt-chung-tu', 'index.ts'))], { type: 'application/typescript' }), 'index.ts');
  const d = await fetch(`https://api.supabase.com/v1/projects/${REF}/functions/deploy?slug=kt-chung-tu`, { method: 'POST', headers: { Authorization: 'Bearer ' + K.SUPABASE_ACCESS_TOKEN }, body: fd });
  const t = await d.text(); console.log('deploy kt-chung-tu:', d.status, d.ok ? JSON.parse(t).version : t.slice(0, 300));
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
