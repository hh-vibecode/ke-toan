// Tạo khuôn xuất sao kê `mau-sao-ke.xlsx` từ file mẫu kế toán "SAO KÊ CÁC TK THÁNG 9.2026.xlsx" (Desktop) — 20/11/2026, Monsieur Claude.
// Kế toán: "xuất ra chuẩn y như mẫu, hàng nào cột A thì phải là cột A, cột B phải là B" (bà thuế đặt công thức theo ô).
// Giữ NGUYÊN định dạng, độ rộng cột, chiều cao hàng, gộp ô, phần đầu + phần cuối của từng kiểu sao kê; bỏ hết dòng giao dịch, chỉ giữ 1 hàng mẫu
// (định dạng, không giá trị). Ô theo kỳ (số TK, ngày, số dư...) xoá trắng — app điền lúc xuất. CIF / số điện thoại / mã khách VIB KHÔNG đưa vào
// (repo công khai). Chạy: ELECTRON_RUN_AS_NODE=1 Code.exe scripts/tao-mau-sao-ke.js <đường dẫn exceljs.min.js 4.4.0> [file mẫu]
const fs = require('fs'), path = require('path');
const E = require(process.argv[2]);
const MAU = process.argv[3] || path.join(require('os').homedir(), 'Desktop', 'SAO KÊ CÁC TK THÁNG 9.2026.xlsx');
// ten: tab mẫu · h: hàng tên cột · d: hàng dữ liệu đầu · het: hàng dữ liệu cuối trong mẫu · xoa: ô theo kỳ / riêng tư (xoá trắng)
const KIEU = {
  VCB: { ten: 'vcb 599', h: 14, d: 15, het: 114, xoa: ['F3', 'C4', 'C8', 'C10', 'F10', 'C11', 'C12', 'C116', 'C117', 'C118'] },
  VIB: { ten: 'vib', h: 16, d: 17, het: 20, xoa: ['C5', 'C6', 'C7', 'C9', 'C10', 'C11', 'C12', 'C13'] },
  THE: { ten: 'THẺ HXT', h: 15, d: 17, het: 19, xoa: ['F5', 'C8', 'C9', 'C10', 'C11', 'B12', 'D12', 'A16'] },
};
const sach = s => { const o = JSON.parse(JSON.stringify(s || {})); if (o.font && o.font.name) o.font.name = o.font.name.replace(/^"(.*)"$/, '$1'); return o; };
const so = a => { const m = /^([A-Z]+)(\d+)$/.exec(a); return [+m[2], m[1].split('').reduce((t, ch) => t * 26 + ch.charCodeAt(0) - 64, 0)]; };
const chu = c => { let s = ''; while (c) { const m = (c - 1) % 26; s = String.fromCharCode(65 + m) + s; c = (c - 1 - m) / 26; } return s; };
(async () => {
  const goc = new E.Workbook(); await goc.xlsx.load(fs.readFileSync(MAU));
  const ra = new E.Workbook(); ra.creator = 'App kế toán';
  for (const [k, m] of Object.entries(KIEU)) {
    const g = goc.getWorksheet(m.ten), w = ra.addWorksheet(k, { views: (g.views || []).map(v => ({ ...v, activeCell: undefined })) });
    const maxC = g.columnCount, xoa = new Set(m.xoa);
    let maxR = m.d; g.eachRow((row, r) => { row.eachCell(c => { if (c.value != null && c.value !== '') maxR = Math.max(maxR, r); }); });
    for (let c = 1; c <= maxC; c++) { const gc = g.getColumn(c); w.getColumn(c).width = gc.width; if (gc.hidden) w.getColumn(c).hidden = true; }
    const dich = r => r <= m.d ? r : r > m.het ? r - m.het + m.d : null;   // hàng mẫu → hàng khuôn (bỏ hàng giao dịch 2..n)
    for (let r = 1; r <= maxR; r++) {
      const t = dich(r); if (!t) continue; const gr = g.getRow(r), wr = w.getRow(t);
      if (gr.height) wr.height = gr.height;
      gr.eachCell({ includeEmpty: true }, (c, ci) => { const o = wr.getCell(ci); o.style = sach(c.style);
        if (r === m.d || xoa.has(chu(ci) + r)) return; if (c.value != null && c.value !== '') { o.value = c.value; } });
    }
    for (const mg of g.model.merges || []) { const [a, b] = mg.split(':'), [r1, c1] = so(a), [r2, c2] = so(b), t1 = dich(r1), t2 = dich(r2);
      if (t1 && t2 && (r1 <= m.d) === (r2 <= m.d)) w.mergeCells(t1, c1, t2, c2); }
    console.log(k, '← tab', m.ten, '· tên cột hàng', m.h, '· dữ liệu từ hàng', m.d, '· phần cuối', m.het < maxR ? 'có' : 'không', '· hàng khuôn', w.rowCount);
  }
  const out = path.join(__dirname, '..', 'mau-sao-ke.xlsx'); fs.writeFileSync(out, Buffer.from(await ra.xlsx.writeBuffer())); console.log('Đã ghi', out);
})().catch(e => { console.log('LỖI', e.stack); process.exit(1); });
