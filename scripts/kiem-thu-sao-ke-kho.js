// KIỂM THỬ popup Kho sao kê (16/11/2026): tài khoản kế toán TẠM, file sao kê GIẢ (TK id 2, số TK đọc từ CSDL lúc chạy, kỳ 01–02/09/2026, 2 dòng).
// Kiểm: popup mở · chọn sai TK → chặn nạp + gợi ý đổi · nạp → kỳ chờ đối chiếu + file gốc trong kho · tải file gốc · hàm xử lý xong (giao dịch huỷ,
// không gửi chuông thật) · xoá kỳ → file gốc ẩn. Chụp ảnh vào thư mục tham số 1. Xong dọn sạch. Monsieur Claude
const fs = require('fs'), os = require('os'), path = require('path'), { spawn } = require('child_process');
const { taoTam, xoaTam } = require('./tk-tam'); const { sql } = require('./sql');
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', ANH = process.argv[2] || os.tmpdir();
const ngu = ms => new Promise(r => setTimeout(r, ms));
const TEN = 'THỬ HỆ THỐNG Sao kê';
(async () => {
  const tk = await taoTam('tam-sk', 'admin', ['*'], TEN);
  const SO_TK = (await sql(`select regexp_replace(ten, '[^0-9]', '', 'g') s from kt_tai_khoan where id = 2`))[0].s;   // không ghi cứng số TK thật (repo công khai)
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sk-')), tep = path.join(dir, 'app.html');
  let html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  html = html.replace('<div id="app"></div>', `<div id="app"></div><script>sessionStorage.setItem("kt_phien",${JSON.stringify(tk.phien)});
    window.__qa=[];const __q=(k,m)=>window.__qa.push([k,String(m).slice(0,300)]);
    window.addEventListener('error',e=>__q('js',e.message+' @'+(e.lineno||'')));window.addEventListener('unhandledrejection',e=>__q('promise',(e.reason&&e.reason.message)||e.reason));
    window.alert=m=>__q('alert',m);window.__toast=[];window.confirm=()=>true;</script>`);
  fs.writeFileSync(tep, html);
  const port = 9300 + Math.floor(Math.random() * 500);
  const ed = spawn(EDGE, ['--headless=new', '--disable-gpu', `--remote-debugging-port=${port}`, `--user-data-dir=${dir}/ud`, '--window-size=1500,1000', 'about:blank'], { stdio: 'ignore' });
  let ws, kyId = null, dat = 0, tong = 0; const kq = (ok, ten, ct) => { tong++; if (ok) dat++; console.log((ok ? 'ĐẠT ' : 'TRƯỢT ') + ten + (ct ? ' — ' + ct : '')); };
  try {
    let list; for (let i = 0; i < 40; i++) { try { list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (list.find(t => t.type === 'page')) break; } catch (e) {} await ngu(300); }
    ws = new WebSocket(list.find(t => t.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
    let n = 0; const cho = new Map(); ws.onmessage = m => { const j = JSON.parse(m.data); if (j.id && cho.has(j.id)) { cho.get(j.id)(j); cho.delete(j.id); } };
    const cdp = (method, params = {}) => new Promise(r => { const id = ++n; cho.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
    const ev = async (expr) => { const r = await cdp('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }); return r.result && r.result.result ? r.result.result.value : undefined; };
    const chup = async ten => { const r = await cdp('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(path.join(ANH, ten + '.png'), Buffer.from(r.result.data, 'base64')); };
    await cdp('Page.enable'); await cdp('Runtime.enable');
    const hookT = () => ev(`(()=>{if(!window.__th){window.__th=1;const o=toast;toast=(m,...a)=>{window.__toast.push(String(m));return o(m,...a)}}})()`);
    await cdp('Page.navigate', { url: 'file:///' + tep.replace(/\\/g, '/') + '#sao_ke_hd' }); await ngu(8000);
    await ev(`go('sao_ke_hd')`); await ngu(4000); await hookT();
    await ev(`skKho()`); await ngu(2500);
    kq(await ev(`!!document.querySelector('#modal .skk-b')&&document.querySelectorAll('#modal .skk-t tr').length>1`), 'Popup Kho sao kê mở, có danh sách sao kê đã lưu');
    await chup('sk-1-kho');
    // file giả cho TK id 2 nhưng chọn TK 599 → phải chặn
    await ev(`S.cache.sk_nap.tk='1';skKhoVe()`);
    await ev(`(async()=>{const X=await napXLSX(),w=X.utils.aoa_to_sheet([['SAO KÊ TÀI KHOẢN'],['Số tài khoản','${SO_TK}'],['Chủ tài khoản','THU NGHIEM'],['Từ ngày','01/09/2026'],['Đến ngày','02/09/2026'],['Số dư đầu kỳ',1000000],[],
      ['STT','Ngày giao dịch','Số CT','Ghi nợ','Ghi có','Số dư','Nội dung'],[1,'01/09/2026','CT1',0,500000,1500000,'THU NGHIEM nop'],[2,'02/09/2026','CT2',200000,0,1300000,'THU NGHIEM chi'],[],['Số dư cuối kỳ',1300000]]);
      const b=X.utils.book_new();X.utils.book_append_sheet(b,w,'Sheet1');const buf=X.write(b,{type:'array',bookType:'xlsx'});
      await skNapFile(new File([buf],'SaoKe-thu-nghiem.xlsx',{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}))})()`); await ngu(1500);
    kq(await ev(`$('#sk-nap').disabled&&/File là sao kê/.test($('#modal').innerText)`), 'Chọn sai TK (599) cho file TK 925 → chặn nạp, báo đúng TK');
    await chup('sk-2-sai-tk');
    await ev(`[...document.querySelectorAll('#modal .m-link')].find(x=>/Đổi sang/.test(x.textContent)).click()`); await ngu(800);
    kq(await ev(`!$('#sk-nap').disabled&&S.cache.sk_nap.tk==='2'&&/Khớp/.test($('#modal .skk-xt').innerText)`), 'Bấm "Đổi sang" → TK 925, cho nạp, số dư khớp');
    await chup('sk-3-xem-truoc');
    await ev(`skNap()`); for (let i = 0; i < 20; i++) { await ngu(1000); if (await ev(`!!document.querySelector('#modal .skk-b')&&!document.querySelector('#sk-nap[disabled]')&&!S.cache.sk_nap.file`)) break; }
    const r = (await sql(`select k.id, k.xu_ly_luc is null cho, (select count(*) from kt_sao_ke s where s.ky_id=k.id) dong, (select count(*) from kt_chung_tu c where c.bang='sao_ke' and c.dong_id=k.id and not c.da_xoa) file
      from kt_sao_ke_ky k where k.tk_id=2 and k.tu='2026-09-01' and k.den='2026-09-02'`))[0];
    kyId = r && r.id;
    kq(r && r.cho && +r.dong === 2 && +r.file === 1, 'Nạp xong: kỳ vào hàng chờ đối chiếu, 2 dòng, 1 file gốc trong kho', JSON.stringify(r));
    kq(await ev(`S.f.sk_ky===${kyId}&&/Chờ đối chiếu/.test($('#modal').innerText)`), 'Trang chuyển sang kỳ vừa nạp, kho hiện "Chờ đối chiếu"');
    await chup('sk-4-da-nap');
    const tai = await ev(`(async()=>{const x=S.cache.sk_ds.find(k=>k.id===${kyId});const {ds}=await ctFn({viec:'xem',ids:[x.file.id]});const b=await (await fetch(ds[0].url)).arrayBuffer();return b.byteLength})()`);
    kq(tai > 1000, 'Tải file gốc từ kho được', tai + ' byte');
    // hàm xử lý xong: chạy trong giao dịch rồi huỷ (không gửi chuông thật cho kế toán)
    try { await sql(`do $$ declare n int; t text; begin perform kt_sao_ke_xu_ly_xong(${kyId}, (select ket_qua from kt_sao_ke_ky where id=${kyId}));
        select count(*), max(tieu_de || ' | ' || noi_dung) into n, t from kt_thong_bao where bang='sao_ke' and dong_id=${kyId};
        raise exception 'KQ:%:%:%', n, t, (select xu_ly_luc is not null from kt_sao_ke_ky where id=${kyId}); end $$`); kq(false, 'xu_ly_xong'); }
    catch (e) { const m = (e.message.match(/KQ:(\d+):(.*?):(t|f|true|false)\b/) || []); kq(+m[1] > 0 && /^t/.test(m[3] || ''), 'Xử lý xong (giao dịch huỷ): lưu kết quả + chuông cho ' + m[1] + ' người', m[2]); }
    kq((await sql(`select count(*) n from kt_thong_bao where bang='sao_ke'`))[0].n == 0, 'Không còn chuông thử nào sót lại');
    // phone
    await cdp('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true }); await ngu(800);
    kq(await ev(`document.querySelector('#modal>div').scrollWidth<=document.querySelector('#modal>div').clientWidth+2`), 'Khổ điện thoại: popup không tràn ngang');
    await chup('sk-5-dien-thoai'); await cdp('Emulation.clearDeviceMetricsOverride');
    await ev(`skKhoXoa(${kyId})`); await ngu(3000);
    const x = (await sql(`select (select count(*) from kt_sao_ke_ky where id=${kyId}) ky, (select count(*) from kt_chung_tu where bang='sao_ke' and dong_id=${kyId} and not da_xoa) file`))[0];
    kq(+x.ky === 0 && +x.file === 0, 'Xoá kỳ trong kho → kỳ + file gốc đều ẩn / xoá');
    console.log('toast:', JSON.stringify(await ev(`window.__toast`)));
    const loi = await ev(`window.__qa`); kq(!loi.length, 'Không lỗi JS / alert', JSON.stringify(loi));
  } catch (e) { kq(false, 'MÁY KIỂM THỬ', e.message); }
  finally {
    try { ws && ws.close(); } catch (e) {} ed.kill(); require('./tat-trinh-duyet')(dir);   // 17/11: tắt CẢ CÂY tiến trình Edge (ed.kill chỉ tắt tiến trình gốc → sót tiến trình con, máy cạn bộ nhớ) await ngu(800);
    if (kyId) {
      const ct = await sql(`select id, duong_dan from kt_chung_tu where bang='sao_ke' and dong_id=${kyId}`);
      if (ct.length) { const K = require('./khoa').docKhoa();   // bảng storage không cho xoá thẳng → Storage API, đúng đường dẫn file thử
        const x = await fetch('https://bcrpxfvvjsjpvbksqzls.supabase.co/storage/v1/object/kt-chung-tu', { method: 'DELETE',
          headers: { apikey: K.SERVICE_ROLE_KEY, Authorization: 'Bearer ' + K.SERVICE_ROLE_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ prefixes: ct.map(c => c.duong_dan) }) });
        console.log('Xoá file thử trong bucket:', x.status); }
      await sql(`delete from kt_chung_tu where bang='sao_ke' and dong_id=${kyId}; delete from kt_sao_ke_ky where id=${kyId}`);
    }
    await sql(`delete from kt_nhat_ky where nguoi = $kt$${TEN}$kt$`);
    await xoaTam('tam-sk'); try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {}
    console.log(`KẾT QUẢ: ${dat}/${tong}`);
  }
})();
