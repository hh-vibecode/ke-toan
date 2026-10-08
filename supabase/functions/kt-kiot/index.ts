// Edge Function kt-kiot — LUỒNG KÉO KIOT RIÊNG của app kế toán (anh chốt 05/10/2026: không dùng chung MKT/Sale, 3 tiếng / lần).
// pg_cron 'kt-kiot' gọi hàm này (header x-kt-cron = secret KT_CRON_KEY). CHỈ ĐỌC Kiot (GET).
// Mỗi lần (mặc định):
//   1. Sổ quỹ 10 ngày gần nhất → kt_kiot_so_quy → kt_dong_bo_kiot() chép phiếu thu sang kt_thu.
//   2. (luồng mới 08/10) Khách · NCC · hàng hoá + tồn kho · hoá đơn · trả hàng · nhập hàng: chỉ phần Kiot SỬA từ lần trước
//      (lastModifiedFrom = mốc sửa mới nhất trong bảng − 2 giờ). Bảng trống → kéo đầy đủ.
//   3. kt_tinh_gia_von() cho hoá đơn mới. Ghi nhật ký.
// Body {"day_du":["khach","hang",...]} = kéo ĐẦY ĐỦ các loại đó (nạp ban đầu); {"chi":[...]} = chỉ chạy các loại đó.
// Secrets (tiền tố KT_): KT_KIOT_CLIENT_ID, KT_KIOT_CLIENT_SECRET, KT_KIOT_RETAILER, KT_CRON_KEY. Monsieur Claude
const SB = Deno.env.get('SUPABASE_URL')!, SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const MOC = '2026-09-01', SO_NGAY = 10;
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
async function mocSua(bang: string) {   // mốc Kiot sửa mới nhất đã có trong bảng (giờ VN, dạng Kiot nhận)
  const r = await fetch(`${SB}/rest/v1/${bang}?select=sua_kiot&sua_kiot=not.is.null&order=sua_kiot.desc&limit=1`, { headers: sbH });
  const j = await r.json(); if (!j.length) return null;
  return new Date(new Date(j[0].sua_kiot).getTime() + 7 * 3600e3 - 2 * 3600e3).toISOString().slice(0, 19);
}
const vn = (s: any) => s ? String(s).slice(0, 19) + '+07:00' : null;
const n0 = (x: any) => x == null ? null : Math.round(Number(x));

// Mỗi loại: đường Kiot · tham số · cách lọc khi kéo đầy đủ · cách đổi sang dòng bảng
const LOAI: Record<string, { bang: string, duong: string, tham: Record<string, string>, dayDu?: Record<string, string>, moc?: (x: any) => boolean, doi: (x: any) => any }> = {
  khach: { bang: 'kt_kiot_khach', duong: 'customers', tham: { includeTotal: 'true' },
    doi: x => ({ id: x.id, ma: x.code, ten: x.name, sdt: x.contactNumber ?? null, loai: x.type ?? null, chi_nhanh_id: x.branchId ?? null,
      cong_no: n0(x.debt), tong_mua: n0(x.totalInvoiced), tong_mua_tru_tra: n0(x.totalRevenue), tao_kiot: vn(x.createdDate), sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }) },
  ncc: { bang: 'kt_kiot_ncc', duong: 'suppliers', tham: {},
    doi: x => ({ id: x.id, ma: x.code, ten: x.name, sdt: x.contactNumber ?? null, hoat_dong: x.isActive ?? true, cong_no: n0(x.debt),
      tong_nhap: n0(x.totalInvoiced), tong_nhap_tru_tra: n0(x.totalInvoicedWithoutReturn), tao_kiot: vn(x.createdDate), sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }) },
  hang: { bang: 'kt_kiot_hang', duong: 'products', tham: { includeInventory: 'true' },
    doi: x => { const ton = (x.inventories || []).map((i: any) => ({ cn: i.branchName, ton: i.onHand, gia_von: n0(i.cost) }));
      return { id: x.id, ma: x.code, ten: x.fullName || x.name, nhom_id: x.categoryId ?? null, nhom: x.categoryName ?? null, don_vi: x.unit ?? null,
        gia_ban: n0(x.basePrice), hoat_dong: x.isActive ?? true, ton, tong_ton: ton.reduce((s: number, t: any) => s + (Number(t.ton) || 0), 0),
        gia_tri_ton: n0(ton.reduce((s: number, t: any) => s + (Number(t.ton) || 0) * (Number(t.gia_von) || 0), 0)),
        tao_kiot: vn(x.createdDate), sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }; } },
  hoa_don: { bang: 'kt_kiot_hoa_don', duong: 'invoices', tham: {}, dayDu: { fromPurchaseDate: MOC, toPurchaseDate: MAI() }, moc: x => String(x.purchaseDate) >= MOC,
    doi: x => ({ id: x.id, ma: x.code, ngay: vn(x.purchaseDate), chi_nhanh: x.branchName ?? null, nv_ban: x.soldByName ?? null,
      khach_id: x.customerId ?? null, khach_ma: x.customerCode ?? null, khach_ten: x.customerName ?? null, ma_dat_hang: x.orderCode ?? null,
      tong: n0(x.total), da_tra: n0(x.totalPayment), trang_thai: x.status ?? null, trang_thai_ten: x.statusValue ?? null,
      chi_tiet: (x.invoiceDetails || []).map((d: any) => ({ sp: d.productId, ma: d.productCode, ten: d.productName, nhom: d.categoryName ?? null,
        sl: d.quantity, gia: n0(d.price), giam: n0(d.discount), tien: n0(d.subTotal), sl_tra: d.returnQuantity ?? 0 })),
      gia_von: null, sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }) },
  tra_hang: { bang: 'kt_kiot_tra_hang', duong: 'returns', tham: {}, dayDu: { fromReturnDate: MOC, toReturnDate: MAI() }, moc: x => String(x.returnDate) >= MOC,
    doi: x => ({ id: x.id, ma: x.code, hoa_don_id: x.invoiceId ?? null, ngay: vn(x.returnDate), chi_nhanh: x.branchName ?? null,
      tong_tra: n0(x.returnTotal), phi_tra: n0(x.returnFee), da_tra: n0(x.totalPayment), trang_thai: x.status ?? null, trang_thai_ten: x.statusValue ?? null,
      chi_tiet: (x.returnDetails || []).map((d: any) => ({ sp: d.productId, ma: d.productCode, ten: d.productName, sl: d.quantity, gia: n0(d.price), tien: n0(d.subTotal) })),
      sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }) },
  nhap_hang: { bang: 'kt_kiot_nhap_hang', duong: 'purchaseorders', tham: {}, dayDu: { fromPurchaseDate: MOC, toPurchaseDate: MAI() }, moc: x => String(x.purchaseDate) >= MOC,
    doi: x => ({ id: x.id, ma: x.code, ngay: vn(x.purchaseDate), chi_nhanh: x.branchName ?? null, ncc_id: x.supplierId ?? null, ncc_ma: x.supplierCode ?? null,
      ncc_ten: x.supplierName ?? null, tong: n0(x.total), da_tra: n0(x.totalPayment), giam_gia: n0(x.discount), trang_thai: x.status ?? null, mo_ta: x.description ?? null,
      chi_tiet: (x.purchaseOrderDetails || []).map((d: any) => ({ sp: d.productId, ma: d.productCode, ten: d.productName, sl: d.quantity, gia: n0(d.price), giam: n0(d.discount) })),
      sua_kiot: vn(x.modifiedDate ?? x.createdDate), keo_luc: new Date().toISOString() }) },
};

