// KIỂM THỬ Báo giá NCC theo mẫu PO + tìm Phiếu chi khi gõ (19/11/2026). Tài khoản TẠM + NCC TẠM, xong dọn sạch. Monsieur Claude
// Tham số: 1 = thư mục ảnh chụp, 2 = file báo giá Excel để đọc thử (vd file Vân Long Đài Loan kế toán gửi)
const fs = require('fs'), os = require('os'), path = require('path'), { spawn } = require('child_process');
const { taoTam, xoaTam } = require('./tk-tam'); const { sql } = require('./sql'); const tatTrinhDuyet = require('./tat-trinh-duyet');
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', ANH = process.argv[2] || os.tmpdir(), TEP = process.argv[3];
const ngu = ms => new Promise(r => setTimeout(r, ms));
const TEN = 'THỬ HỆ THỐNG Báo giá', NCC = 'THỬ HỆ THỐNG NCC báo giá';
(async () => {
  const tk = await taoTam('tam-bg', 'admin', ['*'], TEN);
  const nid = (await sql(`insert into kt_ncc (ten, loai, stk) values ('${NCC}', 'nuoc_ngoai', '{}') returning id`))[0].id;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bgkt-')), tep = path.join(dir, 'app.html');
  let html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  html = html.replace('<div id="app"></div>', `<div id="app"></div><script>sessionStorage.setItem("kt_phien",${JSON.stringify(tk.phien)});
    window.__qa=[];const __q=(k,m)=>window.__qa.push([k,String(m).slice(0,300)]);
    window.addEventListener('error',e=>__q('js',e.message+' @'+(e.lineno||'')));window.addEventListener('unhandledrejection',e=>__q('promise',(e.reason&&e.reason.message)||e.reason));
    window.alert=m=>__q('alert',m);window.confirm=()=>true;window.__blob=[];const __u=URL.createObjectURL;URL.createObjectURL=b=>{window.__blob.push(b);return __u(b)};</script>`);
  fs.writeFileSync(tep, html);
  const port = 9300 + Math.floor(Math.random() * 500);
  const ed = spawn(EDGE, ['--headless=new', '--disable-gpu', `--remote-debugging-port=${port}`, `--user-data-dir=${dir}/ud`, '--window-size=1600,1000', 'about:blank'], { stdio: 'ignore' });
  let ws, dat = 0, tong = 0; const kq = (ok, ten, ct) => { tong++; if (ok) dat++; console.log((ok ? 'ĐẠT ' : 'TRƯỢT ') + ten + (ct ? ' — ' + ct : '')); };
  try {
    let list; for (let i = 0; i < 40; i++) { try { list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (list.find(t => t.type === 'page')) break; } catch (e) {} await ngu(300); }
    ws = new WebSocket(list.find(t => t.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
    let n = 0; const cho = new Map(); ws.onmessage = m => { const j = JSON.parse(m.data); if (j.id && cho.has(j.id)) { cho.get(j.id)(j); cho.delete(j.id); } };
    const cdp = (method, params = {}) => new Promise(r => { const id = ++n; cho.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
    const ev = async (expr) => { const r = await cdp('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }); return r.result && r.result.result ? r.result.result.value : undefined; };
    const chup = async ten => { const r = await cdp('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(path.join(ANH, ten + '.png'), Buffer.from(r.result.data, 'base64')); };
    await cdp('Page.enable'); await cdp('Runtime.enable');
    await cdp('Page.navigate', { url: 'file:///' + tep.replace(/\\/g, '/') + '#bg_nn' }); await ngu(8000);
    await ev(`go('bg_nn')`); await ngu(4000);
    // 1. đọc file kế toán gửi
    if (TEP) {
      const b64 = fs.readFileSync(TEP).toString('base64');
      await ev(`S.cache.hs_d=null;bgNcc(${nid})`); await ngu(2500);
      await ev(`(async()=>{const b=Uint8Array.from(atob(${JSON.stringify(b64)}),c=>c.charCodeAt(0));await bgNhap(new File([b],'bao-gia-thu.xlsx'),${nid})})()`); await ngu(3000);
      const r = await ev(`(()=>{const d=window._bgN.ds;return {n:d.length,thieu:d.filter(x=>x.gia==null).length,anh:d.filter(x=>x._a).length,nhom:[...new Set(d.map(x=>x.nhom))].length,gt:d.filter(x=>/^Giá trống/.test(x.ten)).length,pk:d.filter(x=>x.nhom==='Pháp khí'&&x.gia>0).length}})()`);
      kq(r && r.n === 208 && r.thieu === 0 && r.gt === 7 && r.pk === 15, 'File Vân Long: 208 dòng, 0 dòng thiếu giá, đủ 7 dòng Giá trống, 15 dòng Pháp khí có giá', JSON.stringify(r));
      await chup('bg-1-doc-file');
      await ev(`window._bgN.ds.forEach(x=>{x._a=null;x._u=null})`);   // không tải 200 ảnh lên kho khi thử
      await ev(`bgNhapLuu()`); for (let i = 0; i < 20; i++) { await ngu(1000); if (await ev(`!window._bgN`)) break; }
      const d = (await sql(`select count(*) n, count(*) filter (where gia is null) k from kt_bao_gia where ncc_id = ${nid} and not da_xoa`))[0];
      kq(+d.n === 208 && +d.k === 0, 'Lưu vào danh mục NCC: 208 sản phẩm, đủ giá', JSON.stringify(d));
      await ngu(1500); await chup('bg-2-bang');
      kq(await ev(`[...document.querySelectorAll('#modal .sk-cot th')].map(t=>t.textContent).join('|')`) === 'Mã THT|Mã NCC|Hình ảnh|Tên hàng|Màu|Kích thước|Chất liệu|Quy cách|ĐVT|Đơn giá|Ngày báo', 'Bảng báo giá: cột như PO, có Chất liệu + Kích thước, không MOQ / SL đặt');
      // tải báo giá xuống rồi đọc lại
      await ev(`window.__blob=[];bgExcel(${nid})`); for (let i = 0; i < 30; i++) { await ngu(1000); if (await ev(`window.__blob.some(b=>b.size>5000)`)) break; }
      const rr = await ev(`(async()=>{const b=window.__blob.find(b=>b.size>5000);if(!b)return null;await bgNhap(new File([await b.arrayBuffer()],'tai-ve.xlsx'),${nid});const d=window._bgN.ds;
        return {n:d.length,thieu:d.filter(x=>x.gia==null).length,cu:d.filter(x=>x._cu).length,doiGia:d.filter(x=>x._cu&&+x._cu.gia!==+x.gia).length,nhom:[...new Set(d.map(x=>x.nhom))].length}})()`);
      kq(rr && rr.n === 208 && rr.thieu === 0 && rr.cu === 208 && rr.doiGia === 0, 'Tải báo giá xuống → tải lên lại: 208 dòng khớp hết, giá không đổi', JSON.stringify(rr));
      await ev(`dong2()`);
    }
    // 2. file mẫu: đọc lại được, có Chất liệu / Kích thước
    await ev(`window.__blob=[];bgExcel(null)`); for (let i = 0; i < 15; i++) { await ngu(800); if (await ev(`window.__blob.some(b=>b.size>3000)`)) break; }
    const rm = await ev(`(async()=>{const b=window.__blob.find(b=>b.size>3000);await bgNhap(new File([await b.arrayBuffer()],'mau.xlsx'),${nid});const x=window._bgN.ds[0];return window._bgN.ds.length+'|'+x.ten+'|'+x.kt+'|'+x.chat_lieu+'|'+x.mau+'|'+x.gia})()`);
    kq(rm === '1|Tượng Quan Âm đứng đài sen|Cao 30cm|Đồng|Vàng đồng|850', 'File mẫu tải về → đọc lại đúng (Màu, Kích thước, Chất liệu, Đơn giá)', rm);
    await ev(`dong2()`);
    // 3. phiếu khai lẻ: thêm 1 sản phẩm
    await ev(`bgForm(null,${nid})`); await ngu(800); await chup('bg-3-form');
    kq(await ev(`!/MOQ|tối thiểu/i.test($('#modal2').innerText)&&/chất liệu/i.test($('#modal2').innerText)&&/kích thước/i.test($('#modal2').innerText)`), 'Phiếu khai báo giá lẻ: có Chất liệu, Kích thước, không MOQ');
    await ev(`(()=>{const f=$('#fbg');const s=(k,v)=>f.querySelector('[name='+k+']').value=v;s('ten','THỬ tượng lẻ');s('chat_lieu','Gỗ hương');s('kt','40cm');s('gia','123,5')})()`);
    await ev(`bgLuu(null,${nid})`); await ngu(2500);
    const l = (await sql(`select chat_lieu, kt, gia from kt_bao_gia where ncc_id = ${nid} and ten = 'THỬ tượng lẻ'`))[0];
    kq(l && l.chat_lieu === 'Gỗ hương' && l.kt === '40cm' && +l.gia === 123.5, 'Lưu phiếu lẻ: ghi đúng chất liệu, kích thước, giá', JSON.stringify(l));
    // 4. PO → Lưu vào báo giá NCC
    await ev(`closeModal();poForm(null,{loai:'nhap_khau',ncc_id:${nid},ncc_ten:${JSON.stringify(NCC)},tien_te:'CNY',dong:[{ma_ncc:'THU-PO-1',ten:'THỬ hàng từ PO',mau:'Đỏ',kt:'20cm',dvt:'Cái',sl:3,don_gia:77}]})`); await ngu(2000);
    kq(await ev(`!![...document.querySelectorAll('#modal button')].find(b=>/Lưu vào báo giá NCC/.test(b.textContent))`), 'PO có nút "Lưu vào báo giá NCC"');
    await chup('bg-4-po');
    await ev(`bgTuPO()`); await ngu(2500);
    const p = (await sql(`select mau, kt, gia, tien_te from kt_bao_gia where ncc_id = ${nid} and ma_ncc = 'THU-PO-1'`))[0];
    kq(p && p.mau === 'Đỏ' && p.kt === '20cm' && +p.gia === 77 && p.tien_te === 'CNY', 'PO → báo giá: dòng vào báo giá NCC đúng màu, kích thước, giá, tiền tệ', JSON.stringify(p));
    await ev(`closeModal()`);
    // 4b. Chất liệu trong PO: bảng Hàng đặt + file Excel PO (mẫu mới, cột H) + đọc lại file
    await ev(`closeModal();poForm(null,{loai:'nhap_khau',ncc_id:${nid},ncc_ten:${JSON.stringify(NCC)},tien_te:'CNY',dong:[{ma_tht:'SP-THU',ma_ncc:'THU-CL',ten:'THỬ chất liệu',mau:'Vàng',kt:'30cm',chat_lieu:'Đồng thau',quy_cach:'1 hộp',dvt:'Cái',sl:4,don_gia:12.5}]})`); await ngu(2000);
    const pb = await ev(`({cot:[...document.querySelectorAll('#modal .sk-cot th')].map(t=>t.textContent).join('|'),o:[...document.querySelectorAll('#modal .po-x input')].some(e=>e.value==='Đồng thau')})`);
    kq(/Kích thước\|Chất liệu\|Quy cách/.test(pb.cot) && pb.o, 'PO: bảng Hàng đặt có cột Chất liệu sau Kích thước, hiện đúng giá trị', pb.cot);
    await chup('bg-4b-po-cl');
    await ev(`window.__blob=[];poExcel()`); for (let i = 0; i < 30; i++) { await ngu(800); if (await ev(`window.__blob.some(b=>b.size>3000)`)) break; }
    const px = await ev(`(async()=>{const b=window.__blob.find(b=>b.size>3000);if(!b)return null;const E=await napExcelJS(),wb=new E.Workbook();await wb.xlsx.load(await b.arrayBuffer());const ws=wb.worksheets[0];
      const h=[];for(let c=1;c<=14;c++)h.push(String(ws.getCell(17,c).value||'').split('\\n')[0]);const m=ws.getCell(18,13).value;
      return {h:h.join('|'),cl:ws.getCell(18,8).value,sl:ws.getCell(18,11).value,gia:ws.getCell(18,12).value,f:m&&m.formula,kq:m&&m.result,tong:(()=>{for(let r=19;r<40;r++){const v=ws.getCell(r,13).value;if(v&&v.formula&&/SUM/.test(v.formula))return v.formula}})()}})()`);
    kq(px && px.h === 'STT|Mã THT|Mã NCC|Hình ảnh|Tên hàng|Màu|Kích thước|Chất liệu|Quy cách|ĐVT|Số lượng đặt|Đơn giá|Thành tiền|Ghi chú' && px.cl === 'Đồng thau' && px.sl === 4 && px.gia === 12.5 && /K18\*L18/.test(px.f) && px.kq === 50 && /M18/.test(px.tong || ''),
      'File Excel PO (mẫu mới): cột H = Chất liệu, SL K, Đơn giá L, Thành tiền M = K×L, Tổng cộng cộng cột M', JSON.stringify(px));
    const pr = await ev(`(async()=>{const b=window.__blob.find(b=>b.size>3000);let kq=null;const o=window.poVe;window.poVe=()=>{kq=JSON.parse(JSON.stringify((window._po.dong||[]).map(({_f,_u,...r})=>r)))};
      try{await poDocExcel(new File([await b.arrayBuffer()],'po-thu.xlsx'),[])}catch(e){kq={loi:e.message}}window.poVe=o;return kq&&kq[0]?kq[0]:kq})()`);
    kq(pr && pr.chat_lieu === 'Đồng thau' && pr.kt === '30cm' && +pr.sl === 4 && +pr.don_gia === 12.5, 'Tải file PO vừa xuất lên lại: đọc đúng Chất liệu, Kích thước, SL, Đơn giá', JSON.stringify(pr).slice(0, 300));
    await ev(`closeModal();dong2()`);
    // 4c. "+ Báo giá" ở trang Đặt hàng NCC (danh sách PO), KHÔNG còn ở popup đơn hàng khách đặt
    await ev(`go('po_nk')`); await ngu(4000);
    const nb = await ev(`[...document.querySelectorAll('#page button')].filter(b=>/\\+ Báo giá/.test(b.textContent)).length`);
    const dxk = await ev(`(async()=>{S.cache.dx_d=await rpc('kt_dx_ds');const x=S.cache.dx_d.find(z=>z.loai==='khach_dat');if(!x)return 'không có đơn';await dxMo(x.id);const c=/\\+ Báo giá/.test($('#modal').innerText);closeModal();return c})()`);
    kq(nb > 0 && dxk === false, 'Nút "+ Báo giá" ở danh sách PO (mỗi PO 1 nút), popup Đơn hàng khách đặt không còn nút', `${nb} nút · popup đơn khách: ${dxk}`);
    await chup('bg-4c-po-ds');
    // 4d. form đặt hàng của sale có cột Chất liệu
    await ev(`(()=>{DX.loai='khach_dat';DX.dong=[{}];dxVeDong()})()`).catch(() => {});
    const fdx = await ev(`(()=>{const d=document.createElement('div');d.id='dx-dong';document.body.appendChild(d);window.DX=window.DX||{};DX.loai='khach_dat';DX.dong=[{chat_lieu:'Gỗ gụ'}];dxVeDong();
      const h=[...d.querySelectorAll('th')].map(t=>t.textContent.replace('*','').trim()).join('|'),v=[...d.querySelectorAll('input')].some(e=>e.value==='Gỗ gụ');d.remove();return h+'|'+v})()`);
    kq(/Kích thước\|Chất liệu\|ĐVT/.test(fdx || '') && /true$/.test(fdx || ''), 'Form đặt hàng: có cột Chất liệu sau Kích thước', fdx);
    // 5. phiếu chi: tìm theo số tiền + lọc khi gõ
    const st = (await sql(`select so_tien from kt_chi where so_tien >= 100000 order by id desc limit 1`))[0];
    await ev(`go('chi')`); await ngu(6000);
    const t0 = Date.now();
    await ev(`(()=>{const e=document.querySelector('input[data-tim="chi"]');e.value=${JSON.stringify(String(Math.round(+st.so_tien)))};e.dispatchEvent(new Event('input'))})()`);
    let ok = false; for (let i = 0; i < 40; i++) { await ngu(250); if (await ev(`(S.f.chi_q||'')===${JSON.stringify(String(Math.round(+st.so_tien)))}&&!!document.querySelector('#page table')`)) { ok = true; break; } }
    const lan1 = Date.now() - t0;
    const sl = await ev(`[...document.querySelectorAll('#page table tr')].filter(r=>r.innerText.includes(${JSON.stringify(Number(st.so_tien).toLocaleString('vi-VN'))})).length`);
    kq(ok && sl > 0, 'Phiếu chi: gõ số tiền (không Enter) → lọc ra phiếu đúng số tiền', `${sl} dòng · lần gõ đầu ${lan1} ms`);
    const t1 = Date.now();
    await ev(`(()=>{const e=document.querySelector('input[data-tim="chi"]');e.value='PC';e.dispatchEvent(new Event('input'))})()`);
    for (let i = 0; i < 40; i++) { await ngu(50); if (await ev(`S.f.chi_q==='PC'`)) break; }
    const lan2 = Date.now() - t1;
    kq(lan2 < 800 && await ev(`document.activeElement&&document.activeElement.dataset.tim==='chi'`), 'Gõ tiếp: lọc từ dữ liệu đã tải (không gọi máy chủ), con trỏ vẫn ở ô tìm', lan2 + ' ms (gồm 220 ms chờ dừng gõ)');
    await chup('bg-5-chi-tim');
    const loi = await ev(`window.__qa`); kq(!loi.length, 'Không có lỗi JS / alert', JSON.stringify(loi).slice(0, 400));
  } catch (e) { console.log('LỖI', e.message); }
  finally {
    try { ws && ws.close(); } catch (e) {} try { ed.kill(); } catch (e) {} await tatTrinhDuyet(dir);
    await sql(`delete from kt_chung_tu where bang = 'bao_gia' and dong_id in (select id from kt_bao_gia where ncc_id = ${nid}); delete from kt_bao_gia where ncc_id = ${nid};
      delete from kt_nhat_ky where nguoi = '${TEN}'; delete from kt_ncc where id = ${nid}`).catch(e => console.log('dọn lỗi', e.message));
    await xoaTam('tam-bg');
    const con = (await sql(`select (select count(*) from kt_bao_gia where ncc_id = ${nid}) bg, (select count(*) from kt_ncc where id = ${nid}) ncc`))[0];
    console.log(`\n${dat}/${tong} ĐẠT · dọn: còn ${con.bg} báo giá thử, ${con.ncc} NCC thử`);
  }
})();
