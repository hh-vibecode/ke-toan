// Kéo BÙ 1 lần (14/10/2026) các dữ liệu Kiot mới thêm, cho năm 2026 — CHỈ ĐỌC Kiot. Monsieur Claude
//   · hoá đơn đã có: CHỈ cập nhật kenh_id, ghi_chu, cod, dat_hang_id (KHÔNG kéo lại cả hoá đơn → giữ nguyên giá vốn đã tính lúc bán)
//   · đơn đặt hàng 2026 → kt_kiot_dat_hang · nhóm hàng cha/con → kt_kiot_nhom · kênh bán → kt_kiot_kenh
// Sau đó Edge Function kt-kiot tự kéo phần mới (15 phút / lần). Chạy: Code.exe scripts/keo-bu-kiot-them.js [ghi]
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const K = docKhoa(), GHI = process.argv[2] === 'ghi', J = x => '$kt$' + JSON.stringify(x) + '$kt$';
const vn = s => s ? String(s).slice(0, 19) + '+07:00' : null, ngu = ms => new Promise(r => setTimeout(r, ms));
let H;
async function het(duong, tham) {
  const all = []; let off = 0, total = Infinity;
  while (off < total) {
    let r; for (let lan = 0; lan < 5; lan++) { r = await fetch(`https://public.kiotapi.com/${duong}?${new URLSearchParams({ ...tham, pageSize: '100', currentItem: String(off) })}`, { headers: H }); if (r.status !== 429 && r.status < 500) break; await ngu(2000 * (lan + 1)); }
    if (!r.ok) throw new Error(duong + ' lỗi ' + r.status);
    const j = await r.json(); total = j.total || 0; const d = j.data || []; all.push(...d); if (!d.length) break; off += d.length; await ngu(250);
  }
  return all;
}
(async () => {
  const t = await (await fetch('https://id.kiotviet.vn/connect/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ scopes: 'PublicApi.Access', grant_type: 'client_credentials', client_id: K.KIOT_CLIENT_ID, client_secret: K.KIOT_CLIENT_SECRET }) })).json();
  H = { Retailer: K.KIOT_RETAILER, Authorization: 'Bearer ' + t.access_token };
  const thang = []; for (let m = 1; m <= 12; m++) { const tu = `2026-${String(m).padStart(2, '0')}-01`; if (tu > new Date().toISOString().slice(0, 10)) break; thang.push([tu, new Date(Date.UTC(2026, m, 1)).toISOString().slice(0, 10)]); }
  // 1. danh mục
  const nhom = await het('categories', { hierachicalData: 'false' });
  const kenh = ((await (await fetch('https://public.kiotapi.com/salechannel', { headers: H })).json()).data) || [];
  console.log('nhóm hàng', nhom.length, '· kênh', kenh.length);
  if (GHI) {
    await sql(`insert into kt_kiot_nhom (id, ten, cha_id, sua_kiot, keo_luc) select (x->>'id')::bigint, x->>'ten', (x->>'cha')::bigint, (x->>'sua')::timestamptz, now() from jsonb_array_elements(${J(nhom.map(c => ({ id: c.categoryId, ten: c.categoryName, cha: c.parentId ?? null, sua: vn(c.modifiedDate ?? c.createdDate) })))}::jsonb) x
      on conflict (id) do update set ten = excluded.ten, cha_id = excluded.cha_id, sua_kiot = excluded.sua_kiot, keo_luc = now()`);
    await sql(`insert into kt_kiot_kenh (id, ten, keo_luc) select (x->>'id')::bigint, x->>'ten', now() from jsonb_array_elements(${J(kenh.map(k => ({ id: k.id, ten: k.name })))}::jsonb) x on conflict (id) do update set ten = excluded.ten, keo_luc = now()`);
  }
  // 2. hoá đơn: chỉ 4 cột mới
  let nHD = 0;
  for (const [tu, den] of thang) {
    const ds = await het('invoices', { fromPurchaseDate: tu, toPurchaseDate: den });
    const rows = ds.map(x => ({ id: x.id, k: x.saleChannelId ?? null, g: x.description ?? null, c: x.usingCod ?? null, d: x.orderId ?? null }));
    if (GHI) for (let i = 0; i < rows.length; i += 500)
      await sql(`update kt_kiot_hoa_don h set kenh_id = (x->>'k')::bigint, ghi_chu = x->>'g', cod = (x->>'c')::boolean, dat_hang_id = (x->>'d')::bigint
        from jsonb_array_elements(${J(rows.slice(i, i + 500))}::jsonb) x where h.id = (x->>'id')::bigint`);
    nHD += rows.length; console.log('hoá đơn', tu.slice(0, 7), rows.length, '· có ghi chú', rows.filter(r => r.g).length);
  }
  // 3. đơn đặt hàng
  let nDH = 0;
  for (const [tu, den] of thang) {
    const ds = (await het('orders', { fromPurchaseDate: tu, toPurchaseDate: den })).filter(x => String(x.purchaseDate) >= tu);
    const rows = ds.map(x => ({ id: x.id, ma: x.code, ngay: vn(x.purchaseDate), chi_nhanh: x.branchName ?? null, nv_ban: x.soldByName ?? null, khach_id: x.customerId ?? null,
      khach_ma: x.customerCode ?? null, khach_ten: x.customerName ?? null, tong: Math.round(+x.total || 0), da_tra: Math.round(+x.totalPayment || 0), trang_thai: x.status ?? null,
      trang_thai_ten: x.statusValue ?? null, kenh_id: x.SaleChannelId ?? x.saleChannelId ?? null, ghi_chu: x.description ?? null, cod: x.usingCod ?? null,
      so_mh: (x.orderDetails || []).length, sua_kiot: vn(x.modifiedDate ?? x.createdDate) }));
    if (GHI) for (let i = 0; i < rows.length; i += 500)
      await sql(`insert into kt_kiot_dat_hang select (x->>'id')::bigint, x->>'ma', (x->>'ngay')::timestamptz, x->>'chi_nhanh', x->>'nv_ban', (x->>'khach_id')::bigint, x->>'khach_ma', x->>'khach_ten',
        (x->>'tong')::numeric, (x->>'da_tra')::numeric, (x->>'trang_thai')::int, x->>'trang_thai_ten', (x->>'kenh_id')::bigint, x->>'ghi_chu', (x->>'cod')::boolean, (x->>'so_mh')::int,
        (x->>'sua_kiot')::timestamptz, now() from jsonb_array_elements(${J(rows.slice(i, i + 500))}::jsonb) x on conflict (id) do update set ma = excluded.ma, ngay = excluded.ngay,
        tong = excluded.tong, da_tra = excluded.da_tra, trang_thai = excluded.trang_thai, trang_thai_ten = excluded.trang_thai_ten, kenh_id = excluded.kenh_id, ghi_chu = excluded.ghi_chu,
        cod = excluded.cod, so_mh = excluded.so_mh, sua_kiot = excluded.sua_kiot, keo_luc = now()`);
    nDH += rows.length; console.log('đơn đặt', tu.slice(0, 7), rows.length);
  }
  console.log((GHI ? 'ĐÃ GHI' : 'CHẠY THỬ') + ' · hoá đơn', nHD, '· đơn đặt', nDH);
  if (GHI) await sql(`insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_kiot', 'keo_bu_kiot_them', ${J({ hoa_don: nHD, dat_hang: nDH, nhom: nhom.length, kenh: kenh.length })}::jsonb)`);
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
