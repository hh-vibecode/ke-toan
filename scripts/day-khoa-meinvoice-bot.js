// Đẩy khoá MISA "Xử lý hóa đơn" (meInvoice Bot — hoá đơn ĐẦU VÀO) từ kt-keys.local.txt lên Supabase secrets (tiền tố KT_), để Edge Function dùng.
// CHẠY TRÊN MÁY ANH (phiên cloud không đọc được file khoá trên máy anh): ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" scripts/day-khoa-meinvoice-bot.js
// Lấy mọi dòng tên bắt đầu MEINVOICE_BOT_ trong file khoá → secret KT_MEINVOICE_BOT_<...>. CHỈ in TÊN, không in giá trị. Monsieur Claude 14/10/2026
const { docKhoa } = require('./khoa');
const K = docKhoa(), REF = 'bcrpxfvvjsjpvbksqzls';
(async () => {
  const ten = Object.keys(K).filter(k => /^MEINVOICE_BOT_/.test(k));
  if (!ten.length) {
    console.log('Không thấy dòng nào tên MEINVOICE_BOT_... trong kt-keys.local.txt. Các tên có chữ MEINVOICE / MISA đang có:',
      Object.keys(K).filter(k => /MEINVOICE|MISA/.test(k)).join(', ') || '(không có)');
    console.log('Thêm vào file khoá các dòng: MEINVOICE_BOT_CLIENT_ID, MEINVOICE_BOT_CLIENT_SECRET (lấy ở developer.misa.vn → Xử lý hóa đơn → Xem chi tiết), rồi chạy lại.');
    process.exit(1);
  }
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/secrets`, { method: 'POST',
    headers: { Authorization: 'Bearer ' + K.SUPABASE_ACCESS_TOKEN, 'Content-Type': 'application/json' },
    body: JSON.stringify(ten.map(n => ({ name: 'KT_' + n, value: K[n] }))) });
  console.log(r.ok ? 'Đã đẩy lên Supabase: ' + ten.map(n => 'KT_' + n).join(', ') : 'Lỗi ' + r.status + ' ' + (await r.text()).slice(0, 200));
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
