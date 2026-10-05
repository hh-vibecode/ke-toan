// Chạy SQL trên Supabase qua Management API. Dùng: node scripts/sql.js <file.sql>  |  node scripts/sql.js -e "select 1"
// Token sbp_ đọc từ kt-keys.local.txt, không in ra. Monsieur Claude
const fs = require('fs');
const { docKhoa } = require('./khoa');
const REF = 'bcrpxfvvjsjpvbksqzls';
async function sql(query) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + docKhoa().SUPABASE_ACCESS_TOKEN, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }) });
  const t = await r.text();
  if (!r.ok) throw new Error(`SQL lỗi ${r.status}: ${t.slice(0, 1500)}`);
  return t ? JSON.parse(t) : null;
}
module.exports = { sql };
if (require.main === module) {
  const a = process.argv.slice(2);
  const q = a[0] === '-e' ? a.slice(1).join(' ') : fs.readFileSync(a[0], 'utf8');
  sql(q).then(r => console.log(JSON.stringify(r, null, 1))).catch(e => { console.error(e.message); process.exit(1); });
}
