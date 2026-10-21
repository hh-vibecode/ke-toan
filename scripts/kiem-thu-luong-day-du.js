// Kiểm thử ĐẦY ĐỦ TRÊN TRÌNH DUYỆT THẬT (20/10/2026, anh: "test tạo cẩn thận đầy đủ phiếu, lưu bước đến cùng, đảm bảo mọi thứ chạy" + "chạy xong phải clear hết dữ liệu test").
// Mỗi vai 1 trình duyệt đăng nhập TK tạm (quyền chép TK thật): nhân viên, Admin (kế toán), giám đốc, thủ quỹ, admin kế toán.
// Bấm đúng nút trên giao diện, tải ảnh thật, đi hết bước; đối chiếu CSDL sau mỗi bước.
// Phiếu thử: nội dung "THỬ HỆ THỐNG E2E …" → máy chủ không gửi chuông cho người thật, người thật không thấy phiếu.
// CUỐI CÙNG XOÁ SẠCH: phiếu chi / thu / điều chuyển thử, chứng từ + file trong kho kt-chung-tu, thông báo, nhật ký, bình luận, TK tạm.
// Chạy: node scripts/kiem-thu-luong-day-du.js [ảnh.png]   — cần Chromium + Playwright (phiên cloud có sẵn). Monsieur Claude
const fs = require('fs'), path = require('path');
const { chromium } = require(require.resolve('playwright', { paths: [require('child_process').execSync('npm root -g').toString().trim()] }));
const { taoTam, xoaTam } = require('./tk-tam');
const { sql } = require('./sql');
const { docKhoa } = require('./khoa');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co';
const TAG = 'THỬ HỆ THỐNG E2E ' + Date.now().toString(36);
// ảnh thử: tham số dòng lệnh, không có thì tự tạo 1 ảnh PNG nhỏ trong thư mục tạm của máy
const ANH = process.argv[2] || (() => { const z = require('zlib'), f = path.join(require('os').tmpdir(), 'kt-anh-thu.png');
  const ch = (t, d) => { const b = Buffer.alloc(4); b.writeUInt32BE(d.length); const c = Buffer.alloc(4); c.writeUInt32BE(z.crc32 ? z.crc32(Buffer.concat([Buffer.from(t), d])) : crc(Buffer.concat([Buffer.from(t), d]))); return Buffer.concat([b, Buffer.from(t), d, c]); };
  const crc = buf => { let c = ~0; for (const x of buf) { c ^= x; for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xEDB88320 : c >>> 1; } return ~c >>> 0; };
  const w = 40, h = 30, ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  const raw = Buffer.concat(Array.from({ length: h }, () => Buffer.concat([Buffer.from([0]), Buffer.alloc(w * 3, 180)])));
  fs.writeFileSync(f, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), ch('IHDR', ihdr), ch('IDAT', z.deflateSync(raw)), ch('IEND', Buffer.alloc(0))])); return f; })();
