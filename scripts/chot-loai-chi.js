// CHỐT LOẠI CHI cho các khoản cùng nội dung bị gán lệch (anh 09/10/2026: "cái này m tự quyết, người hay nhầm lắm") — Monsieur Claude
// Nguyên tắc: theo bản chất khoản chi (hướng hạch toán chuẩn): phí dịch vụ ngân hàng = chi phí quản lý (không phải lãi vay);
// chi phí phát sinh khi MUA HÀNG nhập về (phí chuyển tiền nước ngoài, vận chuyển hàng TQ) = giá vốn; trả thẻ tín dụng công ty = Tài chính (trả vay ngắn hạn).
// Dùng chung cho scripts/gan-loai-chi.js (xét TRƯỚC mọi cách gán khác). Chạy: Code.exe scripts/chot-loai-chi.js [ghi]
const CHOT = [
  // trả nợ THẺ TÍN DỤNG công ty (sao kê, phí + lãi thẻ) = trả khoản vay ngắn hạn → Tài chính (kế toán gán vậy ~30 lần; không đoán thẻ quẹt mua gì)
  { ten: 'Trả thẻ tín dụng công ty (sao kê, phí lãi thẻ)', re: /visa business|thanh to[aá]n sk|k[yỳ] sao k[eê]|phi va lai/i, loai: 'FINANCE - Tài chính - vay,lãi' },
  { ten: 'Phí dịch vụ ngân hàng', re: /qltk|sms ?banking|thu phi dich vu sms|phí ngân hàng|phi ngan hang|phí nộp tiền vào|phi quan ly tk/i, loai: 'OPEX - Vận hành & Quản lí' },
  { ten: 'Mua hàng nhập: phí chuyển tiền NN, vận chuyển TQ', re: /ctnn|vận chuyển tq|vc tq|van chuyen tq/i, loai: 'COGS - Giá vốn & Nhập Hàng' },
  { ten: 'NCC hàng hoá (Thảo Nến)', re: /ncc thảo nến/i, loai: 'COGS - Giá vốn & Nhập Hàng' },
  { ten: 'Tiền điện', re: /tiền điện(?! thoại)/i, loai: 'OPEX - Vận hành & Quản lí' },
  { ten: 'Bù quỹ ngoài cửa hàng', re: /quỹ ngoài/i, loai: 'OPEX - Vận hành & Quản lí' },
  { ten: 'Chưa rõ nguyên nhân', re: /chưa rõ nguyên nhân/i, loai: 'OPEX - Khác' },
  { ten: 'Chuyển tiền mặt cho bà Bùi Thị Hiền', re: /bùi thị hiền/i, loai: 'OPEX - Khác' },
];
const chot = nd => CHOT.find(c => c.re.test(String(nd || '')));
module.exports = { CHOT, chot };
if (require.main === module) (async () => {
  const { sql } = require('./sql'); const GHI = process.argv[2] === 'ghi'; const J = x => '$kt$' + x + '$kt$';
  const lo = await sql(`select id, ten from kt_loai where nhom = 'chi'`); const idLo = t => (lo.find(x => x.ten === t) || {}).id;
  const ds = await sql(`select c.id, c.noi_dung, l.ten loai, c.ngay_tt::text ngay from kt_chi c left join kt_loai l on l.id = c.loai_id where not c.da_xoa and c.loai_id is not null`);
  const doi = [], bao = {};
  for (const p of ds) { const c = chot(p.noi_dung); if (!c) continue; const b = bao[c.ten] = bao[c.ten] || { khop: 0, doi: {} }; b.khop++;
    if (p.loai !== c.loai) { b.doi[p.loai] = (b.doi[p.loai] || 0) + 1; doi.push({ id: p.id, loai_id: idLo(c.loai), tu: p.loai, sang: c.loai }); } }
  for (const [t, b] of Object.entries(bao)) console.log(t.padEnd(46), 'khớp', b.khop, '· đổi', Object.values(b.doi).reduce((a, x) => a + x, 0), Object.keys(b.doi).length ? '(từ ' + Object.entries(b.doi).map(([l, n]) => l.slice(0, 22) + ':' + n).join(', ') + ')' : '');
  console.log('Tổng phiếu đổi loại:', doi.length);
  if (!GHI) return console.log('(CHẠY THỬ)');
  await sql(`update kt_chi c set loai_id = x.loai_id from jsonb_to_recordset(${J(JSON.stringify(doi))}::jsonb) as x(id bigint, loai_id int) where c.id = x.id`);
  await sql(`insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Monsieur Claude', 'kt_chi', 'chot_loai_chi', ${J(JSON.stringify({ so: doi.length, chi_tiet: doi.slice(0, 500) }))}::jsonb)`);
  console.log('ĐÃ GHI', doi.length, 'phiếu (nhật ký lưu loại cũ để hoàn tác nếu cần)');
})();
