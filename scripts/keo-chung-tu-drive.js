// Kéo chứng từ cũ (link Google Drive trong phiếu chi chuyển từ sheet: cột hồ sơ + uỷ nhiệm chi) về kho chứng từ của app.
// Anh 09/10/2026: "giao dịch nào có ảnh up hết lên", thử tháng 9 trước.
// Drive phải cho tải KHÔNG cần đăng nhập (thư mục để "Bất kỳ ai có link"), nếu không file trả về trang đăng nhập → bỏ qua, đếm báo.
// Chạy: Code.exe scripts/keo-chung-tu-drive.js [T9|tat_ca] [ghi]   (không có "ghi" = chạy thử, chỉ tải kiểm, không lưu)
// Mỗi file lưu ở chi/<id phiếu>/drive_<id Drive>_<tên> → chạy lại không trùng. Không in khoá. Monsieur Claude
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co', BUCKET = 'kt-chung-tu';
const KY = process.argv[2] || 'T9', GHI = process.argv[3] === 'ghi';
const MIME_OK = /^(image\/(jpeg|png|webp|heic|heif)|application\/pdf)$/;
const sach = s => s.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D').replace(/[^A-Za-z0-9._-]+/g, '-').replace(/-+/g, '-').slice(-60) || 'tep';
const tachId = s => [...String(s || '').matchAll(/(?:id=|\/d\/)([A-Za-z0-9_-]{20,})/g)].map(m => m[1]);
(async () => {
  const dk = KY === 'T9' ? `and c.ngay_tt between '2026-09-01' and '2026-09-30'` : '';
  const rows = await sql(`select c.id, c.chung_tu, c.unc from kt_chi c where not c.da_xoa ${dk}
    and (array_to_string(c.chung_tu, ' ') ~ 'drive.google' or coalesce(c.unc, '') ~ 'drive.google') order by c.id`);
  const da = new Set((await sql(`select duong_dan from kt_chung_tu where bang = 'chi' and duong_dan like '%/drive_%'`))
    .map(x => (x.duong_dan.match(/\/drive_([A-Za-z0-9_-]{20,})_/) || [])[1]));
  const viec = [];
  for (const r of rows) {
    for (const f of [...new Set(r.chung_tu.flatMap(tachId))]) viec.push({ chi: r.id, fid: f, loai: 'Hồ sơ' });
    for (const f of [...new Set(tachId(r.unc))]) viec.push({ chi: r.id, fid: f, loai: 'UNC' });
  }
  const dem = { phieu: rows.length, file: viec.length, da_co: 0, tai_duoc: 0, can_dang_nhap: 0, loai_khac: 0, loi: 0, da_luu: 0, mb: 0 };
  for (const v of viec) {
    if (da.has(v.fid)) { dem.da_co++; continue; }
    try {
      const r = await fetch('https://drive.google.com/uc?export=download&id=' + v.fid, { redirect: 'follow' });
      const ct = (r.headers.get('content-type') || '').split(';')[0].trim();
      const buf = Buffer.from(await r.arrayBuffer());
      if (ct === 'text/html') { buf.toString('utf8').includes('accounts.google.com') ? dem.can_dang_nhap++ : dem.loai_khac++; continue; }
      if (!MIME_OK.test(ct) || buf.length > 15 * 1024 * 1024) { dem.loai_khac++; continue; }
      dem.tai_duoc++; dem.mb += buf.length / 1048576;
      if (!GHI) continue;
      const cd = r.headers.get('content-disposition') || '';
      const ten0 = decodeURIComponent((cd.match(/filename\*=UTF-8''([^;]+)/) || [])[1] || '') || (cd.match(/filename="([^"]+)"/) || [])[1] || (v.fid + (ct === 'application/pdf' ? '.pdf' : '.jpg'));
      const ten = (v.loai === 'UNC' ? 'UNC_' : '') + ten0;
      const duong = `chi/${v.chi}/drive_${v.fid}_${sach(ten)}`;
      const up = await fetch(`${SB}/storage/v1/object/${BUCKET}/${duong}`, { method: 'POST',
        headers: { apikey: K.SERVICE_ROLE_KEY, Authorization: 'Bearer ' + K.SERVICE_ROLE_KEY, 'Content-Type': ct, 'x-upsert': 'true' }, body: buf });
      if (!up.ok) throw new Error('upload ' + up.status);
      await sql(`insert into kt_chung_tu (bang, dong_id, duong_dan, ten_file, mime, kich_thuoc, tao_boi)
        values ('chi', ${v.chi}, $kt$${duong}$kt$, $kt$${ten.slice(0, 200)}$kt$, '${ct}', ${buf.length}, 'Kéo từ Drive (sheet cũ)') on conflict (duong_dan) do nothing`);
      dem.da_luu++;
    } catch (e) { dem.loi++; }
  }
  dem.mb = Math.round(dem.mb * 10) / 10;
  if (GHI && dem.da_luu) await sql(`insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Monsieur Claude', 'kt_chung_tu', 'keo_drive', $kt$${JSON.stringify({ ky: KY, ...dem })}$kt$::jsonb)`);
  console.log((GHI ? 'ĐÃ GHI' : 'CHẠY THỬ (chưa lưu)') + ' · kỳ ' + KY + ' · ' + JSON.stringify(dem));
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
