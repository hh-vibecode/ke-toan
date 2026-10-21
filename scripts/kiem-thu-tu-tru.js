// Kiểm thử KHOẢN TÀI KHOẢN TỰ TRỪ + SỬA NGÀY THANH TOÁN trên trình duyệt thật (21/10/2026). Khung chép từ kiem-thu-luong-day-du.js (20/10/2026, anh: "test tạo cẩn thận đầy đủ phiếu, lưu bước đến cùng, đảm bảo mọi thứ chạy" + "chạy xong phải clear hết dữ liệu test").
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
const TAG = 'THỬ HỆ THỐNG E2E TT' + Date.now().toString(36);
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
  const that = Object.fromEntries((await sql(`select ten_dang_nhap, quyen from kt_nguoi_dung where ten_dang_nhap in ('thuquy','admin.ketoan')`)).map(x => [x.ten_dang_nhap, x.quyen]));
  const id = (await sql(`select (select id from kt_tai_khoan where hoat_dong and loai='tien_mat' and thu_quy_chi limit 1) ket,
      (select id from kt_tai_khoan where hoat_dong and loai='tien_mat' and not coalesce(thu_quy_chi,false) limit 1) quay,
      (select id from kt_tai_khoan where hoat_dong and loai='ngan_hang' and thu_quy_chi order by id limit 1) nh,
      (select id from kt_tai_khoan where hoat_dong and loai='ngan_hang' and not coalesce(thu_quy_chi,false) order by id limit 1) cn,
      (select id from kt_loai where nhom='chi' and hoat_dong order by id limit 1) lc, (select id from kt_loai where nhom='thu' and hoat_dong order by id limit 1) lt`))[0];
  const tk = {}, br = await chromium.launch({ proxy: { server: process.env.HTTPS_PROXY } }), html = fs.readFileSync(path.join(__dirname, '..', 'index.html'));
  const trang = {};
  try {
    for (const [k, vt, q] of [['nv', 'nhan_vien', ['chi_de_nghi']], ['adm', 'admin', ['*']], ['gd', 'admin', ['chi_gd']], ['tq', 'nhan_vien', [...that.thuquy, 'dong_tien']], ['akt', 'nhan_vien', that['admin.ketoan']]])
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

    const hom = new Date(Date.now() + 7 * 36e5).toISOString().slice(0, 10), homQua = new Date(Date.now() + 7 * 36e5 - 864e5).toISOString().slice(0, 10);
    const thieuUNC = async ma => (await db1(`select kt_thieu_unc(c) t from kt_chi c where id = ${ma}`)).t;
    const coNut = async (pg, re) => (await Promise.all((await pg.$$('#modal button')).map(x => x.textContent()))).map(t => t.trim()).some(t => new RegExp(re).test(t));
    // T1 — admin kế toán tạo khoản tự trừ phí vận chuyển
    console.log('\nT1 — "+ Khoản tự trừ" (admin kế toán)');
    pg = await mo('akt'); pg.hop = [];
    kq(!!(await pg.$('button[onclick="formTuTru()"]')), '[admin kế toán] có nút "+ Khoản tự trừ"');
    await pg.evaluate(() => formTuTru()); await pg.waitForTimeout(600);
    await chon(pg, 'kieu', 'van_chuyen'); await pg.evaluate(() => tuTruKieu());
    for (const [n, x] of Object.entries({ tai_khoan_id: id.nh, ngay: hom, so_tien: '52.500', thu_huong_ten: 'THỬ HỆ THỐNG Nhất Tín', noi_dung: TAG + ' T1 phi van chuyen', dv_cp: 2 })) await chon(pg, n, x);
    const loaiTuDong = await pg.evaluate(() => { const e = document.querySelector('#modal [name=loai_id]'); return e.options[e.selectedIndex].text; });
    kq(/Logistics/i.test(loaiTuDong), '[admin kế toán] chọn "Phí vận chuyển" → loại chi tự gợi ý Logistics', loaiTuDong);
    await (await pg.$('#modal .ct input[type=file]')).setInputFiles(ANH); await pg.waitForTimeout(400);
    await pg.evaluate(() => luuTuTru()); await pg.waitForTimeout(2500);
    const r1 = await db1(`select id, trang_thai, tu_tru, nguon, ngay_tt, loai_id, phan_bo from kt_chi where noi_dung = ${lit(TAG + ' T1 phi van chuyen')}`);
    kq(r1.trang_thai === 'da_tt' && r1.tu_tru, '[admin kế toán] ghi nhận → Đã thanh toán ngay + cờ tự trừ', JSON.stringify({ tt: r1.trang_thai, tu_tru: r1.tu_tru, nguon: r1.nguon, pb: r1.phan_bo }) + (pg.hop.length ? ' · ' + pg.hop.join(' / ') : ''));
    if (r1.id) { kq(await thieuUNC(r1.id) === false, 'khoản tự trừ KHÔNG bị nhắc "Thiếu ảnh giao dịch"'); kq(await choCT('chi', r1.id, false), 'chứng từ đính kèm (bảng đối soát) đã lên kho'); }
    // T2 — thủ quỹ không có nút
    pg = await mo('tq'); kq(!(await pg.$('button[onclick="formTuTru()"]')), '[thủ quỹ] không có nút "+ Khoản tự trừ"');
    // T3 — phiếu chưa chi (như phiếu đồng bộ từ sheet đề nghị) → đánh dấu tự trừ, ghi luôn Đã thanh toán
    console.log('\nT3 — phiếu chưa chi → "Tài khoản tự trừ"');
    const c3 = await taoDeNghi('T3 sheet', 5500);
    pg = await moPhieu('tq', c3).catch(() => null); if (pg) kq(!(await coNut(pg, '^Tài khoản tự trừ$')), '[thủ quỹ] không có nút "Tài khoản tự trừ" trên phiếu chưa chi');
    pg = await moPhieu('akt', c3); pg.hop = [];
    kq(await coNut(pg, '^Tài khoản tự trừ$'), '[admin kế toán, có "tự chi không cần duyệt"] thấy nút "Tài khoản tự trừ" trên phiếu chờ xác nhận');
    await nut(pg, '^Tài khoản tự trừ$'); await pg.waitForTimeout(600);
    await pg.evaluate(([tk, lc, ng]) => { const f = document.querySelector('#ftu'); f.querySelector('[name=tai_khoan_id]').value = tk; const l = f.querySelector('[name=loai_id]'); if (l) l.value = lc; f.querySelector('[name=ngay]').value = ng; }, [String(id.nh), String(id.lc), homQua]);
    await nut(pg, '^Ghi nhận$'); await pg.waitForTimeout(2000);
    const r3 = await db1(`select trang_thai, tu_tru, ngay_tt::text n, tai_khoan_id tk from kt_chi where id = ${c3}`);
    kq(r3.trang_thai === 'da_tt' && r3.tu_tru && r3.n === homQua && r3.tk === id.nh, '[admin kế toán] → Đã thanh toán, ngày = ngày bị trừ, TK bị trừ, không qua duyệt', JSON.stringify(r3) + (pg.hop.length ? ' · ' + pg.hop.join(' / ') : ''));
    // T4 — phiếu đã chi đang "Thiếu ảnh giao dịch" → đánh dấu → hết nhắc; bỏ đánh dấu → nhắc lại
    console.log('\nT4 — phiếu đã chi thiếu ảnh → đánh dấu / bỏ đánh dấu');
    pg = await mo('akt'); pg.hop = [];
    await pg.evaluate(() => formChi()); await pg.waitForTimeout(600);
    for (const [n, x] of Object.entries({ hach_toan: 'co', noi_dung: TAG + ' T4 da chi', so_tien: '22000', ngay_su_dung: hom, hinh_thuc_nhan: 'ck', thu_huong_ten: 'THỬ HỆ THỐNG', thu_huong_nh: 'Vietcombank', thu_huong_stk: '0011001234567', co_hd_do: 'false' })) await chon(pg, n, x);
    await pg.evaluate(() => { for (const n of ['bo_phan_id', 'hd_ve', 'dv_cp']) { const e = document.querySelector('#modal [name=' + n + ']'); if (e && !e.value) { const o = [...e.options].find(o => o.value); if (o) e.value = o.value; } }
      const t = document.querySelector('#modal [name=tt_luon]'); if (t) { t.checked = true; t.dispatchEvent(new Event('change', { bubbles: true })); } });
    await chon(pg, 'tai_khoan_id', id.nh); await chon(pg, 'loai_id', id.lc); await pg.evaluate(() => luuChi(null)); await pg.waitForTimeout(2500);
    const c4 = (await db1(`select id from kt_chi where noi_dung = ${lit(TAG + ' T4 da chi')}`)).id;
    kq(c4 && await thieuUNC(c4) === true, 'phiếu đã chi không ảnh → đang bị nhắc "Thiếu ảnh giao dịch"');
    pg = await moPhieu('akt', c4); pg.hop = []; await nut(pg, '^Tài khoản tự trừ$'); await pg.waitForTimeout(2000);
    kq(await thieuUNC(c4) === false, '[admin kế toán] bấm "Tài khoản tự trừ" → hết nhắc thiếu ảnh', pg.hop.join(' / '));
    pg = await moPhieu('akt', c4); pg.hop = []; await nut(pg, '^Bỏ tự trừ$'); await pg.waitForTimeout(2000);
    kq(await thieuUNC(c4) === true && (await db1(`select trang_thai from kt_chi where id=${c4}`)).trang_thai === 'da_tt', '[admin kế toán] "Bỏ tự trừ" → nhắc lại, phiếu vẫn Đã thanh toán', pg.hop.join(' / '));
    // T5 — sửa ngày thanh toán phiếu đã chi (câu hỏi của Trang)
    console.log('\nT5 — sửa ngày thanh toán phiếu đã chi');
    pg = await moPhieu('akt', c4); pg.hop = [];
    const o5 = await pg.$('#pc-ngay-tt'); kq(!!o5, '[admin kế toán] có ô sửa Ngày thanh toán trên phiếu đã chi');
    if (o5) { await o5.fill(homQua); await nut(pg, '^Lưu$'); await pg.waitForTimeout(2000); }
    const r5 = await db1(`select ngay_tt::text n from kt_chi where id = ${c4}`);
    kq(r5.n === homQua, '[admin kế toán] đổi ngày → Lưu → ngày thanh toán đã đổi', r5.n + (pg.hop.length ? ' · ' + pg.hop.join(' / ') : ''));
    kq(!!(await db1(`select 1 x from kt_nhat_ky where bang='kt_chi' and dong_id=${c4} and hanh_dong='doi_ngay_tt'`)).x, 'nhật ký ghi lần đổi ngày');
    pg = await moPhieu('tq', c4).catch(() => null);
    if (pg) kq(!(await pg.$('#pc-ngay-tt')), '[thủ quỹ] không có ô sửa ngày (không có quyền sửa Chi)'); else kq(true, '[thủ quỹ] không thấy phiếu đã chi này trong danh sách (đúng phạm vi thủ quỹ)');
  } catch (e) { kq(false, 'DỪNG GIỮA CHỪNG', e.message.slice(0, 400)); }
  finally {
    await br.close();
    console.log(`\n${dat} đạt / ${truot} trượt\nDỌN DỮ LIỆU THỬ:`);
    const con = await don(tk);
    if (con) { console.log('CÒN SÓT — kiểm tay'); process.exitCode = 1; }
  }
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
