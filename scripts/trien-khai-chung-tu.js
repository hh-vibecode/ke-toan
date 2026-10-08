// Triển khai chứng từ: bucket riêng tư 'kt-chung-tu' + bảng / hàm SQL + Edge Function 'kt-chung-tu'. Khoá không in ra. Monsieur Claude
const fs = require('fs'), path = require('path');
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const REF = 'bcrpxfvvjsjpvbksqzls', K = docKhoa(), SB = `https://${REF}.supabase.co`;
(async () => {
  // 1. bucket riêng tư, tối đa 15 MB / file, chỉ ảnh + PDF
  const H = { apikey: K.SERVICE_ROLE_KEY, Authorization: 'Bearer ' + K.SERVICE_ROLE_KEY, 'Content-Type': 'application/json' };
  const cfg = { public: false, file_size_limit: 15 * 1024 * 1024, allowed_mime_types: ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf'] };
  let r = await fetch(`${SB}/storage/v1/bucket`, { method: 'POST', headers: H, body: JSON.stringify({ id: 'kt-chung-tu', name: 'kt-chung-tu', ...cfg }) });
  if (r.status === 400 || r.status === 409) r = await fetch(`${SB}/storage/v1/bucket/kt-chung-tu`, { method: 'PUT', headers: H, body: JSON.stringify(cfg) });
  console.log('bucket kt-chung-tu:', r.status, (await r.text()).slice(0, 120));
  // 2. SQL
  await sql(fs.readFileSync(path.join(__dirname, '..', 'supabase-schema-kt-chung-tu.sql'), 'utf8'));
  console.log('SQL chứng từ: OK');
  // 2b. quyền theo dòng + thông báo (định nghĩa lại kt_quyen_chung_tu 4 tham số — Edge Function bên dưới gọi bản này)
  await sql(fs.readFileSync(path.join(__dirname, '..', 'supabase-schema-kt-thong-bao.sql'), 'utf8'));
  console.log('SQL thông báo + quyền chi: OK');
  // 3. Edge Function (trang web gọi bằng khoá anon công khai → verify_jwt false, hàm tự kiểm phiên)
  const fd = new FormData();
  fd.append('metadata', JSON.stringify({ entrypoint_path: 'index.ts', name: 'kt-chung-tu', verify_jwt: false }));
  fd.append('file', new Blob([fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'kt-chung-tu', 'index.ts'))], { type: 'application/typescript' }), 'index.ts');
  const d = await fetch(`https://api.supabase.com/v1/projects/${REF}/functions/deploy?slug=kt-chung-tu`, { method: 'POST', headers: { Authorization: 'Bearer ' + K.SUPABASE_ACCESS_TOKEN }, body: fd });
  console.log('deploy kt-chung-tu:', d.status, (await d.text()).slice(0, 120));
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
