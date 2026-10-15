// KIỂM THỬ GIAO DIỆN TOÀN APP (15/10/2026, anh: "tester hết app, trong vai kế toán, báo các lỗi tiềm tàng").
// Edge headless + giao thức DevTools: đăng nhập tài khoản kế toán TẠM → mở MỌI trang trong menu, bấm mở chi tiết dòng đầu, thử khổ điện thoại.
// Ghi lại: lỗi JavaScript, lời hứa bị từ chối, lỗi gọi dữ liệu (rpc), hộp thông báo lỗi, trang treo "Đang tải", tràn ngang. CHỈ ĐỌC — không bấm Lưu / Xoá.
// Chạy: Code.exe scripts/qa-giao-dien.js [vai: admin|han_che]   · xong xoá tài khoản tạm + file tạm. Monsieur Claude
const fs = require('fs'), os = require('os'), path = require('path'), { spawn } = require('child_process');
const { taoTam, xoaTam } = require('./tk-tam');
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', VAI = process.argv[2] || 'admin';
const ngu = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const tk = VAI === 'admin' ? await taoTam('tam-qa', 'admin', ['*'], 'THỬ HỆ THỐNG Kế toán')
    : await taoTam('tam-qa', 'nhan_vien', ['chi_de_nghi', 'tong_quan'], 'THỬ HỆ THỐNG Nhân viên');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'qa-')), tep = path.join(dir, 'app.html');
  let html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  // bẫy lỗi + tự đồng ý hộp xác nhận (không bấm Lưu nên không ghi gì) + ghi lỗi rpc
  html = html.replace('<div id="app"></div>', `<div id="app"></div><script>sessionStorage.setItem("kt_phien",${JSON.stringify(tk.phien)});
    window.__qa=[];const __q=(k,m)=>window.__qa.push([k,String(m).slice(0,300),location.hash]);
    window.addEventListener('error',e=>__q('js',e.message+' @'+(e.lineno||'')));window.addEventListener('unhandledrejection',e=>__q('promise',(e.reason&&e.reason.message)||e.reason));
    const __ce=console.error;console.error=(...a)=>{__q('console',a.join(' '));__ce(...a)};window.alert=m=>__q('alert',m);window.confirm=()=>false;</script>`);
  html = html.replace('</body>', `<script>(()=>{const o=rpc;rpc=async(...a)=>{try{return await o(...a)}catch(e){__q('rpc',a[0]+': '+e.message);throw e}}})();
    const __t=toast;toast=(m,loi)=>{if(loi)__q('toast',m);return __t(m,loi)};</script></body>`);
  fs.writeFileSync(tep, html);
  const port = 9300 + Math.floor(Math.random() * 500);
  const ed = spawn(EDGE, ['--headless=new', '--disable-gpu', `--remote-debugging-port=${port}`, `--user-data-dir=${dir}/ud`, '--window-size=1600,1000', 'about:blank'], { stdio: 'ignore' });
  let ws; const kq = [];
  try {
    let list; for (let i = 0; i < 40; i++) { try { list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (list.find(t => t.type === 'page')) break; } catch (e) {} await ngu(300); }
    ws = new WebSocket(list.find(t => t.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
    let n = 0; const cho = new Map(); ws.onmessage = m => { const j = JSON.parse(m.data); if (j.id && cho.has(j.id)) { cho.get(j.id)(j); cho.delete(j.id); } };
    const cdp = (method, params = {}) => new Promise(r => { const id = ++n; cho.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
    const ev = async (expr) => { const r = await cdp('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }); return r.result && r.result.result ? r.result.result.value : undefined; };
    await cdp('Page.enable'); await cdp('Runtime.enable');
    await cdp('Page.navigate', { url: 'file:///' + tep.replace(/\\/g, '/') + '#tong_quan' }); await ngu(7000);
    const trang = await ev(`Object.keys(PAGES).filter(k=>coXem(k))`);
    const dauLoi = async () => ev(`(()=>{const a=window.__qa.splice(0);return a})()`);
    // tự kiểm bộ bắt lỗi: cố ý gây 1 lỗi JS + 1 lỗi rpc — phải bắt được 2
    await ev(`setTimeout(()=>{throw new Error('qa-tu-kiem')},0);rpc('kt_khong_co_ham').catch(()=>{})`); await ngu(2500);
    const tu = await dauLoi(); console.log('Tự kiểm bộ bắt lỗi:', tu.length >= 2 ? 'OK (' + tu.map(x => x[0]).join(', ') + ')' : 'HỎNG — kết quả không tin được', '· số trang:', trang.length);
    const kiem = async (k, kieu) => {
      const t0 = Date.now(); let treo = true;
      for (let i = 0; i < 30; i++) { await ngu(500); const s = await ev(`(()=>{const p=document.querySelector('#page');return p?p.innerText.slice(0,200):''})()`);
        if (s && !/^\s*Đang (tải|tính)/.test(s)) { treo = false; break; } }
      const tran = await ev(`document.documentElement.scrollWidth-innerWidth`);
      const loi = await dauLoi();
      kq.push({ k, kieu, giay: ((Date.now() - t0) / 1000).toFixed(1), treo, tran, loi });
    };
    for (const k of trang) {
      await ev(`go('${k}')`); await kiem(k, 'mở trang');
      const coDong = await ev(`(()=>{const r=document.querySelector('#page tr.click,#page tr[data-id],#page .m-k.click');if(!r)return false;r.click();return true})()`);
      if (coDong) { await ngu(2500); const loi = await dauLoi(); if (loi.length) kq.push({ k, kieu: 'bấm dòng / thẻ đầu', loi, giay: '-', treo: false, tran: 0 }); }
      // bấm lần lượt các tab (m-seg) của trang — tối đa 6
      const so = await ev(`document.querySelectorAll('#page .m-seg button').length`) || 0;
      for (let i = 0; i < Math.min(so, 6); i++) { await ev(`(()=>{const b=document.querySelectorAll('#page .m-seg button')[${i}];b&&b.click()})()`); await ngu(1500);
        const loi = await dauLoi(); if (loi.length) kq.push({ k, kieu: 'tab ' + (i + 1), loi, giay: '-', treo: false, tran: 0 }); }
    }
    // mở thử mọi form nhập (không bấm Lưu)
    for (const [p, fn] of [['chi','formChi()'],['chi','xemKiotLe()'],['thu','formThu()'],['dieu_chuyen','formDC()'],['tam_ung','formTU()'],['vay','formVay()'],['dong_tien','formKiemKet()'],
      ['bc_ngan_sach','formNganSach("2026-10")'],['kho_thue','formDCT("",0)'],['tong_quan','moDeXuat()'],['khoa_ky','xemKK(S.cache.kk[1].thang)'],['tam_ung','S.cache.tu[0]&&formTUHoan(S.cache.tu[0].id)'],['vay','S.cache.vay[0]&&formVayNhan(S.cache.vay[0].id)'],['vay','S.cache.vay[0]&&formVayTra(S.cache.vay[0].id)']]) {
      if (!trang.includes(p)) continue; await ev(`go('${p}')`); await ngu(4000);
      const e = await ev(`(async()=>{try{await ${fn};return ''}catch(x){return x.message}})()`); await ngu(1500);
      const loi = await dauLoi(); const mo = await ev(`!!document.querySelector('#modal, .m-pn-b, #gt-body')`);
      kq.push({ k: p, kieu: 'form ' + fn, loi: e ? [['js', e], ...loi] : loi, giay: '-', treo: !mo, tran: 0 }); await ev("typeof closeModal==='function'&&closeModal()"); }
    // khổ điện thoại
    await cdp('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
    for (const k of trang) { await ev(`go('${k}')`); await kiem(k, 'điện thoại'); }
    // kỳ khác: năm, khoảng tuỳ chọn
    await cdp('Emulation.clearDeviceMetricsOverride');
    for (const ky of ['nam', 'm:2026-09']) { await ev(`chonKy('${ky}')`); for (const k of trang.filter(x => !/^cd_/.test(x))) { await ev(`go('${k}')`); await kiem(k, 'kỳ ' + ky); } }
    // tìm kiếm đầu trang + chuông
    await ev(`(()=>{const b=document.querySelector('.hd-bell,.bell,[onclick*="ThongBao"]');b&&b.click()})()`); await ngu(1500);
    const lb = await dauLoi(); if (lb.length) kq.push({ k: 'chuông', kieu: 'mở', loi: lb, giay: '-', treo: false, tran: 0 });
  } catch (e) { kq.push({ k: 'MÁY KIỂM THỬ', kieu: 'lỗi', loi: [['qa', e.message]], giay: '-', treo: false, tran: 0 }); }
  finally {
    try { ws && ws.close(); } catch (e) {} ed.kill(); await ngu(800);
    await xoaTam('tam-qa'); try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {}
  }
  const xau = kq.filter(x => x.treo || (x.loi && x.loi.length) || x.tran > 2);
  console.log(`VAI ${VAI}: ${kq.length} lượt kiểm · ${xau.length} lượt có vấn đề`);
  for (const x of xau) console.log(`- [${x.k} · ${x.kieu}] ${x.treo ? 'TREO "Đang tải" > 15s ' : ''}${x.tran > 2 ? 'tràn ngang ' + x.tran + 'px ' : ''}${(x.loi || []).map(l => l[0] + ': ' + l[1]).join(' | ')}`);
  const cham = kq.filter(x => +x.giay > 6).map(x => x.k + ' ' + x.kieu + ' ' + x.giay + 's');
  if (cham.length) console.log('Chậm > 6s:', cham.join(' · '));
})();