let dat = 0, truot = 0; const kq = (ok, ten, them = '') => { ok ? dat++ : truot++; console.log((ok ? 'ĐẠT  ' : 'TRƯỢT ') + ten + (them ? ' — ' + them : '')); return ok; };
const ngu = ms => new Promise(r => setTimeout(r, ms));
const lit = s => "'" + String(s).replace(/'/g, "''") + "'";

async function don(tk) {   // xoá sạch dữ liệu thử
  const ids = async bang => (await sql(`select id from ${bang} where noi_dung like ${lit(TAG + '%')}`)).map(x => x.id);
  const chi = await ids('kt_chi'), thu = await ids('kt_thu'), dc = await ids('kt_dieu_chuyen');
  const dk = (b, a) => a.length ? `(bang = '${b}' and dong_id in (${a.join(',')}))` : 'false';
  const where = [dk('chi', chi), dk('kt_chi', chi), dk('thu', thu), dk('kt_thu', thu), dk('dieu_chuyen', dc), dk('kt_dieu_chuyen', dc)].join(' or ');
  const file = (await sql(`select duong_dan from kt_chung_tu where ${where}`)).map(x => x.duong_dan);
  if (file.length) {
    const r = await fetch(`${SB}/storage/v1/object/kt-chung-tu`, { method: 'DELETE', headers: { apikey: K.SERVICE_ROLE_KEY, Authorization: 'Bearer ' + K.SERVICE_ROLE_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ prefixes: file }) });
    console.log(`  dọn: ${file.length} file trong kho → ${r.ok ? 'đã xoá' : 'LỖI ' + r.status}`);
  }
  await sql(`delete from kt_chung_tu where ${where}; delete from kt_thong_bao where ${where}; delete from kt_binh_luan where ${where}; delete from kt_nhat_ky where ${where};
    ${chi.length ? `delete from kt_tam_ung where chi_id in (${chi.join(',')}); delete from kt_vay_tra where chi_id in (${chi.join(',')}); delete from kt_chi where id in (${chi.join(',')});` : ''}
    ${thu.length ? `delete from kt_tam_ung_hoan where thu_id in (${thu.join(',')}); delete from kt_thu where id in (${thu.join(',')});` : ''}
    ${dc.length ? `delete from kt_dieu_chuyen where id in (${dc.join(',')});` : ''}
    delete from kt_nhat_ky where du_lieu::text like ${lit('%' + TAG + '%')};
    delete from kt_nhat_ky where nguoi in (select ho_ten from kt_nguoi_dung where ten_dang_nhap like 'tam-e2e%');   -- nhật ký tải chứng từ (ghi theo mã chứng từ)`);
  for (const t of Object.values(tk)) await xoaTam(t.ten);
  const con = (await sql(`select (select count(*) from kt_chi where noi_dung like ${lit(TAG + '%')}) + (select count(*) from kt_thu where noi_dung like ${lit(TAG + '%')})
      + (select count(*) from kt_dieu_chuyen where noi_dung like ${lit(TAG + '%')}) + (select count(*) from kt_nguoi_dung where ten_dang_nhap like 'tam-e2e%')
      + (select count(*) from kt_nhat_ky where du_lieu::text like ${lit('%' + TAG + '%')} or nguoi like 'THỬ NGHIỆM tam-e2e%') n`))[0].n;
  console.log(`  dọn: ${chi.length} phiếu chi, ${thu.length} phiếu thu, ${dc.length} điều chuyển, ${Object.keys(tk).length} TK tạm → còn sót ${con}`);
  return con;
}

