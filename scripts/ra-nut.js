// RÀ NÚT TOÀN APP (19/11/2026, anh: "kiểm tra lại toàn bộ các nút chức năng, đảm bảo phải hoạt động hết"). Monsieur Claude
// TK tạm (admin, mọi quyền) · chặn MỌI lệnh ghi: RPC tên có động từ ghi, Edge Function trừ xem, confirm() = Huỷ, tải file = chặn.
// Mỗi trang trong menu: (1) đổi lọc cơ sở (chỉ Chánh Tâm) → nội dung trang có đổi không; (2) bấm từng nút / tab / thẻ / ô chọn → lỗi JS, báo lỗi, không phản ứng.
// Tham số: 1 = file kết quả JSON, 2 = danh sách trang (cách dấu phẩy, bỏ trống = mọi trang)
const fs = require('fs'), os = require('os'), path = require('path'), { spawn } = require('child_process');
const { taoTam, xoaTam } = require('./tk-tam'); const tatTrinhDuyet = require('./tat-trinh-duyet');
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', OUT = process.argv[2] || path.join(os.tmpdir(), 'ra-nut.json'), CHI = (process.argv[3] || '').split(',').filter(Boolean);
const ngu = ms => new Promise(r => setTimeout(r, ms));
// hàm RPC coi là GHI nếu tên có 1 đoạn (tách theo "_") là động từ ghi; CHO = hàm đọc trùng chữ (cho qua)
const GHI = 'luu,xoa,gui,duyet,gan,chot,khoa,them,sua,tao,chay,ghi,keo,nap,nhap,upsert,reset,doi_mk,dang_xuat,danh_dau,xac_nhan,tu_choi,xu_ly,dong_bo,cap_nhat,bao_kq,doc_chuong,da_doc,ap_dung,khong_can,bo_qua,tai_len,dat_lai,mo_lai,phan_hoi,dang_xem,hoan_tac,bo_gan,tach,gop,chuyen,xac,dong_y,ket_thuc,huy,ghep,day,nhac,danh_gia,doi', CHO = 'kt_po_gia_nhap';
(async () => {
  const tk = await taoTam('tam-ra', 'admin', ['*'], 'THỬ HỆ THỐNG Rà nút');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ranut-')), tep = path.join(dir, 'app.html');
  let html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
  html = html.replace('<div id="app"></div>', `<div id="app"></div><script>sessionStorage.setItem("kt_phien",${JSON.stringify(tk.phien)});
    window.__qa=[];window.__chan=[];window.__pend=0;window.__evt=[];const __q=(k,m)=>window.__qa.push([k,String(m).slice(0,240)]);
    window.addEventListener('error',e=>__q('js',e.message+' @'+(e.lineno||'')));window.addEventListener('unhandledrejection',e=>{const m=(e.reason&&e.reason.message)||String(e.reason);if(!/CHẶN GHI/.test(m))__q('promise',m)});
    window.alert=m=>{if(!/CHẶN GHI/.test(String(m)))__q('alert',m)};window.confirm=()=>{window.__evt.push('confirm');return false};window.prompt=()=>{window.__evt.push('prompt');return null};window.open=()=>{window.__evt.push('open');return null};
    HTMLAnchorElement.prototype.click=function(){window.__evt.push('tai:'+(this.download||this.href||'').slice(0,60))};
    const GH='${GHI}'.split(','),CH='${CHO}'.split(','),laGhi=n=>!CH.includes(n)&&!/^kt_doi_soat/.test(n)&&GH.some(v=>('_'+n+'_').includes('_'+v+'_'));
    const __f=window.fetch;window.fetch=async(u,o)=>{const s=String(u);
      if(o&&o.method&&o.method!=='GET'){const m=s.match(/rest\\/v1\\/rpc\\/([a-z0-9_]+)/);if(m&&laGhi(m[1])){window.__chan.push(m[1]);throw new Error('CHẶN GHI '+m[1])}
        if(/functions\\/v1\\//.test(s)){let v='';try{v=JSON.parse(o.body).viec||''}catch(e){}if(!/^(xem|xem_dx|mau|ds)$/.test(v)){window.__chan.push('edge:'+s.split('/').pop()+':'+v);throw new Error('CHẶN GHI edge')}}
        if(/rest\\/v1\\/(?!rpc)/.test(s)){window.__chan.push('rest');throw new Error('CHẶN GHI rest')}}
      window.__pend++;try{return await __f(u,o)}finally{window.__pend--}};</script>`);
  fs.writeFileSync(tep, html);
  const port = 9300 + Math.floor(Math.random() * 500);
  const ed = spawn(EDGE, ['--headless=new', '--disable-gpu', `--remote-debugging-port=${port}`, `--user-data-dir=${dir}/ud`, '--window-size=1600,1000', 'about:blank'], { stdio: 'ignore' });
  let ws; const KQ = [];
  try {
    let list; for (let i = 0; i < 40; i++) { try { list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (list.find(t => t.type === 'page')) break; } catch (e) {} await ngu(300); }
    ws = new WebSocket(list.find(t => t.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
    let n = 0; const cho = new Map(); ws.onmessage = m => { const j = JSON.parse(m.data); if (j.id && cho.has(j.id)) { cho.get(j.id)(j); cho.delete(j.id); } };
    const cdp = (method, params = {}) => new Promise(r => { const id = ++n; cho.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
    const ev = async (expr, to = 30000) => { const r = await Promise.race([cdp('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }), ngu(to).then(() => ({ result: { result: { value: '__treo' } } }))]); return r.result && r.result.result ? r.result.result.value : undefined; };
    const yen = async (max = 15000) => { const t = Date.now(); let ok = 0; while (Date.now() - t < max) { await ngu(150); const v = await ev(`window.__pend===0&&!/Đang tải|Đang kiểm/.test(($('#page')||{}).innerText||'')`); ok = v ? ok + 1 : 0; if (ok >= 3) return true; } return false; };
    await cdp('Page.enable'); await cdp('Runtime.enable'); await cdp('Browser.setDownloadBehavior', { behavior: 'deny' }).catch(() => {});
    await cdp('Page.navigate', { url: 'file:///' + tep.replace(/\\/g, '/') + '#tong_quan' }); await ngu(8000); await yen();
    await ev(`(()=>{const o=window.toast;window.toast=(m,...a)=>{window.__evt.push('toast:'+String(m).slice(0,50));return o(m,...a)}})()`);
    const trang = await ev(`Object.entries(PAGES).filter(([k,v])=>v.nv).map(([k,v])=>[k,v.ten])`);
    const DS = trang.filter(([k]) => !CHI.length || CHI.includes(k));
    const BO = /xo[áa]|l[ưu]u|duy[ệe]t|x[áa]c nh[ậa]n|g[ửu]i|t[ừu] ch[ốo]i|thanh to[áa]n|chi ti[ềe]n|n[ạa]p|t[ảa]i l[êe]n|đ[ồo]ng b[ộo]|ch[ạa]y|kho[áa]|ch[ốo]t|hu[ỷy]|đăng xu[ấa]t|k[ée]o|c[ậa]p nh[ậa]t|[áa]p d[ụu]ng|gh[ée]p|g[ắa]n|đ[ổo]i m[ậa]t|reset|đ[áa]nh d[ấa]u|kh[ôo]ng c[ầa]n|✕|^tải lên|đăng nhập/i;   // lệnh ghi đã chặn ở fetch — chỉ bỏ nút ghi thẳng / đăng xuất cho chắc
    for (const [k, ten] of DS) {
      const r = { k, ten, loi: [], cs: null, nut: [] };
      await ev(`window.__qa=[];closeModal&&closeModal();dong2&&dong2();S.f.loc_cs=null;go('${k}')`); await yen();
      r.loi.push(...(await ev(`window.__qa.splice(0)`)) || []);
      const A = await ev(`($('#page')||{}).innerText||''`);
      await ev(`csChon('CT')`); await yen(); const B = await ev(`($('#page')||{}).innerText||''`);
      await ev(`csChon(null)`); await yen();
      r.cs = A === B ? 'không đổi' : 'đổi'; r.loi.push(...(await ev(`window.__qa.splice(0)`)) || []);
      const goc = await ev(`JSON.stringify(S.f)`);
      // danh sách nút trên trang (theo thứ tự), không bấm nút có chữ ghi / xoá / tạo / tải…
      const nut = await ev(`(()=>{const P=$('#page'),L=[...P.querySelectorAll('button,.m-k.click,[onclick],select')].filter(e=>e.offsetParent&&!e.closest('tr.click td input'));
        window.__nut=L;return L.map((e,i)=>({i,t:(e.tagName==='SELECT'?'[chọn] '+(e.options[e.selectedIndex]||{}).text:(e.innerText||e.title||e.getAttribute('aria-label')||'').replace(/\\s+/g,' ').trim()).slice(0,60),tag:e.tagName,tr:!!e.closest('tr'),on:/(^| )(on|active)( |$)/.test(e.className||''),oc:(e.getAttribute('onclick')||'').slice(0,80)}))})()`) || [];
      // dòng bảng (tr.click): chỉ thử dòng đầu mỗi bảng
      const seen = new Set();
      for (const x of nut) {
        if (x.tr && x.tag !== 'SELECT') { const key = 'tr'; if (seen.has(key)) continue; seen.add(key); }
        if (!x.t && x.tag !== 'SELECT') continue; if (BO.test(x.t)) { r.nut.push({ t: x.t, kq: 'bỏ qua (nút ghi / tải)' }); continue; }
        if (r.nut.length > 60) break; if (x.on) { r.nut.push({ t: x.t, kq: 'đang chọn' }); continue; }
        const truoc = await ev(`({h:(()=>{const s=document.body.innerHTML;let h=0;for(let i=0;i<s.length;i+=3)h=(h*31+s.charCodeAt(i))|0;return h})(),m:!!$('#modal'),m2:!!$('#modal2')})`);
        await ev(`window.__evt=[];window.__chan=[];(()=>{const L=window.__nut||[];const e=L[${x.i}];if(!e||!e.isConnected)return 'mat';if(e.tagName==='SELECT'){const o=[...e.options].findIndex((z,j)=>j!==e.selectedIndex);if(o<0)return 'mat';e.selectedIndex=o;e.dispatchEvent(new Event('change',{bubbles:true}));return}e.click()})()`, 20000);
        await yen(10000);
        const sau = await ev(`({h:(()=>{const s=document.body.innerHTML;let h=0;for(let i=0;i<s.length;i+=3)h=(h*31+s.charCodeAt(i))|0;return h})(),m:!!$('#modal'),m2:!!$('#modal2'),e:window.__evt.slice(),c:window.__chan.slice(),q:window.__qa.splice(0),dd:!!document.querySelector('.tb-menu-dd.open,.dd.open,.tb-dd.open')})`);
        let kq = sau.q.length ? 'LỖI: ' + sau.q.map(z => z.join(' ')).join(' | ') : sau.c.length ? 'gọi ghi (đã chặn): ' + sau.c.join(',') : (sau.m && !truoc.m) || (sau.m2 && !truoc.m2) ? 'mở cửa sổ' : sau.h !== truoc.h ? 'trang đổi' : sau.e.length ? sau.e.join(',') : sau.dd ? 'mở menu' : /scrollIntoView/.test(x.oc) ? 'cuộn tới khối' : 'KHÔNG PHẢN ỨNG';
        r.nut.push({ t: x.t, kq, oc: x.oc });
        // về trạng thái gốc
        const doi = await ev(`(()=>{const c=!!$('#modal')||!!$('#modal2');closeModal&&closeModal();dong2&&dong2();document.querySelectorAll('.open').forEach(e=>e.classList.remove('open'));return c})()`);
        if (sau.h !== truoc.h || (await ev(`JSON.stringify(S.f)`)) !== goc) {
          await ev(`S.f=JSON.parse(${JSON.stringify(goc)});go('${k}')`); await yen();
          await ev(`(()=>{const P=$('#page');window.__nut=[...P.querySelectorAll('button,.m-k.click,[onclick],select')].filter(e=>e.offsetParent&&!e.closest('tr.click td input'))})()`);
        }
      }
      KQ.push(r);
      const xau = r.nut.filter(z => /^LỖI|KHÔNG PHẢN ỨNG/.test(z.kq));
      console.log(`${k} (${ten}) · cơ sở: ${r.cs} · ${r.nut.length} nút · lỗi trang ${r.loi.length} · nút lỗi / chết ${xau.length}${xau.length ? ' → ' + xau.map(z => z.t.slice(0, 40) + ' [' + z.kq.slice(0, 80) + (z.kq === 'KHÔNG PHẢN ỨNG' ? ' · ' + z.oc : '') + ']').join(' ; ') : ''}${r.loi.length ? ' · ' + JSON.stringify(r.loi).slice(0, 200) : ''}`);
      fs.writeFileSync(OUT, JSON.stringify(KQ, null, 1));
    }
  } catch (e) { console.log('LỖI', e.message); }
  finally { try { ws && ws.close(); } catch (e) {} try { ed.kill(); } catch (e) {} await tatTrinhDuyet(dir); await xoaTam('tam-ra'); console.log('xong · kết quả', OUT); }
})();
