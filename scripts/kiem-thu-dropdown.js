// Kiểm thử THẬT 24/10/2026 — bảng chọn danh mục (dropdown kiểu KiotViet): tìm · + Tạo mới · ✏ sửa. Dùng chung khung với kiem-thu-24-10.js.
// (khung gốc) (Mac: node + Chrome; cần kt-keys.local.txt có SUPABASE_ACCESS_TOKEN + ANON_KEY): TK tạm kế toán + giám đốc, bấm trên giao diện → kiểm CSDL → dọn sạch.
// Phủ: mục con lúc duyệt, Tách phiếu, Báo lỗi (ảnh + chuông + tab Log), menu Báo lỗi, xoá phiếu thu Kiot, ô cha/con gộp + ✏ thêm mục con. Chạy: node scripts/kiem-thu-24-10.js — Monsieur Claude
const fs = require('fs'), path = require('path'), os = require('os'), { spawn } = require('child_process');
const REPO = path.join(__dirname, '..');
process.chdir(REPO);
const { taoTam, xoaTam } = require(REPO + '/scripts/tk-tam');
const { sql } = require(REPO + '/scripts/sql');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const ngu = ms => new Promise(r => setTimeout(r, ms));
const TAG = 'THỬ HỆ THỐNG E2E ' + Date.now().toString(36);
let dat = 0, truot = 0; const kq = (ok, ten, them = '') => { ok ? dat++ : truot++; console.log((ok ? 'ĐẠT   ' : 'TRƯỢT ') + ten + (them ? ' — ' + them : '')); return ok; };
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'e2e-out-')); 
// ảnh PNG nhỏ để thử tải lên
const zlib = require('zlib'); const crc = b => { let c = ~0; for (const x of b) { c ^= x; for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xEDB88320 : c >>> 1; } return ~c >>> 0; };
const ch = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const c = Buffer.alloc(4); c.writeUInt32BE(crc(Buffer.concat([Buffer.from(t), d]))); return Buffer.concat([l, Buffer.from(t), d, c]); };
const PNG = (() => { const w = 40, h = 30, ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 2;
  const raw = Buffer.concat(Array.from({ length: h }, () => Buffer.concat([Buffer.from([0]), Buffer.alloc(w * 3, 120)])));
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), ch('IHDR', ih), ch('IDAT', zlib.deflateSync(raw)), ch('IEND', Buffer.alloc(0))]).toString('base64'); })();
const ids = { chi: [], thu: [], bl: [], loai: [] };

