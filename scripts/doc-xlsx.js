// Đọc file .xlsx (không cần thư viện): giải nén bằng PowerShell rồi đọc XML. docXlsx(tep) → { sheets: [{name}], load(sheet) → {dòng: {cột: giá trị}} }
// Monsieur Claude 09/10/2026 (dùng cho scripts/keo-3tshop.js)
const fs = require('fs'), path = require('path'), os = require('os'), { execFileSync } = require('child_process');
function docXlsx(tep) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xl-')), zip = dir + '.zip';
  fs.copyFileSync(tep, zip);
  execFileSync('powershell', ['-NoProfile', '-Command', `Expand-Archive -LiteralPath '${zip}' -DestinationPath '${dir}' -Force`], { stdio: 'pipe' });
  const rd = f => { const p = path.join(dir, f); return fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : ''; };
  const dec = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&#10;/g, '\n').replace(/&amp;/g, '&');
  const ss = []; for (const m of rd('xl/sharedStrings.xml').matchAll(/<si>([\s\S]*?)<\/si>/g)) ss.push(dec([...m[1].matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map(a => a[1]).join('')));
  const wb = rd('xl/workbook.xml'), rels = rd('xl/_rels/workbook.xml.rels');
  const sheets = [...wb.matchAll(/<sheet [^>]*name="([^"]*)"[^>]*r:id="([^"]*)"/g)].map(m => {
    const t = new RegExp('Id="' + m[2] + '"[^>]*Target="([^"]*)"').exec(rels) || new RegExp('Target="([^"]*)"[^>]*Id="' + m[2] + '"').exec(rels);
    return { name: dec(m[1]).trim(), file: 'xl/' + t[1].replace(/^\/?xl\//, '') }; });
  const load = sh => { const rows = {};
    for (const c of rd(sh.file).matchAll(/<c r="([A-Z]+)(\d+)"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const inner = c[4] || '', v = /<v>([\s\S]*?)<\/v>/.exec(inner), is = /<is>([\s\S]*?)<\/is>/.exec(inner);
      let val = v ? v[1] : (is ? [...is[1].matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map(a => a[1]).join('') : '');
      val = /t="s"/.test(c[3]) ? ss[+val] : dec(val); if (val === '') continue;
      (rows[+c[2]] = rows[+c[2]] || {})[c[1]] = typeof val === 'string' ? val.trim() : val; }
    return rows; };
  const xoa = () => { fs.rmSync(dir, { recursive: true, force: true }); fs.rmSync(zip, { force: true }); };
  return { sheets, load, tab: ten => sheets.find(s => s.name.toLowerCase() === ten.toLowerCase()), xoa };
}
module.exports = { docXlsx };
