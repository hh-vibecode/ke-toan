// Kiểm thử "nghi sai loại" (09/10/2026): bật tạm ngày áp dụng = hôm nay, tạo phiếu thử chọn sai loại, kiểm cờ + 2 nút, rồi TRẢ ngày áp dụng về như cũ và dọn sạch.
// Dùng tài khoản tạm (scripts/tk-tam.js). Monsieur Claude
const { sql } = require('./sql'); const { taoTam, xoaTam } = require('./tk-tam'); const { docKhoa } = require('./khoa');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co';
const rpc = async (fn, a) => { const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: K.ANON_KEY, Authorization: 'Bearer ' + K.ANON_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify(a) });
  const t = await r.text(); const j = t ? JSON.parse(t) : null; if (!r.ok) throw new Error(j && j.message || t); return j; };
let dat = 0, truot = 0; const kq = (t, ok, g = '') => { ok ? dat++ : truot++; console.log((ok ? '  ĐẠT ' : '  TRƯỢT ') + t + (g ? ' — ' + g : '')); };
(async () => {
  const cu = (await sql(`select gia_tri from kt_cai_dat where khoa = 'ngay_ap_dung_app'`))[0].gia_tri; const ids = [];
  try {
    const T = await taoTam('tam-luat-loai', 'admin', ['*'], 'THỬ NGHIỆM luật loại');
    const hom = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);
    const lo = Object.fromEntries((await sql(`select ten, id from kt_loai where nhom = 'chi'`)).map(x => [x.ten, x.id]));
    const tk = (await sql(`select id from kt_tai_khoan where hoat_dong order by id limit 1`))[0].id;
    const tao = async nd => rpc('kt_luu_chi', { p_phien: T.phien, p_dong: { noi_dung: nd, so_tien: 11000, trang_thai: 'da_tt', ngay_tt: hom, tai_khoan_id: tk, loai_id: lo['FINANCE - Tài chính - vay,lãi'], kiot: 'khong' } });
    const a = await tao('THU-NGHIEM phí ngân hàng tháng này'); ids.push(a);
    kq('Chưa bật ngày áp dụng → không gắn cờ', !(await sql(`select kt_nghi_loai(c) n from kt_chi c where id = ${a}`))[0].n);
    await sql(`update kt_cai_dat set gia_tri = '${hom}' where khoa = 'ngay_ap_dung_app'`);
    const ds = await rpc('kt_ds', { p_phien: T.phien, p_bang: 'chi', p_tu: hom, p_den: hom }); const x = ds.find(r => r.id === a);
    kq('Bật ngày áp dụng → phiếu sai loại bị gắn cờ, gợi ý đúng loại', x && x.nghi_loai && x.nghi_loai.loai === 'OPEX - Vận hành & Quản lí', x && JSON.stringify(x.nghi_loai));
    await rpc('kt_xu_ly_loai', { p_phien: T.phien, p_id: a, p_doi: true });
    kq('Bấm "Đổi" → loại đổi theo luật, hết cờ', (await sql(`select (select ten from kt_loai where id = c.loai_id) l, kt_nghi_loai(c) n from kt_chi c where id = ${a}`))[0].l === 'OPEX - Vận hành & Quản lí');
    const b = await tao('THU-NGHIEM SMS BANKING phí'); ids.push(b);
    await rpc('kt_xu_ly_loai', { p_phien: T.phien, p_id: b, p_doi: false });
    const rb = (await sql(`select (select ten from kt_loai where id = c.loai_id) l, kt_nghi_loai(c) n, bo_qua_loai from kt_chi c where id = ${b}`))[0];
    kq('Bấm "Giữ" → giữ loại, không báo nữa', rb.l === 'FINANCE - Tài chính - vay,lãi' && !rb.n && rb.bo_qua_loai);
    const c = await tao('THU-NGHIEM mua văn phòng phẩm'); ids.push(c);
    kq('Nội dung không thuộc luật nào → không gắn cờ', !(await sql(`select kt_nghi_loai(c) n from kt_chi c where id = ${c}`))[0].n);
  } catch (e) { truot++; console.log('  DỪNG: ' + e.message); }
  finally {
    await sql(`update kt_cai_dat set gia_tri = ${cu === null ? 'null' : `'${cu}'`} where khoa = 'ngay_ap_dung_app'`);
    if (ids.length) await sql(`delete from kt_thong_bao where bang = 'chi' and dong_id in (${ids.join(',')}); delete from kt_nhat_ky where bang = 'kt_chi' and dong_id in (${ids.join(',')}); delete from kt_chi where id in (${ids.join(',')})`);
    await xoaTam('tam-luat-loai');
    console.log(`\n${dat} đạt · ${truot} trượt · đã trả ngày áp dụng về: ${cu ?? '(trống)'} · đã dọn`);
  }
})();
