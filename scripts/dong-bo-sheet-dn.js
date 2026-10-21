// Đồng bộ file GG Sheet "THT QUẢN LÍ THANH TOÁN 2025+2026" (tab ĐỀ NGHỊ THANH TOÁN) → app — 15/10/2026, anh: "luồng đề nghị thanh toán trên app
// chưa đưa vào hoạt động thì chịu khó update trạng thái các giao dịch bên ấy để clear đi" (bao giờ chạy luồng app anh báo).
// Mỗi lần chạy:
//   1. Phiếu đã có trên app (khớp nội dung + số tiền, phụ: số tiền + ngày ±3) → nâng trạng thái theo sheet (chờ duyệt → chờ TT → đã TT / từ chối),
//      bổ sung ngày TT, TK chi, loại chi, UNC. Không bao giờ hạ trạng thái, không đụng phiếu đã thanh toán trên app.
//   2. Dòng sheet chưa có trên app (đề nghị từ 01/10/2026) → thêm phiếu (nguồn "sheet_cu", mã dntt2:<dấu thời gian form>).
//   3. Dòng trả GỐC vay (THU NO TKV…) → trang Vay (kt_vay_tra), không vào Phiếu chi.
//   4. Đề xuất tự tạo từ Kiot (nguồn kiot, còn chờ) trùng số tiền ±7 ngày với dòng sheet đã thanh toán → ghép phiếu Kiot vào phiếu sheet, đề xuất Kiot → Từ chối (trùng).
//   5. (16/10) Phiếu nguồn sheet còn chờ trên app mà dòng không còn trên sheet → xoá mềm, ghi nhật ký (số phiếu app = số dòng sheet).
// Tải file: rclone backend copyid ktdrive2: <id> <thư mục>  ·  Chạy: Code.exe scripts/dong-bo-sheet-dn.js <file.xlsx> [ghi]
// Không in số tài khoản. Monsieur Claude
const { docXlsx } = require('./doc-xlsx'), { sql } = require('./sql');
const [TEP, CHE_DO] = process.argv.slice(2), GHI = CHE_DO === 'ghi', TU_MOI = '2026-10-01';
const ngay = v => v === undefined || v === '' || isNaN(+v) || +v < 40000 ? null : new Date(Date.UTC(1899, 11, 30) + Math.floor(+v) * 864e5).toISOString().slice(0, 10);
const luc = v => v === undefined || v === '' || isNaN(+v) || +v < 40000 ? null : new Date(Date.UTC(1899, 11, 30) + (+v) * 864e5 - 7 * 3600e3).toISOString();
const so = v => { const t = String(v ?? '').trim(); if (/^-?\d+(\.\d+)?(e[+-]?\d+)?$/i.test(t)) return Math.round(+t); const n = Math.round(+t.replace(/[^\d-]/g, '')); return isNaN(n) ? 0 : n; };
const sach = v => { v = String(v ?? '').trim(); return !v || v === '0' || v === '.' || v === '0.0' ? null : v; };
const chuan = s => String(s ?? '').normalize('NFC').toLowerCase().replace(/\s+/g, ' ').replace(/\s*-\s*/g, '-').trim();
const khoa = (nd, tien) => chuan(nd).replace(/[^a-z0-9à-ỹđ]/g, '') + '|' + tien;
const lech = (a, b) => a && b ? Math.abs((new Date(a) - new Date(b)) / 864e5) : 99;
const f = n => Math.round(n).toLocaleString('vi-VN'), Q = x => x == null ? 'null' : '$q$' + String(x) + '$q$';
const BAC = { cho_duyet: 0, cho_gd: 1, cho_tt: 2, da_tt: 3 };
const laGoc = nd => /(gốc|\bgoc\b)/i.test(nd) || (/(thu no|thu nợ|tk ?vay|tkvay|tai khoan vay|tài khoản vay|tra no tk|trả nợ tk|tra no vay|trả nợ vay|tat toan tai khoan vay|thau chi|thấu chi|khoản vay|khoan vay)/i.test(nd) && !/(lãi|\blai\b|\bphi\b|phí)/i.test(nd));
const laThe = nd => /(sao ke|sao kê|visa|thẻ tín dụng|the tin dung|\bSK\b|credit card)/i.test(nd);
const nhomVay = nd => /406004307224/.test(nd) ? 'BIDV — TK vay 406004307224' : /406004717371/.test(nd) ? 'BIDV — TK vay 406004717371' : /401004519925/.test(nd) ? 'BIDV — TK vay 401004519925'
  : /8837562543/.test(nd) ? 'BIDV — thấu chi 8837562543' : /dài hạn/i.test(nd) ? 'VCB — vay dài hạn (HN)' : /cá nhân/i.test(nd) ? 'VCB — vay cá nhân' : 'VCB — vay ngắn hạn (hạn mức, nhiều khế ước TKV)';

