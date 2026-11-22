// ĐỔI TÊN 1 LẦN các file đã sao lưu trên Drive sang tên dễ đọc (12/11/2026 — xem scripts/sao-luu-ten.js). Chuyển ngay trên Drive (server-side move qua
// rclone rcd, không tải lại), ghi đường dẫn mới vào sao-luu-chung-tu.local.json, xong xoá các thư mục cũ ĐÃ RỖNG (rmdirs — không xoá file).
// Bản đối chiếu cũ → mới lưu sao-luu-doi-ten.local.json để chuyển ngược nếu cần.
// Chạy thử (mặc định, không đổi gì):  Code.exe scripts/sao-luu-doi-ten.js        Chạy thật:  Code.exe scripts/sao-luu-doi-ten.js chay   — Monsieur Claude
const fs = require('fs'), path = require('path'), os = require('os'), { spawn } = require('child_process'), crypto = require('crypto');
const { sql } = require('./sql'); const { napTen } = require('./sao-luu-ten');
const RC = path.join(process.env.USERPROFILE || os.homedir(), 'tools', 'rclone', 'rclone.exe');
const GOC = process.env.KT_SL_GOC || '1TOdKYoSEO4aAlm3qJx1Sn3UUz2emLv3r', FS = `ktdrive-ghi,root_folder_id=${GOC}:`, CU = 'kt-chung-tu';
const TT = path.join(__dirname, '..', 'sao-luu-chung-tu.local.json'), BD = path.join(__dirname, '..', 'sao-luu-doi-ten.local.json');
const CHAY = process.argv[2] === 'chay', SONG_SONG = 6, GH = +process.argv[3] || 0;   // GH: chỉ đổi n file đầu (chạy thử thật)
(async () => {
  const daCo = JSON.parse(fs.readFileSync(TT, 'utf8')), ten = await napTen(sql);
  const ds = await sql(`select name from storage.objects where bucket_id = 'kt-chung-tu'`), names = Object.keys(daCo);
  const moi = ten([...new Set([...ds.map(f => f.name), ...names])]),   // cùng tập tên với script hằng ngày
    can = names.filter(n => (daCo[n].split('|')[2] || CU + '/' + n) !== moi[n]).slice(0, GH || undefined);
  const dem = {}; for (const n of can) { const k = moi[n].split('/')[1]; dem[k] = (dem[k] || 0) + 1; }
  console.log(`Đã sao lưu ${names.length} file · cần đổi tên ${can.length}`); console.log(dem);
  const vd = {}; for (const n of can) { const k = n.split('/')[0]; if ((vd[k] || 0) < 2) { vd[k] = (vd[k] || 0) + 1; console.log('  ' + n + '\n    → ' + moi[n]); } }
  console.log('Trùng tên đã thêm mã:', can.filter(n => / \([0-9a-z]{1,4}\)(\.[A-Za-z0-9]+)?$/.test(moi[n])).length);
  if (!CHAY) { console.log('(chạy thử — chưa đổi gì; chạy thật: thêm tham số "chay")'); return; }
  // rclone rcd tạm trên máy, mật khẩu ngẫu nhiên, chỉ nghe 127.0.0.1
  const port = 5600 + Math.floor(Math.random() * 300), pw = crypto.randomBytes(12).toString('hex');
  const rcd = spawn(RC, ['rcd', '--rc-addr', '127.0.0.1:' + port, '--rc-user', 'kt', '--rc-pass', pw], { stdio: 'ignore' });
  const goi = async (lenh, body) => { const r = await fetch(`http://127.0.0.1:${port}/${lenh}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Basic ' + Buffer.from('kt:' + pw).toString('base64') }, body: JSON.stringify(body) });
    const t = await r.text(); if (!r.ok) throw new Error(t.slice(0, 300)); return t; };
  try {
    for (let i = 0; i < 40; i++) { try { await goi('rc/noop', {}); break; } catch (_) { await new Promise(r => setTimeout(r, 500)); } }
    const bd = fs.existsSync(BD) ? JSON.parse(fs.readFileSync(BD, 'utf8')) : {};
    let xong = 0, loi = 0, i = 0;
    const lam = async () => { while (i < can.length) { const n = can[i++], cu = daCo[n].split('|')[2] || CU + '/' + n;
      try { await goi('operations/movefile', { srcFs: FS, srcRemote: cu, dstFs: FS, dstRemote: moi[n] });
        const [u, s] = daCo[n].split('|'); daCo[n] = `${u}|${s}|${moi[n]}`; bd[n] = { cu, moi: moi[n] }; xong++;
      } catch (e) {
        // 12/11: file đã được chuyển trước đó (lần chạy bị dừng giữa chừng / chạy trùng) → có sẵn ở tên mới thì coi là xong
        let co = false; try { co = /"item"\s*:\s*\{/.test(await goi('operations/stat', { fs: FS, remote: moi[n] })); } catch (_) { }
        if (co) { const [u, s] = daCo[n].split('|'); daCo[n] = `${u}|${s}|${moi[n]}`; bd[n] = { cu, moi: moi[n] }; xong++; }
        else { loi++; if (loi <= 5) console.log('  lỗi', n, String(e.message).slice(0, 160)); }
      }
      if ((xong + loi) % 200 === 0) { fs.writeFileSync(TT, JSON.stringify(daCo)); fs.writeFileSync(BD, JSON.stringify(bd)); console.log(`  ${xong + loi}/${can.length} · lỗi ${loi}`); } } };
    await Promise.all(Array.from({ length: SONG_SONG }, lam));
    fs.writeFileSync(TT, JSON.stringify(daCo)); fs.writeFileSync(BD, JSON.stringify(bd));
    console.log(`Đổi tên xong ${xong}/${can.length} · lỗi ${loi}`);
    if (!loi && !GH) { await goi('operations/rmdirs', { fs: FS, remote: CU, leaveRoot: false }); console.log('Đã xoá các thư mục cũ đã rỗng (' + CU + ')'); }
    await sql(`insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_chung_tu', 'sao_luu_doi_ten', $kt$${JSON.stringify({ xong, loi, tong: can.length })}$kt$::jsonb)`);
  } finally { rcd.kill(); }
})().catch(e => { console.error('DỪNG', e.message); process.exit(1); });
