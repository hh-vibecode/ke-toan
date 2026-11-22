// Đọc kt-keys.local.txt (gitignore). Nhận cả "TEN=giá trị", "TEN: giá trị" và "TEN" rồi giá trị ở dòng dưới.
// KHÔNG BAO GIỜ in giá trị khoá ra màn hình. Monsieur Claude
const fs = require('fs'), path = require('path');
function docKhoa() {
  const dong = fs.readFileSync(path.join(__dirname, '..', 'kt-keys.local.txt'), 'utf8').split(/\r?\n/);
  const k = {};
  for (let i = 0; i < dong.length; i++) {
    const m = dong[i].match(/^\s*([A-Z][A-Z0-9_]+)\s*(?:\([^)]*\))?\s*(?:[=:]\s*(.*))?$/);
    if (!m) continue;
    let v = (m[2] || '').trim();
    if (!v) { let j = i + 1; while (j < dong.length && !dong[j].trim()) j++; if (j < dong.length && !/^\s*[A-Z][A-Z0-9_]+\s*([=:]|$)/.test(dong[j])) v = dong[j].trim(); }
    v = v.replace(/^["']|["']$/g, '');
    if (v && !(m[1] in k)) k[m[1]] = v;
  }
  return k;
}
module.exports = { docKhoa };
if (require.main === module) {   // tự soát: chỉ in TÊN + dạng, không in giá trị
  const k = docKhoa();
  for (const t of ['PROJECT_URL', 'SERVICE_ROLE_KEY', 'SUPABASE_ACCESS_TOKEN', 'KIOT_RETAILER', 'KIOT_CLIENT_ID', 'KIOT_CLIENT_SECRET'])
    console.log(t.padEnd(22), k[t] ? `có, dài ${k[t].length}` + (t === 'SUPABASE_ACCESS_TOKEN' ? `, dạng sbp_: ${k[t].startsWith('sbp_')}` : '') +
      (t === 'SERVICE_ROLE_KEY' ? `, dạng JWT/sb_secret: ${/^eyJ|^sb_secret_/.test(k[t])}` : '') + (t === 'PROJECT_URL' ? `, đúng project: ${k[t].includes('bcrpxfvvjsjpvbksqzls')}` : '') : 'THIẾU');
}
