// Kiểm thử THẬT 24/10/2026 (Mac: node + Chrome; cần kt-keys.local.txt có SUPABASE_ACCESS_TOKEN + ANON_KEY): TK tạm kế toán + giám đốc, bấm trên giao diện → kiểm CSDL → dọn sạch.
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
  let kt, gd, B, G;
  try {
    kt = await taoTam('tam-kt', 'admin', ['*'], 'THỬ HỆ THỐNG Kế toán');
    gd = await taoTam('tam-gd', 'admin', ['*', 'chi_gd'], 'THỬ HỆ THỐNG Giám đốc');
    // dữ liệu thử: 1 phiếu chi chờ xác nhận (lương HT) + 1 phiếu thu Kiot
    const tk = (await sql(`select id from kt_tai_khoan where ten like 'VCB CTY - 1042906599%'`))[0].id;
    const c = (await sql(`insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, noi_dung, so_tien, phan_bo, trang_thai, nguon, tao_boi, loai_id, ngay_su_dung, co_hd_do, chung_tu)
      values (current_date, 'THỬ HỆ THỐNG', '${TAG} lương + hoa hồng', 10000000, '[{"don_vi_id":2,"so_tien":6000000},{"don_vi_id":3,"so_tien":4000000}]', 'cho_duyet', 'app', 'THỬ HỆ THỐNG', 64, current_date, false, '{https://example.com/thu}') returning id`))[0].id;
    ids.chi.push(c);
    const t = (await sql(`insert into kt_thu (ngay, noi_dung, so_tien, tai_khoan_id, loai_id, trang_thai, nguon, ma_nguon, tao_boi) values (current_date, '${TAG} thu Kiot · Kiot TNHTEST', 123456, ${tk}, 4, 'da_duyet', 'kiot', 'kiot:e2e-${Date.now()}', 'Kiot (tự kéo)') returning id`))[0].id;
    ids.thu.push(t);
    console.log('Dữ liệu thử: phiếu chi #' + c + ', phiếu thu #' + t);

    // ── KẾ TOÁN
    B = await trinhDuyet(kt.phien, 'kt');
    kq(await B.ev('S.toi.ho_ten'), 'Đăng nhập tài khoản tạm kế toán', await B.ev('S.toi.ho_ten'));
    await B.ev(`S.f.chi_q='${TAG}';setKy('nam',true);go('chi');1`);
    kq(await doi(B, `(S.cache.chi||[]).some(x=>x.id===${c})`), 'Trang Phiếu chi tải phiếu thử');
    // 1. khung Hạch toán: chọn mục con 1.2 rồi Lưu
    await B.ev(`xemChi(${c});1`); await ngu(800);
    const coCon = await B.ev(`(()=>{const w=document.querySelector('#pc-con-w');return !!w&&w.style.display!=='none'})()`);
    kq(coCon, 'Khung Hạch toán có ô mục con cạnh Loại chi');
    await B.chup('hach-toan');
    await B.ev(`(()=>{const c=document.querySelector('#pc-con');c.value='66';return 1})()`);
    await B.ev(`luuPhieu(${c},null)`); await ngu(2500);
    let r = (await sql(`select loai_id, loai_con_id, loai_con_boi from kt_chi where id=${c}`))[0];
    kq(r.loai_id === 64 && r.loai_con_id === 66, 'Lưu khung Hạch toán ghi mục con 1.2', JSON.stringify(r));
    // 2. tách phiếu 3.000.000 sang 1.1
    await B.ev(`S.cache={};render()`); await doi(B, `(S.cache.chi||[]).some(x=>x.id===${c})`);
    await B.ev(`xemChi(${c});1`); await ngu(600);
    kq(await B.ev(`[...document.querySelectorAll('#modal button')].some(b=>b.textContent.trim()==='Tách phiếu')`), 'Cửa sổ phiếu có nút Tách phiếu');
    await B.ev(`tachPhieu(${c});1`); await ngu(300);
    await B.ev(`(()=>{const f=document.querySelector('#ftach');f.querySelector('[name=tien]').value='3.000.000';tachTinh(10000000);f.querySelector('[name=loai]').value='65';return 1})()`);
    kq((await B.ev(`document.querySelector('#tach-con').textContent`)).replace(/\D/g, '') === '7000000', 'Ô "Phiếu gốc còn" tính đúng 7.000.000');
    await B.chup('tach');
    await B.ev(`luuTach(${c})`); await ngu(3000);
    const moi = (await sql(`select id, so_tien, phan_bo, loai_id, loai_con_id, nguon, ma_nguon, trang_thai, ghi_chu from kt_chi where ghi_chu like 'Tách từ PC${String(c).padStart(6, '0')}%' and not da_xoa`));
    const goc = (await sql(`select so_tien, phan_bo, loai_con_id, ghi_chu from kt_chi where id=${c}`))[0];
    if (moi[0]) ids.chi.push(moi[0].id);
    kq(moi.length === 1 && +moi[0].so_tien === 3000000 && +goc.so_tien === 7000000, 'Tách phiếu: mới 3.000.000 + gốc 7.000.000', moi[0] ? '#' + moi[0].id : 'không thấy phiếu mới');
    if (moi[0]) {
      const pbM = moi[0].phan_bo.map(p => +p.so_tien), pbG = goc.phan_bo.map(p => +p.so_tien);
      kq(pbM[0] + pbG[0] === 6000000 && pbM[1] + pbG[1] === 4000000 && pbM[0] === 1800000, 'Phân bổ chia theo tỷ lệ, cộng lại đúng từng đơn vị', JSON.stringify({ moi: pbM, goc: pbG }));
      kq(moi[0].loai_con_id === 65 && goc.loai_con_id === 66, 'Loại chi: phiếu mới 1.1, phiếu gốc giữ 1.2', `${moi[0].loai_con_id}/${goc.loai_con_id}`);
      kq(moi[0].nguon === 'app' && moi[0].ma_nguon === null && moi[0].trang_thai === 'cho_duyet', 'Phiếu mới: nguồn app, không mã nguồn, cùng trạng thái');
      await ngu(800);
      const link = await B.ev(`!!document.querySelector('#modal .pc-drive .m-link')&&document.querySelector('#modal .pc-drive .m-link').textContent`);
      kq(/phiếu gốc PC/.test(link || ''), 'Phiếu tách hiện link "Chứng từ ở phiếu gốc"', link || '');
      await B.chup('phieu-tach');
    }
    // 3. báo lỗi kèm ảnh từ cửa sổ phiếu
    await B.ev(`closeModal();xemChi(${c});1`); await ngu(600);
    kq(await B.ev(`!!document.querySelector('#modal .nut-loi')`), 'Biểu tượng báo lỗi cạnh nút in phiếu');
    await B.ev(`document.querySelector('#modal .nut-loi').click();1`); await ngu(500);
    await B.ev(`(()=>{document.querySelector('#fbl [name=nd]').value='${TAG} báo lỗi kèm ảnh';const b=Uint8Array.from(atob('${PNG}'),c=>c.charCodeAt(0));ctThem('bao_loi',0,[new File([b],'loi.png',{type:'image/png'})]);return 1})()`);
    await ngu(500); await B.chup('bao-loi');
    await B.ev(`document.querySelector('#modal .btn.pri').click();1`);
    let bl; for (let i = 0; i < 30 && !bl; i++) { await ngu(1000); bl = (await sql(`select b.id, (select count(*) from kt_chung_tu k where k.bang='bao_loi' and k.dong_id=b.id and not k.da_xoa) anh, (select count(*) from kt_thong_bao t where t.loai='bao_loi' and t.dong_id=b.id) tb from kt_bao_loi b where b.noi_dung like '${TAG}%'`))[0]; if (bl && !+bl.anh) bl = null; }
    if (!bl) bl = (await sql(`select b.id, (select count(*) from kt_chung_tu k where k.bang='bao_loi' and k.dong_id=b.id) anh, (select count(*) from kt_thong_bao t where t.loai='bao_loi' and t.dong_id=b.id) tb from kt_bao_loi b where b.noi_dung like '${TAG}%'`))[0];
    if (bl) ids.bl.push(bl.id);
    kq(!!bl, 'Báo lỗi lưu vào log', bl ? '#' + bl.id : (await B.ev('JSON.stringify(window.__alert||[])')));
    kq(bl && +bl.anh === 1, 'Ảnh báo lỗi tải lên kho chứng từ', bl ? 'số ảnh ' + bl.anh : '');
    kq(bl && +bl.tb >= 1, 'Báo lỗi vào chuông Supreme', bl ? 'thông báo ' + bl.tb : '');
    // 4. báo lỗi chung từ menu tài khoản
    kq(await B.ev(`[...document.querySelectorAll('.tb-menu-dd .dd-i')].some(d=>/Báo lỗi/.test(d.textContent))`), 'Menu tài khoản có mục Báo lỗi');
    // 5. xoá phiếu thu Kiot
    await B.ev(`S.f.thu_q='${TAG}';go('thu');1`); await doi(B, `(S.cache.thu||[]).some(x=>x.id===${t})`);
    await B.ev(`xemThu(${t});1`); await ngu(500);
    const coXoa = await B.ev(`[...document.querySelectorAll('#modal button')].some(b=>b.textContent.trim()==='Xoá')`);
    kq(coXoa, 'Phiếu thu Kiot có nút Xoá');
    await B.ev(`[...document.querySelectorAll('#modal button')].find(b=>b.textContent.trim()==='Xoá').click();1`); await ngu(2000);
    r = (await sql(`select da_xoa, xoa_tay from kt_thu where id=${t}`))[0];
    kq(r.da_xoa && r.xoa_tay, 'Xoá phiếu thu Kiot: da_xoa + xoa_tay', JSON.stringify(r));
    kq(B.loi.filter(Boolean).length === 0, 'Không lỗi JS (kế toán)', JSON.stringify(B.loi.slice(0, 3)));

    // ── GIÁM ĐỐC: ô cha / con gộp trên bảng, ✏ thêm mục con, tab Báo lỗi
    G = await trinhDuyet(gd.phien, 'gd');
    await G.ev(`S.f.chi_q='${TAG}';setKy('nam',true);go('chi');1`);
    kq(await doi(G, `(S.cache.chi||[]).some(x=>x.id===${c})`), 'GĐ: trang Phiếu chi tải phiếu thử');
    await ngu(800);
    const o = await G.ev(`(()=>{const tr=[...document.querySelectorAll('#chi-bang tr')].find(r=>r.textContent.includes('PC${String(c).padStart(6, '0')}'));if(!tr)return null;const s=tr.querySelector('.ld-cc select');return s?{chon:s.selectedOptions[0].text.trim()}:'khong co o gop'})()`);
    kq(o && o.chon && /1\.2/.test(o.chon), 'GĐ: bảng hiện 1 ô cha/con, đang chọn 1.2', JSON.stringify(o));
    await G.chup('bang');
    // (thêm / sửa mục con: xem scripts/kiem-thu-dropdown.js — bảng chọn danh mục)
    // tab Báo lỗi + đánh dấu đã xử lý
    await G.ev(`S.f.log_tab='loi';S.f.bl_loc='mo';go('cd_nhat_ky');1`); await ngu(2500);
    kq(await G.ev(`document.body.innerText.includes('${TAG} báo lỗi kèm ảnh')`), 'Log hệ thống → tab Báo lỗi hiện báo lỗi');
    await G.chup('log-bao-loi');
    if (bl) { await G.ev(`xuLyLoi(${bl.id},true)`); await ngu(1500); r = (await sql(`select da_xu_ly, xu_ly_boi, xu_ly_ghi from kt_bao_loi where id=${bl.id}`))[0]; kq(r.da_xu_ly && r.xu_ly_ghi === 'ghi chú thử', 'Đánh dấu Đã xử lý + ghi chú', JSON.stringify(r)); }
    kq(G.loi.filter(Boolean).length === 0, 'Không lỗi JS (giám đốc)', JSON.stringify(G.loi.slice(0, 3)));
  } catch (e) { truot++; console.log('LỖI KIỂM THỬ', e.message); }
  finally {
    try { B && B.dong(); G && G.dong(); } catch (e) {}
    // dọn sạch
    const L = a => a.length ? a.join(',') : '0';
    await sql(`delete from kt_nhat_ky where (bang='kt_chi' and dong_id in (${L(ids.chi)})) or (bang='kt_thu' and dong_id in (${L(ids.thu)})) or (bang='kt_loai' and dong_id in (${L(ids.loai)}));
      delete from kt_thong_bao where (loai='bao_loi' and dong_id in (${L(ids.bl)})) or (bang='chi' and dong_id in (${L(ids.chi)}));
      delete from kt_chung_tu where bang='bao_loi' and dong_id in (${L(ids.bl)});
      delete from kt_bao_loi where id in (${L(ids.bl)}) or noi_dung like '${TAG}%';
      delete from kt_chi where id in (${L(ids.chi)}); delete from kt_thu where id in (${L(ids.thu)}); delete from kt_loai where id in (${L(ids.loai)})`).catch(e => console.log('dọn lỗi', e.message));
    await xoaTam('tam-kt').catch(() => {}); await xoaTam('tam-gd').catch(() => {});
    const con = (await sql(`select (select count(*) from kt_chi where noi_dung like '${TAG}%' or ghi_chu like 'Tách từ PC${String(ids.chi[0] || 0).padStart(6, '0')}%') chi, (select count(*) from kt_thu where noi_dung like '${TAG}%') thu, (select count(*) from kt_bao_loi where noi_dung like '${TAG}%') bl, (select count(*) from kt_nguoi_dung where ten_dang_nhap in ('tam-kt','tam-gd')) tk`))[0];
    console.log('Dọn sạch:', JSON.stringify(con));
    console.log(`KẾT QUẢ: ${dat} đạt, ${truot} trượt`);
  }
})();
