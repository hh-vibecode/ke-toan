// Edge Function kt-kiot — LUỒNG KÉO KIOT RIÊNG của app kế toán (anh chốt 05/10/2026: không dùng chung MKT/Sale, 3 tiếng / lần).
// pg_cron 'kt-kiot' gọi hàm này (header x-kt-cron = secret KT_CRON_KEY). CHỈ ĐỌC Kiot (GET).
// Mỗi lần (mặc định):
//   1. Sổ quỹ 10 ngày gần nhất → kt_kiot_so_quy → kt_dong_bo_kiot() chép phiếu thu sang kt_thu.
//   2. (luồng mới 08/10) Khách · NCC · hàng hoá + tồn kho · hoá đơn · trả hàng · nhập hàng: chỉ phần Kiot SỬA từ lần trước
//      (lastModifiedFrom = mốc sửa mới nhất trong bảng − 2 giờ). Bảng trống → kéo đầy đủ.
//   3. kt_tinh_gia_von() cho hoá đơn mới. Ghi nhật ký.
// Body {"day_du":["khach","hang",...]} = kéo ĐẦY ĐỦ các loại đó (nạp ban đầu); {"chi":[...]} = chỉ chạy các loại đó.
// Kéo DỮ LIỆU CŨ theo khoảng (09/10/2026, anh: xử lý cả năm 2026): {"tu":"2026-01-01","den":"2026-02-01","chi":["so_quy","hoa_don",...],
//   "day_du":["hoa_don",...], "thu_tu":"2026-05-01"} — den KHÔNG gồm; phiếu thu Kiot chỉ chép sang kt_thu từ thu_tu (mặc định = tu).
// SO KHỚP VỚI KIOT (14/10/2026, anh: "làm log lịch sử kéo + dash so sánh khớp Kiot từng tháng"):
//   {"doi_chieu":{"thang":["2026-09"]}} (bỏ trống = tháng này + tháng trước) → kéo LẠI toàn bộ hoá đơn + trả hàng của tháng từ Kiot,
//   so từng mã với bảng app (thiếu / thừa / lệch trạng thái-tiền) + tổng theo chi nhánh → ghi kt_kiot_doi_chieu → tự ghi bù phần thiếu / lệch.
//   Kéo đầy đủ hàng hoá (lịch đêm, hoặc {"day_du":["hang"]}) → so tồn kho app với Kiot TRƯỚC khi ghi đè → ghi kt_kiot_doi_chieu loại 'ton'.
//   Trang web gọi được (Cài đặt → Nhật ký kéo Kiot) bằng {"phien": ...} — hàm kt_quyen_keo kiểm phiên + quyền nhat_ky (sửa).
// Đơn vị quy đổi (14/10/2026): Kiot trả mỗi đơn vị phụ (thùng, tập...) thành 1 dòng hàng riêng có masterUnitId, tồn = tồn gốc ÷ quy đổi
//   → app từng cộng 2 lần vào giá trị tồn. Lưu dv_goc_id / quy_doi; báo cáo tồn chỉ cộng dòng đơn vị gốc (dv_goc_id null).
// Tồn kho giữa ngày (14/10/2026): Kiot không đổi "ngày sửa" hàng khi bán / nhập → lần kéo 3 tiếng lấy lại tồn từng mặt hàng
//   có trong hoá đơn / trả hàng / nhập hàng vừa kéo (kèm dòng đơn vị gốc). Chuyển kho / kiểm kho vẫn chờ lần kéo đầy đủ ban đêm.
// Cảnh báo (14/10/2026): cuối mỗi lần chạy gọi kt_canh_bao_kiot() → lỗi / lệch báo vào chuông app (kèm lịch kt-kiot-canh-bao mỗi giờ).
// Secrets (tiền tố KT_): KT_KIOT_CLIENT_ID, KT_KIOT_CLIENT_SECRET, KT_KIOT_RETAILER, KT_CRON_KEY. Monsieur Claude
const SB = Deno.env.get('SUPABASE_URL')!, SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const MOC = '2026-09-01', SO_NGAY = 10;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type, apikey, authorization, x-kt-cron', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const MAI = () => new Date(Date.now() + 31 * 3600e3).toISOString().slice(0, 10);   // ngày mai giờ VN — Kiot cần đủ cặp từ / đến ngày
let tok = '';

