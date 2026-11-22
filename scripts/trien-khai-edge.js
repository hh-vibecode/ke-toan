// Triển khai 1 Edge Function bất kỳ trong supabase/functions/<tên>. Dùng: trien-khai-edge.js <tên>   (vd kt-hoa-hong-ma). Không in khoá. Monsieur Claude 17/11/2026
const fs = require('fs'), path = require('path');
const { docKhoa } = require('./khoa');
const REF = 'bcrpxfvvjsjpvbksqzls', K = docKhoa(), API = `https://api.supabase.com/v1/projects/${REF}`, ten = process.argv[2];
if (!/^kt-[a-z0-9-]+$/.test(ten || '')) { console.error('Tên Edge phải dạng kt-...'); process.exit(1); }
(async () => {
  const fd = new FormData();
  fd.append('metadata', JSON.stringify({ entrypoint_path: 'index.ts', name: ten, verify_jwt: false }));
  fd.append('file', new Blob([fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', ten, 'index.ts'))], { type: 'application/typescript' }), 'index.ts');
  const d = await fetch(API + '/functions/deploy?slug=' + ten, { method: 'POST', headers: { Authorization: 'Bearer ' + K.SUPABASE_ACCESS_TOKEN }, body: fd });
  console.log('deploy ' + ten + ':', d.status, d.ok ? '' : (await d.text()).slice(0, 300));
})().catch(e => { console.error(e.message); process.exit(1); });
