// Đóng dấu phiên bản app trước khi commit (15/10/2026, anh: "theo số lần sửa, giống app Driver").
// APP_SO = 1.<số lần index.html đã được commit + 1> (lần sửa này) · APP_VERSION = giờ máy thật.
// Dùng: ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" scripts/dong-dau.js   (chạy 1 lần ngay trước git add / commit)
const fs = require('fs'), path = require('path'), { execSync } = require('child_process');
const goc = path.join(__dirname, '..'), f = path.join(goc, 'index.html');
let n = Number(execSync('git rev-list --count HEAD -- index.html', { cwd: goc }).toString().trim()) + 1;
// 20/10/2026: clone NÔNG (phiên cloud) đếm thiếu lịch sử → số lùi, các máy không tự tải bản mới. Không bao giờ thấp hơn phien-ban.txt hiện có + 1
try { const cu = Number((fs.readFileSync(path.join(goc, 'phien-ban.txt'), 'utf8').match(/^1\.(\d+)/) || [])[1]); if (cu >= n) n = cu + 1; } catch (_) {}
const d = new Date(), p = x => String(x).padStart(2, '0');
const gio = `${p(d.getDate())}/${p(d.getMonth() + 1)}/${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
let s = fs.readFileSync(f, 'utf8');
if (!/^const APP_VERSION='[^']*';/m.test(s) || !/^const APP_SO='[^']*';/m.test(s)) throw new Error('Không thấy APP_VERSION / APP_SO trong index.html');
s = s.replace(/^const APP_VERSION='[^']*';/m, `const APP_VERSION='${gio}';`).replace(/^const APP_SO='[^']*';/m, `const APP_SO='1.${n}';`);
fs.writeFileSync(f, s);
// 19/10/2026 anh: "thay đổi bản mới thì các TK tự F5 lại hết" — app mỗi phút đọc phien-ban.txt, số lớn hơn bản đang chạy thì tự tải lại
fs.writeFileSync(path.join(goc, 'phien-ban.txt'), `1.${n}\n`);
// 23/10/2026 SỰ CỐ: add index.html TRƯỚC rồi mới chạy script → commit mang index.html số cũ + phien-ban.txt số mới → app mọi tài khoản
// tự tải lại không dừng. Từ nay script add CẢ index.html + phien-ban.txt và kiểm bản đã add khớp số; sau bước này KHÔNG sửa index.html nữa.
execSync('git add index.html phien-ban.txt', { cwd: goc });
const daAdd = execSync('git show :index.html', { cwd: goc, maxBuffer: 64e6 }).toString().match(/^const APP_SO='([^']*)';/m);
if (!daAdd || daAdd[1] !== `1.${n}`) throw new Error('index.html đã add không khớp số phiên bản — KHÔNG commit');
console.log(`v1.${n} · ${gio}  (đã ghi + git add index.html + phien-ban.txt, đã kiểm khớp)`);