(async () => {
  if (!fs.existsSync(ANH)) throw new Error('thiếu ảnh thử: ' + ANH);
  const VT = Object.fromEntries((await sql(`select ten_dang_nhap, vi_tri from kt_nguoi_dung where ten_dang_nhap in ('thuquy','admin.ketoan')`)).map(x => [x.ten_dang_nhap, x.vi_tri]));   // 21/10: chép cả VỊ TRÍ (admin.ketoan lên Admin 21/10)
  const that = Object.fromEntries((await sql(`select ten_dang_nhap, quyen, vi_tri from kt_nguoi_dung where ten_dang_nhap in ('thuquy','admin.ketoan')`)).map(x => [x.ten_dang_nhap, x.quyen]));
  const id = (await sql(`select (select id from kt_tai_khoan where hoat_dong and loai='tien_mat' and thu_quy_chi limit 1) ket,
      (select id from kt_tai_khoan where hoat_dong and loai='tien_mat' and not coalesce(thu_quy_chi,false) limit 1) quay,
      (select id from kt_tai_khoan where hoat_dong and loai='ngan_hang' and thu_quy_chi order by id limit 1) nh,
      (select id from kt_tai_khoan where hoat_dong and loai='ngan_hang' and not coalesce(thu_quy_chi,false) order by id limit 1) cn,
      (select id from kt_loai where nhom='chi' and hoat_dong order by id limit 1) lc, (select id from kt_loai where nhom='thu' and hoat_dong order by id limit 1) lt`))[0];
  const tk = {}, br = await chromium.launch({ proxy: { server: process.env.HTTPS_PROXY } }), html = fs.readFileSync(path.join(__dirname, '..', 'index.html'));
  const trang = {};
  try {
    for (const [k, vt, q] of [['nv', 'nhan_vien', ['chi_de_nghi']], ['adm', 'admin', ['*']], ['gd', 'admin', ['chi_gd']], ['tq', VT.thuquy, [...that.thuquy, 'dong_tien']], ['akt', VT['admin.ketoan'], that['admin.ketoan']]])
      tk[k] = await taoTam('tam-e2e-' + k, vt, q);
    const mo = async (k, hash = 'chi') => {
      if (!trang[k]) { const ctx = await br.newContext({ viewport: { width: 1500, height: 950 }, timezoneId: 'Asia/Ho_Chi_Minh' });
        await ctx.route('https://ke-toan.test/**', rt => rt.request().url().includes('phien-ban.txt') ? rt.fulfill({ status: 200, contentType: 'text/plain', body: require('fs').readFileSync(require('path').join(__dirname, '..', 'phien-ban.txt')) }) : rt.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', body: html }));
        await ctx.addInitScript(p => sessionStorage.setItem('kt_phien', p), tk[k].phien);
        const pg = await ctx.newPage(); pg.hop = [];
        pg.on('dialog', d => { pg.hop.push(d.message()); d.accept(); }); pg.on('pageerror', e => console.log(`  [${k}] LỖI TRANG`, e.message));
        trang[k] = pg; await pg.goto('https://ke-toan.test/#' + hash); }
      else await trang[k].evaluate(h => { try { closeModal(); } catch (_) {} go(h); }, hash);
      await trang[k].waitForFunction(() => typeof S !== 'undefined' && S.toi && !/Đang tải|Đang tính/.test((document.querySelector('#page') || {}).innerText || 'x'), null, { timeout: 60000 });
      await trang[k].waitForTimeout(800); return trang[k];
    };
    const db1 = async q => (await sql(q))[0] || {};
    const choCT = async (bang, dong, unc, n = 1) => { for (let i = 0; i < 40; i++) { const c = (await db1(`select count(*)::int n from kt_chung_tu where bang='${bang}' and dong_id=${dong} and not da_xoa ${unc ? "and ten_file ilike 'UNC%'" : ''}`)).n; if (c >= n) return true; await ngu(1000); } return false; };
    const nut = async (pg, re) => { const b = await pg.$$('#modal button, .m-pn button'); for (const x of b) { const t = (await x.textContent()).trim(); if (new RegExp(re).test(t) && await x.isVisible()) { await x.click(); await pg.waitForTimeout(1500); return t; } }
      throw new Error('không thấy nút /' + re + '/ · có: ' + (await Promise.all(b.map(x => x.textContent()))).map(t => t.trim()).filter(Boolean).join(' | ')); };
    const chon = (pg, ten, v) => pg.evaluate(([n, v]) => { const e = [...document.querySelectorAll(`#modal [name=${n}]`)].find(e => e.offsetParent !== null) || document.querySelector(`#modal [name=${n}]`); if (!e) return false; e.value = v; e.dispatchEvent(new Event('change', { bubbles: true })); e.dispatchEvent(new Event('input', { bubbles: true })); return true; }, [ten, String(v)]);
    const moPhieu = async (k, ma) => { const pg = await mo(k); await pg.evaluate(() => { try { closeModal(); } catch (_) {} S.cache = {}; render(); });
      await pg.waitForFunction(() => S.cache && Array.isArray(S.cache.chi), null, { timeout: 60000 }); await pg.waitForTimeout(500);
      await pg.evaluate(ma => { if (S.cache.chi.find(c => c.id === ma)) xemChi(ma); }, ma); await pg.waitForTimeout(1500);
      if (!await pg.$('#modal')) throw new Error(`[${k}] không mở được phiếu #${ma} (không có trong danh sách)`); return pg; };
    const trangThai = async ma => (await db1(`select trang_thai, lap_lenh_luc is not null ll, tai_khoan_id tk from kt_chi where id=${ma}`));
    const taoDeNghi = async (ten, tien) => {
      const pg = await mo('nv'); pg.hop = [];
      await pg.evaluate(() => formChi()); await pg.waitForTimeout(600);
      const v = { hach_toan: 'co', noi_dung: TAG + ' ' + ten, so_tien: String(tien), ngay_su_dung: new Date(Date.now() + 7 * 36e5).toISOString().slice(0, 10), hinh_thuc_nhan: 'ck',
        thu_huong_ten: 'THỬ HỆ THỐNG NCC', thu_huong_nh: 'Vietcombank', thu_huong_stk: '0011001234567', co_hd_do: 'false' };
      for (const [n, x] of Object.entries(v)) await chon(pg, n, x);
      await pg.evaluate(() => { for (const n of ['bo_phan_id', 'hd_ve', 'dv_cp']) { const e = document.querySelector('#modal [name=' + n + ']'); if (e && !e.value) { const o = [...e.options].find(o => o.value); if (o) e.value = o.value; } } });
      await (await pg.$('#modal .ct input[type=file]')).setInputFiles(ANH); await pg.waitForTimeout(400);
      await pg.evaluate(() => luuChi(null)); await pg.waitForTimeout(2500);
      const r = await db1(`select id, trang_thai from kt_chi where noi_dung = ${lit(TAG + ' ' + ten)}`);
      if (!r.id) throw new Error('không tạo được phiếu · hộp thoại: ' + pg.hop.join(' / '));
      const ct = await choCT('chi', r.id, false);
      kq(r.trang_thai === 'cho_duyet' && ct, `[nhân viên] tạo đề nghị "${ten}" trên app + đính kèm ảnh`, `#${r.id} ${r.trang_thai}${ct ? ', ảnh đã lên kho' : ', ẢNH CHƯA LÊN'}`);
      return r.id;
    };

    // ── LUỒNG 1: TK ngân hàng công ty — nhân viên → kế toán xác nhận + chọn TK → thủ quỹ lập lệnh (UNC) → kế toán duyệt lệnh
    console.log('\nLUỒNG 1 — chi qua TK ngân hàng công ty (lập lệnh → duyệt lệnh)');
    const c1 = await taoDeNghi('L1 ngan hang', 1234000);
    let pg = await moPhieu('adm', c1); await chon(pg, 'tai_khoan_id', id.nh); await chon(pg, 'loai_id', id.lc); await nut(pg, '✓ Xác nhận');
    let s = await trangThai(c1); kq(s.trang_thai === 'cho_tt' && s.tk === id.nh, '[kế toán] xác nhận + chọn TK ngân hàng', s.trang_thai);
    pg = await moPhieu('tq', c1); pg.hop = [];
    const n1 = await pg.$$('#modal button'); const tq1 = (await Promise.all(n1.map(x => x.textContent()))).map(t => t.trim());
    kq(!tq1.some(t => /^✓ Đã chi tiền/.test(t)), '[thủ quỹ] TK ngân hàng: không có nút "Đã chi tiền" (phải lập lệnh)', tq1.filter(t => /chi|lệnh/i.test(t)).join(' | '));
    await (await pg.$('#modal .ct[data-loc="unc"] input[type=file]')).setInputFiles(ANH); const u1 = await choCT('chi', c1, true);
    kq(u1, '[thủ quỹ] up ảnh uỷ nhiệm chi');
    await pg.evaluate(id => xemChi(id), c1); await pg.waitForTimeout(1200); await nut(pg, 'lập lệnh');
    s = await trangThai(c1); kq(s.trang_thai === 'cho_tt' && s.ll, '[thủ quỹ] bấm "Đã lập lệnh" → vẫn Chờ chi tiền, chờ duyệt lệnh', JSON.stringify(s) + (pg.hop.length ? ' · ' + pg.hop.join(' / ') : ''));
    pg = await moPhieu('adm', c1); await nut(pg, 'duyệt lệnh');
    s = await trangThai(c1); kq(s.trang_thai === 'da_tt', '[kế toán] bấm "Đã duyệt lệnh" → Đã thanh toán', s.trang_thai + (pg.hop.length ? ' · ' + pg.hop.join(' / ') : ''));

    // ── LUỒNG 2: KÉT tiền mặt — giám đốc xác nhận chọn két → admin kế toán không chi được → thủ quỹ up ảnh + người nhận → Đã chi tiền
    console.log('\nLUỒNG 2 — chi tiền mặt từ KÉT (thủ quỹ chi)');
    const c2 = await taoDeNghi('L2 ket', 456000);
    pg = await moPhieu('gd', c2); await chon(pg, 'tai_khoan_id', id.ket); await chon(pg, 'loai_id', id.lc); await nut(pg, 'Xác nhận|Duyệt');
    s = await trangThai(c2); kq(s.trang_thai === 'cho_tt' && s.tk === id.ket, '[giám đốc] xác nhận + chọn KÉT', s.trang_thai);
    pg = await moPhieu('akt', c2); const a2 = (await Promise.all((await pg.$$('#modal button')).map(x => x.textContent()))).map(t => t.trim());
    kq(!a2.some(t => /Đã chi tiền/.test(t)), '[admin kế toán] không có nút "Đã chi tiền" từ két', a2.filter(t => /chi|lệnh|nhận/i.test(t)).join(' | ') || 'không nút chi');
    pg = await moPhieu('tq', c2); pg.hop = [];
    await (await pg.$('#modal .ct[data-loc="unc"] input[type=file]')).setInputFiles(ANH); kq(await choCT('chi', c2, true), '[thủ quỹ] up ảnh phiếu chi ký nhận');
    await pg.evaluate(id => xemChi(id), c2); await pg.waitForTimeout(1200);
    await chon(pg, 'nguoi_nhan_tien', 'THỬ NGƯỜI NHẬN'); await nut(pg, 'Đã chi tiền');
    s = await trangThai(c2); kq(s.trang_thai === 'da_tt', '[thủ quỹ] ghi người nhận + bấm "Đã chi tiền" → Đã thanh toán', s.trang_thai + (pg.hop.length ? ' · ' + pg.hop.join(' / ') : ''));

    // ── LUỒNG 3: TK cá nhân — giám đốc xác nhận + tự chi
    console.log('\nLUỒNG 3 — chi từ TK cá nhân (giám đốc chi)');
    const c3 = await taoDeNghi('L3 ca nhan', 78000);
    pg = await moPhieu('gd', c3); await chon(pg, 'tai_khoan_id', id.cn); await chon(pg, 'loai_id', id.lc); await nut(pg, 'Xác nhận|Duyệt');
    s = await trangThai(c3); kq(s.trang_thai === 'cho_tt', '[giám đốc] xác nhận + chọn TK cá nhân', s.trang_thai);
    pg = await moPhieu('gd', c3); pg.hop = [];
    await (await pg.$('#modal .ct[data-loc="unc"] input[type=file]')).setInputFiles(ANH); kq(await choCT('chi', c3, true), '[giám đốc] up ảnh giao dịch');
    await pg.evaluate(id => xemChi(id), c3); await pg.waitForTimeout(1200); await nut(pg, 'Đã chi tiền');
    s = await trangThai(c3); kq(s.trang_thai === 'da_tt', '[giám đốc] bấm "Đã chi tiền" → Đã thanh toán', s.trang_thai + (pg.hop.length ? ' · ' + pg.hop.join(' / ') : ''));

    // ── LUỒNG 4: từ chối + giám đốc mở lại
    console.log('\nLUỒNG 4 — từ chối rồi giám đốc mở lại');
    const c4 = await taoDeNghi('L4 tu choi', 33000);
    pg = await moPhieu('adm', c4); await nut(pg, 'Từ chối'); s = await trangThai(c4); kq(s.trang_thai === 'tu_choi', '[kế toán] từ chối', s.trang_thai);
    pg = await moPhieu('gd', c4); await nut(pg, 'Mở lại'); s = await trangThai(c4); kq(s.trang_thai === 'cho_duyet', '[giám đốc] mở lại phiếu bị từ chối', s.trang_thai);

    // ── LUỒNG 5: admin kế toán tự chi không cần duyệt
    console.log('\nLUỒNG 5 — tự chi không cần duyệt (admin kế toán)');
    pg = await mo('akt'); pg.hop = [];
    await pg.evaluate(() => formChi()); await pg.waitForTimeout(600);
    for (const [n, x] of Object.entries({ hach_toan: 'co', noi_dung: TAG + ' L5 tu chi', so_tien: '15000', ngay_su_dung: new Date(Date.now() + 7 * 36e5).toISOString().slice(0, 10), hinh_thuc_nhan: 'ck', thu_huong_ten: 'THỬ HỆ THỐNG', thu_huong_nh: 'Vietcombank', thu_huong_stk: '0011001234567', co_hd_do: 'false' })) await chon(pg, n, x);
    await pg.evaluate(() => { for (const n of ['bo_phan_id', 'hd_ve', 'dv_cp']) { const e = document.querySelector('#modal [name=' + n + ']'); if (e && !e.value) { const o = [...e.options].find(o => o.value); if (o) e.value = o.value; } }
      const t = document.querySelector('#modal [name=tt_luon]'); if (t) { t.checked = true; t.dispatchEvent(new Event('change', { bubbles: true })); } });
    const coTL = await pg.$('#modal [name=tt_luon]'); kq(!!coTL, '[admin kế toán] có ô "Đã thanh toán luôn"');
    await chon(pg, 'tai_khoan_id', id.nh); await chon(pg, 'loai_id', id.lc);
    await pg.evaluate(() => luuChi(null)); await pg.waitForTimeout(2500);
    const r5 = await db1(`select id, trang_thai from kt_chi where noi_dung = ${lit(TAG + ' L5 tu chi')}`);
    kq(r5.trang_thai === 'da_tt', '[admin kế toán] tạo phiếu Đã thanh toán luôn', (r5.trang_thai || 'không tạo được') + (pg.hop.length ? ' · ' + pg.hop.join(' / ') : ''));

    // ── LUỒNG 6: thu vào két + điều chuyển quầy → két: chỉ thủ quỹ xác nhận đã nhận tiền
    console.log('\nLUỒNG 6 — tiền vào KÉT (thu + điều chuyển quầy → két)');
    pg = await mo('tq', 'thu'); pg.hop = [];
    await pg.evaluate(() => formThu()); await pg.waitForTimeout(600);
    for (const [n, x] of Object.entries({ hach_toan: 'co', ngay: new Date(Date.now() + 7 * 36e5).toISOString().slice(0, 10), so_tien: '99000', loai_id: id.lt, tai_khoan_id: id.ket, noi_dung: TAG + ' L6 thu' })) await chon(pg, n, x);
    await pg.evaluate(() => { const e = document.querySelector('#modal [name=don_vi_id]'); if (e && !e.value) { const o = [...e.options].find(o => o.value); if (o) e.value = o.value; } });
    await pg.evaluate(() => luuThu(null)); await pg.waitForTimeout(2500);
    const t6 = await db1(`select id from kt_thu where noi_dung = ${lit(TAG + ' L6 thu')}`); kq(!!t6.id, '[thủ quỹ] tạo phiếu thu vào két', pg.hop.join(' / '));
    pg = await mo('adm', 'dieu_chuyen'); pg.hop = [];
    await pg.evaluate(() => formDC()); await pg.waitForTimeout(600);
    for (const [n, x] of Object.entries({ hach_toan: 'co', ngay: new Date(Date.now() + 7 * 36e5).toISOString().slice(0, 10), so_tien: '88000', tk_di_id: id.quay, tk_nhan_id: id.ket, noi_dung: TAG + ' L6 dc' })) await chon(pg, n, x);
    await pg.evaluate(() => luuDC(null)); await pg.waitForTimeout(2500);
    const d6 = await db1(`select id, da_xac_nhan from kt_dieu_chuyen where noi_dung = ${lit(TAG + ' L6 dc')}`); kq(!!d6.id && !d6.da_xac_nhan, '[kế toán] tạo điều chuyển quầy → két (chưa xác nhận)', pg.hop.join(' / '));
    await pg.evaluate(() => { S.cache = {}; render(); }); await pg.waitForTimeout(2500);
    const admNut = await pg.evaluate(i => !!document.querySelector(`[onclick*="tqNhan('dieu_chuyen',${i})"]`) || !!document.querySelector(`[onclick*="xacNhanDC(${i})"]`), d6.id);
    kq(!admNut, '[kế toán Admin] KHÔNG có nút xác nhận / "Đã nhận tiền" cho điều chuyển vào két');
    pg = await mo('tq', 'dieu_chuyen'); pg.hop = [];
    const b6 = await pg.$(`[onclick*="tqNhan('dieu_chuyen',${d6.id})"]`); kq(!!b6, '[thủ quỹ] thấy nút "✓ Đã nhận tiền" trên điều chuyển');
    if (b6) { await b6.click(); await pg.waitForTimeout(2000); }
    const d6b = await db1(`select da_xac_nhan, tq_nhan_luc is not null n from kt_dieu_chuyen where id = ${d6.id}`); kq(d6b.da_xac_nhan && d6b.n, '[thủ quỹ] bấm → điều chuyển đã xác nhận + ghi thủ quỹ đã nhận', pg.hop.join(' / '));
    pg = await mo('tq', 'thu'); pg.hop = [];
    const b6t = await pg.$(`[onclick*="tqNhan('thu',${t6.id})"]`); kq(!!b6t, '[thủ quỹ] thấy nút "✓ Đã nhận tiền" trên phiếu thu');
    if (b6t) { await b6t.click(); await pg.waitForTimeout(2000); }
    kq((await db1(`select tq_nhan_luc is not null n from kt_thu where id = ${t6.id}`)).n, '[thủ quỹ] bấm → phiếu thu ghi đã nhận tiền', pg.hop.join(' / '));

    // ── LUỒNG 7: phiếu đề nghị công khai (không đăng nhập) + ảnh
    console.log('\nLUỒNG 7 — phiếu đề nghị công khai (link không đăng nhập)');
    const ctx = await br.newContext({ viewport: { width: 420, height: 900 } });
    await ctx.route('https://ke-toan.test/**', rt => rt.request().url().includes('phien-ban.txt') ? rt.fulfill({ status: 200, contentType: 'text/plain', body: require('fs').readFileSync(require('path').join(__dirname, '..', 'phien-ban.txt')) }) : rt.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', body: html }));
    const pc = await ctx.newPage(); pc.hop = []; pc.on('dialog', d => { pc.hop.push(d.message()); d.accept(); });
    await pc.goto('https://ke-toan.test/#de-nghi'); await pc.waitForSelector('#dn', { timeout: 30000 }); await pc.waitForTimeout(1500);
    await pc.evaluate(([tag, hom]) => { const f = document.querySelector('#dn'); const set = (k, v) => { const e = f.querySelector(`[name=${k}]`); if (!e) return; if (e.tagName === 'SELECT' && v === '*') { const o = [...e.options].find(o => o.value); e.value = o ? o.value : ''; } else e.value = v; e.dispatchEvent(new Event('change', { bubbles: true })); e.dispatchEvent(new Event('input', { bubbles: true })); };
      set('nguoi_de_nghi', 'THỬ HỆ THỐNG'); set('bo_phan_id', '*'); set('noi_dung', tag + ' L7 cong khai'); set('ngay_su_dung', hom); set('so_tien', '67.000'); set('hinh_thuc', 'ck');
      set('thu_huong_ten', 'THỬ HỆ THỐNG NCC'); set('thu_huong_nh', 'Vietcombank'); set('thu_huong_stk', '0011001234567'); set('co_hd_do', 'false'); set('hd_ve', '*');
      const dv = f.querySelector('[name=dv]'); if (dv) { dv.checked = true; dv.dispatchEvent(new Event('change', { bubbles: true })); } }, [TAG, new Date(Date.now() + 7 * 36e5).toISOString().slice(0, 10)]);
    await (await pc.$('#dn input[type=file]')).setInputFiles(ANH); await pc.waitForTimeout(500);
    await pc.evaluate(() => dnGui()); await pc.waitForTimeout(6000);
    const r7 = await db1(`select id, trang_thai from kt_chi where noi_dung = ${lit(TAG + ' L7 cong khai')}`);
    kq(r7.trang_thai === 'cho_duyet', '[người ngoài] gửi phiếu đề nghị công khai', (r7.trang_thai || 'KHÔNG có phiếu') + ' · lỗi form: ' + (await pc.evaluate(() => (document.querySelector('#dn-err') || {}).textContent || '—')));
    if (r7.id) kq(await choCT('chi', r7.id, false), '[người ngoài] ảnh đính kèm đã lên kho');
  } catch (e) { kq(false, 'DỪNG GIỮA CHỪNG', e.message.slice(0, 400)); }
  finally {
    await br.close();
    console.log(`\n${dat} đạt / ${truot} trượt\nDỌN DỮ LIỆU THỬ:`);
    const con = await don(tk);
    if (con) { console.log('CÒN SÓT — kiểm tay'); process.exitCode = 1; }
  }
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
