// Tự gán phiếu chi loại OPEX cũ (6–11) sang danh mục P&L mới (mã 1.1 … 9.4) theo nội dung (21/10/2026, anh chọn "hệ thống tự gán").
// Khớp từ khoá → gan_loai_tu_dong = 'vua'; không khớp, dùng mặc định theo loại cũ → 'thap'. Kế toán soát ở Phiếu chi → nguồn "Tự gán loại — cần soát".
// Chạy: Code.exe scripts/gan-loai-pl.js [ghi]   (không có "ghi" = chạy thử, chỉ in thống kê) — Monsieur Claude
const { sql } = require('./sql');
const GHI = process.argv[2] === 'ghi';
const bo = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D').toLowerCase();
// [mã, regex trên nội dung không dấu] — thứ tự = ưu tiên
const LUAT = [
  ['5.1.1', /\bseo\b/], ['5.1.2', /thiet ke|design/], ['5.1.3', /quay|dung video|edit video|video/], ['5.1.4', /chup anh|chup hinh|photo/], ['5.1.5', /co van hinh anh/],
  ['5.2', /quang cao|\bads\b|facebook|tiktok|\bmeta\b|google ads|nap tien (fb|tk quang cao)|chay qc|\bqc\b/],
  ['5.3', /pancake|phan mem (ho tro )?mkt|botcake|harasocial|haravan|zalo oa/],
  ['5.1', /marketing|mkt|kol|koc|livestream|booking|seeding|in an|bang ron|banner|standee|to roi|catalog/],
  ['4.4', /phan mem|kiotviet|kiot viet|misa|domain|ten mien|hosting|server|google workspace|gmail|icloud|chatgpt|claude|canva|license|chat ?gpt|gia han pm/],
  ['4.5', /dich vu ke toan|bao cao thue|kiem toan|phap ly|luat su|cong chung|thu tuc|dkkd|dang ky kinh doanh|dia diem kinh doanh/],
  ['4.10', /dao tao|khoa hoc|hoc phi|training|top ?cv|tuyen dung|vieclam|viec lam/],
  ['4.8', /team building|sinh nhat|lien hoan|qua tet|qua trung thu|teambuilding|du lich/],
  ['9.2', /phi ngan hang|phi chuyen tien|phi chuyen khoan|phi giao dich|phi quan ly tk|qltk|sms ?banking|bsms|phi dich vu sms|phi rut tien|phi nop tien|thu phi/],
  ['9.1', /van phong pham|vpp|giay in|but bi|muc in|do muc/],
  ['9.4', /hong huy|hang hong|vo hong|huy hang/],
  ['6.2', /tien dien(?! thoai)/], ['6.3', /tien nuoc|nuoc sinh hoat/], ['6.4', /dien thoai|cuoc vien thong|sim|di dong/], ['6.5', /internet|wifi|cap quang|\bfpt\b|\bvnpt\b|viettel internet/],
  ['3.2', /thue kho|kho tong/],
  ['6.1', /thue (cua hang|mat bang|nha)|tien nha|mat bang/],
  ['7.1', /bao bi|bang dinh|thung carton|thung giay|hop|xop|mang (bong|pe)|tui (nilon|zip)|day buoc/],
  ['7.2', /van chuyen|ship|giao hang|\bcod\b|ghn|ghtk|viettel ?post|nhat tin|j&t|jt express|ninja|xe tai|xe om|grab|cuoc xe|boc xep|chanh xe/],
  ['8.2', /khau hao|dieu hoa|cay nong lanh|may tinh moi|mua may|tam san|ban ghe|lap dat/], ['8.1', /sua chua|bao hanh|bao tri|thay the|sua (may|xe|dien|nuoc|cua)/],
  ['1.2', /hoa hong|thuong doanh so|thuong ban hang/],
  ['4.1', /luong (bgd|giam doc|ban giam doc)/], ['4.2', /luong (ke toan|van phong|backoffice|hanh chinh|nhan su)/], ['3.1', /luong kho|nhan vien kho/],
  ['9.3', /quy ngoai|quy kho|than tai/],
  ['1.1', /luong|bhxh|bao hiem xa hoi|thuong|phu cap|tang ca/],
  ['4.3', /van phong|hanh chinh|nuoc uong|ve sinh|tiep khach|cong tac|xang|di lai|ve may bay|khach san|luu tru/]
];
const MAC_DINH = { 6: '1.1', 7: '5.1', 8: '6.1', 9: '7.2', 10: '4.11', 11: '9.3' };
(async () => {
  const L = await sql(`select id, ma from kt_loai where nhom = 'chi' and ma is not null`);
  const id = Object.fromEntries(L.map(x => [x.ma, x.id]));
  const ds = await sql(`select id, loai_id, noi_dung, thu_huong_ten from kt_chi where not da_xoa and loai_id in (6,7,8,9,10,11)`);
  const tk = {}, sua = [];
  for (const x of ds) {
    const t = bo(x.noi_dung + ' ' + (x.thu_huong_ten || ''));
    let ma = null, muc = 'vua';
    // loại cũ là Lương thì chỉ xét luật lương; Logistics chỉ xét vận chuyển / bao bì; còn lại xét hết
    const luat = x.loai_id === 6 ? LUAT.filter(([m]) => /^(1\.|3\.1|4\.1|4\.2)/.test(m)) : x.loai_id === 9 ? LUAT.filter(([m]) => /^(7\.|3\.2)/.test(m)) : LUAT;
    for (const [m, re] of luat) if (re.test(t)) { ma = m; break; }
    if (!ma) { ma = MAC_DINH[x.loai_id]; muc = 'thap'; }
    tk[x.loai_id + '→' + ma + ' (' + muc + ')'] = (tk[x.loai_id + '→' + ma + ' (' + muc + ')'] || 0) + 1;
    sua.push(`(${x.id},${id[ma]},'${muc}')`);
  }
  Object.entries(tk).sort().forEach(([k, n]) => console.log(String(n).padStart(4), k));
  console.log('Tổng', ds.length, GHI ? '— GHI' : '— CHẠY THỬ');
  if (GHI && sua.length) {
    for (let i = 0; i < sua.length; i += 400)
      await sql(`update kt_chi c set loai_id = v.l, gan_loai_tu_dong = v.m from (values ${sua.slice(i, i + 400).join(',')}) v(id, l, m) where c.id = v.id and c.loai_id in (6,7,8,9,10,11)`);
    console.log('Đã ghi', sua.length);
  }
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
