// Kéo TỒN KHO SỔ THUẾ + HOÁ ĐƠN từ file 3TShop anh xuất ra Google Sheet (3TShop không có API — anh 09/10/2026) — Monsieur Claude
// Nguồn: nguon-3tshop.local.json (gitignore): [{hkd, ky, drive (mã file Drive, đọc qua rclone — chỉ đọc) | xuat_ban (link xuất bản), mau}]
//   mau '3t_quy' (file quý của HT / CT): tab XNT_QUY · HD_XUAT · HD_NHAP
//   mau 'sd_tong' (file tổng Shidai): tab THÔNG TIN XUẤT (hoá đơn bán) · NHẬP HT (hoá đơn mua từ Hiền Thủy). NXT Shidai CHƯA lấy (nhiều tab bản sao, có ô lỗi #VALUE! — đang hỏi).
// Mỗi nguồn: xoá dữ liệu cũ của chính nguồn đó rồi ghi lại (chạy lại không trùng). Chạy: Code.exe scripts/keo-3tshop.js [ghi]
const fs = require('fs'), path = require('path'), os = require('os'), { execFileSync } = require('child_process');
const { sql } = require('./sql'); const { docXlsx } = require('./doc-xlsx');
const GHI = process.argv[2] === 'ghi', J = x => '$kt$' + JSON.stringify(x) + '$kt$';
const RC = path.join(process.env.USERPROFILE || os.homedir(), 'tools', 'rclone', 'rclone.exe');
const so = v => { if (v == null || v === '') return null; const t = String(v).trim(); if (/^-?\d+(\.\d+)?(e[+-]?\d+)?$/i.test(t)) return +t;
  if (/^#|lỗi|error/i.test(t)) return null; const n = +t.replace(/[^\d.-]/g, ''); return isNaN(n) || t.replace(/[^\d]/g, '') === '' ? null : n; };
const ngay = v => { const x = +v; if (!isNaN(x) && x > 40000 && x < 60000) return new Date(Date.UTC(1899, 11, 30) + Math.floor(x) * 864e5).toISOString().slice(0, 10);
  const m = /^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})/.exec(String(v || '')); return m ? `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}` : null; };
const thueSuat = v => { if (v == null || v === '') return null; const t = String(v); if (/kct|kkknt|không chịu|không kê khai/i.test(t)) return null; const n = so(t.replace('%', '')); return n == null ? null : (n <= 1 ? Math.round(n * 1000) / 10 : n); };
const chu = v => v == null || v === '' ? null : String(v).trim();
async function taiVe(ng) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), '3t-'));
  if (ng.drive) execFileSync(RC, ['backend', 'copyid', 'ktdrive:', ng.drive, dir + path.sep, '--drive-export-formats', 'xlsx'], { stdio: 'pipe', timeout: 180000 });
  else { const r = await fetch(ng.xuat_ban); if (!r.ok) throw new Error('tải link xuất bản lỗi ' + r.status); fs.writeFileSync(path.join(dir, 'tong.xlsx'), Buffer.from(await r.arrayBuffer())); }
  const f = fs.readdirSync(dir)[0]; if (!f) throw new Error('không tải được file (không có quyền / sai mã)'); return path.join(dir, f);
}
// Đọc bảng hoá đơn THEO TÊN TIÊU ĐỀ (09/10: mỗi kỳ 3TShop / phần mềm HĐ xuất 1 mẫu cột khác — vd HT quý 3 là bảng kê 36 cột)
const COT_HD = { so_hd: /^(số hóa đơn|số hoá đơn|số hđ viết|số hđ)$/i, mau: /mẫu số/i, ky_hieu: /^ký hiệu/i, ngay: /^(ngày hóa đơn|ngày hoá đơn|ngày|ngày nhập)$/i,
  mst: /mã số thuế/i, don_vi: /^(tên đơn vị|tên khách hàng)$/i, nguoi_mua: /người mua/i, ma: /^mã hàng|^mã sp/i, ten: /tên hàng|mặt hàng|^sản phẩm/i, dvt: /đơn vị tính|^đvt$/i,
  sl: /^số lượng/i, don_gia: /^đơn giá|^giá nhập$/i, thanh_tien: /^thành tiền/i, thue_suat: /^vat$|thuế suất/i, tien_thue: /tiền thuế/i, tong: /^tổng tiền/i,
  ghi_chu: /^ghi chú$/i, tinh_chat: /tính chất hóa đơn|tính chất hoá đơn/i };
