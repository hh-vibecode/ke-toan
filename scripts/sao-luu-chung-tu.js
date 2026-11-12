// SAO LƯU KHO CHỨNG TỪ (Storage bucket kt-chung-tu) → Google Drive (11/11/2026 anh: "drive đi, tầm giờ hành chính chiều, set tự động").
// Supabase chỉ tự backup Database, KHÔNG backup file Storage → script chép file MỚI / ĐỔI sang Drive (chỉ thêm, không xoá bản sao khi file
// trên app bị xoá — để còn khôi phục khi xoá nhầm). Đọc danh sách từ storage.objects, tải bằng khoá service_role (chỉ ĐỌC, trên máy anh),
// đẩy lên Drive bằng rclone theo lô. Trạng thái đã chép: sao-luu-chung-tu.local.json (gitignore). Mỗi lần chạy ghi kt_nhat_ky 'sao_luu_drive'.
// Chạy: Code.exe scripts/sao-luu-chung-tu.js [remote, mặc định ktdrive-ghi:] [giới hạn số file — để thử]. Lịch Windows: kt-sao-luu-chung-tu. — Monsieur Claude
const fs = require('fs'), path = require('path'), os = require('os'), { execFileSync } = require('child_process');
const { sql } = require('./sql'); const { docKhoa } = require('./khoa'); const K = docKhoa(); const { napTen } = require('./sao-luu-ten');
const RC = path.join(process.env.USERPROFILE || os.homedir(), 'tools', 'rclone', 'rclone.exe');
const REMOTE = process.argv[2] || 'ktdrive-ghi:', GIOI_HAN = +process.argv[3] || 0;
// 11/11 anh: lưu vào thư mục Drive "THT.Sao lưu chứng từ" (tech@tht-holding.com) + "đồng nhất cách chia dữ liệu với Supabase" → thư mục con = tên bucket,
// bên trong giữ nguyên đường dẫn file Supabase (chi/<id>/…, thu/…, hd/ra/…). Remote ktdrive-ghi: (đăng nhập lại 11/11), trỏ gốc bằng --drive-root-folder-id.
const GOC_DRIVE = process.env.KT_SL_GOC || '1TOdKYoSEO4aAlm3qJx1Sn3UUz2emLv3r', BUCKET = 'kt-chung-tu', THU_MUC = BUCKET, LO = 150;
const TT = path.join(__dirname, '..', 'sao-luu-chung-tu.local.json');
const J = x => '$kt$' + JSON.stringify(x) + '$kt$';
// 12/11: lần chép đầu dừng giữa chừng vì rớt mạng (rclone lỗi 1 lô → dừng, ghi nhật ký cũng lỗi → không ai biết). Giờ mỗi bước mạng tự thử lại
// (tải file 3 lần, đẩy lô lên Drive 4 lần cách 1 phút, ghi nhật ký 5 lần cách 30 giây). — Monsieur Claude
const ngu = ms => new Promise(r => setTimeout(r, ms));
async function thuLai(n, cho, fn) { for (let i = 1; ; i++) { try { return await fn(); } catch (e) { if (i >= n) throw e; await ngu(cho); } } }
// Chống chạy trùng (lần chép đầu dài hơn 1 giờ, lịch 15:30 có thể bắt đầu khi lần trước chưa xong → 2 tiến trình cùng ghi một thư mục Drive
// sinh file / thư mục trùng tên): có tiến trình khác đang chạy script này thì thoát luôn, không ghi nhật ký. — Monsieur Claude
function dangChay() {
  try {
    const o = execFileSync('powershell', ['-NoProfile', '-Command', "Get-CimInstance Win32_Process | ? { $_.Name -match '^(Code|node).exe$' -and $_.CommandLine -like '*sao-luu-chung-tu.js*' } | % { $_.ProcessId }"], { encoding: 'utf8', timeout: 60e3 });
    return o.split(/\s+/).filter(x => x && +x !== process.pid && +x !== process.ppid).length > 0;
  } catch (_) { return false; }
}
(async () => {
  if (dangChay()) { console.log('Đang có lần sao lưu khác chạy — bỏ qua lần này'); return; }
  const bd = Date.now(), daCo = fs.existsSync(TT) ? JSON.parse(fs.readFileSync(TT, 'utf8')) : {};
  const ds = await thuLai(5, 30e3, () => sql(`select name, updated_at, (metadata->>'size')::bigint size from storage.objects where bucket_id = '${BUCKET}' order by name`));
  // 12/11 anh: tên trên Drive tiếng Việt rõ ràng, phiếu theo mã phiếu (scripts/sao-luu-ten.js). Trạng thái mỗi file: "updated_at|size|đường dẫn Drive".
  // Tập tên tính trên CẢ file đã xoá khỏi app (còn trong trạng thái) để số "Ảnh n" / mã chống trùng không đổi khi app xoá file → không đè bản sao cũ.
  const ten = (await napTen(sql))([...new Set([...ds.map(f => f.name), ...Object.keys(daCo)])]);
  const tt = n => (daCo[n] || '').split('|'), cuaFile = f => tt(f.name).slice(0, 2).join('|') === f.updated_at + '|' + f.size;
  // file không đổi nội dung nhưng tên Drive đổi (vd đổi tên NCC, HĐ mới có số) → chuyển tên trên Drive, không tải lại
  const doi = ds.filter(f => cuaFile(f) && (tt(f.name)[2] || THU_MUC + '/' + f.name) !== ten[f.name]);
  let doiXong = 0;
  for (const f of doi) {
    try { await thuLai(3, 30e3, async () => execFileSync(RC, ['moveto', REMOTE + (tt(f.name)[2] || THU_MUC + '/' + f.name), REMOTE + ten[f.name], '--drive-root-folder-id', GOC_DRIVE, '-q'], { stdio: 'pipe', timeout: 5 * 60e3 }));
      daCo[f.name] = f.updated_at + '|' + f.size + '|' + ten[f.name]; doiXong++; } catch (e) { console.log('  đổi tên lỗi', f.name, String(e.stderr || e.message).slice(0, 120)); }
  }
  if (doi.length) fs.writeFileSync(TT, JSON.stringify(daCo));
  let can = ds.filter(f => !cuaFile(f)); if (GIOI_HAN) can = can.slice(0, GIOI_HAN);
  const kq = { remote: REMOTE, goc: GOC_DRIVE, tong: ds.length, can: can.length, da_chep: 0, mb: 0, loi: 0, loi_cuoi: null, doi_ten: doiXong };
  console.log(`Kho ${ds.length} file · cần chép ${can.length}`);
  for (let i = 0; i < can.length; i += LO) {
    const lo = can.slice(i, i + LO), tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ktsl-')), xong = [];
    try {
      for (const f of lo) {
        try {
          const r = await thuLai(3, 5e3, async () => { const x = await fetch(`${K.PROJECT_URL}/storage/v1/object/${BUCKET}/${f.name.split('/').map(encodeURIComponent).join('/')}`, { headers: { apikey: K.SERVICE_ROLE_KEY, Authorization: 'Bearer ' + K.SERVICE_ROLE_KEY } });
            if (!x.ok) throw new Error('tải ' + x.status); return Buffer.from(await x.arrayBuffer()); });
          const buf = r, dich = path.join(tmp, ...ten[f.name].split('/'));
          fs.mkdirSync(path.dirname(dich), { recursive: true }); fs.writeFileSync(dich, buf); xong.push(f); kq.mb += buf.length / 1048576;
        } catch (e) { kq.loi++; kq.loi_cuoi = f.name + ': ' + String(e.message || e).slice(0, 120); }
      }
      if (xong.length) {
        await thuLai(4, 60e3, async () => execFileSync(RC, ['copy', tmp, REMOTE, '--drive-root-folder-id', GOC_DRIVE, '--transfers', '8', '--checksum', '--retries', '3', '-q'], { stdio: 'pipe', timeout: 30 * 60e3 }));
        for (const f of xong) daCo[f.name] = f.updated_at + '|' + f.size + '|' + ten[f.name]; kq.da_chep += xong.length;
        fs.writeFileSync(TT, JSON.stringify(daCo));
      }
    } catch (e) { kq.loi += lo.length - 0; kq.loi_cuoi = 'rclone: ' + String(e.stderr || e.message || e).replace(/\s+/g, ' ').slice(0, 200); break; }
    finally { fs.rmSync(tmp, { recursive: true, force: true }); }
    console.log(`  lô ${i / LO + 1}: đã chép ${kq.da_chep}/${can.length} · ${Math.round(kq.mb)} MB`);
  }
  kq.mb = Math.round(kq.mb); kq.giay = Math.round((Date.now() - bd) / 1000);
  await thuLai(5, 30e3, () => sql(`insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_chung_tu', ${kq.loi ? "'sao_luu_drive_loi'" : "'sao_luu_drive'"}, ${J(kq)}::jsonb)`));
  console.log(JSON.stringify(kq));
  if (kq.loi) process.exitCode = 1;
})().catch(async e => { console.error('DỪNG', e.message); try { await thuLai(5, 30e3, () => sql(`insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_chung_tu', 'sao_luu_drive_loi', ${J({ loi: String(e.message).slice(0, 300) })}::jsonb)`)); } catch (_) { } process.exit(1); });
