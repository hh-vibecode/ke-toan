// Nhập CHI (tab 7.DATA CHI + bổ sung từ file Đề nghị thanh toán) + ĐIỀU CHUYỂN (file Quản lý dòng tiền) của 1 KHOẢNG NGÀY cũ vào app — 09/10/2026,
// anh: "xử lý hết số liệu 2026, thu chi đề nghị tt có hết ở gg sheet". Cùng luật với lần nhập tháng 9 (05/10).
// Chạy: Code.exe scripts/nhap-sheet-khoang.js <thư mục s1 giải nén> <thư mục s2 giải nén> <từ> <đến (không gồm)> [ghi]
//   - Chi: phiếu "Đã thanh toán" có NGÀY TT trong khoảng — nguồn tab 7.DATA CHI (đối chiếu 09/10: tab này đủ hơn file Đề nghị — có khoản ghi thẳng từ sao kê).
//     Thiếu TK chi / loại chi → để "Chờ thanh toán" + ghi chú cho kế toán bổ sung. Đã có trên app (nội dung + số tiền + ngày) → bỏ qua.
//   - Điều chuyển: tab 8.DATA ĐIỀU CHUYỂN, ngày trong khoảng.
//   - Thu: 5.TH THU-CHI tháng 5–8 chỉ có điều chuyển nội bộ (không có thu ngoài Kiot) → thu lấy từ Kiot (scripts/keo-kiot-cu.js).
// Không in số tài khoản / khoá. Monsieur Claude
const fs = require('fs'), path = require('path');
const { sql } = require('./sql');
const [S1, S2, TU, DEN, CHE_DO] = process.argv.slice(2); const GHI = CHE_DO === 'ghi';
if (!S1 || !S2 || !TU || !DEN) { console.log('thiếu tham số'); process.exit(1); }
const XL = path.join(path.dirname(S1), 'xl.js');
const src = fs.readFileSync(XL, 'utf8').replace(/if\(mode===[\s\S]*$/, 'module.exports={sheets,load};');
const nap = dir => { const m = new module.constructor(); m.paths = module.paths; const a = process.argv[2]; process.argv[2] = dir; m._compile(src, XL + Math.random() + '.js'); process.argv[2] = a; return m.exports; };
const F1 = nap(S1), F2 = nap(S2);
const tab = (F, ten, tu) => { const sh = F.sheets.find(s => s.name === ten); if (!sh) return []; const r = F.load(sh);
  return Object.keys(r).map(Number).filter(n => n >= tu).sort((a, b) => a - b)
  .map(n => ({ _r: n, ...Object.fromEntries(Object.entries(r[n]).map(([k, v]) => [k, typeof v.v === 'string' ? v.v.trim() : v.v])) })); };
const ngay = v => v === undefined || v === '' || isNaN(+v) || +v < 40000 ? null : new Date(Date.UTC(1899, 11, 30) + Math.floor(+v) * 864e5).toISOString().slice(0, 10);
const luc = v => v === undefined || v === '' || isNaN(+v) || +v < 40000 ? null : new Date(Date.UTC(1899, 11, 30) + (+v) * 864e5 - 7 * 3600e3).toISOString();
const so = v => { const t = String(v ?? '').trim(); if (/^-?\d+(\.\d+)?(e[+-]?\d+)?$/i.test(t)) return Math.round(+t); const n = Math.round(+t.replace(/[^\d-]/g, '')); return isNaN(n) ? 0 : n; };
const sach = v => { v = String(v ?? '').trim(); return !v || v === '0' || v === '.' || v === '0.0' ? null : v; };
const chuan = s => String(s ?? '').normalize('NFC').toLowerCase().replace(/\s+/g, ' ').replace(/\s*-\s*/g, '-').trim();
const khoa = (nd, tien) => chuan(nd).replace(/[^a-z0-9à-ỹđ]/g, '') + '|' + tien;
const f = n => Math.round(n).toLocaleString('vi-VN'), J = x => '$kt$' + JSON.stringify(x) + '$kt$';
const trong = d => d && d >= TU && d < DEN;

(async () => {
  const dm = { tk: await sql('select id, ten, ten_cu from kt_tai_khoan'), dv: await sql('select id, ten, ten_cu from kt_don_vi'), lo: await sql('select id, nhom, ten from kt_loai') };
  const tim = (ds, t) => { const c = chuan(t); return ds.find(x => chuan(x.ten) === c || (x.ten_cu || []).some(y => chuan(y) === c)); };
  const timLo = (n, t) => dm.lo.find(x => x.nhom === n && chuan(x.ten) === chuan(t));
  const co = await sql(`select noi_dung, so_tien::bigint so_tien, ngay_su_dung::text sd, ngay_tt::text tt from kt_chi where not da_xoa`);
  const daCo = new Set(co.flatMap(x => [khoa(x.noi_dung, +x.so_tien) + '|' + x.sd, khoa(x.noi_dung, +x.so_tien) + '|tt' + x.tt]));
  const bao = [], B = (...a) => bao.push(a.join(' '));

  // ── CHI: nguồn chính = tab 7.DATA CHI (file dòng tiền — có cả khoản kế toán ghi thẳng từ sao kê, ngày TT cập nhật nhất; báo cáo sheet dựa vào tab này).
  //    Lấy thêm người đề nghị / ngày đề nghị / link UNC / đã nhận HĐ từ file Đề nghị (tab chính + tab tháng), ghép theo nội dung + số tiền.
  const dnMap = new Map(), daLay = new Set();
  const nguon = [['ĐỀ NGHỊ THANH TOÁN', 'dntt']]; for (let m = 1; m <= 12; m++) nguon.push([`THÁNG ${m}.2026`, 'dnt' + m]);
  for (const [ten] of nguon) for (const r of tab(F1, ten, 3).filter(r => r.G && r.E)) {
    const k = khoa(r.E, so(r.G)), kk = (r.A || '') + '|' + k; if (daLay.has(kk)) continue; daLay.add(kk);
    (dnMap.get(k) || dnMap.set(k, []).get(k)).push(r); }
  const chi = []; let thieu = 0, trung = 0, coDn = 0;
  for (const r of tab(F2, '7.DATA CHI', 3).filter(r => r.D && (r.B || r.A))) {
    const dTT = ngay(r.S);
    if (r.R !== 'Đã thanh toán' || !trong(dTT)) continue;
    const tien = so(r.D), kc = khoa(r.B, tien);
    if (daCo.has(kc + '|' + ngay(r.C)) || daCo.has(kc + '|tt' + dTT)) { trung++; continue; }
    const ung = dnMap.get(kc) || []; const dn = ung.find(x => ngay(x.V) === dTT) || ung.find(x => ngay(x.F) === ngay(r.C)) || ung[0];
    if (dn) { ung.splice(ung.indexOf(dn), 1); coDn++; }
    const tk = r.T ? tim(dm.tk, r.T) : null, lo = r.U ? timLo('chi', r.U) : null; let ghi = r.K ? String(r.K) : null, st = 'da_tt';
    if (!tk || !lo) { st = 'cho_tt'; thieu++;
      ghi = '[Sheet cũ ghi Đã thanh toán nhưng thiếu ' + [!tk && 'TK chi', !lo && 'loại chi'].filter(Boolean).join(', ') + ' — kế toán bổ sung]' + (ghi ? ' ' + ghi : ''); }
    if (r.T && !tk) B('  TK chi không ghép được:', String(r.T).replace(/\d{5,}/g, '#'));
    if (r.U && !lo) B('  loại chi không ghép được:', r.U);
    const dvs = String(r.H || '').split(',').map(x => x.trim()).filter(Boolean).map(x => tim(dm.dv, x) || tim(dm.dv, 'Khác'));
    const pb = dvs.map((d, i) => ({ don_vi_id: d.id, so_tien: i < dvs.length - 1 ? Math.floor(tien / dvs.length) : tien - Math.floor(tien / dvs.length) * (dvs.length - 1) }));
    const bp = r.A ? tim(dm.dv, r.A) : null;
    const unc = dn ? [dn.Y, dn.X].find(x => /^https?:/.test(String(x || ''))) || null : null;
    chi.push({ ngay_de_nghi: (dn && ngay(dn.A)) || ngay(r.Q) || ngay(r.C) || dTT, nguoi_de_nghi: dn && dn.C ? String(dn.C).trim() : 'Không rõ (sheet)', bo_phan_id: bp ? bp.id : null,
      noi_dung: String(r.B || '').slice(0, 500), ngay_su_dung: ngay(r.C), so_tien: tien, thu_huong_ten: sach(r.E), thu_huong_nh: sach(r.F), thu_huong_stk: sach(r.G), phan_bo: pb,
      han_tt: ngay(r.I), co_hd_do: /^có/i.test(String(r.J || '').trim()), ghi_chu: ghi, chung_tu: [r.L, r.M, r.N].filter(x => /^https?:/.test(String(x || ''))),
      trang_thai: st, nguoi_duyet: sach(r.O), duyet_luc: luc(r.Q), ngay_tt: st === 'da_tt' ? dTT : null, tai_khoan_id: tk ? tk.id : null, loai_id: lo ? lo.id : null,
      unc, hd_do_nhan: dn ? /đã nhận/i.test(String(dn.Z || '')) : false, ngay_nhan_hd: dn ? ngay(dn.AA) : null,
      ma_nguon: 'datachi_kh:' + dTT + ':' + tien + ':' + r._r, _t: dTT.slice(0, 7) });
  }
  console.log('Ghép được người đề nghị từ file Đề nghị:', coDn, '/', chi.length);
  const theoThang = {}; chi.forEach(x => { const t = theoThang[x._t] = theoThang[x._t] || { n: 0, tien: 0, cho: 0 }; t.n++; t.tien += x.so_tien; if (x.trang_thai !== 'da_tt') t.cho++; });
  console.log('CHI sẽ nhập', chi.length, 'phiếu · bỏ vì đã có trên app', trung, '· thiếu thông tin → Chờ TT', thieu);
  Object.keys(theoThang).sort().forEach(t => console.log('  ', t, theoThang[t].n, 'phiếu', f(theoThang[t].tien), theoThang[t].cho ? '(' + theoThang[t].cho + ' chờ bổ sung)' : ''));

  // ── ĐIỀU CHUYỂN ──
  const dc = [];
  for (const r of tab(F2, '8.DATA ĐIỀU CHUYỂN', 3).filter(r => r.A && r.C && trong(ngay(r.A)))) {
    const a = tim(dm.tk, r.D), b = tim(dm.tk, r.E);
    if (!a || !b) { B('  điều chuyển r' + r._r + ' không ghép TK:', String(!a ? r.D : r.E).replace(/\d{5,}/g, '#')); continue; }
    if (a.id === b.id) continue;
    dc.push({ ngay: ngay(r.A), noi_dung: String(r.B || 'Điều chuyển').slice(0, 300), so_tien: so(r.C), tk_di_id: a.id, tk_nhan_id: b.id, ghi_chu: r.F ? String(r.F) : null,
      ma_nguon: 'sheet_dc:' + ngay(r.A) + ':' + so(r.C) + ':' + a.id + '-' + b.id + ':' + r._r });
  }
  console.log('ĐIỀU CHUYỂN sẽ nhập', dc.length, 'lần ·', f(dc.reduce((s, x) => s + x.so_tien, 0)));
  if (bao.length) console.log(bao.slice(0, 30).join('\n'));
  if (process.env.KT_DUMP) fs.writeFileSync(process.env.KT_DUMP, JSON.stringify({ chi, dc }));   // để đối chiếu từng phiếu
  if (!GHI) return console.log('(CHẠY THỬ — chưa ghi)');

  for (let i = 0; i < chi.length; i += 200) await sql(`insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, thu_huong_nh,
      thu_huong_stk, phan_bo, han_tt, co_hd_do, ghi_chu, chung_tu, trang_thai, nguoi_duyet, duyet_luc, ngay_tt, tai_khoan_id, loai_id, unc, hd_do_nhan, ngay_nhan_hd, nguon, ma_nguon, tao_boi)
    select ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, thu_huong_nh, thu_huong_stk, phan_bo, han_tt, co_hd_do, ghi_chu,
      array(select jsonb_array_elements_text(chung_tu)), trang_thai, nguoi_duyet, duyet_luc, ngay_tt, tai_khoan_id, loai_id, unc, coalesce(hd_do_nhan,false), ngay_nhan_hd, 'sheet_cu', ma_nguon, 'Chuyển từ sheet (${TU}→${DEN})'
    from jsonb_to_recordset(${J(chi.slice(i, i + 200))}::jsonb) as x(ngay_de_nghi date, nguoi_de_nghi text, bo_phan_id int, noi_dung text, ngay_su_dung date, so_tien numeric,
      thu_huong_ten text, thu_huong_nh text, thu_huong_stk text, phan_bo jsonb, han_tt date, co_hd_do boolean, ghi_chu text, chung_tu jsonb, trang_thai text, nguoi_duyet text,
      duyet_luc timestamptz, ngay_tt date, tai_khoan_id int, loai_id int, unc text, hd_do_nhan boolean, ngay_nhan_hd date, ma_nguon text)
    on conflict (ma_nguon) do nothing`);
  if (dc.length) await sql(`insert into kt_dieu_chuyen (ngay, noi_dung, so_tien, tk_di_id, tk_nhan_id, ghi_chu, da_xac_nhan, xac_nhan_boi, nguon, ma_nguon, tao_boi)
    select ngay, noi_dung, so_tien, tk_di_id, tk_nhan_id, ghi_chu, true, 'Sheet cũ', 'sheet_cu', ma_nguon, 'Chuyển từ sheet (${TU}→${DEN})'
    from jsonb_to_recordset(${J(dc)}::jsonb) as x(ngay date, noi_dung text, so_tien numeric, tk_di_id int, tk_nhan_id int, ghi_chu text, ma_nguon text)
    on conflict (ma_nguon) do nothing`);
  await sql(`insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Monsieur Claude', 'kt_chi', 'nhap_sheet_khoang', ${J({ tu: TU, den: DEN, chi: chi.length, dc: dc.length, thieu })}::jsonb)`);
  console.log('ĐÃ GHI.');
})().catch(e => { console.error('DỪNG', e.message); process.exit(1); });