async function soQuy() {
  const vnNow = new Date(Date.now() + 7 * 3600e3);
  // endDate của Kiot KHÔNG gồm chính ngày đó → lấy tới ngày mai để có phiếu hôm nay
  const den = new Date(vnNow.getTime() + 864e5).toISOString().slice(0, 10), tuD = new Date(vnNow.getTime() - SO_NGAY * 864e5).toISOString().slice(0, 10);
  const tu = tuD < MOC ? MOC : tuD;
  const cf = await kiotHet('cashflow', { startDate: tu, endDate: den, includeAccount: 'true', includeBranch: 'true', includeUser: 'true' });
  await ghi('kt_kiot_so_quy', cf.map(x => ({ id: x.id, ma: x.code, ngay: vn(x.transDate), chi_nhanh: x.branch ?? null, la_thu: x.amount > 0,
    so_tien: Math.abs(Math.round(x.amount)), phuong_thuc: x.method ?? null, tai_khoan: x.accountId ? String(x.accountId) : null, doi_tac: x.partnerName ?? null,
    nhom: x.cashGroup ?? null, noi_dung: x.description ?? null, chung_tu_goc: x.origin ?? null, trang_thai: String(x.status), goc: x, keo_luc: new Date().toISOString() })));
  const d = await sb('rpc/kt_dong_bo_kiot', { p_tu: tu }, 'return=representation');
  return { tu, den, so_phieu: cf.length, dong_bo: d.ok ? await d.json() : 'lỗi ' + d.status };
}

Deno.serve(async req => {
  if (req.headers.get('x-kt-cron') !== Deno.env.get('KT_CRON_KEY')) return new Response('không có quyền', { status: 401 });
  const batDau = Date.now(); let body: any = {};
  try { body = await req.json(); } catch (_) { /* cron gửi {} */ }
  const kq: any = {};
  try {
    tok = await kiotToken();
    const dayDu: string[] = body.day_du || [];
    const chay: string[] = body.chi || (dayDu.length ? dayDu : ['so_quy', ...Object.keys(LOAI)]);
    if (chay.includes('so_quy')) kq.so_quy = await soQuy();
    for (const k of chay.filter(k => LOAI[k])) {
      const L = LOAI[k]; const moc = dayDu.includes(k) ? null : await mocSua(L.bang);
      const tham = { ...L.tham, ...(moc ? { lastModifiedFrom: moc } : (L.dayDu || {})) };
      let ds = await kiotHet(L.duong, tham);
      if (L.moc) ds = ds.filter(L.moc);
      await ghi(L.bang, ds.map(L.doi));
      kq[k] = { kieu: moc ? 'phan_sua' : 'day_du', so_dong: ds.length };
    }
    if (kq.hoa_don || kq.hang) { const g = await sb('rpc/kt_tinh_gia_von', { p_tat_ca: false }, 'return=representation'); kq.gia_von = g.ok ? await g.json() : 'lỗi ' + g.status; }
    kq.giay = Math.round((Date.now() - batDau) / 1000);
    await sb('kt_nhat_ky', { nguoi: 'Kiot (tự kéo)', bang: 'kt_kiot', hanh_dong: 'keo_kiot', du_lieu: kq });
    return Response.json(kq);
  } catch (e) {
    await sb('kt_nhat_ky', { nguoi: 'Kiot (tự kéo)', bang: 'kt_kiot', hanh_dong: 'keo_kiot_loi', du_lieu: { loi: String(e), da_xong: kq } });
    return Response.json({ loi: String(e), da_xong: kq }, { status: 500 });
  }
});
