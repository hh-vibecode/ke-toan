// Kiểm thử SỬA NỘI DUNG CHUYỂN KHOẢN ở khung mã QR (26/10/2026, anh: "thêm chỉnh sửa cho phần nội dung đi"). Khung chép từ kiem-thu-tu-tru.js.
// Vai: nhân viên đề nghị, nhân viên khác, Admin, thủ quỹ (quyền chép TK thật), TK chỉ xem Chi. Bấm nút thật trên giao diện, đối chiếu CSDL.
// Phiếu thử nội dung "THỬ HỆ THỐNG E2E …"; CUỐI CÙNG XOÁ SẠCH (phiếu, chứng từ + file kho, nhật ký, thông báo, TK tạm).
// Chạy: node scripts/kiem-thu-nd-ck.js — cần Chromium + Playwright (phiên cloud có sẵn). Monsieur Claude
const fs = require('fs'), path = require('path');
const { chromium } = require(require.resolve('playwright', { paths: [require('child_process').execSync('npm root -g').toString().trim()] }));
const { taoTam, xoaTam } = require('./tk-tam');
const { sql } = require('./sql');
const { docKhoa } = require('./khoa');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co';
const TAG = 'THỬ HỆ THỐNG E2E ND' + Date.now().toString(36);
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
  // KT_QR_JS = đường dẫn qrcode.js (npm qrcode-generator@1.4.4) khi máy chặn cdnjs (phiên cloud); không có thì tải cdnjs bằng curl
  const QR_JS = process.env.KT_QR_JS ? fs.readFileSync(process.env.KT_QR_JS) : require('child_process').execFileSync('curl', ['-sSf', 'https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js']);
  const tk = {}, br = await chromium.launch({ proxy: { server: process.env.HTTPS_PROXY } }), html = fs.readFileSync(path.join(__dirname, '..', 'index.html'));
  const trang = {};
  try {
    for (const [k, vt, q] of [['nv', 'nhan_vien', ['chi_de_nghi']], ['nv2', 'nhan_vien', ['chi_de_nghi']], ['adm', 'admin', ['*']], ['tq', VT.thuquy, [...that.thuquy, 'dong_tien']], ['xem', 'nhan_vien', ['chi']]])
      tk[k] = await taoTam('tam-e2e-' + k, vt, q);
    const mo = async (k, hash = 'chi') => {
      if (!trang[k]) { const ctx = await br.newContext({ viewport: { width: 1500, height: 950 }, timezoneId: 'Asia/Ho_Chi_Minh' });
        await ctx.route('https://ke-toan.test/**', rt => rt.request().url().includes('phien-ban.txt') ? rt.fulfill({ status: 200, contentType: 'text/plain', body: require('fs').readFileSync(require('path').join(__dirname, '..', 'phien-ban.txt')) }) : rt.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', body: html }));
        await ctx.route('https://cdnjs.cloudflare.com/**', rt => rt.fulfill({ status: 200, contentType: 'application/javascript', body: QR_JS }));   // thư viện QR: trình duyệt thử không qua proxy HTTPS → tải bằng curl
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


    let pg;
    const qr = async (pg, ma) => (await pg.waitForSelector('#qrw-' + ma + ' img', { timeout: 15000 }).catch(async () => console.log('  (mã QR chưa hiện: ' + await pg.evaluate(ma => (document.getElementById('qr-' + ma) || {}).innerText, ma) + ')')), pg.evaluate(ma => { const w = document.getElementById('qrw-' + ma); return w ? { co: true, sua: [...w.querySelectorAll('button')].some(b => /Sửa/.test(b.textContent)), o: !!document.getElementById('ndck-' + ma), img: !!w.querySelector('img'), chu: w.innerText } : { co: false }; }, ma));
    const suaND = async (pg, ma, chu) => { await pg.evaluate(ma => [...document.querySelectorAll('#qrw-' + ma + ' button')].find(b => /Sửa/.test(b.textContent)).click(), ma); await pg.waitForTimeout(300);
      await pg.fill('#ndck-' + ma, chu); await pg.press('#ndck-' + ma, 'Enter'); await pg.waitForTimeout(2000); };
    const ndDB = async ma => (await db1(`select noi_dung_ck from kt_chi where id = ${ma}`)).noi_dung_ck;
    const rpcThu = async (k, ma, nd) => { const r = await fetch(`${SB}/rest/v1/rpc/kt_sua_nd_ck`, { method: 'POST', headers: { apikey: K.ANON_KEY, Authorization: 'Bearer ' + K.ANON_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_phien: tk[k].phien, p_id: ma, p_nd: nd }) }); return { ok: r.ok, t: (await r.text()).slice(0, 160) }; };

    console.log('\nN1 — người đề nghị sửa nội dung CK khi phiếu còn chờ duyệt');
    const c = await taoDeNghi('N1', 12000);
    pg = await moPhieu('nv', c); pg.hop = [];
    let q = await qr(pg, c);
    kq(q.co && q.sua && q.img, '[nhân viên tạo phiếu] khung QR có nút "Sửa" cạnh nút Chép', JSON.stringify({ sua: q.sua, img: q.img }));
    await pg.evaluate(() => { const e = document.querySelector('#modal h4'); if (e) e.dataset.giu = '1'; });
    await suaND(pg, c, 'Tien hang T10 AB');
    q = await qr(pg, c);
    kq(await ndDB(c) === 'Tien hang T10 AB', 'Enter → lưu vào phiếu', String(await ndDB(c)) + (pg.hop.length ? ' · ' + pg.hop.join(' / ') : ''));
    kq(q.img && new RegExp('PC' + String(c).padStart(6, '0') + ' Tien hang T10 AB').test(q.chu) && !q.o, 'khung QR vẽ lại: mã mới, nội dung = số phiếu + phần vừa gõ, thoát ô sửa');
    kq(await pg.evaluate(() => !!document.querySelector('#modal h4[data-giu]')), 'không vẽ lại cả cửa sổ (ô đang điền dở ở phần khác không mất)');
    kq(!!(await db1(`select 1 x from kt_nhat_ky where bang='kt_chi' and dong_id=${c} and hanh_dong='doi_nd_ck' and du_lieu->>'sang'='Tien hang T10 AB'`)).x, 'nhật ký ghi lần đổi (cũ → mới)');
    await pg.evaluate(ma => [...document.querySelectorAll('#qrw-' + ma + ' button')].find(b => /Sửa/.test(b.textContent)).click(), c); await pg.waitForTimeout(300);
    await pg.fill('#ndck-' + c, 'KHONG LUU'); await pg.press('#ndck-' + c, 'Escape'); await pg.waitForTimeout(800);
    q = await qr(pg, c);
    kq(await ndDB(c) === 'Tien hang T10 AB' && !q.o && !!(await pg.$('#modal')), 'Esc → huỷ, không lưu, cửa sổ phiếu vẫn mở');
    const r2 = await rpcThu('nv2', c, 'NV KHAC SUA');
    kq(!r2.ok && await ndDB(c) === 'Tien hang T10 AB', '[nhân viên khác] máy chủ chặn sửa phiếu không phải của mình', r2.t);

    console.log('\nN2 — phiếu đã xác nhận, chờ chi tiền (thủ quỹ chuyển khoản)');
    await sql(`update kt_chi set trang_thai = 'cho_tt', tai_khoan_id = ${id.nh} where id = ${c}`);   // dữ liệu thử: đẩy thẳng sang Chờ chi tiền
    pg = await moPhieu('nv', c).catch(() => null);
    if (pg) { q = await qr(pg, c); kq(!q.sua, '[người đề nghị] hết nút Sửa khi phiếu đã qua duyệt'); } else kq(true, '[người đề nghị] không còn thấy phiếu (đúng phạm vi)');
    kq(!(await rpcThu('nv', c, 'NV SUA SAU DUYET')).ok, '[người đề nghị] máy chủ chặn sửa sau khi đã duyệt');
    pg = await moPhieu('tq', c); pg.hop = [];
    q = await qr(pg, c);
    kq(q.sua, '[thủ quỹ] có nút Sửa nội dung CK');
    await suaND(pg, c, 'Trả #5 Shidai');
    kq(await ndDB(c) === 'Tra 5 Shidai', '[thủ quỹ] gõ có dấu / ký tự lạ → lưu dạng không dấu như ngân hàng nhận', String(await ndDB(c)) + (pg.hop.length ? ' · ' + pg.hop.join(' / ') : ''));
    await pg.evaluate(ma => [...document.querySelectorAll('#qrw-' + ma + ' button')].find(b => /Sửa/.test(b.textContent)).click(), c); await pg.waitForTimeout(300);
    kq(await pg.$eval('#ndck-' + c, e => e.maxLength) === 16, 'ô sửa phần gõ thêm giới hạn 16 ký tự (+ số phiếu = 25, giới hạn trường nội dung mã VietQR)');
    await (await pg.$('#qrw-' + c)).screenshot({ path: path.join(require('os').tmpdir(), 'kt-nd-ck.png') });
    await pg.fill('#ndck-' + c, ''); await pg.press('#ndck-' + c, 'Enter'); await pg.waitForTimeout(2000);
    q = await qr(pg, c);
    kq(await ndDB(c) === null && new RegExp('PC' + String(c).padStart(6, '0')).test(q.chu), 'để trống → bỏ phần gõ thêm, quay về "số phiếu + nội dung chi"', q.chu.split('\n').find(l => /PC\d/.test(l)));
    pg = await moPhieu('xem', c).catch(() => null);
    if (pg) { q = await qr(pg, c); kq(q.co && !q.sua, '[TK chỉ xem Chi] thấy mã QR, không có nút Sửa'); } else kq(false, '[TK chỉ xem Chi] không mở được phiếu');
    kq(!(await rpcThu('xem', c, 'XEM SUA')).ok, '[TK chỉ xem Chi] máy chủ chặn');

    console.log('\nN3 — phiếu đã chi tiền');
    await sql(`update kt_chi set trang_thai = 'da_tt', ngay_tt = current_date, loai_id = ${id.lc} where id = ${c}`);
    const r3 = await rpcThu('adm', c, 'SUA SAU KHI CHI');
    kq(!r3.ok && await ndDB(c) === null, '[Admin] máy chủ chặn sửa nội dung CK khi phiếu đã chi', r3.t);
  } catch (e) { kq(false, 'DỪNG GIỮA CHỪNG', e.message.slice(0, 400)); }
  finally {
    await br.close();
    console.log(`\n${dat} đạt / ${truot} trượt\nDỌN DỮ LIỆU THỬ:`);
    const con = await don(tk);
    if (con) { console.log('CÒN SÓT — kiểm tay'); process.exitCode = 1; }
  }
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });

