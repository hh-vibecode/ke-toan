// Edge Function kt-meinvoice — kéo HOÁ ĐƠN CÔNG TY TỔNG từ MISA meInvoice (12/10/2026). CHỈ ĐỌC: token · templates · paging.
// pg_cron 'kt-meinvoice' gọi mỗi đêm (header x-kt-cron = secret KT_CRON_KEY). Mặc định nạp lại tháng này + tháng trước
// (bắt hoá đơn điều chỉnh / thay thế). Body {"tu":"2026-01","den":"2026-10"} = nạp lại các tháng đó.
// Bỏ ký hiệu *MHH, *MSH (Hong Kong Center / Saikung Hot Pot — dịch vụ khác, anh chốt 12/10 không tính).
// Secrets: KT_MEINVOICE_CLIENT_ID, KT_MEINVOICE_CLIENT_SECRET, KT_MEINVOICE_MST, KT_MEINVOICE_USER, KT_MEINVOICE_PASS, KT_CRON_KEY. Monsieur Claude
const SB = Deno.env.get('SUPABASE_URL')!, SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const MI = 'https://developer.misa.vn/apis/itg/meinvoice', BO_QUA = ['MHH', 'MSH'];
const H = { 'Content-Type': 'application/json', ClientID: Deno.env.get('KT_MEINVOICE_CLIENT_ID')!, ClientSecret: Deno.env.get('KT_MEINVOICE_CLIENT_SECRET')! };
const sbH = { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/json' };
const sb = (duong: string, body: unknown, prefer = 'return=minimal') => fetch(SB + '/rest/v1/' + duong, { method: 'POST', headers: { ...sbH, Prefer: prefer }, body: JSON.stringify(body) });
const doc = (x: any) => { try { return typeof x === 'string' ? JSON.parse(x) : x; } catch (_) { return x; } };
const ngu = (ms: number) => new Promise(r => setTimeout(r, ms));

// MISA thỉnh thoảng trả 500 / rớt kết nối giữa chừng → thử lại
async function goi(url: string, opt: RequestInit) {
  for (let lan = 1; ; lan++) {
    try { const r = await fetch(url, opt); const j = JSON.parse(await r.text()); if (j.Success === false) throw new Error('MISA: ' + (j.ErrorCode || JSON.stringify(j.Errors))); return j; }
    catch (e) { if (lan >= 5) throw e; await ngu(3000 * lan); }
  }
}
// 23/10/2026: tải PDF HĐ bán ra đã gắn phiếu thu (POST /invoice/Download?downloadDataType=Pdf, body = [mã tra cứu], data = PDF base64)
// vào chứng từ phiếu thu: thu/{thu}/misa_{ký hiệu-số}.pdf. Body {"pdf":true} = chỉ tải PDF, không kéo lại danh sách HĐ.
async function taiPdfRa(A: any, n: number, batDau: number) {
  const r = await sb('rpc/kt_hd_ra_can_pdf', { p_n: n }, 'return=representation');
  const ds = r.ok ? await r.json() as any[] : []; const m: any = { can: ds.length, luu: 0, loi: 0 };
  for (let i = 0; i < ds.length && Date.now() - batDau < 110e3; i += 3) {   // lô 3 file: lô 10 (~7MB base64) vượt bộ nhớ Edge
    const nhom = ds.slice(i, i + 3);
    let kq: any[] = [];
    try { const j = await goi(MI + '/invoice/Download?downloadDataType=Pdf&invoiceWithCode=true', { method: 'POST', headers: A, body: JSON.stringify(nhom.map(x => x.ma_tra_cuu)) }); kq = (doc(j.Data) || []) as any[]; }
    catch (e) { m.loi += nhom.length; m.loi_cuoi = String(e).slice(0, 160); continue; }
    for (const x of nhom) {
      const f = kq.find(k => String(k.TransactionID) === String(x.ma_tra_cuu));
      const b64 = f ? (f.Data || f.data) : null;   // thực tế MISA trả "Data" (tài liệu ghi "data")
      if (!f || !b64 || f.ErrorCode) { m.loi++; if (f?.ErrorCode) m.loi_cuoi = f.ErrorCode; continue; }
      try {
        const pdf = Uint8Array.from(atob(String(b64)), c => c.charCodeAt(0));
        const duong = `thu/${x.thu_id}/misa_${x.hd_ma}.pdf`;
        const up = await fetch(`${SB}/storage/v1/object/kt-chung-tu/${duong}`, { method: 'POST', headers: { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/pdf', 'x-upsert': 'true' }, body: pdf });
        if (!up.ok) { m.loi++; continue; }
        const ins = await fetch(SB + '/rest/v1/kt_chung_tu?on_conflict=duong_dan', { method: 'POST', headers: { ...sbH, Prefer: 'resolution=ignore-duplicates,return=minimal' },
          body: JSON.stringify({ bang: 'thu', dong_id: x.thu_id, duong_dan: duong, ten_file: `HĐ ${x.ky_hieu || ''} số ${x.so_hd || ''} (MISA).pdf`, mime: 'application/pdf', kich_thuoc: pdf.length, tao_boi: 'Hệ thống (MISA)' }) });
        if (ins.ok) m.luu++; else m.loi++;
      } catch (_) { m.loi++; }
    }
  }
  return m;
}
const thangVN = (lech: number) => { const d = new Date(Date.now() + 7 * 3600e3); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() + lech); return d.toISOString().slice(0, 7); };
const cuoiThang = (t: string) => new Date(Date.UTC(+t.slice(0, 4), +t.slice(5, 7), 0)).toISOString().slice(0, 10);

Deno.serve(async req => {
  if (req.headers.get('x-kt-cron') !== Deno.env.get('KT_CRON_KEY')) return new Response('không có quyền', { status: 401 });
  const batDau = Date.now(); let body: any = {};
  try { body = await req.json(); } catch (_) { /* cron gửi {} */ }
  const kq: any = { thang: {} };
  try {
    const t = await goi(MI + '/invoice/token', { method: 'POST', headers: H, body: JSON.stringify({
      taxcode: Deno.env.get('KT_MEINVOICE_MST'), username: Deno.env.get('KT_MEINVOICE_USER'), password: Deno.env.get('KT_MEINVOICE_PASS') }) });
    const A = { ...H, Authorization: 'Bearer ' + t.Data };
    const mau = doc((await goi(MI + '/invoice/templates?invoiceWithCode=true', { headers: A })).Data) as any[];
    const ten: Record<string, string> = {}; mau.forEach(m => ten[m.InvSeries] = m.TemplateName);
    const ks = mau.map(m => m.InvSeries).filter(s => !BO_QUA.includes(String(s).slice(-3)));
    kq.ky_hieu = ks;
    const ds: string[] = []; for (let th = String(body.tu || thangVN(-1)); th <= String(body.den || thangVN(0)); th = new Date(Date.UTC(+th.slice(0, 4), +th.slice(5, 7), 1)).toISOString().slice(0, 7)) ds.push(th);
    if (body.pdf) ds.length = 0;
    for (const th of ds) {
      const hd: any[] = [];
      for (let sk = 0; ; sk += 50) {
        const p = await goi(MI + '/invoice/paging?invoiceWithCode=true', { method: 'POST', headers: A,
          body: JSON.stringify({ FromDate: th + '-01', ToDate: cuoiThang(th), Skip: sk, Take: 50, ListInvTemplate: ks }) });
        const it = (doc(doc(p.Data)?.PageData) || []) as any[]; hd.push(...it); if (it.length < 50) break; await ngu(300);
      }
      const dong = hd.filter(x => !BO_QUA.includes(String(x.InvSeries).slice(-3)) && String(x.InvDate || '').slice(0, 7) === th).map(x => ({
        so_hd: x.InvNo == null ? null : String(x.InvNo), mau: x.InvTemplateNo ?? null, ky_hieu: x.InvSeries, ngay: String(x.InvDate).slice(0, 10),
        mst: x.BuyerTaxCode || '', nguoi_mua: x.BuyerLegalName || x.BuyerFullName || 'Khách lẻ', ten: ten[x.InvSeries] || x.InvoiceName || null,
        thanh_tien: +x.TotalAmountWithoutVAT || 0, tien_thue: +x.TotalVATAmount || 0, tong: +x.TotalAmount || 0,
        ma: x.TransactionID || x.TransactionId || x.transactionID || '',
        ghi_chu: x.OrgInvNo ? `Điều chỉnh / thay thế HĐ ${x.OrgInvSeries || ''} ${x.OrgInvNo}`.replace(/\s+/g, ' ') : '' }));
      const r = await sb('rpc/kt_nap_meinvoice', { p_thang: th, p_ds: dong }, 'return=representation');
      if (!r.ok) throw new Error(`nạp ${th} lỗi ${r.status} ${(await r.text()).slice(0, 200)}`);
      kq.thang[th] = await r.json();
    }
    kq.pdf = await taiPdfRa(A, +body.n || 15, batDau);
    kq.giay = Math.round((Date.now() - batDau) / 1000);
    await sb('kt_nhat_ky', { nguoi: 'meInvoice (tự kéo)', bang: 'kt_thue_hd', hanh_dong: 'keo_meinvoice', du_lieu: kq });
    return Response.json(kq);
  } catch (e) {
    await sb('kt_nhat_ky', { nguoi: 'meInvoice (tự kéo)', bang: 'kt_thue_hd', hanh_dong: 'keo_meinvoice_loi', du_lieu: { loi: String(e), da_xong: kq } });
    return Response.json({ loi: String(e), da_xong: kq }, { status: 500 });
  }
});
