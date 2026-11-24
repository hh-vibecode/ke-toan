// Chụp 1 trang app bằng TK tạm (chặn mọi lệnh ghi như ra-nut.js). Monsieur Claude 19/11/2026
// node chup-trang.js <file.png> <trang> [JS chạy sau khi mở trang] [JS chạy tiếp → chụp file thứ 2 tên <file>-2.png]
const fs = require('fs'), os = require('os'), path = require('path'), { spawn } = require('child_process');
const { taoTam, xoaTam } = require('./tk-tam'); const tatTrinhDuyet = require('./tat-trinh-duyet');
// 24/11: máy Mac dùng Chrome (Windows giữ Edge)
const EDGE = process.platform === 'darwin' ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' : 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', [OUT, TRANG, JS1, JS2] = process.argv.slice(2);
const ngu = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const tk = await taoTam('tam-chup', 'admin', ['*'], 'THỬ HỆ THỐNG Chụp');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'chup-')), tep = path.join(dir, 'app.html');
  let html = fs.readFileSync(process.env.KT_HTML || path.join(__dirname, '..', 'index.html'), 'utf8');   // KT_HTML: chụp 1 bản khác (vd bản cũ để so)
  html = html.replace('<div id="app"></div>', `<div id="app"></div><script>sessionStorage.setItem("kt_phien",${JSON.stringify(tk.phien)});window.__qa=[];
    window.addEventListener('error',e=>window.__qa.push(e.message));window.alert=m=>window.__qa.push('alert '+m);window.confirm=()=>false;
    const __f=window.fetch;window.fetch=(u,o)=>{const s=String(u),m=s.match(/rpc\\/(kt_[a-z0-9_]+)/);if(o&&o.method&&o.method!=='GET'&&(/rest\\/v1\\/(?!rpc)/.test(s)||(m&&/_(luu|xoa|gui|duyet|gan|chot|khoa|them|sua|tao|nhap|xu_ly|cap_nhat|doc_chuong|dang_xem|lap|tra_ho)(_|$)/.test(m[1]))))return Promise.reject(new Error('CHẶN GHI'));return __f(u,o)};</script>`);
  fs.writeFileSync(tep, html);
  const port = 9300 + Math.floor(Math.random() * 500);
  const ed = spawn(EDGE, ['--headless=new', '--disable-gpu', `--remote-debugging-port=${port}`, `--user-data-dir=${dir}/ud`, '--window-size=1600,1000', 'about:blank'], { stdio: 'ignore' });
  let ws;
  try {
    let list; for (let i = 0; i < 40; i++) { try { list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (list.find(t => t.type === 'page')) break; } catch (e) {} await ngu(300); }
    ws = new WebSocket(list.find(t => t.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
    let n = 0; const cho = new Map(); ws.onmessage = m => { const j = JSON.parse(m.data); if (j.id && cho.has(j.id)) { cho.get(j.id)(j); cho.delete(j.id); } };
    const cdp = (method, params = {}) => new Promise(r => { const id = ++n; cho.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
    const ev = async e => { const r = await cdp('Runtime.evaluate', { expression: e, awaitPromise: true, returnByValue: true }); return r.result && r.result.result ? r.result.result.value : undefined; };
    const chup = async f => { const r = await cdp('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(f, Buffer.from(r.result.data, 'base64')); };
    await cdp('Page.enable'); await cdp('Runtime.enable');
    await cdp('Page.navigate', { url: 'file:///' + tep.replace(/\\/g, '/') + '#' + TRANG }); await ngu(8000); await ev(`go('${TRANG}')`); await ngu(5000);
    if (JS1) { console.log('JS1:', String(JSON.stringify(await ev(JS1))).slice(0, 500)); await ngu(3000); }
    await chup(OUT);
    if (JS2) { console.log('JS2:', String(JSON.stringify(await ev(JS2))).slice(0, 500)); await ngu(3000); await chup(OUT.replace(/\.png$/, '-2.png')); }
    console.log('lỗi:', JSON.stringify(await ev('window.__qa')));
  } catch (e) { console.log('LỖI', e.message); }
  finally { try { ws && ws.close(); } catch (e) {} try { ed.kill(); } catch (e) {} await tatTrinhDuyet(dir); await xoaTam('tam-chup'); }
})();
