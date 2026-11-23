// Kiểm 23/11/2026 (VIEC 416): lô đường biển / đường bộ · công nợ forwarder gồm thuế nộp thay · Lập phiếu chi từ chi phí lô (tự nối) · Chốt chi phí · thuế NK theo tờ khai.
// Dữ liệu thử tên "THỬ HỆ THỐNG …" — xoá sạch khi xong (lô, đơn, chi phí, phiếu chi, gắn NCC, chuông, nhật ký, NCC thử, TK tạm). Monsieur Claude
// Chạy: ELECTRON_RUN_AS_NODE=1 Code.exe scripts/kiem-thu-lo-nk-hinh-thuc.js [thư mục ảnh]
const fs = require('fs'), os = require('os'), path = require('path'), { spawn } = require('child_process');
const { taoTam, xoaTam } = require('./tk-tam'); const { sql } = require('./sql'); const { docKhoa } = require('./khoa'); const tatTrinhDuyet = require('./tat-trinh-duyet');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co', ANH = process.argv[2] || os.tmpdir();
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', TK = 'tam-lonk';
const rpc = async (f, b) => { const r = await fetch(`${SB}/rest/v1/rpc/${f}`, { method: 'POST', headers: { apikey: K.ANON_KEY, Authorization: 'Bearer ' + K.ANON_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify(b) }); const t = await r.text(); const j = t ? JSON.parse(t) : null; if (!r.ok) throw new Error(f + ': ' + (j && j.message || t)); return j; };
const ngu = ms => new Promise(r => setTimeout(r, ms));
let dat = 0, hong = 0; const ok = (d, t) => { d ? dat++ : hong++; console.log((d ? 'ĐẠT ' : 'HỎNG') + ' ' + t); };
const loi = async (fn, mau, t) => { try { await fn(); ok(false, t + ' (không bị chặn)'); } catch (e) { ok(mau.test(e.message), t + ' → ' + e.message.slice(0, 90)); } };
const S = { lo: null, vc: null, chi: [] };
async function don() {
  if (S.lo) await sql(`delete from kt_thong_bao where bang = 'lo_nk' and dong_id = ${S.lo};
    delete from kt_nhat_ky where (bang in ('kt_lo_nk_cp','kt_lo_nk_don') and dong_id in (select id from kt_lo_nk_cp where lo_id = ${S.lo} union select id from kt_lo_nk_don where lo_id = ${S.lo}))
      or (bang = 'kt_lo_nk' and dong_id = ${S.lo}) or (bang = 'kt_lo_nk_cp' and hanh_dong = 'noi_chi' and nguoi like 'THỬ HỆ THỐNG%');
    delete from kt_lo_nk_cp where lo_id = ${S.lo}; delete from kt_lo_nk_don where lo_id = ${S.lo}; delete from kt_lo_nk where id = ${S.lo}`);
  const chi = (await sql(`select id from kt_chi where noi_dung like '%THỬ-LONK%'`)).map(r => r.id);
  for (const id of chi) await sql(`delete from kt_ncc_gan where bang = 'chi' and dong_id = ${id}; delete from kt_chung_tu where bang = 'chi' and dong_id = ${id};
    delete from kt_thong_bao where bang = 'chi' and dong_id = ${id}; delete from kt_nhat_ky where bang = 'kt_chi' and dong_id = ${id}; delete from kt_chi_phieu where chi_id = ${id}; delete from kt_chi where id = ${id}`);
  if (S.vc) await sql(`delete from kt_ncc_gan where ncc_id = ${S.vc}; delete from kt_ncc where id = ${S.vc}`);
  await xoaTam(TK);
}
(async () => {
  const T = await taoTam(TK, 'admin', ['*'], 'THỬ HỆ THỐNG Lô NK'), P = { p_phien: T.phien };
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lonk-')); let ed, ws;
  try {
    S.vc = (await sql(`insert into kt_ncc (ma, ten, loai, tao_boi) values ('THU-LONK', 'THỬ HỆ THỐNG Vận chuyển', 'van_chuyen', 'THỬ HỆ THỐNG') returning id`))[0].id;
    const nn = (await sql(`select id from kt_ncc where loai = 'nuoc_ngoai' and not da_xoa order by id limit 1`))[0].id;
    S.lo = await rpc('kt_luu_lo_nk', { ...P, p_dong: { ten: 'THỬ HỆ THỐNG lô đường bộ THỬ-LONK', hinh_thuc: 'bo', dv_vc_id: S.vc, forwarder: 'THỬ HỆ THỐNG Vận chuyển', tien_te: 'VND', cach_pb: 'gia_tri', trang_thai: 'van_chuyen' } });
    await rpc('kt_luu_lo_nk_don', { ...P, p_dong: { lo_id: S.lo, ncc_id: nn, tien_te: 'VND', hang: [{ ma: 'A1', ten: 'Tượng A', sl: 2, gia: 1000000 }, { ma: 'B1', ten: 'Tượng B', sl: 1, gia: 2000000 }] } });
    const c1 = await rpc('kt_luu_lo_nk_cp', { ...P, p_dong: { lo_id: S.lo, loai: 'van_chuyen_qt', so_tien: 300000, tinh_gv: true, noi_dung: 'Cước xe THỬ-LONK' } });
    const c2 = await rpc('kt_luu_lo_nk_cp', { ...P, p_dong: { lo_id: S.lo, loai: 'vat_nk', so_tien: 50000, tinh_gv: false, noi_dung: 'VAT nộp thay THỬ-LONK' } });
    const c3 = await rpc('kt_luu_lo_nk_cp', { ...P, p_dong: { lo_id: S.lo, loai: 'boc_xep', so_tien: 100000, tinh_gv: true, noi_dung: 'Bốc xếp THỬ-LONK', don_vi_nhan: 'Kho bãi khác' } });
    const L = (await rpc('kt_ds_lo_nk', P)).find(x => x.id === S.lo);
    ok(L.hinh_thuc === 'bo', 'lô lưu hình thức Đường bộ');
    ok(+L.phai_tra_vc === 350000, `công nợ đơn vị vận chuyển = cước + VAT nộp thay, không tính khoản trả đơn vị khác (${L.phai_tra_vc})`);
    ok(+L.phi_vc === 300000, 'phí vận chuyển (hiện ở PO) vẫn chỉ cước');
    // ── chốt
    await rpc('kt_lo_nk_chot', { ...P, p_id: S.lo, p_chot: true });
    const tb = await sql(`select count(*)::int n, count(*) filter (where nguoi_dung_id = ${T.id})::int minh from kt_thong_bao where bang = 'lo_nk' and dong_id = ${S.lo}`);
    ok(tb[0].n >= 1 && tb[0].minh === 0, `chốt → chuông cho ${tb[0].n} người có quyền NCC (không gửi chính mình)`);
    await sql(`delete from kt_thong_bao where bang = 'lo_nk' and dong_id = ${S.lo}`);   // xoá ngay để người thật không thấy chuông thử
    await loi(() => rpc('kt_luu_lo_nk_cp', { ...P, p_dong: { lo_id: S.lo, loai: 'khac', so_tien: 1 } }), /chốt/, 'đã chốt: thêm chi phí bị chặn');
    await loi(() => rpc('kt_luu_lo_nk_cp', { ...P, p_dong: { id: c1, lo_id: S.lo, loai: 'van_chuyen_qt', so_tien: 999, tinh_gv: true } }), /chốt/, 'đã chốt: sửa số tiền bị chặn');
    await loi(() => rpc('kt_xoa_lo_nk_cp', { ...P, p_id: c1 }), /chốt/, 'đã chốt: xoá chi phí bị chặn');
    const d1 = (await sql(`select id from kt_lo_nk_don where lo_id = ${S.lo}`))[0].id;
    await loi(() => rpc('kt_xoa_lo_nk_don', { ...P, p_id: d1 }), /chốt/, 'đã chốt: xoá đơn bị chặn');
    const lo0 = (await sql(`select to_jsonb(l) j from kt_lo_nk l where id = ${S.lo}`))[0].j;
    await loi(() => rpc('kt_luu_lo_nk', { ...P, p_dong: { ...lo0, cach_pb: 'so_luong' } }), /chốt/, 'đã chốt: đổi cách chia bị chặn');
    await rpc('kt_luu_lo_nk', { ...P, p_dong: { ...lo0, ma_van_don: 'VD-THU' } }); ok(true, 'đã chốt: sửa mã vận đơn vẫn được');
    await rpc('kt_luu_lo_nk_cp', { ...P, p_dong: { id: c1, lo_id: S.lo, loai: 'van_chuyen_qt', so_tien: 300000, tinh_gv: true, noi_dung: 'Cước xe THỬ-LONK (sửa)' } }); ok(true, 'đã chốt: sửa nội dung chi phí vẫn được');
    await loi(() => rpc('kt_lo_nk_chot', { ...P, p_id: S.lo, p_chot: true }), /đã chốt/, 'chốt lần 2 bị chặn');
    await rpc('kt_lo_nk_chot', { ...P, p_id: S.lo, p_chot: false }); ok((await sql(`select chot_luc from kt_lo_nk where id = ${S.lo}`))[0].chot_luc === null, 'mở chốt');

    // ── trình duyệt: giao diện + Lập phiếu chi (cho ghi thật trên dữ liệu thử)
    const tep = path.join(dir, 'app.html');
    let html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
    html = html.replace('<div id="app"></div>', `<div id="app"></div><script>sessionStorage.setItem("kt_phien",${JSON.stringify(T.phien)});window.__qa=[];
      window.addEventListener('error',e=>window.__qa.push(e.message));window.alert=m=>window.__qa.push('alert '+m);window.confirm=()=>true;</script>`);
    fs.writeFileSync(tep, html);
    const port = 9300 + Math.floor(Math.random() * 500);
    ed = spawn(EDGE, ['--headless=new', '--disable-gpu', `--remote-debugging-port=${port}`, `--user-data-dir=${dir}/ud`, '--window-size=1600,1000', 'about:blank'], { stdio: 'ignore' });
    let list; for (let i = 0; i < 40; i++) { try { list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (list.find(t => t.type === 'page')) break; } catch (e) {} await ngu(300); }
    ws = new WebSocket(list.find(t => t.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
    let n = 0; const cho = new Map(); ws.onmessage = m => { const j = JSON.parse(m.data); if (j.id && cho.has(j.id)) { cho.get(j.id)(j); cho.delete(j.id); } };
    const cdp = (method, params = {}) => new Promise(r => { const id = ++n; cho.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
    const ev = async e => { const r = await cdp('Runtime.evaluate', { expression: e, awaitPromise: true, returnByValue: true }); if (r.result && r.result.exceptionDetails) return 'LỖI ' + JSON.stringify(r.result.exceptionDetails).slice(0, 300); return r.result && r.result.result ? r.result.result.value : undefined; };
    const chup = async f => { const r = await cdp('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(path.join(ANH, f), Buffer.from(r.result.data, 'base64')); };
    await cdp('Page.enable'); await cdp('Runtime.enable');
    await cdp('Page.navigate', { url: 'file:///' + tep.replace(/\\/g, '/') + '#lo_nk' }); await ngu(8000); await ev(`go('lo_nk')`); await ngu(4000);
    await chup('lonk-1-danh-sach.png');
    await ev(`lnkMo(${S.lo},'cp')`); await ngu(2500);
    const cp = await ev(`(()=>{const m=$('#modal');return {tra:[...m.querySelectorAll('th')].some(t=>t.textContent==='Trả cho'),gop:[...m.querySelectorAll('button')].map(b=>b.textContent).find(t=>/Lập 1 phiếu chi/.test(t))||'',tabs:[...m.querySelectorAll('.m-tab')].map(b=>b.textContent),bo:m.textContent.includes('Đường bộ (hàng lẻ)')}})()`);
    ok(cp.tra && /2 khoản chưa trả · 350\.000/.test(cp.gop), 'tab Cước & chi phí: cột Trả cho + nút gộp ' + cp.gop);
    ok(!cp.tabs.some(t => /Kê khai/.test(t)) && cp.bo, 'đường bộ: không có tab Kê khai, Thông tin chung ghi Đường bộ · tabs ' + cp.tabs.join(' | '));
    await chup('lonk-2-chi-phi.png');
    await ev(`S.f.lnk_tab='pb';lnkVe()`); await ngu(800); await chup('lonk-3-phan-bo.png');
    ok(await ev(`[...$('#modal').querySelectorAll('button')].some(b=>/Chốt chi phí/.test(b.textContent))`), 'tab Phân bổ có nút Chốt chi phí');
    await ev(`lnkForm(${S.lo})`); await ngu(1200);
    const fm = await ev(`(()=>{const v=e=>e&&e.getClientRects().length>0;const f=$('#flnk');return {cont:v(f.querySelector('[name=so_cont]').closest('label')),cang:v(f.querySelector('[name=cang_di]').closest('label')),tk:v(f.querySelector('[name=dv_mo_tk]').closest('label')),sec:$('#lnk-sec4').textContent}})()`);
    ok(!fm.cont && !fm.cang && !fm.tk && /^3\./.test(fm.sec), 'form lô đường bộ ẩn container / cảng / tờ khai, mục 3 = Quy đổi');
    await chup('lonk-4-form-bo.png');
    await ev(`$('#flnk [name=hinh_thuc]').value='bien';lnkHTDoi('bien')`); await ngu(400);
    const fm2 = await ev(`(()=>{const f=$('#flnk');return f.querySelector('[name=so_cont]').getClientRects().length>0&&f.querySelector('[name=dv_mo_tk]').getClientRects().length>0&&$('#lnk-sec4').textContent.startsWith('4.')})()`);
    ok(fm2, 'đổi sang Đường biển → hiện lại container / tờ khai, mục 4');
    await chup('lonk-5-form-bien.png'); await ev(`dong2()`);
    // Lập 1 phiếu chi cho 2 khoản chưa trả
    await ev(`S.f.lnk_tab='cp';lnkVe()`); await ngu(500); await ev(`lnkLapChi()`); await ngu(1500);
    const f0 = await ev(`(()=>{const f=$('#f');return {nd:f.querySelector('[name=noi_dung]').value,tien:f.querySelector('[name=so_tien]').value,th:f.querySelector('[name=thu_huong_ten]').value}})()`);
    ok(/lô NK-/.test(f0.nd) && f0.tien === '350.000' && f0.th === 'THỬ HỆ THỐNG Vận chuyển', `form Đề nghị chi điền sẵn: "${f0.nd}" · ${f0.tien} · ${f0.th}`);
    await chup('lonk-6-de-nghi-chi.png');
    await ev(`(()=>{const f=$('#f');f.querySelector('[name=noi_dung]').value+=' THỬ-LONK';const b=f.querySelector('[name=bo_phan_id]');b.selectedIndex=1;const h=f.querySelector('[name=hinh_thuc_nhan]');h.value='tien_mat';chiHT()})()`);
    await ev(`luuChi(null).then(()=>'ok')`); await ngu(3000);
    const ch = await sql(`select id from kt_chi where noi_dung like '%THỬ-LONK%'`);
    ok(ch.length === 1, 'đã tạo 1 phiếu chi thử');
    if (ch.length) {
      const cps = await sql(`select id, chi_id from kt_lo_nk_cp where lo_id = ${S.lo} order by id`), m = Object.fromEntries(cps.map(r => [r.id, r.chi_id]));
      ok(m[c1] === ch[0].id && m[c2] === ch[0].id && m[c3] == null, 'phiếu tự nối vào cước + VAT nộp thay, không nối khoản trả đơn vị khác');
      const g = await sql(`select ncc_id from kt_v_ncc_phieu where bang = 'chi' and dong_id = ${ch[0].id}`);
      ok(g.length === 1 && g[0].ncc_id === S.vc, 'phiếu chi tự gắn về đơn vị vận chuyển (công nợ tự trừ khi đã chi)');
    }
    console.log('lỗi JS:', JSON.stringify(await ev('window.__qa')));
    ok(!(await ev('window.__qa')).some(x => !/^alert/.test(x)), 'không có lỗi JS');
    // ── thuế NK theo tờ khai (tính thuần trên trang)
    const pb = await ev(`(()=>{const c={lo:{cach_pb:'gia_tri',hinh_thuc:'bien',tien_te:'VND'},don:[{tien_te:'VND',hang:[{ma:'A1',ten:'A',sl:2,gia:1000000},{ma:'B1',ten:'B',sl:1,gia:2000000}],ncc:{ten:'x'}}],
      cp:[{loai:'thue_nk',so_tien:400000,tinh_gv:true},{loai:'van_chuyen_qt',so_tien:400000,tinh_gv:true}]};
      const a=lnkPB(c,{ds:[{ma:'A1',thue_nk:300},{ma:'B1',thue_nk:100}]}),b=lnkPB(c,{ds:[{ma:'Z9',thue_nk:300}]});return {a:a.rows.map(r=>Math.round(r.pb)),ka:a.thueKK,b:b.rows.map(r=>Math.round(r.pb)),kb:b.thueKK}})()`);
    ok(pb.ka && pb.a[0] === 500000 && pb.a[1] === 300000, 'thuế NK theo tờ khai: A gánh 300k thuế + 200k cước, B 100k + 200k → ' + pb.a.join(' / '));
    ok(!pb.kb && pb.b[0] === 400000 && pb.b[1] === 400000, 'tờ khai không khớp mã → chia chung theo giá trị như cũ → ' + pb.b.join(' / '));
    // lô biển thật (chỉ xem): NK-2026-01
    const nk = (await sql(`select id from kt_lo_nk where ma = 'NK-2026-01'`))[0];
    if (nk) { await ev(`closeModal();lnkMo(${nk.id},'don')`); await ngu(3500);
      const t2 = await ev(`[...$('#modal').querySelectorAll('.m-tab')].map(b=>b.textContent).join(' | ')`);
      ok(/Kê khai/.test(t2), 'lô đường biển thật NK-2026-01 vẫn có tab Kê khai · ' + t2); await chup('lonk-7-bien-that.png'); }
  } catch (e) { ok(false, 'LỖI ' + e.message); }
  finally { try { ws && ws.close(); } catch (e) {} try { ed && ed.kill(); } catch (e) {} tatTrinhDuyet(dir); await don(); }
  const con = await sql(`select (select count(*) from kt_lo_nk where ten like 'THỬ HỆ THỐNG%') lo, (select count(*) from kt_chi where noi_dung like '%THỬ-LONK%') chi, (select count(*) from kt_ncc where ma = 'THU-LONK') ncc, (select count(*) from kt_nguoi_dung where ten_dang_nhap = '${TK}') tk`);
  console.log('còn sót:', JSON.stringify(con[0]));
  console.log(`${dat}/${dat + hong} đạt`); process.exit(hong ? 1 : 0);
})().catch(async e => { console.error(e.message); await don().catch(() => {}); process.exit(1); });
