// Đối chiếu đề nghị thanh toán (app, T1–T8) ↔ chi phí công ty (file CHI PHÍ CÔNG TY THÁNG n) ↔ 4 P&L (Hiền Thủy, Chánh Tâm, Shidai T1–T8; Thị trường T1–T6)
// anh 21/10/2026: "kéo 4 PnL về (chỉ tab BÁO CÁO P&L, tab khác kệ), đối chiếu tất cả đề nghị thanh toán với toàn bộ chi phí công ty và 4 PnL, thống kê dữ liệu chưa khớp T1–T8".
//  A. 4 P&L: tab BÁO CÁO P&L — mỗi tháng 4 cột TARGET · % · THỰC HIỆN · %, cột A = mã mục (1, 1.1 …), cột B = tên → bảng kt_pnl_cu (để tạm)
//     So với chi phí hạch toán trên app (kt_v_chi_ht) cùng tháng · cùng đơn vị (HT=2, CT=3, SD=4+5, TT=6) · cùng mã mục → kt_dcp_pnl
//  B. Chi phí công ty T1–T8 (các sheet bảng chi + CP RIÊNG TỪNG CƠ SỞ) ↔ đề nghị thanh toán: ghép từng dòng (cùng số tiền, ngày lệch ≤ 10 ngày, nội dung giống) → kt_dcp_dong / kt_dcp_phieu
// Xem trên app: Hệ thống → Nhật ký so khớp → tab P&L T1–T8. Chạy: Code.exe scripts/doi-chieu-pnl.js [ghi] — Monsieur Claude
const fs = require('fs'), os = require('os'), path = require('path'), { execFileSync } = require('child_process');
const { docXlsx } = require('./doc-xlsx'), { sql } = require('./sql');
const GHI = process.argv[2] === 'ghi', RC = path.join(os.homedir(), 'tools', 'rclone', 'rclone.exe');
const PNL = [['HT', '192-kqBBmsUXVHBOiljiAR9amG3bHYfvUjvImj-VX1QE', 8, [2]], ['CT', '1iTpFWKGBo5FunVDz6tKgyI4o3mD0Lv9kzq_Dkd0mgHM', 8, [3]],
  ['SD', '11eZdTT13lPx7Myq1QpOVu5KOnchnnkdoHPRq0SVBkJU', 8, [4, 5]], ['TT', '1q6uKgBXugC2OlohO5mnYvTcYS2gCN368zpZEGkBw-vk', 6, [6]]];
const THU_MUC_CP = '17A8xhElMSnVpbN0pSC2ETHBRg6mk65hX';
const bo = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D').toLowerCase();
const so = v => { if (v == null || v === '') return null; const n = typeof v === 'number' ? v : +String(v).replace(/[^\d.-]/g, ''); return isFinite(n) ? Math.round(n) : null; };
const ngayEx = v => { if (v == null || v === '') return null; if (/^\d+(\.\d+)?$/.test(String(v))) { const d = new Date(Date.UTC(1899, 11, 30) + Math.floor(+v) * 864e5); return d.toISOString().slice(0, 10); }
  const m = String(v).match(/(\d{1,2})\/(\d{1,2})\/(\d{4})/); return m ? `${m[3]}-${m[1].padStart(2, '0')}-${m[2].padStart(2, '0')}` : null; };   // dạng m/d/yyyy của Google Sheets
const cot = i => { let s = ''; i++; while (i > 0) { const m = (i - 1) % 26; s = String.fromCharCode(65 + m) + s; i = Math.floor((i - 1) / 26); } return s; };   // 0 → A
const tai = (id, dir, laThuMuc) => { fs.mkdirSync(dir, { recursive: true });
  if (laThuMuc) execFileSync(RC, ['copy', 'ktdrive2:', dir, '--drive-root-folder-id', id, '--include', '*/CHI PHÍ CÔNG TY THÁNG*'], { stdio: 'pipe', timeout: 600000 });
  else execFileSync(RC, ['backend', 'copyid', 'ktdrive2:', id, dir + path.sep, '--drive-export-formats', 'xlsx'], { stdio: 'pipe', timeout: 300000 });
  const all = []; const di = d => fs.readdirSync(d, { withFileTypes: true }).forEach(e => e.isDirectory() ? di(path.join(d, e.name)) : /\.xlsx$/i.test(e.name) && all.push(path.join(d, e.name))); di(dir); return all; };
