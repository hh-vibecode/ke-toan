// Kết nối KiotViet Public API cho app kế toán (luồng RIÊNG, anh chốt 05/10). CHỈ ĐỌC (GET).
// Khoá đọc từ kt-keys.local.txt / biến môi trường (GitHub Actions), không in ra. Monsieur Claude
const { docKhoa } = require('./khoa');
let K = {}; try { K = docKhoa(); } catch (e) {}
const env = n => process.env[n] || K[n];
let token = null;
async function layToken() {
  if (token) return token;
  const r = await fetch('https://id.kiotviet.vn/connect/token', { method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ scopes: 'PublicApi.Access', grant_type: 'client_credentials',
      client_id: env('KIOT_CLIENT_ID'), client_secret: env('KIOT_CLIENT_SECRET') }) });
  if (!r.ok) throw new Error('Kiot token lỗi ' + r.status);
  token = (await r.json()).access_token; return token;
}
async function get(duong, tham = {}) {
  const qs = new URLSearchParams(tham);
  for (let lan = 0; lan < 4; lan++) {
    const r = await fetch(`https://public.kiotapi.com/${duong}?${qs}`, { headers: { Retailer: env('KIOT_RETAILER'), Authorization: 'Bearer ' + await layToken() } });
    if (r.status === 429 || r.status >= 500) { await new Promise(s => setTimeout(s, 1500 * (lan + 1))); continue; }
    const t = await r.text();
    if (!r.ok) throw new Error(`Kiot ${duong} lỗi ${r.status}: ${t.slice(0, 300)}`);
    return JSON.parse(t);
  }
  throw new Error('Kiot ' + duong + ' lỗi lặp lại');
}
// Lấy hết các trang (pageSize 100)
async function getHet(duong, tham = {}) {
  let all = [], off = 0, total = Infinity;
  while (off < total) {
    const j = await get(duong, { ...tham, pageSize: 100, currentItem: off });
    total = j.total || 0; const d = j.data || []; all = all.concat(d);
    if (!d.length) break; off += d.length; await new Promise(s => setTimeout(s, 120));
  }
  return all;
}
module.exports = { get, getHet };
