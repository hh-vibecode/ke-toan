// Kiểm thử công nợ khách PA3 (28/10/2026): trang Phải thu 4 phần, cột Phân loại, form nhập tay trả 1 phần, gỡ về ghi chú Kiot, nhân viên bị chặn. Dọn sạch. Chạy: node scripts/kiem-thu-cong-no-pa3.js <thư mục ảnh>. Monsieur Claude
const fs = require('fs'), R = '/home/user/ke-toan', OUT = process.argv[2];
const { chromium } = require(require.resolve('playwright', { paths: [require('child_process').execSync('npm root -g').toString().trim()] }));
const { taoTam, xoaTam } = require(R + '/scripts/tk-tam'), { sql } = require(R + '/scripts/sql');
const KH = 1012417313, HD = 1120414863;
let dat = 0, truot = 0; const kq = (ok, t, x = '') => { ok ? dat++ : truot++; console.log((ok ? 'ĐẠT  ' : 'TRƯỢT ') + t + (x ? ' — ' + x : '')); };
(async () => {
  const t = await taoTam('tam-e2e-no', 'admin', []), br = await chromium.launch({ proxy: { server: process.env.HTTPS_PROXY } }), loi = [];
  try {
    if ((await sql(`select count(*)::int n from kt_no_tach where hoa_don_id = ${HD}`))[0].n) throw new Error('HĐ thử đã có phân loại tay — dừng');
    const ctx = await br.newContext({ viewport: { width: 1500, height: 950 } }), html = fs.readFileSync(R + '/index.html');
    await ctx.route('https://ke-toan.test/**', rt => rt.request().url().includes('phien-ban.txt') ? rt.fulfill({ status: 200, body: fs.readFileSync(R + '/phien-ban.txt') }) : rt.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', body: html }));
    await ctx.addInitScript(p => sessionStorage.setItem('kt_phien', p), t.phien);
    const pg = await ctx.newPage(); pg.on('pageerror', e => loi.push(e.message)); pg.on('dialog', d => { loi.push('hộp thoại: ' + d.message()); d.accept(); });
    await pg.goto('https://ke-toan.test/#no_kh'); await pg.waitForFunction(() => typeof S !== 'undefined' && S.toi && S.cache && S.cache.no_kh, null, { timeout: 90000 }); await pg.waitForTimeout(1500);
    const tieu = await pg.evaluate(() => document.querySelector('.m-ch').innerText);
    kq(/Sẽ trả hàng/.test(tieu) && /COD chưa thu hồi/.test(tieu) && /Nợ thật/.test(tieu), 'trang Phải thu: 4 nhãn tổng (nợ thật / COD / chưa lấy hàng / sẽ trả hàng)', tieu.replace(/\s+/g, ' ').slice(0, 200));
    await pg.evaluate(id => xemCongNo('kh', id), KH); await pg.waitForTimeout(3000);
    const ct = await pg.evaluate(() => { const t = [...document.querySelectorAll('.m-st')].find(x => /Nợ theo chứng từ/.test(x.textContent)); const b = t && t.nextElementSibling; return b ? b.innerText : ''; });
    kq(/Phân loại/.test(ct) && /COD/.test(ct), 'khung chi tiết: cột Phân loại hiện COD theo ghi chú', ct.replace(/\s+/g, ' ').slice(0, 260));
    await pg.screenshot({ path: OUT + '/no-ct.png' });
    await pg.evaluate(([h, id]) => formNoTach(h, 'kh', id), [HD, KH]); await pg.waitForTimeout(800);
    const con = await pg.evaluate(h => S.cache.no_ct.dang_no.find(x => x.id === h).con_no, HD);
    await pg.fill('#fnt [name=tra]', '200.000'); await pg.fill('#fnt [name=cod]', String(Math.max(con - 200000, 0))); await pg.fill('#fnt [name=ly_do]', 'THU HE THONG E2E');
    await pg.press('#fnt [name=cod]', 'End'); await pg.waitForTimeout(200);
    kq((await pg.$eval('#nt-that', e => e.textContent)) === '0', 'form: nợ thật tự tính = còn nợ − các phần', await pg.$eval('#nt-that', e => e.textContent));
    await pg.screenshot({ path: OUT + '/no-form.png' });
    await pg.click('#modal .btn.pri'); await pg.waitForTimeout(3500);
    const r = (await sql(`select tra_hang::int, cod::int, tra_luc is not null tl from kt_no_tach where hoa_don_id = ${HD}`))[0] || {};
    kq(r.tra_hang === 200000 && r.tl, 'lưu: sẽ trả hàng 200.000 (trả 1 phần) + COD phần còn lại', JSON.stringify(r));
    await pg.evaluate(id => xemCongNo('kh', id), KH); await pg.waitForTimeout(3000);
    const ct2 = await pg.evaluate(() => { const t = [...document.querySelectorAll('.m-st')].find(x => /Nợ theo chứng từ/.test(x.textContent)); return t.nextElementSibling.innerText; });
    kq(/Sẽ trả hàng/.test(ct2) && /nhập tay/.test(ct2), 'chi tiết hiện "Sẽ trả hàng" + "kế toán nhập tay"');
    const ds = await pg.evaluate(id => (S.cache.no_kh || []).find(x => x.id === id), KH);
    kq(ds && +ds.no_tra_hang === 200000, 'danh sách: khách có no_tra_hang 200.000, nợ thật trừ tương ứng', ds && JSON.stringify({ no: ds.no, cod: ds.no_cod, tra: ds.no_tra_hang, that: ds.no_that }));
    await pg.evaluate(([h, id]) => formNoTach(h, 'kh', id), [HD, KH]); await pg.waitForTimeout(600);
    await pg.evaluate(() => [...document.querySelectorAll('#modal button')].find(b => /Theo ghi chú Kiot/.test(b.textContent)).click()); await pg.waitForTimeout(3000);
    kq(!(await sql(`select count(*)::int n from kt_no_tach where hoa_don_id = ${HD}`))[0].n, '"Theo ghi chú Kiot" → gỡ số tay');
    // nhân viên không quyền Công nợ ghi → máy chủ chặn
    const nv = await taoTam('tam-e2e-nv', 'nhan_vien', ['khach_hang']);
    const { docKhoa } = require(R + '/scripts/khoa'), K = docKhoa();
    const x = await fetch('https://bcrpxfvvjsjpvbksqzls.supabase.co/rest/v1/rpc/kt_luu_no_tach', { method: 'POST', headers: { apikey: K.ANON_KEY, Authorization: 'Bearer ' + K.ANON_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_phien: nv.phien, p_hd: HD, p_tra: 1, p_cod: 0, p_cl: 0, p_ly_do: 'x' }) });
    kq(!x.ok, '[nhân viên chỉ xem Khách hàng] máy chủ chặn lưu', (await x.text()).slice(0, 120)); await xoaTam('tam-e2e-nv');
  } catch (e) { kq(false, 'DỪNG', e.message); }
  finally { await br.close(); await sql(`delete from kt_no_tach where hoa_don_id = ${HD} and ly_do = 'THU HE THONG E2E'; delete from kt_nhat_ky where bang = 'kt_no_tach' and dong_id = ${HD} and nguoi like 'THỬ NGHIỆM tam-e2e%'`); await xoaTam('tam-e2e-no');
    console.log(`${dat} đạt / ${truot} trượt · lỗi JS: ${loi.length ? loi.join(' | ') : 0}`);
    console.log('còn sót:', JSON.stringify(await sql(`select (select count(*) from kt_no_tach where hoa_don_id = ${HD}) tach, (select count(*) from kt_nhat_ky where bang='kt_no_tach' and nguoi like 'THỬ NGHIỆM%') nk, (select count(*) from kt_nguoi_dung where ten_dang_nhap like 'tam-%') tk`))); }
})();
