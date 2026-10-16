// Đồng bộ ĐỊNH KỲ sheet "THT QUẢN LÍ THANH TOÁN 2025+2026" (tab ĐỀ NGHỊ THANH TOÁN) → app (16/10/2026, anh: "định kỳ quét lại đề nghị thanh toán
// để cập nhật cho tới khi t với m xác định bắt đầu luồng này"). Chạy bằng Task Scheduler "kt-dong-bo-sheet-dn" (mỗi giờ 8h–20h, ẩn cửa sổ — scripts/dong-bo-sheet-dinh-ky.vbs).
//  1. tải file bằng rclone (quyền chỉ đọc) vào thư mục tạm mới   2. file giống lần trước (md5) → bỏ qua   3. chạy dong-bo-sheet-dn.js <file> ghi
//  4. ghi log vào dong-bo-sheet.local.log (gitignore, không lên repo)   5. xoá thư mục tạm.
// TẮT khi anh chốt bắt đầu luồng đề nghị trên app: schtasks /Delete /TN kt-dong-bo-sheet-dn /F   — Monsieur Claude
const fs = require('fs'), os = require('os'), path = require('path'), crypto = require('crypto'), { execFileSync, spawnSync } = require('child_process');
const GOC = path.join(__dirname, '..'), LOG = path.join(GOC, 'dong-bo-sheet.local.log'), TT = path.join(GOC, 'dong-bo-sheet.local.json');
const RCLONE = path.join(os.homedir(), 'tools', 'rclone', 'rclone.exe'), ID = '1XA4yM1MEWMV--qsp2sgLBLcaIwJAbsc9DF6mWkB5AN4';
const luc = () => new Date(Date.now() + 7 * 3600e3).toISOString().replace('T', ' ').slice(0, 16);
const ghi = t => fs.appendFileSync(LOG, `[${luc()}] ${t}\n`);
let dir;
try {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kt-sheet-'));
  execFileSync(RCLONE, ['backend', 'copyid', 'ktdrive2:', ID, dir + path.sep], { stdio: 'pipe', timeout: 180000 });
  const tep = fs.readdirSync(dir).find(f => /\.xlsx$/i.test(f)); if (!tep) throw new Error('không tải được file sheet');
  // so theo NỘI DUNG tab (file xlsx Google xuất mỗi lần một khác dù sheet không đổi)
  const { docXlsx } = require('./doc-xlsx'), F = docXlsx(path.join(dir, tep)), sh = F.sheets.find(s => s.name === 'ĐỀ NGHỊ THANH TOÁN');
  if (!sh) throw new Error('không thấy tab ĐỀ NGHỊ THANH TOÁN');
  const md5 = crypto.createHash('md5').update(JSON.stringify(F.load(sh))).digest('hex');
  let cu = {}; try { cu = JSON.parse(fs.readFileSync(TT, 'utf8')); } catch (e) {}
  if (cu.md5 === md5) { ghi('sheet không đổi — bỏ qua'); }
  else {
    const r = spawnSync(process.execPath, [path.join(__dirname, 'dong-bo-sheet-dn.js'), path.join(dir, tep), 'ghi'], { env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' }, encoding: 'utf8', timeout: 300000 });
    const out = (r.stdout || '') + (r.stderr || '');
    const tom = out.split('\n').filter(l => /^(Sheet 2026|[1-4]\. |Phiếu sheet_cu|ĐÃ GHI|SQL lỗi|Error)/.test(l)).join(' | ');
    if (r.status !== 0 || !/ĐÃ GHI/.test(out)) throw new Error('đồng bộ lỗi: ' + out.slice(-600));
    fs.writeFileSync(TT, JSON.stringify({ md5, luc: luc() }));
    ghi('đã đồng bộ — ' + tom);
  }
} catch (e) { ghi('LỖI ' + e.message.replace(/\s+/g, ' ').slice(0, 800)); process.exitCode = 1; }
finally { try { dir && fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {} }
