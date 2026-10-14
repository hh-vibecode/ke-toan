// Edge Function kt-meinvoice-bot — kéo HOÁ ĐƠN ĐẦU VÀO (mua vào) của công ty THT từ MISA "Xử lý hóa đơn" (meInvoice Bot). CHỈ ĐỌC MISA.
// Luồng (tài liệu developer.misa.vn → Xử lý hóa đơn): validateuser → auth/jwttoken → subscribers/code/{MST} → {sub}/organizations → {sub}/{org}/invoices/v2/modified.
// Body {"tu":"2026-09","den":"2026-09","thu":true} = CHẠY THỬ: chỉ trả số đếm / tổng, KHÔNG ghi gì. Gọi bằng header x-kt-cron = secret KT_CRON_KEY.
// Secrets: KT_MEINVOICE_BOT_CLIENT_ID, KT_MEINVOICE_BOT_CLIENT_SECRET, KT_MEINVOICE_MST / USER / PASS (cùng tài khoản MISA với meInvoice). Monsieur Claude 14/10/2026
const MI = 'https://developer.misa.vn/apis/meinvoicebot/v1';
const CID = Deno.env.get('KT_MEINVOICE_BOT_CLIENT_ID')!, CSEC = Deno.env.get('KT_MEINVOICE_BOT_CLIENT_SECRET')!;
const MST = Deno.env.get('KT_MEINVOICE_BOT_MST') || Deno.env.get('KT_MEINVOICE_MST')!;
const USER = Deno.env.get('KT_MEINVOICE_BOT_USER') || Deno.env.get('KT_MEINVOICE_USER')!;
const PASS = Deno.env.get('KT_MEINVOICE_BOT_PASS') || Deno.env.get('KT_MEINVOICE_PASS')!;
const H0 = { 'Content-Type': 'application/json', ClientID: CID, ClientSecret: CSEC };
const ngu = (ms: number) => new Promise(r => setTimeout(r, ms));
const thangVN = (lech: number) => { const d = new Date(Date.now() + 7 * 3600e3); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() + lech); return d.toISOString().slice(0, 7); };
const cuoiThang = (t: string) => new Date(Date.UTC(+t.slice(0, 4), +t.slice(5, 7), 0)).toISOString().slice(0, 10);
const sauThang = (t: string) => new Date(Date.UTC(+t.slice(0, 4), +t.slice(5, 7), 1)).toISOString().slice(0, 7);
// lỗi trả về: chỉ mã lỗi / thông điệp của MISA, KHÔNG kèm header hay token
class LoiMisa extends Error {}
async function goi(buoc: string, url: string, opt: RequestInit, lanMax = 4) {
  for (let lan = 1; ; lan++) {
    try {
      const r = await fetch(url, opt); const t = await r.text(); let j: any; try { j = JSON.parse(t); } catch (_) { j = null; }
      if (!r.ok || !j || j.Success === false) throw new LoiMisa(`${buoc}: HTTP ${r.status} ${j ? (j.ErrorCode || '') + ' ' + JSON.stringify(j.Errors || j.Message || '').slice(0, 200) : t.slice(0, 120)}`);
      return j;
    } catch (e) { if (lan >= lanMax || (e instanceof LoiMisa && /HTTP 4\d\d/.test(e.message))) throw e; await ngu(2000 * lan); }
  }
}
async function dangNhap() {
  const v = await goi('validateuser', MI + '/validateuser', { method: 'POST', headers: { ...H0, CompanyTaxCode: MST, UserName: USER }, body: JSON.stringify({ PassWord: PASS }) }, 2);
  const du = String(v.Data || ''), sau = du.includes(';') ? du.slice(du.indexOf(';') + 1) : du;
  // tài liệu: Data = "{CompanyID};{securetoken}" — thử phần sau dấu ";" trước, không được thì cả chuỗi
  let loi = '';
  for (const st of [sau, du]) {
    try {
      const j = await goi('jwttoken', MI + '/auth/jwttoken', { method: 'POST', headers: { ...H0, companytaxcode: MST, username: USER, securetoken: st }, body: '{}' }, 1);
      const d = typeof j.Data === 'string' ? (() => { try { return JSON.parse(j.Data); } catch (_) { return j.Data; } })() : j.Data;
      const tok = typeof d === 'string' ? d : (d?.AccessToken || d?.accessToken || d?.access_token);
      if (tok) return { tok: String(tok), cach: st === sau ? 'sau_cham_phay' : 'ca_chuoi', congTy: du.includes(';') ? du.slice(0, du.indexOf(';')) : '' };
      loi = 'jwttoken: không thấy AccessToken trong Data (khoá: ' + Object.keys(d || {}).join(',') + ')';
    } catch (e) { loi = String(e); }
  }
  throw new Error(loi);
}
Deno.serve(async req => {
  if (req.headers.get('x-kt-cron') !== Deno.env.get('KT_CRON_KEY')) return new Response('không có quyền', { status: 401 });
  let body: any = {}; try { body = await req.json(); } catch (_) { /* {} */ }
  const kq: any = { thu: !!body.thu, buoc: [] as string[] };
  try {
    const { tok, cach, congTy } = await dangNhap(); kq.buoc.push('token ok (' + cach + ')');
    // header gửi 1 lần ClientId (gửi cả ClientID lẫn ClientId thì fetch gộp thành "id, id" → MISA báo không có quyền)
    const A = { ClientId: CID, Authorization: 'Bearer ' + tok };
    const sub = await goi('subscribers', MI + '/subscribers/code/' + encodeURIComponent(MST), { headers: A });
    // tài liệu ghi lẫn "Id" của subscribers và "CompanyID" → thử lần lượt, mã nào lấy được danh sách tổ chức thì dùng
    const ung = [...new Set([sub.Data?.Id, congTy].filter(Boolean).map(String))];
    let subId = '', og: any = null; const loiOrg: string[] = [];
    for (const u of ung) { try { og = await goi('organizations', `${MI}/${u}/organizations`, { headers: A }, 1); subId = u; break; } catch (e) { loiOrg.push(String(e)); } }
    if (!og) throw new Error('organizations lỗi với cả ' + ung.length + ' mã: ' + loiOrg.join(' | '));
    const orgs = (Array.isArray(og.Data) ? og.Data : og.Data?.Items || []) as any[];
    kq.to_chuc = orgs.map(o => ({ ten: o.Name || null, so_hd_vao: o.InvoiceCount ?? null, con: (o.Childrens || []).length }));
    kq.thang = {};
    for (let th = String(body.tu || thangVN(-1)); th <= String(body.den || thangVN(0)); th = sauThang(th)) {
      const m: any = { so_hd: 0, so_dong_hang: 0, tong: 0, chua_thue: 0, thue: 0, ncc: 0, theo_trang_thai: {}, bi_xoa: 0, khac_ky: 0 };
      const ncc = new Set<string>();
      for (const o of orgs) {
        const oid = o.Id || o.id || o.OrganizationID;
        for (let sk = 0; ; sk += 100) {
          const p = await goi('invoices', `${MI}/${subId}/${oid}/invoices/v2/modified?take=100&skip=${sk}&from=${th}-01&to=${cuoiThang(th)}&IsFilterInvDate=true`, { headers: A });
          const dd = typeof p.Data === 'string' ? JSON.parse(p.Data) : p.Data;
          if (!kq.dang_tra) kq.dang_tra = { kieu: Array.isArray(dd) ? 'mang' : typeof dd, khoa: dd && !Array.isArray(dd) ? Object.keys(dd) : [], total: dd?.Total ?? dd?.total ?? null };
          const it = (Array.isArray(dd) ? dd : dd?.Items || dd?.items || dd?.Data || []) as any[];
          if (!kq.mau_khoa && it[0]) kq.mau_khoa = { hd: Object.keys(it[0]), dong: Object.keys((it[0].Items || [])[0] || {}) };
          for (const x of it) {
            if (x.IsDeleted) { m.bi_xoa++; continue; }
            if (String(x.InvoiceDate || '').slice(0, 7) !== th) m.khac_ky++;
            m.so_hd++; m.so_dong_hang += (x.Items || []).length; m.tong += +x.TotalAmount || 0; m.chua_thue += +x.TotalAmountWithoutVat || 0; m.thue += +x.TotalVATAmount || 0;
            const tt = String(x.StatusInvoice ?? x.InvoiceCodeStatus ?? '?'); m.theo_trang_thai[tt] = (m.theo_trang_thai[tt] || 0) + 1;
            if (x.SellerTaxCode) ncc.add(x.SellerTaxCode);
          }
          if (it.length < 100) break; await ngu(300);
        }
      }
      m.ncc = ncc.size; m.tong = Math.round(m.tong); m.chua_thue = Math.round(m.chua_thue); m.thue = Math.round(m.thue);
      kq.thang[th] = m;
    }
    return Response.json(kq);
  } catch (e) {
    kq.loi = String(e); return Response.json(kq, { status: 500 });
  }
});
