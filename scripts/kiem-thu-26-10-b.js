// Kiểm thử 26/10/2026 (kế toán qua anh): (A) Admin up ảnh + bấm Đã chi tiền cho phiếu chi từ TK cá nhân GĐ; (B) ô Mục con: thêm mục mới đúng cấp,
// xoá mục tạo nhầm; (C) tách phiếu đã khớp Kiot. Khung chép từ kiem-thu-nd-ck.js. TK tạm chép quyền + vị trí TK thật; CUỐI CÙNG XOÁ SẠCH.
// Chạy: KT_QR_JS=<qrcode.js> node scripts/kiem-thu-26-10-b.js. Monsieur Claude
const fs = require('fs'), path = require('path');
const { chromium } = require(require.resolve('playwright', { paths: [require('child_process').execSync('npm root -g').toString().trim()] }));
const { taoTam, xoaTam } = require('./tk-tam');
const { sql } = require('./sql');
const { docKhoa } = require('./khoa');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co';
const TAG = 'THỬ HỆ THỐNG E2E K' + Date.now().toString(36);
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
    for (const [k, vt, q] of [['nv', 'nhan_vien', ['chi_de_nghi']], ['adm', VT['admin.ketoan'], that['admin.ketoan']], ['tq', VT.thuquy, [...that.thuquy, 'dong_tien']]])
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
    const nuts = async pg => (await Promise.all((await pg.$$('#modal button')).map(x => x.textContent()))).map(t => t.trim()).filter(Boolean);
    const rpcThu = async (k, fn, a) => { const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: K.ANON_KEY, Authorization: 'Bearer ' + K.ANON_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_phien: tk[k].phien, ...a }) }); return { ok: r.ok, t: (await r.text()).slice(0, 200) }; };

    console.log('\nA — phiếu chi từ TÀI KHOẢN CÁ NHÂN của GĐ: Admin (vai admin.ketoan) up ảnh + bấm Đã chi tiền');
    const a = await taoDeNghi('A ca nhan', 15000);
    await sql(`update kt_chi set trang_thai = 'cho_tt', tai_khoan_id = ${id.cn}, loai_id = ${id.lc} where id = ${a}`);   // dữ liệu thử: GĐ đã xác nhận + chọn TK cá nhân
    pg = await moPhieu('tq', a).catch(() => null);
    if (pg) kq(!(await nuts(pg)).some(t => /Đã chi tiền/.test(t)), '[thủ quỹ] không có nút "Đã chi tiền" cho TK cá nhân'); else kq(true, '[thủ quỹ] không thấy phiếu TK cá nhân (đúng phạm vi)');
    pg = await moPhieu('adm', a); pg.hop = [];
    const oUnc = await pg.$('#modal .ct[data-loc="unc"] input[type=file]');
    kq(!!oUnc && (await nuts(pg)).some(t => /Đã chi tiền/.test(t)), '[admin kế toán] thấy ô up ảnh giao dịch + nút "Đã chi tiền"', (await nuts(pg)).filter(t => /chi|lệnh|Lưu/i.test(t)).join(' | '));
    if (oUnc) { await oUnc.setInputFiles(ANH); kq(await choCT('chi', a, true), '[admin kế toán] up ảnh giao dịch lên kho'); }
    await pg.evaluate(id => xemChi(id), a); await pg.waitForTimeout(1200); await nut(pg, 'Đã chi tiền');
    let s = await trangThai(a); kq(s.trang_thai === 'da_tt', '[admin kế toán] bấm "Đã chi tiền" → Đã thanh toán', s.trang_thai + (pg.hop.length ? ' · ' + pg.hop.join(' / ') : ''));

    console.log('\nB — ô Mục con: thêm mục mới đúng cấp, xoá mục tạo nhầm');
    const b = await taoDeNghi('B muc con', 9000);
    pg = await moPhieu('adm', b); pg.hop = [];
    await pg.evaluate(() => { pcHT3('co'); const l = document.querySelector('#pc-loai'); l.value = '85'; l.dispatchEvent(new Event('change', { bubbles: true })); pcCon(); });
    await pg.waitForTimeout(300);
    const moDD = () => pg.evaluate(() => document.querySelector('#pc-con').dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true })));
    await moDD(); await pg.waitForSelector('#dd-pn .dd-tim');
    const TEN = TAG + ' muc';
    await pg.fill('#dd-pn .dd-tim', TEN); await pg.waitForTimeout(200); await pg.click('#dd-pn .dd-them'); await pg.waitForTimeout(2500);
    const moi = await db1(`select id, ma, cha_id from kt_loai where ten = ${lit(TEN)}`);
    kq(moi.id && moi.cha_id === 85, 'tạo mục con mới dưới "5 Chi phí marketing" (CSDL)', JSON.stringify(moi) + (pg.hop.length ? ' · ' + pg.hop.join(' / ') : ''));
    const thut = await pg.evaluate(id => { const o = [...document.querySelectorAll('#pc-con option')], f = v => { const x = o.find(x => x.value === String(v)); return x ? (/^[　 ]*/.exec(x.text) || [''])[0].length : -1; };
      return { moi: f(id), ngang: f(93), sau: (o.find(x => x.value === String(id)) || {}).previousElementSibling?.value }; }, moi.id);
    kq(thut.moi === thut.ngang && thut.moi >= 0, 'mục mới thụt ngang hàng 5.3 (không còn trông như mục con của 5.3)', JSON.stringify(thut));
    await moDD(); await pg.waitForSelector('#dd-pn .dd-tim');
    await pg.evaluate(id => { const r = [...document.querySelectorAll('#dd-pn .dd-i')].find(x => /muc$/.test(x.textContent.trim().replace(/✏$/, '').trim())); r.querySelector('.dd-sua').click(); }, moi.id);
    await pg.waitForTimeout(300);
    kq(!!(await pg.$('#dd-pn .dd-xoa')), 'bấm ✏ → có nút xoá');
    await pg.screenshot({ path: path.join(require('os').tmpdir(), 'kt-dd-xoa.png'), clip: await (await pg.$('#dd-pn')).boundingBox() });
    await pg.click('#dd-pn .dd-xoa'); await pg.waitForTimeout(2500);
    kq(!(await db1(`select id from kt_loai where id = ${moi.id}`)).id && !(await pg.$(`#pc-con option[value="${moi.id}"]`)), 'xoá → mất khỏi CSDL và khỏi ô chọn', pg.hop.join(' / '));
    const dung = (await db1(`select loai_id id from kt_chi c where loai_id is not null and not exists (select 1 from kt_loai l where l.cha_id = c.loai_id) limit 1`)).id;
    const rx = await rpcThu('adm', 'kt_xoa_loai', { p_id: dung });
    kq(!rx.ok && !!(await db1(`select id from kt_loai where id = ${dung}`)).id, 'mục đã dùng ở phiếu → máy chủ chặn xoá, mục còn nguyên', rx.t);
    kq(!(await rpcThu('nv', 'kt_xoa_loai', { p_id: dung })).ok, '[nhân viên] không có quyền Danh mục → bị chặn');

    console.log('\nC — tách phiếu đã khớp Kiot');
    const c = await taoDeNghi('C tach', 20000);
    await sql(`update kt_chi set trang_thai = 'da_tt', tai_khoan_id = ${id.nh}, loai_id = ${id.lc}, ngay_tt = current_date, kiot = 'da_tao', kiot_so_quy_id = ${-c}, kiot_ma = 'THU${c}' where id = ${c}`);
    const rt = await rpcThu('adm', 'kt_tach_chi', { p_id: c, p_so_tien: 5000, p_noi_dung: TAG + ' C tach phan', p_loai_id: 66 });
    const nt = await db1(`select id, kiot, kiot_ly_do, kiot_so_quy_id, so_tien::int st, loai_id from kt_chi where noi_dung = ${lit(TAG + ' C tach phan')}`), gc = await db1(`select so_tien::int st, kiot, kiot_so_quy_id from kt_chi where id = ${c}`);
    kq(rt.ok && nt.st === 5000 && gc.st === 15000 && +gc.kiot_so_quy_id === -c, 'tách 5.000 sang phiếu mới (loại 1.2 Quỹ hoa hồng), phiếu gốc còn 15.000 + giữ liên kết Kiot', rt.ok ? JSON.stringify({ moi: nt, goc: gc }) : rt.t);
    kq(nt.kiot === 'khong_tao' && /phiếu Kiot ghi ở phiếu gốc/.test(nt.kiot_ly_do || ''), 'phiếu tách: "không cần phiếu Kiot" (không bị kéo Kiot ghép nhầm)', nt.kiot + ' · ' + nt.kiot_ly_do);
  } catch (e) { kq(false, 'DỪNG GIỮA CHỪNG', e.message.slice(0, 400)); }
  finally {
    await br.close();
    console.log(`\n${dat} đạt / ${truot} trượt\nDỌN DỮ LIỆU THỬ:`);
    await sql(`delete from kt_nhat_ky where bang = 'kt_loai' and du_lieu::text like ${lit('%' + TAG + '%')}; delete from kt_loai where ten like ${lit(TAG + '%')}`);
    const con = await don(tk) + (await sql(`select count(*)::int n from kt_loai where ten like ${lit(TAG + '%')}`))[0].n;
    if (con) { console.log('CÒN SÓT — kiểm tay'); process.exitCode = 1; }
  }
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });


