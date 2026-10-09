// Gán LOẠI CHI tự động theo mẫu phiếu đã có loại (anh 09/10/2026: "dùng mẫu số T5–T9"). Monsieur Claude
// Cách gán (theo thứ tự): (1) cùng NGƯỜI THỤ HƯỞNG đã có ≥2 phiếu và ≥80% cùng 1 loại → loại đó (độ tin cao)
//   (1b) LUẬT TỪ KHOÁ học từ mẫu (09/10): từ khoá có ≥5 phiếu mẫu và ≥80% cùng 1 loại → loại đó (vd lương → Lương & BHXH, cước → Logistics)
//   (2) nội dung giống nhất (TF-IDF từ + cặp từ, cosine, 7 phiếu gần nhất có trọng số) → loại được nhiều phiếu giống nhất.
// Chạy:  Code.exe scripts/gan-loai-chi.js cham     → chấm điểm: học trên phiếu trả T5–T7, gán thử T8–T9, so với loại kế toán đã gán
// Dùng trong script khác: const { hoc, gan } = require('./gan-loai-chi')
const { sql } = require('./sql');
const bo = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D').toLowerCase();
const tu = s => { const w = bo(s).replace(/[^a-z0-9 ]+/g, ' ').split(/\s+/).filter(x => x.length > 1 && !/^\d+$/.test(x)); return [...w, ...w.slice(1).map((x, i) => w[i] + '_' + x)]; };
const nguoiTH = s => { const t = bo(s).replace(/[^a-z0-9]+/g, ' ').trim(); return !t || /^(0|tien mat|chi tien mat|khong|\.)$/.test(t) || t.length < 3 ? null : t; };
// thêm đặc trưng: bộ phận đề nghị, đơn vị chịu chi phí, cỡ số tiền
const them = m => [m.bo_phan && 'bp_' + bo(m.bo_phan).replace(/[^a-z0-9]+/g, ''), ...(m.don_vi || []).map(d => 'dv_' + bo(d).replace(/[^a-z0-9]+/g, '')),
  m.so_tien ? 'tien_' + Math.min(9, Math.floor(Math.log10(+m.so_tien))) : null].filter(Boolean);
const LUAT = { luong: /lương|bhxh|bảo hiểm xã hội|thưởng|phụ cấp|bhyt/i, thue_nha: /thuê nhà|thuê kho|thuê mặt bằng|tiền nhà|tiền thuê|thuê cửa hàng/i,
  van_chuyen: /vận chuyển|\bship|cước|giao hàng|chành|xe tải|nhất tín|viettel post|ghtk|ghn/i, ngan_hang: /qltk|sms|phí dịch vụ|lãi vay|khoản vay|thẻ tín dụng|visa|thu phi|phi quan ly/i,
  marketing: /quảng cáo|facebook|\bads\b|marketing|in ấn|banner|kol|tiktok|livestream/i, ncc: /nhập hàng|tiền hàng|\bncc\b|nhà cung cấp|cọc hàng|mua hàng/i,
  dien_nuoc: /tiền điện|tiền nước|internet|wifi|viễn thông/i, thue: /thuế|gtgt|tncn|môn bài/i };
function hocLuat(mau) {   // luật nào trong mẫu đủ ≥5 phiếu và ≥80% cùng 1 loại thì dùng
  const out = [];
  for (const [ten, re] of Object.entries(LUAT)) { const m = mau.filter(x => re.test(x.noi_dung)); if (m.length < 5) continue;
    const c = {}; m.forEach(x => c[x.loai] = (c[x.loai] || 0) + 1); const [l, n] = Object.entries(c).sort((a, b) => b[1] - a[1])[0];
    if (n / m.length >= 0.8) out.push({ ten, re, loai: l, ty: n / m.length, n: m.length }); }
  return out.sort((a, b) => b.ty - a.ty);
}
function hoc(mau) {   // mau: [{noi_dung, thu_huong_ten, loai}]
  const df = new Map(), docs = mau.map(m => { const t = [...tu(m.noi_dung + ' ' + (m.thu_huong_ten || '')), ...them(m)]; new Set(t).forEach(x => df.set(x, (df.get(x) || 0) + 1)); return { ...m, t }; });
  const N = docs.length, idf = x => Math.log((N + 1) / ((df.get(x) || 0) + 1)) + 1;
  const vec = t => { const v = new Map(); t.forEach(x => v.set(x, (v.get(x) || 0) + 1)); let n = 0; for (const [k, c] of v) { const w = c * idf(k); v.set(k, w); n += w * w; } n = Math.sqrt(n) || 1; for (const [k, w] of v) v.set(k, w / n); return v; };
  docs.forEach(d => d.v = vec(d.t));
  // người thụ hưởng là NHÂN VIÊN (cũng là người đề nghị trong mẫu) = nhận tiền đi trả hộ → không suy loại theo tên (sửa 09/10)
  const nhanVien = new Set(mau.map(m => nguoiTH(m.nguoi_de_nghi)).filter(Boolean));
  const theoTH = new Map(); docs.forEach(d => { const k = nguoiTH(d.thu_huong_ten); if (k && !nhanVien.has(k)) (theoTH.get(k) || theoTH.set(k, []).get(k)).push(d.loai); });
  return { docs, vec, theoTH, luat: hocLuat(mau) };
}
function gan(md, p) {   // p: {noi_dung, thu_huong_ten} → {loai, tin: 'cao'|'vua'|'thap', cach, diem}
  // luật từ khoá RẤT CHẮC (≥90% trong mẫu) xét TRƯỚC người thụ hưởng — vd phiếu lương của nhân viên từng được hoàn ứng loại Khác (sửa 09/10)
  const lu0 = (md.luat || []).find(x => x.ty >= 0.9 && x.re.test(p.noi_dung || ''));
  if (lu0) return { loai: lu0.loai, tin: 'cao', cach: 'từ khoá "' + lu0.ten + '"', diem: Math.round(lu0.ty * 100) / 100 };
  const k = nguoiTH(p.thu_huong_ten), ds = k && md.theoTH.get(k);
  if (ds && ds.length >= 2) { const c = {}; ds.forEach(l => c[l] = (c[l] || 0) + 1); const [l, n] = Object.entries(c).sort((a, b) => b[1] - a[1])[0];
    if (n / ds.length >= 0.8) return { loai: l, tin: 'cao', cach: 'thụ hưởng', diem: n / ds.length }; }
  const lu = (md.luat || []).find(x => x.re.test(p.noi_dung || ''));
  if (lu) return { loai: lu.loai, tin: lu.ty >= 0.9 ? 'cao' : 'vua', cach: 'từ khoá "' + lu.ten + '"', diem: Math.round(lu.ty * 100) / 100 };
  const v = md.vec([...tu(p.noi_dung + ' ' + (p.thu_huong_ten || '')), ...them(p)]);
  const sim = md.docs.map(d => { let s = 0; for (const [x, w] of v) { const y = d.v.get(x); if (y) s += w * y; } return { d, s }; }).sort((a, b) => b.s - a.s).slice(0, 7);
  const c = {}; sim.forEach(({ d, s }) => c[d.loai] = (c[d.loai] || 0) + s);
  const xep = Object.entries(c).sort((a, b) => b[1] - a[1]); if (!xep.length || !sim[0].s) return { loai: null, tin: 'thap', cach: 'không có mẫu giống', diem: 0 };
  const tong = xep.reduce((a, x) => a + x[1], 0), ty = xep[0][1] / tong, top = sim[0].s;
  return { loai: xep[0][0], tin: ty >= 0.75 && top >= 0.5 ? 'cao' : ty >= 0.5 && top >= 0.3 ? 'vua' : 'thap', cach: 'nội dung giống', diem: Math.round(ty * 100) / 100 };
}
module.exports = { hoc, gan };
if (require.main === module && process.argv[2] === 'cham') (async () => {
  const ds = await sql(`select c.noi_dung, c.thu_huong_ten, c.nguoi_de_nghi, l.ten loai, c.ngay_tt::text ngay, c.so_tien, (select ten from kt_don_vi where id = c.bo_phan_id) bo_phan,
    array(select d.ten from jsonb_array_elements(c.phan_bo) e join kt_don_vi d on d.id = (e->>'don_vi_id')::int) don_vi from kt_chi c join kt_loai l on l.id = c.loai_id
    where not c.da_xoa and c.trang_thai = 'da_tt' and c.nguon = 'sheet_cu' and c.ngay_tt between '2026-05-01' and '2026-09-30'`);
  const hocMau = ds.filter(x => x.ngay < '2026-08-01'), thu = ds.filter(x => x.ngay >= '2026-08-01');
  const md = hoc(hocMau); const kq = { cao: [0, 0], vua: [0, 0], thap: [0, 0] }; const sai = {};
  for (const p of thu) { const g = gan(md, p); kq[g.tin][1]++; if (g.loai === p.loai) kq[g.tin][0]++; else { const k = p.loai + ' → ' + g.loai; sai[k] = (sai[k] || 0) + 1; } }
  const tong = thu.length, dung = kq.cao[0] + kq.vua[0] + kq.thap[0];
  console.log('Luật từ khoá dùng:', md.luat.map(x => x.ten + '→' + x.loai.slice(0, 18) + ' ' + Math.round(x.ty * 100) + '%/' + x.n).join(' · '));
  console.log(`Học ${hocMau.length} phiếu (T5–T7) · gán thử ${tong} phiếu (T8–T9) · ĐÚNG ${dung}/${tong} = ${Math.round(dung * 100 / tong)}%`);
  for (const t of ['cao', 'vua', 'thap']) console.log(`  độ tin ${t.padEnd(4)}: ${kq[t][1]} phiếu, đúng ${kq[t][0]} (${kq[t][1] ? Math.round(kq[t][0] * 100 / kq[t][1]) : 0}%)`);
  console.log('Hay nhầm nhất:'); Object.entries(sai).sort((a, b) => b[1] - a[1]).slice(0, 8).forEach(([k, n]) => console.log('  ', n, 'x', k));
})();
// regan: gán LẠI các phiếu Claude đã gán (chưa ai sửa) bằng bộ gán mới nhất, học trên mọi phiếu kế toán gán từ 01/05 (anh: "dùng logic cao nhất", 09/10)
if (require.main === module && process.argv[2] === 'regan') (async () => {
  const { sql } = require('./sql'); const GHI = process.argv[3] === 'ghi'; const J = x => '$kt$' + x + '$kt$';
  const cot = `c.id, c.noi_dung, c.thu_huong_ten, c.nguoi_de_nghi, c.so_tien, c.ghi_chu, l.ten loai, (select ten from kt_don_vi where id = c.bo_phan_id) bo_phan,
    array(select d.ten from jsonb_array_elements(c.phan_bo) e join kt_don_vi d on d.id = (e->>'don_vi_id')::int) don_vi`;
  const mau = await sql(`select ${cot} from kt_chi c join kt_loai l on l.id = c.loai_id where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt >= '2026-05-01' and coalesce(c.ghi_chu, '') not like '[Claude gán%'`);
  const md = hoc(mau); console.log('Mẫu', mau.length, '· luật:', md.luat.map(x => x.ten + '→' + x.loai.slice(0, 16)).join(' · '));
  const ds = await sql(`select ${cot} from kt_chi c left join kt_loai l on l.id = c.loai_id where not c.da_xoa and c.sua_boi is null and c.ghi_chu like '[Claude gán loại chi%'`);
  const lo = await sql(`select id, ten from kt_loai where nhom = 'chi'`); const doi = []; const tin = { cao: 0, vua: 0, thap: 0 }; const chuyen = {};
  for (const p of ds) { const g = gan(md, p); if (!g.loai) continue; tin[g.tin]++;
    const nhan = `[Claude gán loại chi — tin ${g.tin === 'vua' ? 'vừa' : g.tin === 'thap' ? 'thấp' : 'cao'} (${g.cach})]`;
    const ghi = p.ghi_chu.replace(/^\[Claude gán loại chi — [^\]]*\]/, nhan);
    if (g.loai !== p.loai) { const k = (p.loai || '?').slice(0, 20) + ' → ' + g.loai.slice(0, 20); chuyen[k] = (chuyen[k] || 0) + 1; }
    if (g.loai !== p.loai || ghi !== p.ghi_chu) doi.push({ id: p.id, loai_id: lo.find(x => x.ten === g.loai).id, ghi_chu: ghi }); }
  console.log('Phiếu Claude gán:', ds.length, '· đổi loại:', Object.values(chuyen).reduce((a, b) => a + b, 0), '· mức tin mới', JSON.stringify(tin));
  Object.entries(chuyen).sort((a, b) => b[1] - a[1]).slice(0, 12).forEach(([k, n]) => console.log('  ', n, 'x', k));
  if (!GHI) return console.log('(CHẠY THỬ)');
  await sql(`update kt_chi c set loai_id = x.loai_id, ghi_chu = x.ghi_chu from jsonb_to_recordset(${J(JSON.stringify(doi))}::jsonb) as x(id bigint, loai_id int, ghi_chu text) where c.id = x.id and c.sua_boi is null`);
  await sql(`insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Monsieur Claude', 'kt_chi', 'gan_lai_loai_chi', ${J(JSON.stringify({ so: doi.length, tin }))}::jsonb)`);
  console.log('ĐÃ GHI', doi.length, 'phiếu');
})();
