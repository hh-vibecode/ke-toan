// Nhập CHI tháng 1–4/2026 (anh 09/10/2026: "auke gán đi") — Monsieur Claude
// Nguồn: file Đề nghị thanh toán — tab "NĂM 2025", "THÁNG 1..4.2026", tab chính (cột nhận theo TÊN tiêu đề vì mỗi tab xếp cột khác)
//   + tab 7.DATA CHI (khoản kế toán ghi thẳng từ sao kê, không có trong đề nghị). Chỉ phiếu "Đã thanh toán" có ngày TT trong khoảng.
// Loại chi: lấy theo sheet nếu có; không có → TỰ GÁN theo mẫu T5–T9 (scripts/gan-loai-chi.js), ghi chú "[Claude gán loại chi — tin cao/vừa/thấp]".
// Thiếu TK chi / ngày TT → "Chờ thanh toán" cho kế toán bổ sung. Đã có trên app (nội dung + số tiền + ngày) → bỏ qua.
// Chạy: Code.exe scripts/nhap-chi-t1-4.js <thư mục s1> <thư mục s2> [tu=2026-01-01] [den=2026-05-01] [ghi]
const fs = require('fs'), path = require('path'); const { sql } = require('./sql'); const { hoc, gan } = require('./gan-loai-chi');
const a = process.argv.slice(2); const GHI = a.includes('ghi'); const [S1, S2, TU = '2026-01-01', DEN = '2026-05-01'] = a.filter(x => x !== 'ghi' && x !== 'tao_tk');
const XL = path.join(path.dirname(S1), 'xl.js');
const src = fs.readFileSync(XL, 'utf8').replace(/if\(mode===[\s\S]*$/, 'module.exports={sheets,load};');
const nap = dir => { const m = new module.constructor(); m.paths = module.paths; const o = process.argv[2]; process.argv[2] = dir; m._compile(src, XL + Math.random() + '.js'); process.argv[2] = o; return m.exports; };
const F1 = nap(S1), F2 = nap(S2);
const ngay = v => v === undefined || v === '' || isNaN(+v) || +v < 40000 ? null : new Date(Date.UTC(1899, 11, 30) + Math.floor(+v) * 864e5).toISOString().slice(0, 10);
const luc = v => v === undefined || v === '' || isNaN(+v) || +v < 40000 ? null : new Date(Date.UTC(1899, 11, 30) + (+v) * 864e5 - 7 * 3600e3).toISOString();
const so = v => { const t = String(v ?? '').trim(); if (/^-?\d+(\.\d+)?(e[+-]?\d+)?$/i.test(t)) return Math.round(+t); const n = Math.round(+t.replace(/[^\d-]/g, '')); return isNaN(n) ? 0 : n; };
const sach = v => { v = String(v ?? '').trim(); return !v || v === '0' || v === '.' || v === '0.0' ? null : v; };
const chuan = s => String(s ?? '').normalize('NFC').toLowerCase().replace(/\s+/g, ' ').replace(/\s*-\s*/g, '-').trim();
const khoa = (nd, tien) => chuan(nd).replace(/[^a-z0-9à-ỹđ]/g, '') + '|' + tien;
const f = n => Math.round(n).toLocaleString('vi-VN'), J = x => '$kt$' + JSON.stringify(x) + '$kt$';
const trong = d => d && d >= TU && d < DEN, link = x => /^https?:/.test(String(x || '')) ? String(x).trim() : null;
// đọc 1 tab theo tên tiêu đề cột
const COT = { ts: /dấu thời gian/i, nguoi: /họ & tên/i, bp: /bộ phận/i, nd: /nội dung chi/i, sd: /ngày sử dụng/i, tien: /số tiền/i, th: /tên người|người thụ hưởng|^6\./i,
  nh: /thông tin ngân hàng/i, stk: /stk/i, dv: /đơn vị chịu/i, han: /mong muốn/i, hd: /hoá đơn đỏ|hóa đơn đỏ|có hoá đơn|có hóa đơn/i, gc: /^12\.|ghi chú/i,
  duyet: /^người duyệt/i, trangDuyet: /trạng thái phê duyệt/i, lucDuyet: /thời gian phê duyệt/i, tt: /trạng thái thanh toán/i, ngayTT: /ngày thanh toán/i,
  tk: /tài khoản chi/i, loai: /loại chi/i, unc: /uỷ nhiệm chi|ủy nhiệm chi|unc/i, nhanHD: /tình trạng nhận/i, ngayNhan: /ngày nhận/i };
function docTab(F, ten) {
  const sh = F.sheets.find(s => s.name === ten); if (!sh) return [];
  const r = F.load(sh), ns = Object.keys(r).map(Number).sort((x, y) => x - y);
  const hr = ns.slice(0, 4).find(n => Object.values(r[n]).some(c => /nội dung chi/i.test(String(c.v)))); if (!hr) return [];
  const map = {}; for (const [c, v] of Object.entries(r[hr])) { const t = String(v.v || '').trim();
    for (const [k, re] of Object.entries(COT)) if (re.test(t) && !(k in map)) { if (k === 'gc' && /hồ sơ/i.test(t)) continue; map[k] = c; } }
  const hs = Object.entries(r[hr]).filter(([, v]) => /hồ sơ đính kèm/i.test(String(v.v))).map(([c]) => c);
  return ns.filter(n => n > hr).map(n => { const o = {}; for (const k in map) { const v = r[n][map[k]]; o[k] = v ? (typeof v.v === 'string' ? v.v.trim() : v.v) : undefined; }
    o.hs = hs.map(c => r[n][c] && link(r[n][c].v)).filter(Boolean); o._r = n; o._tab = ten; return o; });
}
(async () => {
  const dm = { tk: await sql('select id, ten, ten_cu from kt_tai_khoan'), dv: await sql('select id, ten, ten_cu from kt_don_vi'), lo: await sql("select id, ten from kt_loai where nhom = 'chi'") };
  const tim = (ds, t) => { const c = chuan(t); return ds.find(x => chuan(x.ten) === c || (x.ten_cu || []).some(y => chuan(y) === c)); };
  const co = await sql(`select noi_dung, so_tien::bigint so_tien, ngay_su_dung::text sd, ngay_tt::text tt from kt_chi where not da_xoa`);
  const daCo = new Set(co.flatMap(x => [khoa(x.noi_dung, +x.so_tien) + '|' + x.sd, khoa(x.noi_dung, +x.so_tien) + '|tt' + x.tt]));
  // mẫu học loại chi: phiếu đã trả T5–T10 có loại
  const mau = await sql(`select c.noi_dung, c.thu_huong_ten, l.ten loai, c.so_tien, (select ten from kt_don_vi where id = c.bo_phan_id) bo_phan,
    array(select d.ten from jsonb_array_elements(c.phan_bo) e join kt_don_vi d on d.id = (e->>'don_vi_id')::int) don_vi
    from kt_chi c join kt_loai l on l.id = c.loai_id where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt >= '2026-05-01'`);
  const md = hoc(mau); console.log('Mẫu học loại chi:', mau.length, 'phiếu (T5 trở đi)');
  const bao = [], B = (...x) => bao.push(x.join(' ')), tkThieu = new Set();
  // ── 1. file Đề nghị ──
  const tabs = ['ĐỀ NGHỊ THANH TOÁN', 'NĂM 2025', ...[1, 2, 3, 4, 5].map(m => `THÁNG ${m}.2026`)];
  const daLay = new Set(), chi = []; let trung = 0, thieu = 0; const tinDem = { cao: 0, vua: 0, thap: 0 };
  const them = (o, nguon) => {
    const tien = o.tien, dTT = o.ngayTT;
    if (daCo.has(khoa(o.nd, tien) + '|' + o.sd) || (dTT && daCo.has(khoa(o.nd, tien) + '|tt' + dTT))) { trung++; return; }
    const tk = o.tk ? tim(dm.tk, o.tk) : null; let lo = o.loai ? tim(dm.lo, o.loai) : null, ghi = o.gc ? String(o.gc) : null, st = 'da_tt';
    const dvs = String(o.dv || '').split(',').map(x => x.trim()).filter(Boolean).map(x => tim(dm.dv, x) || tim(dm.dv, 'Khác'));
    const bp = o.bp ? tim(dm.dv, o.bp) : null;
    if (!lo) { const g = gan(md, { noi_dung: o.nd, thu_huong_ten: o.th, so_tien: tien, bo_phan: bp && bp.ten, don_vi: dvs.map(d => d.ten) });
      if (g.loai) { lo = tim(dm.lo, g.loai); tinDem[g.tin]++; ghi = `[Claude gán loại chi — tin ${g.tin === 'vua' ? 'vừa' : g.tin === 'thap' ? 'thấp' : 'cao'} (${g.cach})]` + (ghi ? ' ' + ghi : ''); } }
    if (!dTT || !tk || !lo) { st = 'cho_tt'; thieu++; ghi = '[Sheet cũ ghi Đã thanh toán nhưng thiếu ' + [!dTT && 'ngày TT', !tk && 'TK chi', !lo && 'loại chi'].filter(Boolean).join(', ') + ' — kế toán bổ sung]' + (ghi ? ' ' + ghi : ''); }
    if (o.tk && !tk) { B('  TK chi không ghép:', String(o.tk).replace(/\d{5,}/g, '#')); tkThieu.add(String(o.tk).trim()); }
    const pb = dvs.map((d, i) => ({ don_vi_id: d.id, so_tien: i < dvs.length - 1 ? Math.floor(tien / dvs.length) : tien - Math.floor(tien / dvs.length) * (dvs.length - 1) }));
    chi.push({ ngay_de_nghi: o.ts || o.sd || dTT, nguoi_de_nghi: o.nguoi ? String(o.nguoi).trim() : 'Không rõ (sheet)', bo_phan_id: bp ? bp.id : null, noi_dung: String(o.nd || '').slice(0, 500),
      ngay_su_dung: o.sd, so_tien: tien, thu_huong_ten: sach(o.th), thu_huong_nh: sach(o.nh), thu_huong_stk: sach(o.stk), phan_bo: pb, han_tt: o.han, co_hd_do: /^có/i.test(String(o.hd || '').trim()),
      ghi_chu: ghi, chung_tu: o.hs || [], trang_thai: st, nguoi_duyet: sach(o.duyet), duyet_luc: o.lucDuyet, ngay_tt: st === 'da_tt' ? dTT : null, tai_khoan_id: tk ? tk.id : null,
      loai_id: lo ? lo.id : null, unc: o.unc || null, hd_do_nhan: /đã nhận/i.test(String(o.nhanHD || '')), ngay_nhan_hd: o.ngayNhan || null,
      ma_nguon: nguon, _t: (dTT || o.ts || '').slice(0, 7) });
  };
  const dnKhoa = new Set();
  for (const ten of tabs) for (const r of docTab(F1, ten)) {
    if (!r.tien || !(r.nd || r.nguoi) || r.tt !== 'Đã thanh toán') continue;
    const dTT = ngay(r.ngayTT); if (!trong(dTT)) continue;
    const tien = so(r.tien), k = (r.ts || '') + '|' + tien + '|' + chuan(r.nd); if (daLay.has(k)) continue; daLay.add(k);
    dnKhoa.add(khoa(r.nd, tien) + '|' + dTT);
    them({ ts: ngay(r.ts), nguoi: r.nguoi, bp: r.bp, nd: r.nd, sd: ngay(r.sd), tien, th: r.th, nh: r.nh, stk: r.stk, dv: r.dv, han: ngay(r.han), hd: r.hd, gc: r.gc, hs: r.hs,
      duyet: r.duyet, lucDuyet: luc(r.lucDuyet), ngayTT: dTT, tk: r.tk, loai: r.loai && !link(r.loai) ? r.loai : null, unc: link(r.unc) || (r.loai && link(r.loai)), nhanHD: r.nhanHD, ngayNhan: ngay(r.ngayNhan) },
      'dn14:' + r._tab.replace(/\W+/g, '') + ':' + r._r + ':' + tien);
  }
  const tuDn = chi.length;
  // ── 2. DATA CHI: khoản không có trong đề nghị ──
  const dch = F2.load(F2.sheets.find(s => s.name === '7.DATA CHI'));
  for (const n of Object.keys(dch).map(Number).filter(n => n >= 3)) {
    const o = Object.fromEntries(Object.entries(dch[n]).map(([k, v]) => [k, typeof v.v === 'string' ? v.v.trim() : v.v]));
    if (o.R !== 'Đã thanh toán' || !o.D) continue; const dTT = ngay(o.S); if (!trong(dTT)) continue;
    const tien = so(o.D); if (dnKhoa.has(khoa(o.B, tien) + '|' + dTT)) continue;
    them({ nguoi: null, bp: o.A, nd: o.B, sd: ngay(o.C), tien, th: o.E, nh: o.F, stk: o.G, dv: o.H, han: ngay(o.I), hd: o.J, gc: o.K, hs: [o.L, o.M, o.N].map(link).filter(Boolean),
      duyet: o.O, lucDuyet: luc(o.Q), ngayTT: dTT, tk: o.T, loai: o.U }, 'datachi_kh:' + dTT + ':' + tien + ':' + n);
  }
  const tt = {}; chi.forEach(x => { const t = tt[x._t] = tt[x._t] || { n: 0, tien: 0, cho: 0 }; t.n++; if (x.trang_thai === 'da_tt') t.tien += x.so_tien; else t.cho++; });
  console.log(`CHI sẽ nhập ${chi.length} phiếu (đề nghị ${tuDn} + chỉ có ở DATA CHI ${chi.length - tuDn}) · bỏ vì đã có ${trung} · chờ bổ sung ${thieu}`);
  console.log('Tự gán loại:', JSON.stringify(tinDem));
  Object.keys(tt).sort().forEach(t => console.log('  ', t, tt[t].n, 'phiếu · đã trả', f(tt[t].tien), tt[t].cho ? '· ' + tt[t].cho + ' chờ bổ sung' : ''));
  if (bao.length) console.log([...new Set(bao)].slice(0, 20).join('\n'));
  // tao_tk: thêm tài khoản cũ T1–T4 còn thiếu vào danh mục (NGỪNG DÙNG; số dư không tính — mốc số dư 01/09) rồi chạy lại
  if (a.includes('tao_tk')) { for (const t of tkThieu) await sql(`insert into kt_tai_khoan (ten, hoat_dong, thu_tu) select ${J(t)}::jsonb#>>'{}', false, 900
      where not exists (select 1 from kt_tai_khoan where ten = ${J(t)}::jsonb#>>'{}')`);
    return console.log('Đã thêm', tkThieu.size, 'tài khoản cũ (ngừng dùng) vào danh mục'); }
  if (process.env.KT_DUMP) fs.writeFileSync(process.env.KT_DUMP, JSON.stringify(chi));
  if (!GHI) return console.log('(CHẠY THỬ — chưa ghi)');
  for (let i = 0; i < chi.length; i += 200) await sql(`insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, thu_huong_nh,
      thu_huong_stk, phan_bo, han_tt, co_hd_do, ghi_chu, chung_tu, trang_thai, nguoi_duyet, duyet_luc, ngay_tt, tai_khoan_id, loai_id, unc, hd_do_nhan, ngay_nhan_hd, nguon, ma_nguon, tao_boi)
    select ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, thu_huong_nh, thu_huong_stk, phan_bo, han_tt, co_hd_do, ghi_chu,
      array(select jsonb_array_elements_text(chung_tu)), trang_thai, nguoi_duyet, duyet_luc, ngay_tt, tai_khoan_id, loai_id, unc, coalesce(hd_do_nhan,false), ngay_nhan_hd, 'sheet_cu', ma_nguon, 'Chuyển từ sheet (${TU}→${DEN})'
    from jsonb_to_recordset(${J(chi.slice(i, i + 200))}::jsonb) as x(ngay_de_nghi date, nguoi_de_nghi text, bo_phan_id int, noi_dung text, ngay_su_dung date, so_tien numeric,
      thu_huong_ten text, thu_huong_nh text, thu_huong_stk text, phan_bo jsonb, han_tt date, co_hd_do boolean, ghi_chu text, chung_tu jsonb, trang_thai text, nguoi_duyet text,
      duyet_luc timestamptz, ngay_tt date, tai_khoan_id int, loai_id int, unc text, hd_do_nhan boolean, ngay_nhan_hd date, ma_nguon text)
    on conflict (ma_nguon) do nothing`);
  await sql(`insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Monsieur Claude', 'kt_chi', 'nhap_chi_t1_4', ${J({ tu: TU, den: DEN, chi: chi.length, gan: tinDem, thieu })}::jsonb)`);
  console.log('ĐÃ GHI.');
})().catch(e => { console.error('DỪNG', e.message); process.exit(1); });
