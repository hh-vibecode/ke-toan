// Kiểm thử XEM NHƯ (20/10/2026, anh: "nhớ dùng view as, tương tác = quyền đánh giá mới chuẩn"). Xem như TK thật (chỉ xem) — soi menu + nút ở phiếu thật theo từng vai. Không bấm lưu. Dọn phiên xem như + TK tạm sau khi chạy.
// Chạy: node scripts/kiem-thu-xem-nhu.js — Supreme tạm bấm Xem như thuquy / admin.ketoan / ketoan / giamdoc. Lưu ý: chế độ Xem như ẨN nút "Đã nhận tiền" / "Xác nhận" điều chuyển (chỉ xem) → phần đó kiểm ở kiem-thu-luong-day-du.js. Monsieur Claude
const fs = require('fs');
const { chromium } = require(require.resolve('playwright', { paths: [require('child_process').execSync('npm root -g').toString().trim()] }));
const { taoTam, xoaTam } = require('./tk-tam');
const { sql } = require('./sql');
(async () => {
  const sup = await taoTam('tam-xn', 'supreme', []);
  const that = await sql(`select id, ten_dang_nhap, ho_ten from kt_nguoi_dung where ten_dang_nhap in ('thuquy','admin.ketoan','ketoan','giamdoc') order by id`);
  const mau = (await sql(`select
      (select json_agg(d.id) from kt_dieu_chuyen d join kt_tai_khoan t on t.id=d.tk_nhan_id where not d.da_xoa and t.loai='tien_mat' and t.thu_quy_chi and not d.da_xac_nhan) dc_ket,
      (select c.id from kt_chi c join kt_tai_khoan t on t.id=c.tai_khoan_id where not c.da_xoa and c.trang_thai='cho_tt' and t.loai='ngan_hang' and t.thu_quy_chi and c.noi_dung not like 'THỬ%' order by c.id desc limit 1) chi_nh,
      (select c.id from kt_chi c join kt_tai_khoan t on t.id=c.tai_khoan_id where not c.da_xoa and c.trang_thai='cho_tt' and t.loai='tien_mat' and c.noi_dung not like 'THỬ%' order by c.id desc limit 1) chi_ket,
      (select c.id from kt_chi c where not c.da_xoa and c.trang_thai='cho_duyet' and c.noi_dung not like 'THỬ%' order by c.id desc limit 1) chi_cd`))[0];
  console.log('phiếu thật dùng để soi:', JSON.stringify(mau));
  const br = await chromium.launch({ proxy: { server: process.env.HTTPS_PROXY } });
  try {
    for (const a of that) {
      const ctx = await br.newContext({ viewport: { width: 1500, height: 950 }, timezoneId: 'Asia/Ho_Chi_Minh' });
      await ctx.route('https://ke-toan.test/**', rt => rt.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', body: fs.readFileSync(require('path').join(__dirname, '..', 'index.html')) }));
      await ctx.addInitScript(p => { if (!sessionStorage.getItem('kt_phien')) sessionStorage.setItem('kt_phien', p); }, sup.phien);
      const pg = await ctx.newPage(); const hop = []; pg.on('dialog', d => { hop.push(d.message()); d.dismiss(); }); pg.on('pageerror', e => console.log('  LỖI TRANG', e.message));
      await pg.goto('https://ke-toan.test/#tong_quan'); await pg.waitForFunction(() => typeof S !== 'undefined' && S.toi, null, { timeout: 60000 }); await pg.waitForTimeout(1500);
      await pg.evaluate(([i, t]) => xemNhu(i, t), [a.id, a.ho_ten]); await pg.waitForFunction(t => typeof S !== 'undefined' && S.toi && S.toi.ho_ten === t, a.ho_ten, { timeout: 60000 }); await pg.waitForTimeout(2000);
      const out = [];
      out.push('menu: ' + await pg.evaluate(() => Object.keys(PAGES).filter(p => coXem(p) && !/^cd_/.test(p)).join(', ')));
      const vao = async h => { await pg.evaluate(h => { try { closeModal(); } catch (_) {} S.cache = {}; go(h); }, h); await pg.waitForTimeout(500);
        await pg.waitForFunction(() => !/Đang tải|Đang tính/.test((document.querySelector('#page') || {}).innerText || 'x'), null, { timeout: 60000 }).catch(() => {}); await pg.waitForTimeout(1200);
        return pg.evaluate(() => { const t = (document.querySelector('#page') || {}).innerText || ''; return /chưa được cấp quyền|lỗi/i.test(t.slice(0, 300)) ? 'LỖI/CHẶN: ' + t.slice(0, 120).replace(/\s+/g, ' ') : 'mở được'; }); };
      out.push('Sổ quỹ: ' + await vao('dong_tien'));
      out.push('Điều chuyển: ' + await vao('dieu_chuyen'));
      for (const d of mau.dc_ket || []) out.push(`  điều chuyển vào két #${d}: ` + await pg.evaluate(d => { const nn = document.querySelector(`[onclick*="tqNhan('dieu_chuyen',${d})"]`), xn = document.querySelector(`[onclick*="xacNhanDC(${d})"]`);
        const co = (S.cache.dc || []).some(x => x.id === d); return !co ? 'không thấy trong kỳ đang xem' : nn ? 'CÓ nút "Đã nhận tiền"' : xn ? 'CÓ nút "Xác nhận"' : 'không có nút xác nhận'; }, d));
      out.push('Phiếu chi: ' + await vao('chi'));
      const nutPhieu = async ma => { if (!ma) return 'không có phiếu mẫu'; const co = await pg.evaluate(ma => { const x = (S.cache.chi || []).find(c => c.id === ma); if (x) xemChi(ma); return !!x; }, ma);
        if (!co) return 'không thấy phiếu (ngoài kỳ / không có quyền)'; await pg.waitForTimeout(1500);
        const b = await pg.evaluate(() => [...document.querySelectorAll('#modal button')].filter(b => b.offsetParent).map(b => b.textContent.trim()).filter(t => /Xác nhận|Từ chối|Đã chi|lập lệnh|duyệt lệnh|Lùi|Huỷ|Mở lại|Chỉnh sửa|Xoá/.test(t)));
        await pg.evaluate(() => { try { closeModal(); } catch (_) {} }); return b.join(' | ') || 'không có nút thao tác'; };
      out.push('  phiếu chờ chi TK ngân hàng #' + mau.chi_nh + ': ' + await nutPhieu(mau.chi_nh));
      out.push('  phiếu chờ chi tiền mặt #' + mau.chi_ket + ': ' + await nutPhieu(mau.chi_ket));
      out.push('  phiếu chờ kiểm #' + mau.chi_cd + ': ' + await nutPhieu(mau.chi_cd));
      out.push('  form tạo phiếu chi có "Đã thanh toán luôn": ' + await pg.evaluate(async () => { formChi(); await new Promise(r => setTimeout(r, 500)); const c = !!document.querySelector('#modal [name=tt_luon]'); closeModal(); return c ? 'CÓ' : 'không'; }));
      out.push('Phân quyền (Hệ thống): ' + (await pg.evaluate(() => coXem('cd_phan_quyen')) ? 'xem được' : 'không'));
      console.log(`\n=== Xem như ${a.ten_dang_nhap} (${a.ho_ten}) ===\n` + out.join('\n') + (hop.length ? '\n  hộp thoại: ' + hop.join(' / ') : ''));
      await pg.evaluate(() => thoatXemNhu()).catch(() => {}); await ctx.close();
    }
  } finally {
    await br.close();
    await sql(`delete from kt_phien where xem_boi = ${sup.id}; delete from kt_nhat_ky where nguoi = 'THỬ NGHIỆM tam-xn';`);
    await xoaTam(sup.ten);
    console.log('\ndọn:', JSON.stringify(await sql(`select (select count(*) from kt_phien where xem_boi = ${sup.id}) phien_xem_nhu, (select count(*) from kt_nguoi_dung where ten_dang_nhap like 'tam-%') tk_tam, (select count(*) from kt_nhat_ky where nguoi like '%tam-%') nhat_ky`)));
  }
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
