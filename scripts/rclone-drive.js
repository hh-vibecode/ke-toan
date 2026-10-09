// Đọc file Google Drive của anh Hải qua rclone (remote 'ktdrive:', quyền CHỈ ĐỌC drive.readonly) — anh cho phép 09/10/2026.
// rclone cài ở %USERPROFILE%\tools\rclone\rclone.exe; đăng nhập lưu ở %APPDATA%\rclone\rclone.conf (trên máy, không lên GitHub).
// Gỡ quyền: myaccount.google.com/permissions hoặc xoá mục [ktdrive] trong rclone.conf. Không in token. Monsieur Claude
const fs = require('fs'), path = require('path'), os = require('os'), { execFileSync } = require('child_process');
const EXE = path.join(process.env.USERPROFILE || os.homedir(), 'tools', 'rclone', 'rclone.exe');
const CONF = path.join(process.env.APPDATA || '', 'rclone', 'rclone.conf');
const MIME = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', heic: 'image/heic', heif: 'image/heif', pdf: 'application/pdf' };
const coSan = () => fs.existsSync(EXE) && fs.existsSync(CONF) && /\[ktdrive\]/.test(fs.readFileSync(CONF, 'utf8'));
// Tải 1 file theo id Drive → { ten, mime, buf }. File không có quyền / không tồn tại → ném lỗi.
function taiFile(id) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ktd-'));
  try {
    execFileSync(EXE, ['backend', 'copyid', 'ktdrive:', id, dir + path.sep], { stdio: 'pipe', timeout: 120000 });
    const f = fs.readdirSync(dir)[0]; if (!f) throw new Error('không tải được (không quyền / không có file)');
    const ext = (f.split('.').pop() || '').toLowerCase();
    return { ten: f, mime: MIME[ext] || 'application/octet-stream', buf: fs.readFileSync(path.join(dir, f)) };
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
}
module.exports = { coSan, taiFile };