// 22/10 anh: "so 2 cái khớp đấy (đề nghị + file chi phí) với P&L" — số file chi phí đã chia cho từng cơ sở (HT / CT / SD / TT) theo mục P&L:
//  dòng tiêu đề nhóm sheet CP TOÀN CÔNG TY (→ 4.3…4.11) · CP KHO KIẾN AN (→ 3.1…3.4, vật tư → 7.1) · dòng "TỔNG CHI PHÍ TỪNG CƠ SỞ" sheet CP MKT (→ 5)
//  · sheet LƯƠNG+BHXH (BGĐ → 4.1, HCNS/MKT → 4.2, lương cơ sở + hỗ trợ → 1.1, Sales Online → 2) · dòng tổng sheet CP GIAO VẬN (→ GV)
const CS_TEN = t => /hien thuy/.test(t) ? 'HT' : /chanh tam/.test(t) ? 'CT' : /shidai|^si /.test(t) ? 'SD' : /thi truong/.test(t) ? 'TT' : null;
const MA_CTY = [[/van phong/, '4.3'], [/phan mem/, '4.4'], [/ke toan/, '4.5'], [/ngan hang/, '4.6'], [/truyen thong cong ty/, '4.7'], [/truyen thong noi bo/, '4.8'], [/nghien cuu/, '4.9'], [/dao tao/, '4.10'], [/khac/, '4.11']];
const MA_KHO = [[/luong/, '3.1'], [/thue kho|mat bang/, '3.2'], [/vat tu|dong goi/, '7.1'], [/sua chua/, '3.3'], [/khac/, '3.4']];
function pbSheet(b, R, thang, out) {
  const rows = Object.keys(R).map(Number).sort((a, c) => a - c); let col = null;
  for (const r of rows) { const e = Object.entries(R[r]); if (e.some(([cc, v]) => cc > 'C' && /hien thuy/.test(bo(v)))) { col = {}; e.forEach(([cc, v]) => { const cs = cc > 'C' && CS_TEN(bo(v)); if (cs && !Object.values(col).includes(cs)) col[cc] = cs; }); break; } }
  if (!col) return;
  const ghi = (r, ma, nguon) => Object.entries(col).forEach(([cc, cs]) => { const v = so(R[r][cc]); if (v) out.push({ thang, cs, ma, so_tien: v, nguon }); });
  for (const r of rows) { const x = R[r], a = bo(x.A), c = bo(x.C);
    if (/toan cong ty/.test(b) && /^\d+\.\s*[^\d\s]/.test(a)) { const m = MA_CTY.find(([re]) => re.test(a)); if (m) ghi(r, m[1], sheetTen(b, x.A)); }
    else if (/kho kien an/.test(b) && /^\d+\.\s*[^\d\s]/.test(a)) { const m = MA_KHO.find(([re]) => re.test(a)); if (m) ghi(r, m[1], sheetTen(b, x.A)); }
    else if (/mkt/.test(b) && /tong chi phi tung co so/.test(a)) ghi(r, '5', 'CP MKT · tổng từng cơ sở');
    else if (/mkt/.test(b) && /online nen/.test(c)) ghi(r, '5-nen', 'CP MKT · ' + x.C);
    else if (/luong/.test(b) && !/tong/.test(a)) { const ma = /bgd/.test(c) ? '4.1' : /hcns|mkt/.test(c) ? '4.2' : /sale onl/.test(c) ? '2' : /hien thuy|chanh tam|bp si|thi truong|ho tro/.test(c) ? '1.1' : null; if (ma) ghi(r, ma, 'LƯƠNG+BHXH · ' + String(x.C).replace(/\n/g, ' ')); }
    else if (/giao van/.test(b) && /tong trong ki/.test(a)) ghi(r, 'GV', 'CP GIAO VẬN · tổng trong kì'); } }
