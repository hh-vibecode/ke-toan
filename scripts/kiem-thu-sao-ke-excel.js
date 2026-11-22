// KIỂM THỬ xuất Excel Đối chiếu sao kê theo đúng ô của file mẫu (20/11/2026): tài khoản kế toán TẠM, mở từng kỳ đang có, bấm Excel,
// lưu file xuất vào thư mục tham số 1 (máy, KHÔNG commit — có số liệu thật). Chỉ đọc, không ghi CSDL ngoài tài khoản tạm (xoá khi xong). Monsieur Claude
const fs = require('fs'), os = require('os'), path = require('path'), http = require('http'), { spawn } = require('child_process');
const { taoTam, xoaTam } = require('./tk-tam'); const { sql } = require('./sql');
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', RA = process.argv[2] || os.tmpdir(), GOC = path.join(__dirname, '..');
const ngu = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const tk = await taoTam('tam-skx', 'admin', ['*'], 'THỬ HỆ THỐNG Sao kê Excel');
  const kys = (await sql(`select id from kt_sao_ke_ky order by id`)).map(x => +x.id);
  let html = fs.readFileSync(path.join(GOC, 'index.html'), 'utf8').replace('<div id="app"></div>', `<div id="app"></div><script>sessionStorage.setItem("kt_phien",${JSON.stringify(tk.phien)});
    window.__qa=[];const __q=(k,m)=>window.__qa.push([k,String(m).slice(0,300)]);
    window.addEventListener('error',e=>__q('js',e.message+' @'+(e.lineno||'')));window.addEventListener('unhandledrejection',e=>__q('promise',(e.reason&&e.reason.message)||e.reason));
    window.alert=m=>__q('alert',m);window.confirm=()=>true;window.__blob=null;const __cu=URL.createObjectURL;URL.createObjectURL=b=>{window.__blob=b;return __cu(b)};</script>`);
  const sv = http.createServer((q, s) => { const u = q.url.split('?')[0];
    if (u === '/' || u === '/index.html') { s.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }); return s.end(html); }
    const f = path.join(GOC, decodeURIComponent(u)); if (path.dirname(f) === GOC && /\.xlsx$/.test(f) && fs.existsSync(f)) { s.writeHead(200); return s.end(fs.readFileSync(f)); }
    s.writeHead(404); s.end(); }).listen(0);
  const web = `http://127.0.0.1:${sv.address().port}/`;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'skx-')), port = 9300 + Math.floor(Math.random() * 500);
  const ed = spawn(EDGE, ['--headless=new', '--disable-gpu', `--remote-debugging-port=${port}`, `--user-data-dir=${dir}/ud`, '--window-size=1500,1000', 'about:blank'], { stdio: 'ignore' });
  let ws;
  try {
    let list; for (let i = 0; i < 40; i++) { try { list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (list.find(t => t.type === 'page')) break; } catch (e) {} await ngu(300); }
    ws = new WebSocket(list.find(t => t.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
    let n = 0; const cho = new Map(); ws.onmessage = m => { const j = JSON.parse(m.data); if (j.id && cho.has(j.id)) { cho.get(j.id)(j); cho.delete(j.id); } };
    const cdp = (method, params = {}) => new Promise(r => { const id = ++n; cho.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
    const ev = async (expr) => { const r = await cdp('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }); return r.result && r.result.result ? r.result.result.value : r.result; };
    await cdp('Page.enable'); await cdp('Runtime.enable');
    await cdp('Page.navigate', { url: web + '#sao_ke_hd' }); await ngu(8000);
    await ev(`(()=>{window.__toast=[];const o=toast;toast=(m,...a)=>{window.__toast.push(String(m));return o(m,...a)}})()`);
    for (const id of kys) {
      await ev(`S.f.sk_ky=${id};go('sao_ke_hd')`); await ngu(3500);
      await ev(`window.__blob=null;window.__toast=[];skExcel(S.cache.sk_kq)`);
      let b64 = null; for (let i = 0; i < 40 && !b64; i++) { await ngu(500); b64 = await ev(`window.__blob?new Promise(r=>{const f=new FileReader();f.onload=()=>r(f.result.split(',')[1]);f.readAsDataURL(window.__blob)}):null`); }
      const t = await ev(`window.__toast.join(' | ')`), tk = await ev(`S.cache.sk_kq.tk+' · '+S.cache.sk_kq.tu`);
      if (b64) fs.writeFileSync(path.join(RA, `ky${id}.xlsx`), Buffer.from(b64, 'base64'));
      console.log(`kỳ ${id}`, String(tk).replace(/\d{6,}/g, '#'), b64 ? 'ĐÃ XUẤT' : 'KHÔNG XUẤT', '—', t);
    }
    console.log('Lỗi trang:', JSON.stringify(await ev('window.__qa')));
  } catch (e) { console.log('LỖI', e.stack); }
  finally { try { ws && ws.close(); } catch (e) {} ed.kill(); require('./tat-trinh-duyet')(dir); sv.close();
    await xoaTam('tam-skx'); try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {} }
})();
