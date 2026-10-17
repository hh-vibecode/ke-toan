// Kéo ĐỊNH KỲ file "THT BẢNG KIỂM SOÁT DÒNG TIỀN THÁNG m.yyyy" (Drive kế toán) → bảng đối chiếu sổ quỹ / số dư trên app (16/10/2026,
// anh: "đưa việc duy trì kéo dữ liệu file gg sheet dòng tiền T10 vào để đối chiếu", "không khớp note ra, note vào app luôn").
//  1. liệt kê thư mục Drive (rclone, quyền chỉ đọc) → file tháng này (+ tháng trước nếu đang ngày 1–5)
//  2. tải về thư mục tạm, đọc tab 3.CASHFLOW TỔNG: dòng 2 = tên TK (mỗi TK 5 cột Thu/Chi/Tồn sổ sách/Tồn thực tế/Lệch, bắt đầu cột H),
//     dòng 3 = tồn đầu kì, từ dòng 5 mỗi ngày
//  3. gọi kt_nap_dcf (service_role, khoá trong kt-keys.local.txt) — hàm tự ghi chú ngày lệch
//  4. log vào keo-file-dong-tien.local.log (gitignore). Chạy: Task Scheduler "kt-keo-file-dong-tien" (scripts/keo-file-dong-tien.vbs)
// Thử không ghi: ... keo-file-dong-tien.js thu    — Monsieur Claude
const fs = require('fs'), os = require('os'), path = require('path'), { execFileSync } = require('child_process');
const GOC = path.join(__dirname, '..'), LOG = path.join(GOC, 'keo-file-dong-tien.local.log');
const RCLONE = path.join(os.homedir(), 'tools', 'rclone', 'rclone.exe'), REMOTE = 'ktdrive2:', THU_MUC = '1_fhF9Mx9nygJVgn36IuX1_6Qxn1wdRHj';
const THU = process.argv[2] === 'thu';
const luc = () => new Date(Date.now() + 7 * 3600e3).toISOString().replace('T', ' ').slice(0, 16);
const ghi = t => { console.log(t); if (!THU) fs.appendFileSync(LOG, `[${luc()}] ${t}\n`); };
const cot = i => { let s = ''; i++; while (i > 0) { const m = (i - 1) % 26; s = String.fromCharCode(65 + m) + s; i = Math.floor((i - 1) / 26); } return s; };   // 0 → A
const so = v => { if (v === undefined || v === null || v === '') return null; const t = String(v).trim();   // số XML thô (1728, 1.5E7) hoặc chữ định dạng VN (26.521.821)
  const n = /^-?\d+(\.\d+)?(e[+-]?\d+)?$/i.test(t) ? Number(t) : Number(t.replace(/\./g, '').replace(',', '.')); return isFinite(n) ? Math.round(n) : null; };
const ngayExcel = v => { const n = Number(v); if (!isFinite(n) || n < 40000) return null; return new Date(Math.round((n - 25569) * 864e5)).toISOString().slice(0, 10); };

// đọc tab 3.CASHFLOW TỔNG từ object {dòng: {cột: giá trị}} (scripts/doc-xlsx.js) → payload kt_nap_dcf
function docCashflow(rows, thang) {
  const dau = [], ngay = [], r2 = rows[2] || {}, r3 = rows[3] || {};
  for (let c = 7; ; c += 5) {
    const ten = String(r2[cot(c)] || '').trim(); if (!ten) break;
    dau.push({ tk: ten, ton: so(r3[cot(c + 1)]) || 0 });
    for (let r = 5; r < 80; r++) {
      const d = ngayExcel((rows[r] || {}).A); if (!d || d.slice(0, 7) !== thang) continue;
      const x = rows[r];
      ngay.push({ tk: ten, ngay: d, thu: so(x[cot(c)]) || 0, chi: so(x[cot(c + 1)]) || 0, ton_ss: so(x[cot(c + 2)]), ton_tt: so(x[cot(c + 3)]) });
    }
  }
  return { thang, dau, ngay };
}
module.exports = { docCashflow };

async function chay() {
  const { docXlsx } = require('./doc-xlsx'), { docKhoa } = require('./khoa');
  const ds = JSON.parse(execFileSync(RCLONE, ['lsjson', REMOTE, '--drive-root-folder-id', THU_MUC], { encoding: 'utf8', timeout: 120000 }));
  const nay = new Date(Date.now() + 7 * 3600e3), thangs = [[nay.getUTCMonth() + 1, nay.getUTCFullYear()]];
  if (nay.getUTCDate() <= 5) { const t = new Date(Date.UTC(nay.getUTCFullYear(), nay.getUTCMonth() - 1, 1)); thangs.push([t.getUTCMonth() + 1, t.getUTCFullYear()]); }
  const k = docKhoa();
  for (const [m, y] of thangs) {
    const f = ds.find(x => new RegExp(`DÒNG TIỀN THÁNG 0?${m}\\.${y}`, 'i').test(x.Name.normalize('NFC')));
    if (!f) { ghi(`không thấy file tháng ${m}.${y}`); continue; }
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kt-dt-'));
    try {
      execFileSync(RCLONE, ['backend', 'copyid', REMOTE, f.ID, dir + path.sep], { stdio: 'pipe', timeout: 180000 });
      const tep = fs.readdirSync(dir).find(x => /\.xlsx$/i.test(x)); if (!tep) throw new Error('không tải được file');
      const F = docXlsx(path.join(dir, tep)), sh = F.sheets.find(s => s.name.normalize('NFC') === '3.CASHFLOW TỔNG'.normalize('NFC'));
      if (!sh) throw new Error('không thấy tab 3.CASHFLOW TỔNG');
      const dl = docCashflow(F.load(sh), `${y}-${String(m).padStart(2, '0')}`);
      if (THU) { ghi(`[thử] ${f.Name}: ${dl.dau.length} TK, ${dl.ngay.length} dòng ngày`); continue; }
      const r = await fetch(k.PROJECT_URL.replace(/\/$/, '') + '/rest/v1/rpc/kt_nap_dcf', { method: 'POST',
        headers: { apikey: k.SERVICE_ROLE_KEY, Authorization: 'Bearer ' + k.SERVICE_ROLE_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_dl: dl }) });
      const t = await r.text(); if (!r.ok) throw new Error(`nạp lỗi ${r.status}: ${t.slice(0, 300)}`);
      ghi(`${f.Name}: ${t}`);
    } catch (e) { ghi(`LỖI ${m}.${y}: ${e.message}`); }
    finally { fs.rmSync(dir, { recursive: true, force: true }); }
  }
}
if (require.main === module) chay().catch(e => { ghi('LỖI: ' + e.message); process.exit(1); });
