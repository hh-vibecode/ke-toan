// Edge Function kt-meinvoice-nhap — TẠO HOÁ ĐƠN NHÁP trên MISA meInvoice từ đơn lập ở app (09/11/2026 anh: "thế nháp đi").
// Nháp = hoá đơn chưa ký, chưa cấp số: kế toán vào meInvoice kiểm rồi tự ký phát hành. App KHÔNG ký / phát hành.
// Lệnh MISA (nhóm "Tạo hóa đơn nháp", developer.misa.vn/backend/api/products/docs/MEINVOICE):
//   /invoiceweb/token · /invoiceweb/templates · /invoiceweb/insert · /invoiceweb/getlist · DELETE /invoiceweb/delete (chỉ xoá được nháp CHƯA phát hành).
// Body {viec, phien, id?, ky_hieu?}: mau = ký hiệu dùng được · day = tạo nháp (đơn đã có nháp chưa phát hành → xoá nháp cũ rồi tạo lại)
//   · xoa = xoá nháp · kiem = lấy số HĐ các nháp kế toán đã phát hành → đơn "Đã xuất HĐ". Quyền: phiên app kế toán + trang Hoá đơn & Thuế
//   (day / xoa cần quyền sửa) — kiểm trong kt_thue_don_misa_lay. — Monsieur Claude
const SB = Deno.env.get('SUPABASE_URL')!, SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const MI = 'https://developer.misa.vn/apis/itg/meinvoice', BO_QUA = ['MHH', 'MSH'];
const MST = Deno.env.get('KT_MEINVOICE_MST')!, USER = Deno.env.get('KT_MEINVOICE_USER')!, PASS = Deno.env.get('KT_MEINVOICE_PASS')!;
const H: Record<string, string> = { 'Content-Type': 'application/json', ClientID: Deno.env.get('KT_MEINVOICE_CLIENT_ID')!, ClientSecret: Deno.env.get('KT_MEINVOICE_CLIENT_SECRET')! };
const sbH = { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/json' };
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type, apikey, authorization', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const traJ = (x: unknown, s = 200) => new Response(JSON.stringify(x), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
const doc = (x: any) => { try { return typeof x === 'string' ? JSON.parse(x) : x; } catch (_) { return x; } };
async function rpc(fn: string, args: unknown) {
  const r = await fetch(SB + '/rest/v1/rpc/' + fn, { method: 'POST', headers: sbH, body: JSON.stringify(args) });
  const t = await r.text(); const j = t ? JSON.parse(t) : null; if (!r.ok) throw new Error(j?.message || 'Lỗi ' + r.status); return j;
}
// MISA trả {Success|success, Data|data, ErrorCode|errorCode, descriptionErrorCode, Errors|error}
async function misa(duong: string, opt: RequestInit) {
  const r = await fetch(MI + duong, opt); const t = await r.text(); let j: any;
  try { j = JSON.parse(t); } catch (_) { throw new Error(`MISA ${r.status}: ${t.slice(0, 200)}`); }
  const ok = j.Success ?? j.success;
  if (ok === false || !r.ok) {
    const loi = [j.ErrorCode ?? j.errorCode, j.descriptionErrorCode ?? j.ErrorDescription, ...(Array.isArray(j.Errors ?? j.error) ? (j.Errors ?? j.error) : [])].filter(Boolean).join(' · ');
    throw new Error('MISA: ' + (loi || r.status));
  }
  return { data: doc(j.Data ?? j.data), j };
}
let TOKEN = '';
async function dauA() {
  if (!TOKEN) { const { data } = await misa('/invoiceweb/token', { method: 'POST', headers: H, body: JSON.stringify({ taxcode: MST, username: USER, password: PASS }) });
    TOKEN = typeof data === 'string' ? data : (data?.access_token || data?.AccessToken || data?.token || ''); if (!TOKEN) throw new Error('MISA không trả token'); }
  return { ...H, TaxCode: MST, Authorization: 'Bearer ' + TOKEN };
}
async function mauDs() {
  const { data } = await misa('/invoiceweb/templates?invoiceWithCode=true', { method: 'POST', headers: await dauA(), body: JSON.stringify({ TypeInvoice: 0, TaxCode: MST, UserName: USER, Password: PASS }) });
  return ((data || []) as any[]).filter(m => !m.Inactive && !BO_QUA.includes(String(m.InvSeries).slice(-3)))
    .map(m => ({ id: m.IPTemplateID, ky_hieu: m.InvSeries, ky_hieu_goc: m.InvSeries, ten: m.TemplateName }));
}
// RefID → {so, ky_hieu} (null = MISA không còn nháp này)
async function layDs(refs: string[]) {
  const kq: Record<string, any> = {};
  for (let i = 0; i < refs.length; i += 50) {
    const { data } = await misa('/invoiceweb/getlist?invoiceWithCode=true', { method: 'POST', headers: await dauA(), body: JSON.stringify(refs.slice(i, i + 50)) });
    for (const x of (data || []) as any[]) { const so = String(x.InvNo ?? '').trim(); kq[String(x.RefID).toLowerCase()] = { so: /^\d+$/.test(so) ? so : '', ky_hieu: x.InvSeries || '' }; }
  }
  return kq;
}
const xoaNhap = async (ref: string) => misa(`/invoiceweb/delete?invoiceWithCode=true&refid=${encodeURIComponent(ref)}`, { method: 'DELETE', headers: await dauA() });
const gioVN = (d?: string) => (d ? d + 'T00:00:00' : new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 19)) + '+07:00';