(async () => {
  if (!TEP) return console.log('thiếu file xlsx');
  const F = docXlsx(TEP), sh = F.sheets.find(s => s.name === 'ĐỀ NGHỊ THANH TOÁN'), R = F.load(sh);
  const rows = Object.keys(R).map(Number).filter(n => n >= 3).map(n => ({ _r: n, ...Object.fromEntries(Object.entries(R[n]).map(([k, v]) => [k, typeof v === 'string' ? v.trim() : v])) }))
    .filter(r => r.E && so(r.G) > 0 && (ngay(r.A) || '') >= '2026-01-01');
  const dm = { tk: await sql('select id, ten, ten_cu from kt_tai_khoan'), dv: await sql('select id, ten, ten_cu from kt_don_vi'), lo: await sql("select id, ten from kt_loai where nhom = 'chi'"),
    vay: await sql('select id, ten from kt_vay where not da_xoa') };
  const tim = (ds, t) => { const c = chuan(t); return c ? ds.find(x => chuan(x.ten) === c || (x.ten_cu || []).some(y => chuan(y) === c)) : null; };
  const loTen = t => dm.lo.find(x => x.ten === t);
  const timLo = (x, nd) => { if (!x) return null; if (/^FINANCE/i.test(x)) return laThe(nd) ? loTen('FINANCE - Trả thẻ tín dụng') : loTen('FINANCE - Lãi vay & phí tài chính');
    return dm.lo.find(l => chuan(l.ten) === chuan(x)) || null; };
  const app = await sql(`select id, noi_dung, so_tien::bigint so_tien, trang_thai, nguon, ma_nguon, ngay_tt::text tt, ngay_su_dung::text sd, ngay_de_nghi::text dn, tai_khoan_id, loai_id, unc, kiot_so_quy_id, nguoi_de_nghi nn
    from kt_chi where not da_xoa and nguon <> 'kiot'`);
  const kiotCho = await sql(`select id, so_tien::bigint so_tien, ngay_de_nghi::text dn, noi_dung, kiot_so_quy_id, kiot_ma from kt_chi where not da_xoa and nguon = 'kiot' and trang_thai in ('cho_duyet','cho_gd','cho_tt')`);
  const vayTra = await sql(`select id, (goc + lai)::bigint goc, ngay::text ngay from kt_vay_tra where not da_xoa`);
  const theoKhoa = new Map(); app.forEach(a => { const k = khoa(a.noi_dung, +a.so_tien); (theoKhoa.get(k) || theoKhoa.set(k, []).get(k)).push(a); });
  const dung = new Set(), dungVay = new Set(), dungKiot = new Set();
  const capNhat = [], them = [], vayMoi = [], ghepKiot = [], bao = [], gop = [];
  for (const r of rows) {
    const tien = so(r.G), nd = String(r.E), dA = ngay(r.A), dTT = ngay(r.V) || ngay(r.T), S = String(r.S || ''), U = String(r.U || '');
    const st = /từ chối/i.test(S + U) ? 'tu_choi' : /đã thanh toán/i.test(U) ? 'da_tt' : /đã duyệt/i.test(S) ? 'cho_tt' : 'cho_duyet';
    // 3. trả gốc vay → trang Vay
    if (laGoc(nd) && (!r.X || /^FINANCE/i.test(String(r.X))) && st === 'da_tt') {
      const v = vayTra.find(x => !dungVay.has(x.id) && +x.goc === tien && lech(x.ngay, dTT) <= 3);   // 21/10: so gốc + lãi — dòng đã đổi sang lãi trên app vẫn nhận ra (trước thêm trùng 6 dòng)
      if (v) { dungVay.add(v.id); continue; }
      const old = (theoKhoa.get(khoa(nd, tien)) || []).find(a => !dung.has(a.id)); if (old) dung.add(old.id);   // phiếu chi trả gốc còn sót trên app → ẩn
      vayMoi.push({ r, tien, dTT, tk: tim(dm.tk, r.W), nhom: nhomVay(nd), an: old && old.id }); continue;
    }
    // 1. đã có trên app?
    let a = app.find(x => !dung.has(x.id) && x.ma_nguon === 'dntt2:' + String(r.A)) || (theoKhoa.get(khoa(nd, tien)) || []).find(x => !dung.has(x.id));
    if (!a) a = app.find(x => !dung.has(x.id) && +x.so_tien === tien && (lech(x.tt, dTT) <= 3 || lech(x.sd, ngay(r.F)) === 0 || lech(x.dn, dA) === 0) && chuan(x.noi_dung).slice(0, 12) === chuan(nd).slice(0, 12));
    // phụ 2: phiếu sheet đang chờ trên app, cùng số tiền, ngày đề nghị lệch ≤ 3 ngày (nội dung sửa chữ)
    if (!a && (dA || '') >= TU_MOI) a = app.find(x => !dung.has(x.id) && x.nguon === 'sheet_cu' && +x.so_tien === tien && lech(x.dn, dA) <= 3);
    const tk = tim(dm.tk, r.W), lo = timLo(r.X, nd);
    // phụ 3 (19/10/2026, anh: "thấy trùng thì gộp, tránh vừa app vừa sheet"): phiếu đã gửi trên APP (link đề nghị / tạo trên app), cùng số tiền,
    // ngày đề nghị lệch ≤ 3 ngày, cùng người đề nghị hoặc nội dung gần giống → coi là 1 phiếu, không thêm dòng sheet
    if (!a) a = app.find(x => !dung.has(x.id) && x.nguon !== 'sheet_cu' && +x.so_tien === tien && lech(x.dn, dA) <= 3
      && ((chuan(x.nn) && chuan(x.nn) === chuan(r.C)) || chuan(x.noi_dung).slice(0, 8) === chuan(nd).slice(0, 8)));
    if (a) { dung.add(a.id);
      // phiếu gốc trên APP: app là chính (từ 19/10) → sheet KHÔNG đổi trạng thái / tài khoản / loại, chỉ bổ sung link UNC nếu app chưa có
      if (a.nguon !== 'sheet_cu') { const unc = [r.Y].find(x => /^https?:/.test(String(x || ''))); if (unc && !a.unc) capNhat.push({ id: a.id, cu: a.trang_thai, doi: { unc }, nd, tien, R: sach(r.R), luc: luc(r.T) });
        gop.push(`#${a.id} (app) = sheet r${r._r}`); continue; }
      const doi = {};
      if (st === 'tu_choi' && a.trang_thai !== 'da_tt' && a.trang_thai !== 'tu_choi') doi.trang_thai = 'tu_choi';
      else if (st !== 'tu_choi' && BAC[st] > (BAC[a.trang_thai] ?? 9)) {
        if (st === 'da_tt' && (!tk || !lo)) { if (a.trang_thai !== 'cho_tt') doi.trang_thai = 'cho_tt'; bao.push(`#${a.id} sheet đã TT nhưng thiếu ${!tk ? 'TK' : ''} ${!lo ? 'loại' : ''} → Chờ TT`); }
        else { doi.trang_thai = st; if (st === 'da_tt') { doi.ngay_tt = dTT; doi.tai_khoan_id = tk.id; doi.loai_id = lo.id; } }
      }
      if (a.trang_thai === 'da_tt' || doi.trang_thai === 'da_tt') { if (!a.tai_khoan_id && tk && !doi.tai_khoan_id) doi.tai_khoan_id = tk.id; if (!a.loai_id && lo && !doi.loai_id) doi.loai_id = lo.id; }
      const unc = [r.Y].find(x => /^https?:/.test(String(x || ''))); if (unc && !a.unc) doi.unc = unc;
      if (Object.keys(doi).length) capNhat.push({ id: a.id, cu: a.trang_thai, doi, nd, tien, R: sach(r.R), luc: luc(r.T) });
      if ((doi.trang_thai || a.trang_thai) === 'da_tt' && !a.kiot_so_quy_id) { const k = kiotCho.find(x => !dungKiot.has(x.id) && +x.so_tien === tien && lech(x.dn, dTT) <= 7); if (k) { dungKiot.add(k.id); ghepKiot.push({ sheetId: a.id, k }); } }
      continue;
    }
    // 2. dòng mới
    if ((dA || '') < TU_MOI) { bao.push(`r${r._r} ${dA} không khớp app (cũ, bỏ qua): ${nd.slice(0, 40)} ${f(tien)}`); continue; }
    const dvs = String(r.K || '').split(',').map(x => x.trim()).filter(Boolean).map(x => tim(dm.dv, x)).filter(Boolean);
    const pb = dvs.map((d, i) => ({ don_vi_id: d.id, so_tien: i < dvs.length - 1 ? Math.floor(tien / dvs.length) : tien - Math.floor(tien / dvs.length) * (dvs.length - 1) }));
    let tt = st, ghi = sach(r.N); if (tt === 'da_tt' && (!tk || !lo)) { tt = 'cho_tt'; ghi = '[Sheet ghi Đã thanh toán nhưng thiếu ' + [!tk && 'TK chi', !lo && 'loại chi'].filter(Boolean).join(', ') + ']' + (ghi ? ' ' + ghi : ''); }
    const bp = tim(dm.dv, r.D);
    const p = { ngay_de_nghi: dA, nguoi_de_nghi: sach(r.C) || 'Không rõ (sheet)', bo_phan_id: bp ? bp.id : null, noi_dung: nd.slice(0, 500), ngay_su_dung: ngay(r.F), so_tien: tien,
      thu_huong_ten: sach(r.H), thu_huong_nh: sach(r.I), thu_huong_stk: sach(r.J), phan_bo: pb, han_tt: ngay(r.L), co_hd_do: /^có/i.test(String(r.M || '')), ghi_chu: ghi,
      chung_tu: [r.O, r.P, r.Q].filter(x => /^https?:/.test(String(x || ''))), trang_thai: tt, nguoi_duyet: sach(r.R), duyet_luc: tt === 'cho_duyet' ? null : luc(r.T),
      ngay_tt: tt === 'da_tt' ? dTT : null, tai_khoan_id: tt === 'da_tt' ? tk.id : (tk ? tk.id : null), loai_id: lo ? lo.id : null, unc: [r.Y].find(x => /^https?:/.test(String(x || ''))) || null,
      ma_nguon: 'dntt2:' + String(r.A) };
    them.push(p);
    if (tt === 'da_tt') { const k = kiotCho.find(x => !dungKiot.has(x.id) && +x.so_tien === tien && lech(x.dn, dTT) <= 7); if (k) { dungKiot.add(k.id); ghepKiot.push({ ma: p.ma_nguon, k }); } }
  }
  const cho = app.filter(a => a.nguon === 'sheet_cu' && a.trang_thai !== 'da_tt' && a.trang_thai !== 'tu_choi' && !dung.has(a.id));
  console.log('Sheet 2026:', rows.length, 'dòng');
  console.log('0. Gộp trùng app ↔ sheet (phiếu gửi trên app, sheet không ghi đè):', gop.length, gop.slice(-5).join(', '));
  console.log('1. Cập nhật trạng thái phiếu đã có:', capNhat.length, Object.entries(capNhat.reduce((o, x) => { const k = x.cu + '→' + (x.doi.trang_thai || '(bổ sung TK/loại/UNC)'); o[k] = (o[k] || 0) + 1; return o }, {})).map(([k, v]) => k + ': ' + v).join(' · '));
  console.log('2. Thêm phiếu mới (đề nghị từ ' + TU_MOI + '):', them.length, Object.entries(them.reduce((o, x) => { o[x.trang_thai] = (o[x.trang_thai] || 0) + 1; return o }, {})).map(([k, v]) => k + ': ' + v).join(' · '), '·', f(them.reduce((s, x) => s + x.so_tien, 0)));
  console.log('3. Trả gốc vay mới → trang Vay:', vayMoi.length, f(vayMoi.reduce((s, x) => s + x.tien, 0)), vayMoi.filter(x => x.an).length ? '(+ ẩn ' + vayMoi.filter(x => x.an).length + ' phiếu chi trả gốc còn sót)' : '');
  console.log('4. Đề xuất Kiot trùng dòng sheet → ghép + bỏ trùng:', ghepKiot.length, f(ghepKiot.reduce((s, x) => s + +x.k.so_tien, 0)), '/ còn', kiotCho.length - ghepKiot.length, 'đề xuất Kiot chờ');
  console.log('Phiếu sheet_cu còn chờ trên app mà không thấy trên sheet:', cho.length, cho.map(x => '#' + x.id).join(' '));
  if (process.env.KT_CHI_TIET) { capNhat.forEach(x => console.log('  CN #' + x.id, x.cu, '→', JSON.stringify(x.doi).replace(/https?:\S+?"/g, 'link"'), x.nd.slice(0, 40), f(x.tien)));
    them.forEach(x => console.log('  MỚI', x.ngay_de_nghi, x.trang_thai, x.noi_dung.slice(0, 45), f(x.so_tien))); ghepKiot.forEach(x => console.log('  GHÉP', x.k.kiot_ma, x.k.noi_dung.slice(0, 35), f(x.k.so_tien), '↔', x.sheetId ? '#' + x.sheetId : x.ma)); }
  if (bao.length) console.log(bao.slice(0, 40).join('\n'));
  if (!GHI) return console.log('(CHẠY THỬ — chưa ghi)');

  const NG = 'Hệ thống (đồng bộ sheet đề nghị)';
  for (const x of capNhat) {
    const set = Object.entries(x.doi).map(([k, v]) => `${k} = ${typeof v === 'number' ? v : Q(v)}`);
    if (x.doi.trang_thai && x.doi.trang_thai !== 'cho_duyet') set.push(`nguoi_duyet = coalesce(nguoi_duyet, ${Q(x.R)})`, `duyet_luc = coalesce(duyet_luc, ${Q(x.luc)}::timestamptz)`);
    set.push(`sua_boi = ${Q(NG)}`, 'sua_luc = now()');
    await sql(`update kt_chi set ${set.join(', ')} where id = ${x.id}; insert into kt_nhat_ky (nguoi, bang, dong_id, hanh_dong, du_lieu) values (${Q(NG)}, 'kt_chi', ${x.id}, 'dong_bo_sheet', ${Q(JSON.stringify({ cu: x.cu, doi: x.doi }))}::jsonb)`);
  }
  if (them.length) await sql(`insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, thu_huong_nh, thu_huong_stk, phan_bo, han_tt, co_hd_do, ghi_chu,
      chung_tu, trang_thai, nguoi_duyet, duyet_luc, ngay_tt, tai_khoan_id, loai_id, unc, nguon, ma_nguon, tao_boi)
    select ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, thu_huong_nh, thu_huong_stk, phan_bo, han_tt, co_hd_do, ghi_chu,
      array(select jsonb_array_elements_text(chung_tu)), trang_thai, nguoi_duyet, duyet_luc, ngay_tt, tai_khoan_id, loai_id, unc, 'sheet_cu', ma_nguon, ${Q(NG)}
    from jsonb_to_recordset(${Q(JSON.stringify(them))}::jsonb) as x(ngay_de_nghi date, nguoi_de_nghi text, bo_phan_id int, noi_dung text, ngay_su_dung date, so_tien numeric, thu_huong_ten text,
      thu_huong_nh text, thu_huong_stk text, phan_bo jsonb, han_tt date, co_hd_do boolean, ghi_chu text, chung_tu jsonb, trang_thai text, nguoi_duyet text, duyet_luc timestamptz, ngay_tt date,
      tai_khoan_id int, loai_id int, unc text, ma_nguon text) on conflict (ma_nguon) do nothing`);
  for (const v of vayMoi) {
    let vid = (dm.vay.find(x => x.ten === v.nhom) || {}).id;
    if (!vid) vid = (await sql(`insert into kt_vay (ten, ben_cho_vay, so_tien, ngay_vay, hinh_thuc, tai_khoan_id, ghi_chu, chung_tu, tao_boi) values (${Q(v.nhom)}, ${Q(v.nhom.split(' — ')[0])}, 0, ${Q(v.dTT)}, 'goc_cuoi_ky', ${v.tk ? v.tk.id : 'null'}, 'Cần nhập các lần nhận tiền (giải ngân).', '{}', ${Q(NG)}) returning id`))[0].id;
    await sql(`insert into kt_vay_tra (vay_id, ngay, goc, lai, da_tra, ghi_chu, tao_boi, tai_khoan_id) values (${vid}, ${Q(v.dTT)}, ${v.tien}, 0, true, ${Q(String(v.r.E).slice(0, 300))}, ${Q(NG)}, ${v.tk ? v.tk.id : 'null'})`);
    if (v.an) await sql(`update kt_chi set da_xoa = true, ghi_chu = concat_ws(' ', ghi_chu, '[Trả gốc vay — chuyển sang trang Vay & lãi vay]') where id = ${v.an}`);
  }
  for (const g of ghepKiot) {
    const sid = g.sheetId || (await sql(`select id from kt_chi where ma_nguon = ${Q(g.ma)}`))[0].id;
    await sql(`update kt_chi set kiot_so_quy_id = null, trang_thai = 'tu_choi', nguoi_duyet = ${Q(NG)}, duyet_luc = now(),
        ghi_chu = concat_ws(' ', ghi_chu, '[Trùng phiếu đề nghị #${sid} (sheet) — phiếu Kiot đã ghép vào #${sid}]') where id = ${g.k.id};
      update kt_chi set kiot_so_quy_id = ${g.k.kiot_so_quy_id}, kiot_ma = ${Q(g.k.kiot_ma)}, kiot = 'da_tao' where id = ${sid} and kiot_so_quy_id is null;
      insert into kt_nhat_ky (nguoi, bang, dong_id, hanh_dong, du_lieu) values (${Q(NG)}, 'kt_chi', ${g.k.id}, 'trung_sheet', ${Q(JSON.stringify({ ghep_vao: sid }))}::jsonb)`);
  }
  // 16/10 anh: "thu chi chỉ cần đầy đủ số lượng phiếu giống trên gg sheet" → phiếu sheet còn chờ mà dòng đã xoá / đã sửa thành dòng khác trên sheet: xoá MỀM (khôi phục được)
  // chặn an toàn: file đọc ra quá ít dòng (file hỏng / tab sai) thì không xoá gì
  if (cho.length && rows.length > 500) await sql(`update kt_chi set da_xoa = true, sua_boi = ${Q(NG)}, sua_luc = now(),
      ghi_chu = concat_ws(' ', ghi_chu, '[Không còn trên sheet đề nghị — xoá theo sheet]') where id in (${cho.map(x => x.id).join(',')}) and not da_xoa;
    insert into kt_nhat_ky (nguoi, bang, dong_id, hanh_dong, du_lieu) select ${Q(NG)}, 'kt_chi', id, 'xoa_theo_sheet', '{}'::jsonb from kt_chi where id in (${cho.map(x => x.id).join(',')})`);
  // phiếu hoàn quỹ ngoài cửa hàng mới → gắn cửa hàng (như supabase-schema-kt-quy-ngoai.sql)
  await sql(`update kt_chi set hoan_quy = case when noi_dung ~* '(\mHT\M|hiền thủy|hien thuy)' then 'HT' when noi_dung ~* '(\mCT\M|chánh tâm|chanh tam)' then 'CT'
      when noi_dung ~* '(shidai|kho|\mSD\M)' then 'SD' else case (phan_bo->0->>'don_vi_id')::int when 2 then 'HT' when 3 then 'CT' when 4 then 'SD' end end
    where hoan_quy is null and not da_xoa and noi_dung ~* '(thanh toán|tt|hoàn|bù|fill).*(tiền )?quỹ ngoài'`);
  console.log('ĐÃ GHI');
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
