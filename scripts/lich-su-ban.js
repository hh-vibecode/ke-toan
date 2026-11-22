// Lịch sử cập nhật phiên bản (26/10/2026, anh: "log hệ thống thêm lịch sử update các phiên bản — bản nào thay đổi gì nhét hết vào đây").
// Dựng lich-su-ban.json từ git: mỗi commit sửa index.html = 1 bản; số bản lấy đúng APP_SO trong index.html của commit đó (có cache theo hash).
// Nội dung = tiêu đề + các dòng thân commit (bỏ dòng ký tên / Co-Authored-By).
// Dùng: node scripts/lich-su-ban.js [so_ban_moi "giờ" "mô tả"]   — dong-dau.js gọi kèm bản đang đóng dấu (commit chưa có) để có ngay dòng mới nhất.
// Monsieur Claude
const fs = require('fs'), path = require('path'), { execSync } = require('child_process');
const goc = path.join(__dirname, '..'), f = path.join(goc, 'lich-su-ban.json');
const git = c => execSync('git ' + c, { cwd: goc, maxBuffer: 256e6 }).toString();
let cu = []; try { cu = JSON.parse(fs.readFileSync(f, 'utf8')); } catch (_) {}
const theoHash = Object.fromEntries(cu.filter(x => x.h).map(x => [x.h, x]));
const SEP = '\u001e', NL = '\u001f';
const log = git(`log --format=%h${NL}%ad${NL}%s${NL}%b${SEP} --date=format:%d/%m/%Y_%H:%M -- index.html`).split(SEP).map(s => s.trim()).filter(Boolean);
const ds = [];
for (const e of log) {
  const [h, luc, s, b = ''] = e.split(NL);
  let v = theoHash[h] && theoHash[h].v;
  if (v === undefined) { try { v = (git(`show ${h}:index.html`).match(/^const APP_SO='([^']*)';/m) || [])[1] || null; } catch (_) { v = null; } }
  const chi = b.split('\n').map(x => x.trim()).filter(x => x && !/^Co-Authored-By:/i.test(x) && !/^Monsieur Claude$/i.test(x));
  ds.push({ v, h, luc: luc.replace('_', ' '), nd: s, ct: chi });
}
const [moi, gio, mt] = process.argv.slice(2);
if (moi && !ds.some(x => x.v === moi)) ds.unshift({ v: moi, h: null, luc: gio || '', nd: mt || '(đang đẩy bản — nội dung cập nhật ở lần đóng dấu sau)', ct: [] });
fs.writeFileSync(f, JSON.stringify(ds, null, 0));
console.log('lich-su-ban.json:', ds.length, 'bản · mới nhất', ds[0] && ds[0].v);