// 10/11/2026 anh: "chuyển hết thông tin phiếu nháp của mình sang luôn, tiết kiệm time cho kế toán đỡ phải làm 2 lần" → nháp MISA mang đủ:
// ký hiệu + ngày, người mua (đơn kt_thue_don.mua: MST, tên đơn vị, địa chỉ, họ tên, SĐT, email, CCCD, hình thức TT, TK + tên ngân hàng),
// từng dòng mã hàng · tên · ĐVT · SL · đơn giá · thành tiền · THUẾ SUẤT RIÊNG DÒNG (theo nhóm / chọn tay) · tiền thuế; dòng ghi chú (tc 4). — Monsieur Claude
function hoaDon(d: any, mau: any, ref: string, nguoi: string) {
  const m = d.mua || {}, tsDon = d.thue_suat == null ? null : +d.thue_suat;
  const dong = ((d.dong || []) as any[]).filter(x => String(x.ten || x.ma || '').trim()); if (!dong.filter(x => +x.tc !== 4).length) throw new Error('Đơn chưa có dòng hàng');
  const vrOf = (r: any) => r == null ? -1 : Math.round(+r * 100);
  let stt = 0;
  const ct = dong.map((x, i) => {
    if (+x.tc === 4) return { InventoryItemType: 3, Description: String(x.ten || '').trim(), SortOrder: i + 1, SortOrderView: null, UnitName: '', Quantity: 0, UnitPrice: 0,
      AmountOC: 0, Amount: 0, DiscountRate: 0, DiscountAmountOC: 0, DiscountAmount: 0, VATRate: null, VATAmountOC: 0, VATAmount: 0 };
    const r = x.ts !== undefined ? x.ts : tsDon, tien = Math.round(+x.thanh_tien || (+x.sl * +x.don_gia)), thue = r == null ? 0 : Math.round(tien * +r);
    return { InventoryItemType: 0, InventoryItemCode: x.ma || undefined, Description: x.ten || x.ma, UnitName: x.dvt || '', Quantity: +x.sl, UnitPrice: +x.don_gia,
      AmountOC: tien, Amount: tien, DiscountRate: 0, DiscountAmountOC: 0, DiscountAmount: 0, VATRate: vrOf(r), VATAmountOC: thue, VATAmount: thue, SortOrder: i + 1, SortOrderView: ++stt };
  });
  const hh = ct.filter(x => x.InventoryItemType === 0), hang = hh.reduce((a, x) => a + x.AmountOC, 0), thueDon = hh.reduce((a, x) => a + x.VATAmountOC, 0);
  const cccd = String(m.cccd || '').replace(/\D/g, '');
  return { RefID: ref, InvoiceTemplateID: mau.id, InvSeries: mau.ky_hieu_goc, InvDate: gioVN(String(d.ngay).slice(0, 10)), EInvoiceStatus: 1,
    AccountObjectTaxCode: m.mst || d.mst || undefined, AccountObjectName: m.ten_dv || d.khach || undefined, AccountObjectAddress: m.dia_chi || undefined,
    ContactName: m.nguoi_mua || undefined, ReceiverName: m.nguoi_mua || undefined, ReceiverMobile: m.sdt || undefined, ReceiverEmail: m.email || undefined,
    CitizenIDNumber: cccd.length === 12 ? cccd : undefined, AccountObjectBankAccount: m.tk_nh || undefined, AccountObjectBankName: m.ten_nh || undefined,
    PaymentMethod: m.httt || 'TM/CK', CurrencyCode: 'VND', CurrencyID: 'VND',
    DiscountRate: 0, ExchangeRate: 1, VATRate: hh.length ? hh[0].VATRate : -1, TotalSaleAmountOC: hang, TotalSaleAmount: hang, TotalDiscountAmountOC: 0, TotalDiscountAmount: 0,
    TotalVATAmountOC: thueDon, TotalVATAmount: thueDon, TotalAmountOC: hang + thueDon, TotalAmount: hang + thueDon,
    CreatedDate: gioVN(), ModifiedDate: gioVN(), CreatedBy: nguoi, ModifiedBy: nguoi, InvoiceDetails: ct };
}
// đồng bộ số HĐ đã phát hành + bỏ liên kết nháp kế toán đã xoá trên MISA
async function kiem(cho: any[]) {
  if (!cho.length) return { cho: 0, phat_hanh: 0, mat: 0 };
  const kq = await layDs(cho.map(x => String(x.ref))); let ph = 0, mat = 0;
  for (const x of cho) { const k = kq[String(x.ref).toLowerCase()];
    if (!k) { await rpc('kt_thue_don_misa_ghi', { p_id: x.id, p_ref: null, p_ky_hieu: null, p_nguoi: 'Hệ thống' }); mat++; }
    else if (k.so) { await rpc('kt_thue_don_misa_ghi', { p_id: x.id, p_ref: x.ref, p_ky_hieu: k.ky_hieu, p_nguoi: 'Hệ thống', p_so_hd: k.so }); ph++; } }
  return { cho: cho.length, phat_hanh: ph, mat };
}
Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  let b: any = {}; try { b = await req.json(); } catch (_) { /* rỗng */ }
  try {
    // 10/11/2026 anh "bịt hẳn vào": Edge kt-meinvoice cuối mỗi lượt kéo HĐ gọi {viec:'kiem'} bằng khoá lịch (x-kt-cron) → ghi số HĐ nháp đã phát hành ngay. Monsieur Claude
    if (b.viec === 'kiem' && req.headers.get('x-kt-cron') && req.headers.get('x-kt-cron') === Deno.env.get('KT_CRON_KEY'))
      return traJ(await kiem(await rpc('kt_thue_don_misa_cho', {}) || []));
    const id = ['day', 'xoa'].includes(b.viec) ? +b.id : null;
    const L = await rpc('kt_thue_don_misa_lay', { p_phien: String(b.phien || ''), p_id: id });
    if (b.viec === 'mau') return traJ({ mau: await mauDs() });
    if (b.viec === 'kiem') return traJ(await kiem(L.cho || []));
    const d = L.don;
    if (b.viec === 'xoa') {
      if (!d.misa_ref) return traJ({ ok: true });
      const k = (await layDs([d.misa_ref]))[String(d.misa_ref).toLowerCase()];
      if (k?.so) { await rpc('kt_thue_don_misa_ghi', { p_id: d.id, p_ref: d.misa_ref, p_ky_hieu: k.ky_hieu, p_nguoi: 'Hệ thống', p_so_hd: k.so });
        throw new Error(`Hoá đơn đã phát hành trên MISA (số ${k.so}) — không xoá được nháp`); }
      if (k) await xoaNhap(d.misa_ref);
      await rpc('kt_thue_don_misa_ghi', { p_id: d.id, p_ref: null, p_ky_hieu: null, p_nguoi: L.nguoi });
      return traJ({ ok: true });
    }
    if (b.viec === 'day') {
      const mau = (await mauDs()).find(m => m.ky_hieu === b.ky_hieu || m.ky_hieu_goc === b.ky_hieu);
      if (!mau) throw new Error('Ký hiệu hoá đơn không có trên MISA: ' + (b.ky_hieu || '(trống)'));
      if (d.misa_ref) {   // đẩy lại: nháp cũ chưa phát hành → xoá; đã phát hành → chặn
        const k = (await layDs([d.misa_ref]))[String(d.misa_ref).toLowerCase()];
        if (k?.so) { await rpc('kt_thue_don_misa_ghi', { p_id: d.id, p_ref: d.misa_ref, p_ky_hieu: k.ky_hieu, p_nguoi: 'Hệ thống', p_so_hd: k.so });
          throw new Error(`Hoá đơn đã phát hành trên MISA (số ${k.so}) — không đẩy lại được`); }
        if (k) await xoaNhap(d.misa_ref);
        await rpc('kt_thue_don_misa_ghi', { p_id: d.id, p_ref: null, p_ky_hieu: null, p_nguoi: L.nguoi });
      }
      const ref = crypto.randomUUID(), hd = hoaDon(d, mau, ref, L.nguoi);
      const { data } = await misa('/invoiceweb/insert', { method: 'POST', headers: await dauA(), body: JSON.stringify([hd]) });
      const r0 = Array.isArray(data) ? doc(data[0]) : data;   // phản hồi từng HĐ: có ErrorCode = lỗi
      if (r0 && typeof r0 === 'object' && (r0.ErrorCode || r0.errorCode)) throw new Error('MISA: ' + (r0.ErrorCode || r0.errorCode) + ' ' + (r0.descriptionErrorCode || r0.ErrorDescription || ''));
      await rpc('kt_thue_don_misa_ghi', { p_id: d.id, p_ref: ref, p_ky_hieu: mau.ky_hieu, p_nguoi: L.nguoi });
      return traJ({ ok: true, ref, ky_hieu: mau.ky_hieu, tong: hd.TotalAmountOC, phan_hoi: r0 });
    }
    return traJ({ loi: 'Việc không hợp lệ' }, 400);
  } catch (e) { return traJ({ loi: String((e as Error).message || e) }, 400); }
});