async function kiotToken() {
  const r = await fetch('https://id.kiotviet.vn/connect/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ scopes: 'PublicApi.Access', grant_type: 'client_credentials',
      client_id: Deno.env.get('KT_KIOT_CLIENT_ID')!, client_secret: Deno.env.get('KT_KIOT_CLIENT_SECRET')! }) });
  if (!r.ok) throw new Error('Kiot token lỗi ' + r.status);
  return (await r.json()).access_token as string;
}
async function kiotHet(duong: string, tham: Record<string, string>) {
  const all: any[] = []; let off = 0, total = Infinity;
  while (off < total) {
    const qs = new URLSearchParams({ ...tham, pageSize: '100', currentItem: String(off) });
    let r: Response | null = null;
    for (let lan = 0; lan < 4; lan++) {
      r = await fetch(`https://public.kiotapi.com/${duong}?${qs}`, { headers: { Retailer: Deno.env.get('KT_KIOT_RETAILER')!, Authorization: 'Bearer ' + tok } });
      if (r.status !== 429 && r.status < 500) break;
      await new Promise(s => setTimeout(s, 1500 * (lan + 1)));
    }
    if (!r || !r.ok) throw new Error(`Kiot ${duong} lỗi ${r && r.status}`);
    const j = await r.json(); total = j.total || 0; const d = j.data || [];
    all.push(...d); if (!d.length) break; off += d.length;
  }
  return all;
}
async function kiotMot(duong: string) {   // 1 bản ghi (vd products/{id}); 404 → null
  for (let lan = 0; lan < 4; lan++) {
    const r = await fetch(`https://public.kiotapi.com/${duong}`, { headers: { Retailer: Deno.env.get('KT_KIOT_RETAILER')!, Authorization: 'Bearer ' + tok } });
    if (r.status === 404) return null;
    if (r.ok) return await r.json();
    if (r.status !== 429 && r.status < 500) throw new Error(`Kiot ${duong} lỗi ${r.status}`);
    await new Promise(s => setTimeout(s, 1500 * (lan + 1)));
  }
  throw new Error(`Kiot ${duong} lỗi lặp lại`);
}
const sbH = { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/json' };
const sb = (duong: string, body: unknown, prefer = 'return=minimal') => fetch(SB + '/rest/v1/' + duong, { method: 'POST', headers: { ...sbH, Prefer: prefer }, body: JSON.stringify(body) });
async function ghi(bang: string, rows0: any[]) {
  // Kiot có lúc trả 1 dòng ở 2 trang (dữ liệu đổi khi đang phân trang) → bỏ trùng theo id, giữ bản sau cùng
  const rows = [...new Map(rows0.map(r => [r.id, r])).values()];
  for (let i = 0; i < rows.length; i += 500) {
    const r = await sb(bang + '?on_conflict=id', rows.slice(i, i + 500), 'resolution=merge-duplicates,return=minimal');
    if (!r.ok) throw new Error(`Ghi ${bang} lỗi ${r.status} ${(await r.text()).slice(0, 200)}`);
  }
}
// 14/10/2026: danh mục nhóm hàng (cha / con) + kênh bán — vài chục dòng, kéo đầy đủ
async function danhMuc() {
  const nhom = await kiotHet('categories', { hierachicalData: 'false' });
  await ghi('kt_kiot_nhom', nhom.map((c: any) => ({ id: c.categoryId, ten: c.categoryName, cha_id: c.parentId ?? null, sua_kiot: vn(c.modifiedDate ?? c.createdDate), keo_luc: new Date().toISOString() })));
  const r = await fetch('https://public.kiotapi.com/salechannel', { headers: { Retailer: Deno.env.get('KT_KIOT_RETAILER')!, Authorization: 'Bearer ' + tok } });
  const kenh = r.ok ? ((await r.json()).data || []) : [];
  if (kenh.length) await ghi('kt_kiot_kenh', kenh.map((k: any) => ({ id: k.id, ten: k.name, keo_luc: new Date().toISOString() })));
  return { nhom: nhom.length, kenh: kenh.length };
}
async function mocSua(bang: string) {   // mốc Kiot sửa mới nhất đã có trong bảng (giờ VN, dạng Kiot nhận)
  const r = await fetch(`${SB}/rest/v1/${bang}?select=sua_kiot&sua_kiot=not.is.null&order=sua_kiot.desc&limit=1`, { headers: sbH });
  const j = await r.json(); if (!j.length) return null;
  return new Date(new Date(j[0].sua_kiot).getTime() + 7 * 3600e3 - 2 * 3600e3).toISOString().slice(0, 19);
}
const vn = (s: any) => s ? String(s).slice(0, 19) + '+07:00' : null;
const n0 = (x: any) => x == null ? null : Math.round(Number(x));

// Mỗi loại: đường Kiot · tham số · cách lọc khi kéo đầy đủ · cách đổi sang dòng bảng
const LOAI: Record<string, { bang: string, duong: string, tham: Record<string, string>, dayDu?: (tu: string, den: string) => Record<string, string>, moc?: (x: any, tu: string) => boolean, doi: (x: any) => any }> = {
  khach: { bang: 'kt_kiot_khach', duong: 'customers', tham: { includeTotal: 'true' },
    doi: x => ({ id: x.id, ma: x.code, ten: x.name, sdt: x.contactNumber ?? null, loai: x.type ?? null, chi_nhanh_id: x.branchId ?? null,
      cong_no: n0(x.debt), tong_mua: n0(x.totalInvoiced), tong_mua_tru_tra: n0(x.totalRevenue), tao_kiot: vn(x.createdDate), sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }) },
  ncc: { bang: 'kt_kiot_ncc', duong: 'suppliers', tham: {},
    doi: x => ({ id: x.id, ma: x.code, ten: x.name, sdt: x.contactNumber ?? null, hoat_dong: x.isActive ?? true, cong_no: n0(x.debt),
      tong_nhap: n0(x.totalInvoiced), tong_nhap_tru_tra: n0(x.totalInvoicedWithoutReturn), tao_kiot: vn(x.createdDate), sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }) },
  hang: { bang: 'kt_kiot_hang', duong: 'products', tham: { includeInventory: 'true' },
    doi: x => { const ton = (x.inventories || []).map((i: any) => ({ cn: i.branchName, ton: i.onHand, gia_von: n0(i.cost) }));
      return { id: x.id, ma: x.code, ten: x.fullName || x.name, nhom_id: x.categoryId ?? null, nhom: x.categoryName ?? null, don_vi: x.unit ?? null,
        dv_goc_id: x.masterUnitId ?? null, quy_doi: x.conversionValue ?? 1,
        gia_ban: n0(x.basePrice), hoat_dong: x.isActive ?? true, ton, tong_ton: ton.reduce((s: number, t: any) => s + (Number(t.ton) || 0), 0),
        gia_tri_ton: n0(ton.reduce((s: number, t: any) => s + (Number(t.ton) || 0) * (Number(t.gia_von) || 0), 0)),
        tao_kiot: vn(x.createdDate), sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }; } },
  hoa_don: { bang: 'kt_kiot_hoa_don', duong: 'invoices', tham: {}, dayDu: (tu, den) => ({ fromPurchaseDate: tu, toPurchaseDate: den }), moc: (x, tu) => String(x.purchaseDate) >= tu,
    doi: x => ({ id: x.id, ma: x.code, ngay: vn(x.purchaseDate), chi_nhanh: x.branchName ?? null, nv_ban: x.soldByName ?? null,
      khach_id: x.customerId ?? null, khach_ma: x.customerCode ?? null, khach_ten: x.customerName ?? null, ma_dat_hang: x.orderCode ?? null,
      tong: n0(x.total), da_tra: n0(x.totalPayment), trang_thai: x.status ?? null, trang_thai_ten: x.statusValue ?? null,
      // 14/10/2026 (kế toán): kênh bán · ghi chú đơn (sales ghi đơn vị vận chuyển / thu COD) · ô COD · đơn đặt hàng gốc
      kenh_id: x.saleChannelId ?? null, ghi_chu: x.description ?? null, cod: x.usingCod ?? null, dat_hang_id: x.orderId ?? null,
      chi_tiet: (x.invoiceDetails || []).map((d: any) => ({ sp: d.productId, ma: d.productCode, ten: d.productName, nhom: d.categoryName ?? null,
        sl: d.quantity, gia: n0(d.price), giam: n0(d.discount), tien: n0(d.subTotal), sl_tra: d.returnQuantity ?? 0 })),
      gia_von: null, sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }) },
  // 14/10/2026: ĐƠN ĐẶT HÀNG — "doanh thu đã đánh đơn" + "khách đã cọc chưa đi hàng" (Tổng quan)
  dat_hang: { bang: 'kt_kiot_dat_hang', duong: 'orders', tham: {}, dayDu: (tu, den) => ({ fromPurchaseDate: tu, toPurchaseDate: den }), moc: (x, tu) => String(x.purchaseDate) >= tu,
    doi: x => ({ id: x.id, ma: x.code, ngay: vn(x.purchaseDate), chi_nhanh: x.branchName ?? null, nv_ban: x.soldByName ?? null,
      khach_id: x.customerId ?? null, khach_ma: x.customerCode ?? null, khach_ten: x.customerName ?? null, tong: n0(x.total), da_tra: n0(x.totalPayment),
      trang_thai: x.status ?? null, trang_thai_ten: x.statusValue ?? null, kenh_id: x.SaleChannelId ?? x.saleChannelId ?? null, ghi_chu: x.description ?? null,
      cod: x.usingCod ?? null, so_mh: (x.orderDetails || []).length, sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }) },
  tra_hang: { bang: 'kt_kiot_tra_hang', duong: 'returns', tham: {}, dayDu: (tu, den) => ({ fromReturnDate: tu, toReturnDate: den }), moc: (x, tu) => String(x.returnDate) >= tu,
    doi: x => ({ id: x.id, ma: x.code, hoa_don_id: x.invoiceId ?? null, ngay: vn(x.returnDate), chi_nhanh: x.branchName ?? null,
      tong_tra: n0(x.returnTotal), phi_tra: n0(x.returnFee), da_tra: n0(x.totalPayment), trang_thai: x.status ?? null, trang_thai_ten: x.statusValue ?? null,
      chi_tiet: (x.returnDetails || []).map((d: any) => ({ sp: d.productId, ma: d.productCode, ten: d.productName, sl: d.quantity, gia: n0(d.price), tien: n0(d.subTotal) })),
      sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }) },
  nhap_hang: { bang: 'kt_kiot_nhap_hang', duong: 'purchaseorders', tham: {}, dayDu: (tu, den) => ({ fromPurchaseDate: tu, toPurchaseDate: den }), moc: (x, tu) => String(x.purchaseDate) >= tu,
    doi: x => ({ id: x.id, ma: x.code, ngay: vn(x.purchaseDate), chi_nhanh: x.branchName ?? null, ncc_id: x.supplierId ?? null, ncc_ma: x.supplierCode ?? null,
      ncc_ten: x.supplierName ?? null, tong: n0(x.total), da_tra: n0(x.totalPayment), giam_gia: n0(x.discount), trang_thai: x.status ?? null, mo_ta: x.description ?? null,
      chi_tiet: (x.purchaseOrderDetails || []).map((d: any) => ({ sp: d.productId, ma: d.productCode, ten: d.productName, sl: d.quantity, gia: n0(d.price), giam: n0(d.discount) })),
      sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }) },
};

async function soQuy(khoang?: { tu: string, den: string, thu_tu: string }) {
  const vnNow = new Date(Date.now() + 7 * 3600e3);
  // endDate của Kiot KHÔNG gồm chính ngày đó → lấy tới ngày mai để có phiếu hôm nay
  const den = new Date(vnNow.getTime() + 864e5).toISOString().slice(0, 10), tuD = new Date(vnNow.getTime() - SO_NGAY * 864e5).toISOString().slice(0, 10);
  const tu = khoang ? khoang.tu : (tuD < MOC ? MOC : tuD);
  const cf = await kiotHet('cashflow', { startDate: tu, endDate: khoang ? khoang.den : den, includeAccount: 'true', includeBranch: 'true', includeUser: 'true' });
  await ghi('kt_kiot_so_quy', cf.map(x => ({ id: x.id, ma: x.code, ngay: vn(x.transDate), chi_nhanh: x.branch ?? null, la_thu: x.amount > 0,
    so_tien: Math.abs(Math.round(x.amount)), phuong_thuc: x.method ?? null, tai_khoan: x.accountId ? String(x.accountId) : null, doi_tac: x.partnerName ?? null,
    nhom: x.cashGroup ?? null, noi_dung: x.description ?? null, chung_tu_goc: x.origin ?? null, trang_thai: String(x.status), goc: x, keo_luc: new Date().toISOString() })));
  const d = await sb('rpc/kt_dong_bo_kiot', { p_tu: khoang ? khoang.thu_tu : tu }, 'return=representation');
  return { tu, den: khoang ? khoang.den : den, so_phieu: cf.length, dong_bo: d.ok ? await d.json() : 'lỗi ' + d.status };
}

// ── SO KHỚP VỚI KIOT ──────────────────────────────────────────────────────────
const rpcJ = async (fn: string, body: unknown) => { const r = await sb('rpc/' + fn, body, 'return=representation');
  if (!r.ok) throw new Error(`${fn} lỗi ${r.status} ${(await r.text()).slice(0, 200)}`); return await r.json(); };
const thangSau = (m: string) => { const d = new Date(m + '-01T00:00:00Z'); d.setUTCMonth(d.getUTCMonth() + 1); return d.toISOString().slice(0, 7); };
const cong = (o: any, cn: string, k: string, v: number) => { o[cn] = o[cn] || {}; o[cn][k] = (o[cn][k] || 0) + v; };

// Tháng m ('YYYY-MM'): hoá đơn + trả hàng Kiot (kéo lại toàn bộ) so với bảng app. Chỉ số cùng cách tính báo cáo app:
//   hoá đơn Hoàn thành (trạng thái 1): tiền hàng (Σ dòng) − giảm giá hoá đơn = doanh thu; trả hàng trạng thái 1; doanh thu thuần = doanh thu − trả.
async function doiChieuThang(m: string, nguoi: string) {
  const tu = m + '-01', den = thangSau(m) + '-01', trong = (s: any) => { const x = String(s || '').slice(0, 10); return x >= tu && x < den; };
  const hdK = (await kiotHet('invoices', { fromPurchaseDate: tu, toPurchaseDate: den })).filter(x => trong(x.purchaseDate));
  const thK = (await kiotHet('returns', { fromReturnDate: tu, toReturnDate: den })).filter(x => trong(x.returnDate));
  const db = await rpcJ('kt_kiot_dc_db', { p_tu: tu, p_den: den });   // hd: [id, trạng thái, tổng, tiền hàng, chi nhánh, mã] · th: [id, trạng thái, tổng trả, chi nhánh, mã]
  const kiot: any = {}, app: any = {};
  for (const x of hdK) if (x.status === 1) { const th = (x.invoiceDetails || []).reduce((s: number, d: any) => s + Math.round(d.subTotal || 0), 0);
    cong(kiot, x.branchName, 'so_hd', 1); cong(kiot, x.branchName, 'tien_hang', th); cong(kiot, x.branchName, 'doanh_thu', Math.round(x.total)); }
  for (const x of thK) if (x.status === 1) { cong(kiot, x.branchName, 'so_tra', 1); cong(kiot, x.branchName, 'tra_hang', Math.round(x.returnTotal || 0)); }
  for (const [, tt, tong, th, cn] of (db.hd || [])) if (tt === 1) { cong(app, cn, 'so_hd', 1); cong(app, cn, 'tien_hang', Number(th)); cong(app, cn, 'doanh_thu', Number(tong)); }
  for (const [, tt, tra, cn] of (db.th || [])) if ((tt ?? 1) === 1) { cong(app, cn, 'so_tra', 1); cong(app, cn, 'tra_hang', Number(tra)); }
  // so từng mã
  const soMa = (dsK: any[], dsA: any[], tienK: (x: any) => number) => {
    const mA = new Map(dsA.map((r: any) => [Number(r[0]), r])), mK = new Map(dsK.map(x => [Number(x.id), x]));
    const thieu = dsK.filter(x => !mA.has(Number(x.id))), thua = dsA.filter((r: any) => !mK.has(Number(r[0])));
    const lech = dsK.filter(x => { const r: any = mA.get(Number(x.id)); return r && (Number(r[1] ?? 1) !== x.status || Number(r[2]) !== tienK(x)); });
    return { thieu, thua, lech };
  };
  const h = soMa(hdK, db.hd || [], x => Math.round(x.total)), t = soMa(thK, db.th || [], x => Math.round(x.returnTotal || 0));
  const ma = (ds: any[]) => ds.slice(0, 50).map((x: any) => Array.isArray(x) ? x[x.length - 1] : x.code);
  const so_lech = h.thieu.length + h.thua.length + h.lech.length + t.thieu.length + t.thua.length + t.lech.length;
  // tự ghi bù phiếu thiếu / lệch (đúng như lần kéo đầy đủ) — phiếu app thừa KHÔNG xoá, chỉ báo
  const suaH = [...h.thieu, ...h.lech], suaT = [...t.thieu, ...t.lech];
  if (suaH.length) await ghi('kt_kiot_hoa_don', suaH.map(LOAI.hoa_don.doi));
  if (suaT.length) await ghi('kt_kiot_tra_hang', suaT.map(LOAI.tra_hang.doi));
  if (suaH.length) await rpcJ('kt_tinh_gia_von', { p_tat_ca: false });
  const ket_qua = { tu, den, kiot, app, hd: { kiot: hdK.length, app: (db.hd || []).length, thieu: ma(h.thieu), thua: ma(h.thua), lech: ma(h.lech) },
    th: { kiot: thK.length, app: (db.th || []).length, thieu: ma(t.thieu), thua: ma(t.thua), lech: ma(t.lech) } };
  await sb('kt_kiot_doi_chieu', { nguoi, loai: 'thang', thang: m, khop: so_lech === 0, so_lech, so_sua: suaH.length + suaT.length, ket_qua });
  return { thang: m, khop: so_lech === 0, so_lech, so_sua: suaH.length + suaT.length };
}

// Tồn kho: ds = toàn bộ hàng Kiot vừa kéo; so với bảng app TRƯỚC khi ghi đè. Giá trị tồn = Σ tồn > 0 × giá vốn, chỉ dòng đơn vị gốc.
async function doiChieuTon(ds: any[], nguoi: string) {
  const db: any[] = await rpcJ('kt_kiot_ton_db', {});   // [id, dv_goc_id, ton jsonb]
  const kiot: any = {}, app: any = {}, mK = new Map(ds.map(x => [Number(x.id), x]));
  for (const x of ds) if (!x.masterUnitId) for (const i of (x.inventories || [])) {
    const sl = Number(i.onHand) || 0, gt = sl * (Number(i.cost) || 0);
    if (sl > 0) { cong(kiot, i.branchName, 'sl', sl); cong(kiot, i.branchName, 'gt', gt); cong(kiot, i.branchName, 'so_ma', 1); } else if (sl < 0) cong(kiot, i.branchName, 'am', gt); }
  let dvPhu = 0; const lech: any[] = []; const coDB = new Set<number>();
  for (const [id, dvg, ton] of db) {
    coDB.add(Number(id)); const k = mK.get(Number(id)), phu = dvg != null || (k && k.masterUnitId);
    for (const t of (ton || [])) {
      const sl = Number(t.ton) || 0, gt = sl * (Number(t.gia_von) || 0);
      if (dvg == null) { if (sl > 0) { cong(app, t.cn, 'sl', sl); cong(app, t.cn, 'gt', gt); cong(app, t.cn, 'so_ma', 1); } else if (sl < 0) cong(app, t.cn, 'am', gt);
        if (phu && sl > 0) dvPhu += gt; }   // app đang cộng cả dòng đơn vị phụ (trước khi có cột dv_goc_id)
      if (k && !k.masterUnitId) { const i = (k.inventories || []).find((z: any) => z.branchName === t.cn);
        if (i && (Number(i.onHand) !== sl || Math.round(Number(i.cost) || 0) !== Math.round(Number(t.gia_von) || 0)))
          lech.push({ ma: k.code, cn: t.cn, app: sl, kiot: Number(i.onHand), gt: Math.round(Number(i.onHand) * (Number(i.cost) || 0) - gt) }); }
    }
  }
  const thieu = ds.filter(x => !coDB.has(Number(x.id))).length;
  for (const o of [kiot, app]) for (const cn in o) for (const k in o[cn]) o[cn][k] = Math.round(o[cn][k] * 1000) / 1000;
  lech.sort((a, b) => Math.abs(b.gt) - Math.abs(a.gt));
  const so_lech = lech.length + thieu, ngay = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);
  await sb('kt_kiot_doi_chieu', { nguoi, loai: 'ton', thang: ngay, khop: so_lech === 0 && Math.round(dvPhu) === 0, so_lech, so_sua: so_lech,
    ket_qua: { kiot, app, dv_phu: Math.round(dvPhu), thieu, lech: lech.slice(0, 50), so_dong_lech: lech.length } });
  return { so_lech, dv_phu: Math.round(dvPhu) };
}