function docHD(rows, goc) {
  const ns = Object.keys(rows).map(Number).sort((a, b) => a - b);
  const hr = ns.slice(0, 8).find(n => { const v = Object.values(rows[n]).map(String); return v.some(x => /tên hàng|mặt hàng/i.test(x)) && v.some(x => /số lượng/i.test(x)); });
  if (!hr) return [];
  const map = {}; for (const [c, v] of Object.entries(rows[hr])) for (const [k, re] of Object.entries(COT_HD)) if (re.test(String(v).replace(/\s+/g, ' ').trim()) && !(k in map)) map[k] = c;
  return ns.filter(n => n > hr).map(n => { const r = rows[n], g = k => map[k] ? r[map[k]] : undefined; if (!g('ten') && !g('ma')) return null;
    if (/^(tổng|cộng)/i.test(String(g('ten') || ''))) return null;
    return { ...goc, so_hd: chu(g('so_hd')), mau: chu(g('mau')), ky_hieu: chu(g('ky_hieu')), ngay: ngay(g('ngay')), mst: chu(g('mst')), nguoi_mua: chu(g('don_vi')) || chu(g('nguoi_mua')),
      ma: chu(g('ma')), ten: chu(g('ten')), dvt: chu(g('dvt')), sl: so(g('sl')), don_gia: so(g('don_gia')), thanh_tien: so(g('thanh_tien')), thue_suat: thueSuat(g('thue_suat')),
      tien_thue: so(g('tien_thue')), tong: so(g('tong')), ghi_chu: [chu(g('tinh_chat')) === 'Hóa đơn gốc' ? null : chu(g('tinh_chat')), chu(g('ghi_chu')), goc.ghi_chu].filter(Boolean).join(' · ') || null, dong: n }; }).filter(Boolean);
}
function hang(rows, tu) { return Object.keys(rows).map(Number).filter(n => n >= tu).sort((a, b) => a - b).map(n => ({ _r: n, ...rows[n] })); }
(async () => {
  const nguon = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'nguon-3tshop.local.json'), 'utf8'));
  const tong = { xnt: 0, ra: 0, vao: 0 };
  for (const ng of nguon) {
    if (!ng.drive && !ng.xuat_ban) { console.log(`- ${ng.hkd} ${ng.ky || ''}: BỎ QUA — ${ng.ten}`); continue; }
    let x; try { x = docXlsx(await taiVe(ng)); } catch (e) { console.log(`- ${ng.hkd} ${ng.ky || ''}: LỖI tải — ${e.message}`); continue; }
    const key = ng.hkd + ':' + (ng.ky || 'tong'); const xnt = [], hd = [];
    if (ng.mau === '3t_quy') {
      const t1 = x.tab('XNT_QUY'); if (t1) { const gop = {};
        for (const r of hang(x.load(t1), 4)) { const ma = chu(r.B); if (!ma || /^mã/i.test(ma)) continue;
          const g = gop[ma] = gop[ma] || { hkd: ng.hkd, ky: ng.ky, ma, ten: chu(r.C), chung_loai: chu(r.D), dvt: chu(r.E), gia_nhap: so(r.F), dau_sl: 0, dau_tien: 0, nhap_sl: 0, nhap_tien: 0, xuat_sl: 0, xuat_tien: 0, cuoi_sl: 0, cuoi_tien: 0, nguon: key };
          [['dau_sl', 'G'], ['dau_tien', 'H'], ['nhap_sl', 'I'], ['nhap_tien', 'J'], ['xuat_sl', 'K'], ['xuat_tien', 'L'], ['cuoi_sl', 'M'], ['cuoi_tien', 'N']].forEach(([k, c]) => g[k] += so(r[c]) || 0); }
        xnt.push(...Object.values(gop)); }
      const t2 = x.tab('HD_XUAT'); if (t2) hd.push(...docHD(x.load(t2), { hkd: ng.hkd, chieu: 'ra', nguon: key + ':HD_XUAT' }));
      const t3 = x.tab('HD_NHAP'); if (t3) hd.push(...docHD(x.load(t3), { hkd: ng.hkd, chieu: 'vao', nguon: key + ':HD_NHAP' }));
    } else if (ng.mau === 'sd_tong') {
      const t2 = x.tab('THÔNG TIN XUẤT'); if (t2) hd.push(...docHD(x.load(t2), { hkd: 'SD', chieu: 'ra', nguon: key + ':THONG_TIN_XUAT' }));
      const t3 = x.tab('NHẬP HT'); if (t3) hd.push(...docHD(x.load(t3), { hkd: 'SD', chieu: 'vao', nguon: key + ':NHAP_HT', ghi_chu: 'Mua từ HKD Hiền Thủy' }));
    }
    x.xoa();
    const ra = hd.filter(h => h.chieu === 'ra'), vao = hd.filter(h => h.chieu === 'vao'), f = n => Math.round(n).toLocaleString('vi-VN');
    console.log(`- ${ng.hkd} ${ng.ky || '(tổng)'}: tồn kho ${xnt.length} mã (tồn cuối ${f(xnt.reduce((a, r) => a + r.cuoi_tien, 0))}) · HĐ bán ${ra.length} dòng (${f(ra.reduce((a, r) => a + (r.thanh_tien || 0), 0))} chưa thuế) · nhập ${vao.length} dòng · ngày lỗi ${hd.filter(h => !h.ngay || h.ngay < '2025-01-01' || h.ngay > '2026-12-31').length}`);
    tong.xnt += xnt.length; tong.ra += ra.length; tong.vao += vao.length;
    if (!GHI) continue;
    await sql(`delete from kt_thue_xnt where nguon = ${J(key)}::jsonb#>>'{}'; delete from kt_thue_hd where nguon like ${J(key + ':%')}::jsonb#>>'{}'`);
    for (let i = 0; i < xnt.length; i += 500) await sql(`insert into kt_thue_xnt select * from jsonb_populate_recordset(null::kt_thue_xnt, ${J(xnt.slice(i, i + 500).map(r => ({ ...r, keo_luc: new Date().toISOString() })))}::jsonb)
      on conflict (hkd, ky, ma) do update set ten = excluded.ten, cuoi_sl = excluded.cuoi_sl, cuoi_tien = excluded.cuoi_tien, nguon = excluded.nguon, keo_luc = now()`);
    for (let i = 0; i < hd.length; i += 500) await sql(`insert into kt_thue_hd (hkd, chieu, so_hd, mau, ky_hieu, ngay, mst, nguoi_mua, ma, ten, dvt, sl, don_gia, thanh_tien, thue_suat, tien_thue, tong, ghi_chu, nguon, dong)
      select hkd, chieu, so_hd, mau, ky_hieu, ngay, mst, nguoi_mua, ma, ten, dvt, sl, don_gia, thanh_tien, thue_suat, tien_thue, tong, ghi_chu, nguon, dong
      from jsonb_populate_recordset(null::kt_thue_hd, ${J(hd.slice(i, i + 500))}::jsonb)`);
  }
  if (GHI) await sql(`insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Monsieur Claude', 'kt_thue', 'keo_3tshop', ${J(tong)}::jsonb)`);
  console.log((GHI ? 'ĐÃ GHI' : 'CHẠY THỬ') + ' · ' + JSON.stringify(tong));
})().catch(e => { console.error('DỪNG', e.message); process.exit(1); });