async function trinhDuyet(phien, ten) {
  const prof = fs.mkdtempSync(path.join(os.tmpdir(), 'e2e-')); const port = 9400 + Math.floor(Math.random() * 300);
  const p = spawn(CHROME, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + prof, '--window-size=1440,900', 'about:blank'], { stdio: 'ignore' });
  let ws; for (let i = 0; i < 40 && !ws; i++) { try { const j = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); const pg = j.find(x => x.type === 'page'); if (pg) ws = pg.webSocketDebuggerUrl; } catch (e) {} await ngu(250); }
  const sock = new WebSocket(ws); await new Promise(r => sock.onopen = r);
  let n = 0; const cho = {}, loi = [];
  sock.onmessage = e => { const m = JSON.parse(e.data); if (m.id && cho[m.id]) { cho[m.id](m); delete cho[m.id]; }
    if (m.method === 'Runtime.exceptionThrown') loi.push(m.params.exceptionDetails.exception?.description?.split('\n')[0]); };
  const goi = (method, params = {}) => new Promise(r => { const id = ++n; cho[id] = r; sock.send(JSON.stringify({ id, method, params })); });
  const ev = async x => { const r = await goi('Runtime.evaluate', { expression: x, awaitPromise: true, returnByValue: true }); if (r.result.exceptionDetails) throw new Error(r.result.exceptionDetails.exception?.description || 'eval'); return r.result.result.value; };
  await goi('Runtime.enable'); await goi('Page.enable');
  await goi('Page.navigate', { url: require('url').pathToFileURL(REPO + '/index.html').href }); await ngu(1500);
  await ev(`sessionStorage.setItem('kt_phien',${JSON.stringify(phien)});1`);
  await goi('Page.navigate', { url: require('url').pathToFileURL(REPO + '/index.html').href });
  for (let i = 0; i < 60; i++) { await ngu(500); try { if (await ev('!!(window.S&&S.toi&&S.dm)')) break; } catch (e) {} }
  await ev(`window.confirm=()=>true;window.alert=m=>{window.__alert=(window.__alert||[]).concat(String(m))};window.prompt=()=>'ghi chú thử';1`);
  const chup = async f => { const s = await goi('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(path.join(OUT, ten + '-' + f + '.png'), Buffer.from(s.result.data, 'base64')); };
  return { ev, chup, loi, dong: () => { try { sock.close(); p.kill(); } catch (e) {} } };
}
const doi = async (b, expr, ms = 15000) => { for (let t = 0; t < ms; t += 300) { try { if (await b.ev(expr)) return true; } catch (e) {} await ngu(300); } return false; };

(async () => {
  let kt, nv, B, N; const tao = { loai: [], tk: [] };
  const mo = async (b, sel) => { await b.ev(`(()=>{const s=document.querySelector(${JSON.stringify(sel)});s.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));return 1})()`); await ngu(250); };
  const pn = b => b.ev(`(()=>{const p=document.querySelector('#dd-pn');if(!p)return null;return {ten:p.querySelector('.dd-h b').textContent,tao:!!p.querySelector('.dd-h .m-link'),dong:p.querySelectorAll('.dd-i').length,sua:p.querySelectorAll('.dd-sua').length}})()`);
  try {
    kt = await taoTam('tam-kt', 'admin', ['*'], 'THỬ HỆ THỐNG Kế toán');
    nv = await taoTam('tam-nv', 'nhan_vien', ['chi_de_nghi'], 'THỬ HỆ THỐNG Nhân viên');
    const c = (await sql(`insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, noi_dung, so_tien, phan_bo, trang_thai, nguon, tao_boi, loai_id, ngay_su_dung, co_hd_do, chung_tu, bo_phan_id)
      values (current_date, 'THỬ HỆ THỐNG Nhân viên', '${TAG} dropdown', 5000000, '[{"don_vi_id":2,"so_tien":5000000}]', 'cho_duyet', 'app', 'THỬ HỆ THỐNG Nhân viên', 64, current_date, false, '{https://example.com/thu}',
      (select id from kt_don_vi where la_bo_phan and hoat_dong limit 1)) returning id`))[0].id;
    ids.chi.push(c);
    B = await trinhDuyet(kt.phien, 'kt');
    await B.ev(`S.f.chi_q='${TAG}';setKy('nam',true);go('chi');1`); await doi(B, `(S.cache.chi||[]).some(x=>x.id===${c})`);
    await B.ev(`xemChi(${c});1`); await ngu(700);
    // 1. ô Loại chi
    await mo(B, '#pc-loai'); let p = await pn(B);
    kq(p && p.ten === 'Loại chi' && p.tao && p.dong > 5 && p.sua > 5, 'Ô Loại chi mở bảng chọn: tiêu đề + Tạo mới + ✏ từng dòng', JSON.stringify(p));
    await B.chup('dd-loai');
    await B.ev(`(()=>{const t=document.querySelector('#dd-pn .dd-tim');t.value='nhan su';t.dispatchEvent(new Event('input'));return 1})()`); await ngu(150);
    const loc = await B.ev(`[...document.querySelectorAll('#dd-pn .dd-i span')].map(x=>x.textContent)`);
    kq(loc.length >= 1 && loc.every(t => /nhân sự/i.test(t)), 'Tìm kiếm không dấu "nhan su" lọc đúng', JSON.stringify(loc));
    await B.ev(`ddChon('85');1`); await ngu(300);
    kq(await B.ev(`document.querySelector('#pc-loai').value==='85'&&document.querySelector('#pc-con-w').style.display!=='none'`), 'Bấm dòng → chọn nhóm 5, ô mục con cập nhật theo');
    // 2. ô Mục con: gõ tên chưa có → "+ Thêm" (kiểu app MKT)
    await mo(B, '#pc-con'); p = await pn(B);
    kq(p && p.ten === 'Mục con', 'Ô Mục con mở bảng chọn "Mục con"', JSON.stringify(p));
    kq(await B.ev(`document.querySelector('#dd-pn .dd-tim').placeholder`) === 'Chọn hoặc thêm mới', 'Ô tìm là "Chọn hoặc thêm mới"');
    await B.ev(`(()=>{const t=document.querySelector('#dd-pn .dd-tim');t.value='${TAG} mục con';t.dispatchEvent(new Event('input'));return 1})()`); await ngu(150);
    kq(await B.ev(`!!document.querySelector('#dd-pn .dd-them')&&document.querySelector('#dd-pn .dd-them').textContent.includes('Thêm')`), 'Gõ tên chưa có → hiện dòng "+ Thêm “…”"');
    await B.chup('dd-them');
    await B.ev(`document.querySelector('#dd-pn .dd-them').click();1`); await ngu(2500);
    let l = (await sql(`select id, ten, ma, cha_id, nhom, nhom_bc from kt_loai where ten like '${TAG}%'`))[0]; if (l) tao.loai.push(l.id);
    kq(l && l.cha_id === 85 && l.nhom === 'chi' && /^5\.\d+$/.test(l.ma || '') && l.nhom_bc, '+ Thêm nhanh: vào nhóm cha 5, mã tự gợi ý, có nhóm báo cáo', l ? JSON.stringify(l) : '');
    kq(l && await B.ev(`document.querySelector('#pc-con').value==='${l && l.id}'`), 'Mục con vừa thêm được chọn sẵn trong ô');
    // 3. ✏ → sửa tên ngay trên dòng, Enter lưu
    if (l) { await mo(B, '#pc-con');
      await B.ev(`(()=>{const r=[...document.querySelectorAll('#dd-pn .dd-i')].find(x=>x.textContent.includes('${TAG}'));r.querySelector('.dd-sua').click();return 1})()`); await ngu(200);
      kq(await B.ev(`!!document.querySelector('#dd-pn .dd-sua-dong input')`), '✏ biến dòng thành ô nhập tại chỗ');
      await B.chup('dd-sua');
      await B.ev(`(()=>{const i=document.querySelector('#dd-pn .dd-sua-dong input');i.value='${TAG} mục con đã sửa';i.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));return 1})()`); await ngu(2500);
      const l2 = (await sql(`select ten, nhom_bc, cha_id, ma from kt_loai where id=${l.id}`))[0];
      kq(/đã sửa$/.test(l2.ten) && l2.nhom_bc === l.nhom_bc && l2.cha_id === 85 && l2.ma === l.ma, 'Enter lưu tên mới, giữ nhóm báo cáo / nhóm cha / mã', JSON.stringify(l2));
      kq(await B.ev(`[...document.querySelector('#pc-con').options].some(o=>o.text.includes('đã sửa'))`), 'Ô chọn hiện tên mới ngay'); }
    await B.ev(`ddDong();1`);
    // 4. ô Tài khoản (xác nhận) + Tạo mới thẻ tín dụng
    await mo(B, '#ftt select[name=tai_khoan_id]'); p = await pn(B);
    kq(p && p.ten === 'Tài khoản' && p.tao, 'Ô Tài khoản đi tiền mở bảng chọn "Tài khoản"', JSON.stringify(p));
    await B.ev(`ddForm();1`); await ngu(200);
    await B.ev(`(()=>{document.querySelector('#dd-pn [name=ten]').value='${TAG} thẻ';document.querySelector('#dd-pn [name=loai]').value='the_tin_dung';return 1})()`); await B.ev(`ddLuu(0)`); await ngu(2500);
    const t = (await sql(`select id, loai, ton_dau, hoat_dong from kt_tai_khoan where ten like '${TAG}%'`))[0]; if (t) tao.tk.push(t.id);
    kq(t && t.loai === 'the_tin_dung' && +t.ton_dau === 0, 'Tạo mới tài khoản thẻ tín dụng từ ô chọn', t ? JSON.stringify(t) : '');
    // 5. ô Bộ phận trong form Chỉnh sửa
    await B.ev(`closeModal();formChi(${c});1`); await ngu(800);
    await mo(B, '#f select[name=bo_phan_id]'); p = await pn(B);
    kq(p && p.ten === 'Bộ phận' && p.tao, 'Form phiếu: ô Bộ phận mở bảng chọn "Bộ phận"', JSON.stringify(p));
    await B.ev(`ddDong();closeModal();1`);
    kq(B.loi.filter(Boolean).length === 0, 'Không lỗi JS (kế toán)', JSON.stringify(B.loi.slice(0, 3)));
    // 6. nhân viên: không có ✏ / Tạo mới
    N = await trinhDuyet(nv.phien, 'nv');
    await N.ev(`formChi(0);1`); await ngu(800);
    const coBP = await N.ev(`!!document.querySelector('#f select[name=bo_phan_id]')`);
    if (coBP) { await mo(N, '#f select[name=bo_phan_id]'); p = await pn(N);
      kq(p && !p.tao && p.sua === 0 && p.dong > 0, 'Nhân viên: bảng chọn có tìm kiếm nhưng không ✏ / Tạo mới', JSON.stringify(p)); }
    else kq(false, 'Nhân viên: form đề nghị có ô Bộ phận');
    kq(N.loi.filter(Boolean).length === 0, 'Không lỗi JS (nhân viên)', JSON.stringify(N.loi.slice(0, 3)));
  } catch (e) { truot++; console.log('LỖI KIỂM THỬ', e.message); }
  finally {
    try { B && B.dong(); N && N.dong(); } catch (e) {}
    const L = a => a.length ? a.join(',') : '0';
    await sql(`delete from kt_nhat_ky where (bang='kt_chi' and dong_id in (${L(ids.chi)})) or (bang='kt_loai' and dong_id in (${L(tao.loai)})) or (bang='kt_tai_khoan' and dong_id in (${L(tao.tk)}));
      delete from kt_thong_bao where bang='chi' and dong_id in (${L(ids.chi)});
      delete from kt_chi where id in (${L(ids.chi)}); delete from kt_loai where id in (${L(tao.loai)}) or ten like '${TAG}%'; delete from kt_tai_khoan where id in (${L(tao.tk)}) or ten like '${TAG}%'`).catch(e => console.log('dọn lỗi', e.message));
    await xoaTam('tam-kt').catch(() => {}); await xoaTam('tam-nv').catch(() => {});
    const con = (await sql(`select (select count(*) from kt_chi where noi_dung like '${TAG}%') chi, (select count(*) from kt_loai where ten like '${TAG}%') loai, (select count(*) from kt_tai_khoan where ten like '${TAG}%') tk, (select count(*) from kt_nguoi_dung where ten_dang_nhap like 'tam-%') tk_tam`))[0];
    console.log('Dọn sạch:', JSON.stringify(con)); console.log(`KẾT QUẢ: ${dat} đạt, ${truot} trượt`);
  }
})();
