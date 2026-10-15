// Đóng dấu phiên bản app trước khi commit (15/10/2026, anh: "theo số lần sửa, giống app Driver").
// APP_SO = 1.<số lần index.html đã được commit + 1> (lần sửa này) · APP_VERSION = giờ máy thật.
// Dùng: ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" scripts/dong-dau.js   (chạy 1 lần ngay trước git add / commit)
const fs = require('fs'), path = require('path'), { execSync } = require('child_process');
const goc = path.join(__dirname, '..'), f = path.join(goc, 'index.html');
const n = Number(execSync('git rev-list --count HEAD -- index.html', { cwd: goc }).toString().trim()) + 1;
const d = new Date(), p = x => String(x).padStart(2, '0');
const gio = `${p(d.getDate())}/${p(d.getMonth() + 1)}/${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
let s = fs.readFileSync(f, 'utf8');
if (!/^const APP_VERSION='[^']*';/m.test(s) || !/^const APP_SO='[^']*';/m.test(s)) throw new Error('Không thấy APP_VERSION / APP_SO trong index.html');
s = s.replace(/^const APP_VERSION='[^']*';/m, `const APP_VERSION='${gio}';`).replace(/^const APP_SO='[^']*';/m, `const APP_SO='1.${n}';`);
fs.writeFileSync(f, s);
console.log(`v1.${n} · ${gio}`);
