// Kéo dữ liệu Kiot CŨ theo từng tháng qua Edge Function kt-kiot (cùng cách chuyển dữ liệu như job 3 tiếng) — 09/10/2026,
// anh: "xử lý hết số liệu của 2026". Sổ quỹ + hoá đơn + trả hàng + nhập hàng từ 01/01/2026; phiếu thu Kiot chỉ chép vào kt_thu từ THU_TU.
// Chạy: Code.exe scripts/keo-kiot-cu.js [2026-01] [2026-08] [THU_TU=2026-05-01]. Khoá KT_CRON_KEY đọc từ file, không in. Monsieur Claude
const { docKhoa } = require('./khoa'); const K = docKhoa();
const [tuT = '2026-01', denT = '2026-08', THU_TU = '2026-05-01'] = process.argv.slice(2);
const thang = []; for (let d = new Date(tuT + '-01T00:00:00Z'); d.toISOString().slice(0, 7) <= denT; d.setUTCMonth(d.getUTCMonth() + 1)) thang.push(d.toISOString().slice(0, 7));
const sau = t => { const d = new Date(t + '-01T00:00:00Z'); d.setUTCMonth(d.getUTCMonth() + 1); return d.toISOString().slice(0, 10); };
(async () => {
  for (const t of thang) {
    const body = { tu: t + '-01', den: sau(t), thu_tu: THU_TU, chi: ['so_quy', 'hoa_don', 'tra_hang', 'nhap_hang'], day_du: ['hoa_don', 'tra_hang', 'nhap_hang'] };
    const bd = Date.now();
    const r = await fetch('https://bcrpxfvvjsjpvbksqzls.supabase.co/functions/v1/kt-kiot', { method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-kt-cron': K.KT_CRON_KEY }, body: JSON.stringify(body) });
    const j = await r.json().catch(() => ({}));
    const sq = j.so_quy || {}, db = sq.dong_bo || {};
    console.log(t, r.status, `sổ quỹ ${sq.so_phieu ?? '?'} · HĐ ${(j.hoa_don || {}).so_dong ?? '?'} · trả ${(j.tra_hang || {}).so_dong ?? '?'} · nhập ${(j.nhap_hang || {}).so_dong ?? '?'}`,
      `· thu mới ${db.them ?? '?'} · giá vốn ${JSON.stringify(j.gia_von ?? '?')} · ${Math.round((Date.now() - bd) / 1000)}s`, j.loi ? 'LỖI ' + j.loi : '');
    if (!r.ok) { console.log('DỪNG ở tháng', t); process.exit(1); }
  }
})();