// Lần kéo 3 tiếng: lấy lại tồn từng mặt hàng vừa có phát sinh (bán / trả / nhập) + dòng đơn vị gốc của nó
async function tonGiuaNgay(ids: Set<number>) {
  const ds: any[] = [], xong = new Set<number>(); let hang = [...ids].slice(0, 300);
  for (let vong = 0; vong < 2 && hang.length; vong++) {
    const goc = new Set<number>();
    for (let i = 0; i < hang.length; i += 5) {
      const lo = await Promise.all(hang.slice(i, i + 5).map(id => kiotMot('products/' + id)));
      for (const x of lo) if (x) { ds.push(x); xong.add(Number(x.id)); if (x.masterUnitId && !xong.has(Number(x.masterUnitId)) && !ids.has(Number(x.masterUnitId))) goc.add(Number(x.masterUnitId)); }
    }
    hang = [...goc];
  }
  if (ds.length) await ghi('kt_kiot_hang', ds.map(LOAI.hang.doi));
  return ds.length;
}

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  const tra = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
  const batDau = Date.now(); let body: any = {};
  try { body = await req.json(); } catch (_) { /* cron gửi {} */ }
  let nguoi = 'Kiot (tự kéo)';
  if (req.headers.get('x-kt-cron') !== Deno.env.get('KT_CRON_KEY')) {
    // trang web bấm "Kéo ngay" / "So lại": kiểm phiên + quyền (Nhật ký, sửa)
    if (!body.phien) return tra({ loi: 'không có quyền' }, 401);
    const q = await sb('rpc/kt_quyen_keo', { p_phien: String(body.phien) }, 'return=representation');
    if (!q.ok) { const j = await q.json().catch(() => ({})); return tra({ loi: j.message || 'Không có quyền' }, 403); }
    nguoi = 'Bấm tay: ' + (await q.json());
  }
  const kq: any = {};
  try {
    tok = await kiotToken();
    if (body.doi_chieu) {   // so khớp theo tháng (mặc định tháng này + tháng trước)
      const nay = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 7), d = new Date(nay + '-01T00:00:00Z'); d.setUTCMonth(d.getUTCMonth() - 1);
      const ds: string[] = (body.doi_chieu.thang || [d.toISOString().slice(0, 7), nay]).filter((m: string) => /^\d{4}-\d{2}$/.test(m)).slice(0, 3);
      kq.doi_chieu = [];
      for (const m of ds) kq.doi_chieu.push(await doiChieuThang(m, nguoi));
      kq.giay = Math.round((Date.now() - batDau) / 1000);
      await sb('kt_nhat_ky', { nguoi, bang: 'kt_kiot', hanh_dong: 'doi_chieu_kiot', du_lieu: kq });
      await sb('rpc/kt_canh_bao_kiot', {});   // có vấn đề → chuông app (supabase-schema-kt-kiot-canh-bao.sql)
      return tra(kq);
    }
    const dayDu: string[] = body.day_du || [];
    const chay: string[] = body.chi || (dayDu.length ? dayDu : ['so_quy', ...Object.keys(LOAI)]);
    const khoang = body.tu ? { tu: String(body.tu), den: String(body.den || MAI()), thu_tu: String(body.thu_tu || body.tu) } : undefined;
    const TU = khoang ? khoang.tu : MOC, DEN = khoang ? khoang.den : MAI();
    if (chay.includes('so_quy')) kq.so_quy = await soQuy(khoang);
    if (dayDu.includes('hang') || chay.includes('danh_muc')) kq.danh_muc = await danhMuc();
    const phatSinh = new Set<number>();
    for (const k of chay.filter(k => LOAI[k])) {
      const L = LOAI[k]; const moc = dayDu.includes(k) ? null : await mocSua(L.bang);
      const tham = { ...L.tham, ...(moc ? { lastModifiedFrom: moc } : (L.dayDu ? L.dayDu(TU, DEN) : {})) };
      let ds = await kiotHet(L.duong, tham);
      if (L.moc) ds = ds.filter(x => L.moc!(x, TU));
      if (k === 'hang' && !moc && !body.tu) kq.so_ton = await doiChieuTon(ds, nguoi);   // kéo đầy đủ hàng → so tồn trước khi ghi đè
      await ghi(L.bang, ds.map(L.doi));
      kq[k] = { kieu: moc ? 'phan_sua' : 'day_du', so_dong: ds.length };
      if (moc && !body.tu) for (const x of ds) for (const d of (x.invoiceDetails || x.returnDetails || x.purchaseOrderDetails || [])) if (d.productId) phatSinh.add(Number(d.productId));
    }
    // tồn giữa ngày: chỉ khi lần này không kéo đầy đủ hàng
    if (phatSinh.size && !(kq.hang && kq.hang.kieu === 'day_du')) kq.ton_cap_nhat = await tonGiuaNgay(phatSinh);
    if (kq.hoa_don || kq.hang) { const g = await sb('rpc/kt_tinh_gia_von', { p_tat_ca: false }, 'return=representation'); kq.gia_von = g.ok ? await g.json() : 'lỗi ' + g.status; }
    kq.giay = Math.round((Date.now() - batDau) / 1000);
    await sb('kt_nhat_ky', { nguoi, bang: 'kt_kiot', hanh_dong: 'keo_kiot', du_lieu: kq });
    await sb('rpc/kt_canh_bao_kiot', {});
    return tra(kq);
  } catch (e) {
    await sb('kt_nhat_ky', { nguoi, bang: 'kt_kiot', hanh_dong: 'keo_kiot_loi', du_lieu: { loi: String(e), da_xong: kq } });
    await sb('rpc/kt_canh_bao_kiot', {});
    return tra({ loi: String(e), da_xong: kq }, 500);
  }
});
