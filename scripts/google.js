// Đăng nhập Google Drive của anh Hải (CHỈ ĐỌC) cho script app kế toán — anh chốt 09/10/2026: "m login vào drive của t luôn".
//   1 lần:  Code.exe scripts/google.js dang_nhap   → mở trình duyệt, anh đăng nhập + Cho phép → lưu refresh token vào kt-google.local.json
//   dùng:   const g = require('./google'); await g.taiFile(id) / g.thongTin(id)
// Cần kt-google-oauth.local.json (mã OAuth "Desktop app" tải từ Google Cloud Console). Cả 2 file *.local.* đã gitignore.
// KHÔNG in token. Quyền chỉ đọc (drive.readonly) — gỡ quyền: myaccount.google.com/permissions. Monsieur Claude
const fs = require('fs'), path = require('path'), http = require('http');
const GOC = path.join(__dirname, '..'), F_OAUTH = path.join(GOC, 'kt-google-oauth.local.json'), F_TOKEN = path.join(GOC, 'kt-google.local.json');
const SCOPE = 'https://www.googleapis.com/auth/drive.readonly';
const client = () => { if (!fs.existsSync(F_OAUTH)) throw new Error('thiếu kt-google-oauth.local.json (mã OAuth Desktop app)');
  const j = JSON.parse(fs.readFileSync(F_OAUTH, 'utf8')); const c = j.installed || j.web || j; return { id: c.client_id, secret: c.client_secret }; };

async function dangNhap() {
  const c = client();
  const srv = http.createServer(); await new Promise(r => srv.listen(0, '127.0.0.1', r));
  const ve = `http://127.0.0.1:${srv.address().port}`;
  const url = 'https://accounts.google.com/o/oauth2/v2/auth?' + new URLSearchParams({ client_id: c.id, redirect_uri: ve, response_type: 'code',
    scope: SCOPE, access_type: 'offline', prompt: 'consent' });
  console.log('Đang mở trình duyệt để anh đăng nhập Google (chờ tối đa 5 phút)...');
  require('child_process').spawn('rundll32', ['url.dll,FileProtocolHandler', url], { detached: true, stdio: 'ignore' }).unref();
  const code = await new Promise((ok, loi) => {
    const hen = setTimeout(() => loi(new Error('quá 5 phút chưa đăng nhập')), 300000);
    srv.on('request', (req, res) => { const q = new URL(req.url, ve).searchParams;
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(q.get('code') ? '<h2>Đã cho phép. Anh đóng tab này được rồi — Monsieur Claude</h2>' : '<h2>Không cho phép / lỗi: ' + (q.get('error') || '') + '</h2>');
      clearTimeout(hen); q.get('code') ? ok(q.get('code')) : loi(new Error('Google trả lỗi: ' + q.get('error'))); });
  });
  srv.close();
  const r = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ code, client_id: c.id, client_secret: c.secret, redirect_uri: ve, grant_type: 'authorization_code' }) });
  const j = await r.json(); if (!j.refresh_token) throw new Error('không nhận được refresh token: ' + (j.error_description || j.error || r.status));
  fs.writeFileSync(F_TOKEN, JSON.stringify({ refresh_token: j.refresh_token, scope: j.scope, luc: new Date().toISOString() }));
  const ai = await (await fetch('https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)', { headers: { Authorization: 'Bearer ' + j.access_token } })).json();
  console.log('Đã đăng nhập Drive (chỉ đọc) bằng tài khoản:', ai.user && ai.user.emailAddress);
}

let tok = null, het = 0;
async function token() {
  if (tok && Date.now() < het) return tok;
  if (!fs.existsSync(F_TOKEN)) throw new Error('chưa đăng nhập Google — chạy: scripts/google.js dang_nhap');
  const c = client(), t = JSON.parse(fs.readFileSync(F_TOKEN, 'utf8'));
  const r = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: c.id, client_secret: c.secret, refresh_token: t.refresh_token, grant_type: 'refresh_token' }) });
  const j = await r.json(); if (!j.access_token) throw new Error('làm mới token Google lỗi: ' + (j.error_description || j.error));
  tok = j.access_token; het = Date.now() + (j.expires_in - 60) * 1000; return tok;
}
async function thongTin(id) {
  const r = await fetch(`https://www.googleapis.com/drive/v3/files/${id}?fields=id,name,mimeType,size&supportsAllDrives=true`, { headers: { Authorization: 'Bearer ' + await token() } });
  if (!r.ok) throw new Error('Drive ' + r.status); return r.json();
}
async function taiFile(id) {
  const r = await fetch(`https://www.googleapis.com/drive/v3/files/${id}?alt=media&supportsAllDrives=true`, { headers: { Authorization: 'Bearer ' + await token() } });
  if (!r.ok) throw new Error('Drive tải ' + r.status); return Buffer.from(await r.arrayBuffer());
}
module.exports = { token, thongTin, taiFile };
if (require.main === module && process.argv[2] === 'dang_nhap') dangNhap().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
