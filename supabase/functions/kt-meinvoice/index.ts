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
// 03/11/2026: giải base64 PDF bằng data: URL (máy giải gốc) — trước dùng Uint8Array.from(atob(), fn) gọi hàm từng ký tự,
// ~28 file / lượt là vượt CPU Edge (546 WORKER_RESOURCE_LIMIT) → hàm chết trước khi ghi nhật ký tai_pdf_hd_ra. Monsieur Claude
const b64Pdf = async (s: string) => new Uint8Array(await (await fetch('data:application/pdf;base64,' + s)).arrayBuffer());

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
        const pdf = await b64Pdf(String(b64));
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

// 03/11/2026 anh: "bấm vào 1 hoá đơn không ra cái gì, MISA xem được ảnh" → {viec:'xem_hd', phien, so_hd, hkd, ngay} từ trình duyệt:
// kiểm phiên + quyền (rpc kt_hd_xem) → PDF có sẵn trong kt-chung-tu hd/{chieu}/{mã}.pdf thì ký link, chưa có thì tải từ MISA rồi lưu. — Monsieur Claude
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type, apikey, authorization', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const traJ = (x: unknown, s = 200) => new Response(JSON.stringify(x), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
async function kyLink(duong: string) {
  const r = await fetch(`${SB}/storage/v1/object/sign/kt-chung-tu/${duong}`, { method: 'POST', headers: sbH, body: JSON.stringify({ expiresIn: 600 }) });
  if (!r.ok) return null; const j = await r.json(); return j.signedURL ? `${SB}/storage/v1${j.signedURL}` : null;
}
// 03/11/2026 anh: "kéo ảnh định kỳ về đắp lên Supabase" — lưu PDF vào kt-chung-tu hd/{chieu}/{mã}.pdf + ghi kt_hd_pdf
async function luuPdf(chieu: string, ma: string, pdf: Uint8Array) {
  const duong = `hd/${chieu}/${String(ma).replace(/[^A-Za-z0-9_-]/g, '_')}.pdf`;
  const up = await fetch(`${SB}/storage/v1/object/kt-chung-tu/${duong}`, { method: 'POST', headers: { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/pdf', 'x-upsert': 'true' }, body: pdf });
  if (!up.ok) return false;
  await fetch(SB + '/rest/v1/kt_hd_pdf?on_conflict=ma', { method: 'POST', headers: { ...sbH, Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify({ ma, chieu, duong, kich_thuoc: pdf.length }) });
  return true;
}
// 10/11/2026 kế toán: "tồn file đến hết T9 — cần trừ tồn của toàn bộ HĐ đã xuất từ T10 đến giờ" → tải XML HĐ bán ra công ty
// (POST /invoice/Download?downloadDataType=Xml), tách dòng hàng <HHDVu> (mã MHHDVu · tên · ĐVT · SL · đơn giá · thành tiền · thuế suất)
// → kt_thue_hd_dong (kt_thue_lap_nguon trừ tồn sổ sách). Mỗi HĐ lấy 1 lần; lỗi thử lại sau 6 giờ. Body {"xml":true} = chỉ chạy bước này. — Monsieur Claude
const tagX = (s: string, t: string) => { const m = s.match(new RegExp('<' + t + '>([\\s\\S]*?)</' + t + '>')); return m ? m[1].trim() : ''; };
const txtX = (s: string) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
const docXml = (xml: string) => [...xml.matchAll(/<HHDVu>([\s\S]*?)<\/HHDVu>/g)].map((m, i) => { const b = m[1];
  return { stt: i + 1, tc: +tagX(b, 'TChat') || 1, ma: txtX(tagX(b, 'MHHDVu')), ten: txtX(tagX(b, 'THHDVu')), dvt: txtX(tagX(b, 'DVTinh')),
    sl: +tagX(b, 'SLuong') || 0, dg: +tagX(b, 'DGia') || 0, tt: +tagX(b, 'ThTien') || 0, ts: tagX(b, 'TSuat') }; });
// 10/11/2026 anh "bịt hẳn vào": sau khi kéo HĐ + dòng hàng, hỏi luôn kt-meinvoice-nhap {viec:'kiem'} → nháp app đã phát hành chuyển "Đã xuất HĐ"
// trong CÙNG lượt (không chờ người mở trang) → tồn sổ sách không trừ 2 lần (đơn app + HĐ MISA). Monsieur Claude
async function kiemNhap() {
  try { const r = await fetch(SB + '/functions/v1/kt-meinvoice-nhap', { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-kt-cron': Deno.env.get('KT_CRON_KEY')! }, body: JSON.stringify({ viec: 'kiem' }) });
    return await r.json(); } catch (e) { return { loi: String(e) }; }
}
async function taiXmlRa(A: any, batDau: number) {
  const r = await sb('rpc/kt_thue_hd_can_xml', { p_tu: '2026-10-01', p_n: 300 }, 'return=representation');
  const ds = r.ok ? await r.json() as any[] : []; const m: any = { can: ds.length, luu: 0, loi: 0, dong: 0 };
  for (let i = 0; i < ds.length && Date.now() - batDau < 100e3; i += 10) {
    const nhom = ds.slice(i, i + 10); let kq: any[] = [];
    try { const j = await goi(MI + '/invoice/Download?downloadDataType=Xml&invoiceWithCode=true', { method: 'POST', headers: A, body: JSON.stringify(nhom.map(x => x.ma)) }); kq = (doc(j.Data) || []) as any[]; }
    catch (e) { m.loi += nhom.length; m.loi_cuoi = String(e).slice(0, 160); continue; }
    for (const x of nhom) {
      const f = kq.find(k => String(k.TransactionID) === String(x.ma)); let xml = f ? String(f.Data || f.data || '') : '';
      if (!xml || f.ErrorCode) { await sb('rpc/kt_thue_hd_luu_dong', { p_ma: x.ma, p_ds: [], p_loi: String(f?.ErrorCode || 'MISA không trả XML') }); m.loi++; continue; }
      if (!xml.trimStart().startsWith('<')) xml = new TextDecoder().decode(new Uint8Array(await (await fetch('data:text/xml;base64,' + xml)).arrayBuffer()));
      const dong = docXml(xml);
      const rr = await sb('rpc/kt_thue_hd_luu_dong', { p_ma: x.ma, p_ds: dong, p_loi: dong.length ? null : 'XML không có dòng hàng' });
      if (rr.ok && dong.length) { m.luu++; m.dong += dong.length; } else m.loi++;
    }
  }
  return m;
}
async function taiPdfXem(A: any, batDau: number) {
  const r = await sb('rpc/kt_hd_can_pdf_xem', { p_chieu: 'ra', p_n: 90 }, 'return=representation');
  const ds = r.ok ? await r.json() as any[] : []; const m: any = { can: ds.length, luu: 0, loi: 0 };
  for (let i = 0; i < ds.length && Date.now() - batDau < 105e3; i += 3) {
    const nhom = ds.slice(i, i + 3); let kq: any[] = [];
    try { const j = await goi(MI + '/invoice/Download?downloadDataType=Pdf&invoiceWithCode=true', { method: 'POST', headers: A, body: JSON.stringify(nhom.map(x => x.ma)) }); kq = (doc(j.Data) || []) as any[]; }
    catch (e) { m.loi += nhom.length; m.loi_cuoi = String(e).slice(0, 160); continue; }
    for (const x of nhom) {
      const f = kq.find(k => String(k.TransactionID) === String(x.ma)), b64 = f ? (f.Data || f.data) : null;
      const hong = (ly: string) => { m.loi++; (m.ma_loi ||= []).push(`${x.ky_hieu || ''} ${x.so_hd || ''}: ${ly}`.slice(0, 120)); };
      if (!b64 || f.ErrorCode) { hong(f?.ErrorCode || 'MISA không trả file'); continue; }
      try { if (await luuPdf('ra', x.ma, await b64Pdf(String(b64)))) m.luu++; else hong('lưu Storage lỗi'); } catch (e) { hong(String(e)); }
    }
  }
  return m;
}
async function xemHd(b: any, taiPdf: (ma: string) => Promise<Uint8Array | null>) {
  try {
    const q = await fetch(SB + '/rest/v1/rpc/kt_hd_xem', { method: 'POST', headers: sbH, body: JSON.stringify({ p_phien: b.phien, p_so_hd: String(b.so_hd || ''), p_hkd: String(b.hkd || ''), p_ngay: b.ngay || null, p_ma: b.ma || null }) });
    const hd = await q.json(); if (!q.ok) throw new Error(hd.message || 'Không có quyền');
    if (!hd || !hd.ma) throw new Error('Hoá đơn này không có mã trên MISA');
    const duong = `hd/${hd.chieu}/${String(hd.ma).replace(/[^A-Za-z0-9_-]/g, '_')}.pdf`;
    // 03/11: bản lưu sẵn (kt_hd_pdf) của CẢ 2 chiều ký link tại đây; HĐ vào chưa có bản lưu → trả thieu để trang gọi kt-meinvoice-bot. Monsieur Claude
    let url = hd.pdf === false ? null : await kyLink(duong);
    if (!url && hd.chieu !== 'ra') return traJ({ thieu: hd.chieu, hd });
    if (!url) {
      const pdf = await taiPdf(String(hd.ma));
      if (!pdf) throw new Error('MISA chưa trả được bản hoá đơn, thử lại sau ít phút');
      const up = await fetch(`${SB}/storage/v1/object/kt-chung-tu/${duong}`, { method: 'POST', headers: { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/pdf', 'x-upsert': 'true' }, body: pdf });
      if (!up.ok) throw new Error('Lưu hoá đơn lỗi ' + up.status);
      await fetch(SB + '/rest/v1/kt_hd_pdf?on_conflict=ma', { method: 'POST', headers: { ...sbH, Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify({ ma: hd.ma, chieu: hd.chieu, duong, kich_thuoc: pdf.length }) });
      url = await kyLink(duong);
    }
    return traJ({ url, hd });
  } catch (e) { return traJ({ loi: String((e as any)?.message || e) }, 400); }
}
async function pdfRaMot(ma: string) {
  const t = await goi(MI + '/invoice/token', { method: 'POST', headers: H, body: JSON.stringify({ taxcode: Deno.env.get('KT_MEINVOICE_MST'), username: Deno.env.get('KT_MEINVOICE_USER'), password: Deno.env.get('KT_MEINVOICE_PASS') }) });
  const A = { ...H, Authorization: 'Bearer ' + t.Data };
  const j = await goi(MI + '/invoice/Download?downloadDataType=Pdf&invoiceWithCode=true', { method: 'POST', headers: A, body: JSON.stringify([ma]) });
  const f = ((doc(j.Data) || []) as any[]).find(k => String(k.TransactionID) === ma), b64 = f ? (f.Data || f.data) : null;
  return b64 && !f.ErrorCode ? await b64Pdf(String(b64)) : null;
}
Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  const batDau = Date.now(); let body: any = {};
  try { body = await req.json(); } catch (_) { /* cron gửi {} */ }
  if (body.viec === 'xem_hd') return xemHd(body, pdfRaMot);
  if (req.headers.get('x-kt-cron') !== Deno.env.get('KT_CRON_KEY')) return new Response('không có quyền', { status: 401 });
  const kq: any = { thang: {} };
  try {
    const t = await goi(MI + '/invoice/token', { method: 'POST', headers: H, body: JSON.stringify({
      taxcode: Deno.env.get('KT_MEINVOICE_MST'), username: Deno.env.get('KT_MEINVOICE_USER'), password: Deno.env.get('KT_MEINVOICE_PASS') }) });
    const A = { ...H, Authorization: 'Bearer ' + t.Data };
    if (body.xml) { kq.xml = await taiXmlRa(A, batDau); kq.nhap = await kiemNhap(); kq.giay = Math.round((Date.now() - batDau) / 1000); return Response.json(kq); }
    if (body.pdf_xem) {   // chỉ tải sẵn PDF hoá đơn ra (lịch kt-hd-pdf-ra mỗi giờ)
      kq.pdf_xem = await taiPdfXem(A, batDau); kq.giay = Math.round((Date.now() - batDau) / 1000);
      if (kq.pdf_xem.can) await sb('kt_nhat_ky', { nguoi: 'meInvoice (tự kéo)', bang: 'kt_hd_pdf', hanh_dong: 'tai_pdf_hd_ra', du_lieu: kq });
      return Response.json(kq);
    }
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
    kq.xml = await taiXmlRa(A, batDau);
    kq.nhap = await kiemNhap();
    kq.giay = Math.round((Date.now() - batDau) / 1000);
    await sb('kt_nhat_ky', { nguoi: 'meInvoice (tự kéo)', bang: 'kt_thue_hd', hanh_dong: 'keo_meinvoice', du_lieu: kq });
    return Response.json(kq);
  } catch (e) {
    await sb('kt_nhat_ky', { nguoi: 'meInvoice (tự kéo)', bang: 'kt_thue_hd', hanh_dong: 'keo_meinvoice_loi', du_lieu: { loi: String(e), da_xong: kq } });
    return Response.json({ loi: String(e), da_xong: kq }, { status: 500 });
  }
});