const sheetTen = (b, a) => (/toan cong ty/.test(b) ? 'CP TOÀN CÔNG TY · ' : 'CP KHO KIẾN AN · ') + String(a);
(async () => {
  const goc = fs.mkdtempSync(path.join(os.tmpdir(), 'dcp-')), pnl = [], dong = [], pbcs = [];
  try {
    // ── A. tab BÁO CÁO P&L của 4 file
    for (const [ma, id, den] of PNL) {
      const F = docXlsx(tai(id, path.join(goc, ma))[0]);
      const sh = F.sheets.find(s => /^\d+\.\s*(bao cao|bc) p&l$/.test(bo(s.name))), R = F.load(sh);
      let n = 0;
      for (const r of Object.keys(R).map(Number).sort((a, b) => a - b)) { if (r < 4) continue; const x = R[r];
        const a = String(x.A || '').trim(), maMuc = /^\d+(\.\d+)*$/.test(a) ? a.replace(/\.0$/, '') : '', ten = String(maMuc ? x.B || '' : (x.B || x.A || '')).trim(); if (!ten) continue;
        for (let t = 1; t <= den; t++) { const c0 = 2 + (t - 1) * 4, tg = so(x[cot(c0)]), th = so(x[cot(c0 + 2)]); if (tg == null && th == null) continue;
          pnl.push({ nguon: ma, thang: '2026-' + String(t).padStart(2, '0'), dong: r, ma: maMuc, ten, target: tg, thuc_hien: th }); n++; } }
      F.xoa(); console.log(ma, sh.name, n, 'ô số');
    }
    // ── B. chi phí công ty T1–T8: các sheet dạng bảng chi (STT · ngày · nội dung · số tiền · nguồn) + CP RIÊNG TỪNG CƠ SỞ
    for (const f of tai(THU_MUC_CP, path.join(goc, 'CP'), true)) {
      const t = +(path.basename(f).match(/THÁNG (\d+)/) || [])[1]; if (!t || t > 8) continue;
      const F = docXlsx(f), thang = '2026-' + String(t).padStart(2, '0'); let n0 = dong.length;
      for (const sh of F.sheets) { const b = bo(sh.name); if (!/ti le|kho hn|rieng/.test(b)) pbSheet(b, F.load(sh), thang, pbcs);
        if (/luong|giao van|ti le|kho hn/.test(b)) continue; const R = F.load(sh);   // 22/10 anh: bỏ hết nhà hàng — CP KHO HN chỉ Saikung / Hongkong
        let h = null, nhom = '', pb = null;
        for (const r of Object.keys(R).map(Number).sort((a, c) => a - c)) { const x = R[r];
          if (!h) { const c = Object.fromEntries(Object.entries(x).map(([cc, v]) => [bo(v), cc])); const ten = k => Object.keys(c).find(z => k.test(z));
            if (ten(/^noi dung/)) h = { ngay: c[ten(/^ngay( chi| thanh toan)?$/)], nd: c[ten(/^noi dung/)], tien: c[ten(/^so tien/)], nguon: c[ten(/^nguon thanh toan/)], dv: c[ten(/don vi chiu/)] };
            continue; }
          const a = String(x.A || '');
          // dòng tên các cột phân bổ (HIỀN THUỶ · CHÁNH TÂM · … · SAIKUNG · HONGKONG) ngay dưới tiêu đề
          if (!pb && !x[h.nd] && Object.values(x).some(v => /hien thuy|saikung/.test(bo(v)))) { pb = Object.fromEntries(Object.entries(x).map(([cc, v]) => [cc, bo(v)])); continue; }
          // 22/10: dòng nhóm "1. CHI PHÍ…" phải có chữ sau số — trước đây ngày giờ dạng số lẻ (46238.0003…) bị tưởng là dòng nhóm nên MẤT dòng đó
          if (/^\d+\.\s*[^\d\s]/.test(a)) { nhom = a; continue; }   // dòng nhóm "1. CHI PHÍ VĂN PHÒNG…"
          let tien = so(x[h.tien]); if (!tien && /mkt/.test(b)) tien = Object.entries(x).filter(([cc]) => cc >= 'G' && cc.length === 1).reduce((s, [, v]) => s + (so(v) || 0), 0) || null;   // CP MKT: số tiền nằm ở cột phân bổ
          const nd = String(x[h.nd] || ''); if (!tien || !nd || /khong phat sinh/.test(bo(nd))) continue;
          const ng = ngayEx(x[h.ngay]), dv = h.dv ? String(x[h.dv] || '') : '';
          // 22/10 anh: "các khoản liên quan tới nhà hàng bỏ hết, chỉ lấy khoản liên quan tới đồ thờ" — đơn vị chịu là nhà hàng / chỉ chia cho Saikung, Hongkong
          if (/saikung|hongkong|hong kong|amhp/.test(bo(dv + ' ' + nd))) continue;
          if (pb) { const co = Object.keys(pb).filter(cc => cc >= 'G' && cc.length === 1 && so(x[cc])); if (co.length && co.every(cc => /saikung|hongkong/.test(pb[cc]))) continue; }
          dong.push({ nguon: 'CPCT', sheet: sh.name, dong: r, ngay: ng && ng.slice(0, 7) >= '2026-01' && ng.slice(0, 7) <= thang ? ng : null, thang, danh_muc: nhom || dv, noi_dung: nd, so_tien: tien,
            nguon_tt: String(x[h.nguon] || '') }); }
      }
      F.xoa(); console.log('CP T' + t, dong.length - n0, 'dòng');
    }
  } finally { fs.rmSync(goc, { recursive: true, force: true }); }
  // ── B2. đề nghị thanh toán trên app T1–T8 (đã chi; bỏ nhập hàng, trả gốc vay, trả thẻ, tạm ứng, phiếu Kiot, giao dịch cá nhân) ↔ dòng chi phí công ty
  const app = await sql(`select c.id, coalesce(c.ngay_tt, c.ngay_de_nghi)::text ngay, c.so_tien::bigint so_tien, c.noi_dung, c.thu_huong_ten, kt_dcp_nhom_dn(c.noi_dung, c.hoan_quy) gop from kt_chi c
    where not c.da_xoa and c.trang_thai = 'da_tt' and coalesce(c.ngay_tt, c.ngay_de_nghi) between '2026-01-01' and '2026-08-31' and c.nguon <> 'kiot' and not c.la_tam_ung
      and coalesce(c.loai_id, 0) not in (5, 15, 16) and not c.khong_hach_toan`);
  const tok = s => new Set(bo(s).split(/[^a-z0-9]+/).filter(w => w.length > 2)), giong = (a, b) => { const A = tok(a), B = tok(b); let n = 0; A.forEach(w => B.has(w) && n++); return n; };
  const lech = (a, b) => Math.abs((new Date(a) - new Date(b)) / 864e5);
  const theoTien = {}; dong.forEach(d => (theoTien[d.so_tien] = theoTien[d.so_tien] || []).push(d));
  let khopApp = 0;
  // 22/10 anh: quỹ ngoài / thẻ Visa công ty khớp GỘP (phiếu thanh toán quỹ ngoài của cơ sở ↔ các khoản chi quỹ ngoài đó) — không ghép lẻ 1-1
  const nguonDS = [...new Set(dong.map(d => d.nguon_tt || ''))];
  const gopM = Object.fromEntries((await sql(`select n, kt_dcp_nhom_cp(n) g from unnest(array[${nguonDS.map(n => `$q$${n.replace(/\$q\$/g, '')}$q$`).join(',')}]::text[]) n`)).map(r => [r.n, r.g]));
  dong.forEach(d => d.gop = gopM[d.nguon_tt || ''] || null);
  for (const p of app.sort((a, b) => a.ngay < b.ngay ? -1 : 1)) {   // phiếu thanh toán quỹ ngoài / thẻ vẫn ghép 1-1 với dòng "Thanh toán quỹ ngoài…" trong file
    const nd = p.noi_dung + ' ' + (p.thu_huong_ten || '');
    const d = (theoTien[p.so_tien] || []).filter(z => !z.chi_id && !z.gop && (z.ngay ? lech(z.ngay, p.ngay) <= 10 : z.thang === p.ngay.slice(0, 7)))
      .sort((a, b) => (giong(nd, b.noi_dung) - giong(nd, a.noi_dung)) || ((a.ngay ? lech(a.ngay, p.ngay) : 15) - (b.ngay ? lech(b.ngay, p.ngay) : 15)))[0];
    if (d) { d.chi_id = p.id; p.khop = true; khopApp++; }
  }
  // ── A2. P&L ↔ chi phí hạch toán trên app (cùng tháng · đơn vị · mã mục; nhóm cha = tổng mục con)
  const L = await sql(`select id, ma, cha_id from kt_loai where nhom = 'chi'`), maCua = {}; L.forEach(l => maCua[l.id] = l);
  const maLa = id => { let l = maCua[id]; while (l && !l.ma && l.cha_id) l = maCua[l.cha_id]; return l && l.ma; };
  const ht = await sql(`select loai_id, thang, don_vi_id, round(sum(tien))::bigint tien from kt_v_chi_ht where thang between '2026-01' and '2026-08' group by 1, 2, 3`);
  const appSo = {}; for (const x of ht) { const m = maLa(x.loai_id); if (!m) continue;
    for (const [ma, , , dvs] of PNL) if (dvs.includes(x.don_vi_id)) for (let k = m; k; k = k.includes('.') ? k.slice(0, k.lastIndexOf('.')) : '') { const key = ma + '|' + x.thang + '|' + k; appSo[key] = (appSo[key] || 0) + +x.tien; } }
  const ss = pnl.filter(p => p.ma).map(p => ({ ...p, app: appSo[p.nguon + '|' + p.thang + '|' + p.ma] || 0 })).map(p => ({ ...p, lech: (p.thuc_hien || 0) - p.app }));
  const tk = {}; ss.forEach(p => { const k = p.nguon + ' ' + p.thang; const o = tk[k] = tk[k] || { muc: 0, khop: 0, lech: 0 }; o.muc++; Math.abs(p.lech) < 1000 ? o.khop++ : o.lech++; });
  Object.entries(tk).sort().forEach(([k, o]) => console.log('P&L', k.padEnd(10), JSON.stringify(o)));
  const tkc = {}; dong.forEach(d => { const o = tkc[d.thang] = tkc[d.thang] || { dong: 0, khop: 0 }; o.dong++; if (d.chi_id) o.khop++; });
  Object.entries(tkc).sort().forEach(([k, o]) => console.log('CP công ty', k, JSON.stringify(o)));
  console.log('Số chia cơ sở theo mục P&L:', pbcs.length, 'ô');
  console.log('Phiếu đề nghị T1–T8:', app.length, '· khớp chi phí công ty', khopApp, '· chưa', app.length - khopApp);
  if (!GHI) { console.log('(CHẠY THỬ — chưa ghi)'); return; }
  const Q = s => s == null ? 'null' : `$q$${String(s).replace(/\$q\$/g, '')}$q$`;
  await sql(`drop table if exists kt_dcp_dong; create table kt_dcp_dong (id bigserial primary key, sheet text, dong int, thang text, ngay date, danh_muc text, noi_dung text, so_tien bigint,
      nguon_tt text, chi_id bigint, chay_luc timestamptz default now());
    create table if not exists kt_dcp_phieu (chi_id bigint primary key, khop boolean, chay_luc timestamptz default now());
    create table if not exists kt_pnl_cu (id bigserial primary key, nguon text, thang text, dong int, ma text, ten text, target bigint, thuc_hien bigint, app bigint, lech bigint, chay_luc timestamptz default now());
    alter table kt_dcp_dong enable row level security; alter table kt_dcp_phieu enable row level security; alter table kt_pnl_cu enable row level security;
    revoke all on kt_dcp_dong, kt_dcp_phieu, kt_pnl_cu from anon, authenticated;
    truncate kt_dcp_phieu; truncate kt_pnl_cu;`);
  for (let i = 0; i < dong.length; i += 300) await sql(`insert into kt_dcp_dong (sheet, dong, thang, ngay, danh_muc, noi_dung, so_tien, nguon_tt, chi_id) values ` +
    dong.slice(i, i + 300).map(d => `(${Q(d.sheet)},${d.dong},${Q(d.thang)},${d.ngay ? Q(d.ngay) : 'null'},${Q(d.danh_muc)},${Q(d.noi_dung.slice(0, 300))},${d.so_tien},${Q(d.nguon_tt || null)},${d.chi_id || 'null'})`).join(','));
  await sql(`create table if not exists kt_dcp_pb (id bigserial primary key, thang text, cs text, ma text, so_tien bigint, nguon text, chay_luc timestamptz default now());
    alter table kt_dcp_pb enable row level security; revoke all on kt_dcp_pb from anon, authenticated; truncate kt_dcp_pb;`);
  for (let i = 0; i < pbcs.length; i += 400) await sql(`insert into kt_dcp_pb (thang, cs, ma, so_tien, nguon) values ` + pbcs.slice(i, i + 400).map(p => `(${Q(p.thang)},${Q(p.cs)},${Q(p.ma)},${p.so_tien},${Q(p.nguon)})`).join(','));
  for (let i = 0; i < app.length; i += 500) await sql(`insert into kt_dcp_phieu (chi_id, khop) values ` + app.slice(i, i + 500).map(p => `(${p.id},${!!p.khop})`).join(','));
  const ap = Object.fromEntries(ss.map(p => [p.nguon + '|' + p.thang + '|' + p.dong, p]));
  for (let i = 0; i < pnl.length; i += 400) await sql(`insert into kt_pnl_cu (nguon, thang, dong, ma, ten, target, thuc_hien, app, lech) values ` + pnl.slice(i, i + 400).map(p => { const s = ap[p.nguon + '|' + p.thang + '|' + p.dong];
    return `(${Q(p.nguon)},${Q(p.thang)},${p.dong},${Q(p.ma || null)},${Q(p.ten.slice(0, 200))},${p.target == null ? 'null' : p.target},${p.thuc_hien == null ? 'null' : p.thuc_hien},${s ? s.app : 'null'},${s ? s.lech : 'null'})`; }).join(','));
  console.log('Đã ghi', pnl.length, 'ô P&L +', dong.length, 'dòng chi phí công ty +', app.length, 'phiếu');
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
