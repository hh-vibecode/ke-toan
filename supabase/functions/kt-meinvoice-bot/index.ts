// Edge Function kt-meinvoice-bot — kéo HOÁ ĐƠN ĐẦU VÀO (mua vào) của công ty THT từ MISA "Xử lý hóa đơn" (meInvoice Bot). CHỈ ĐỌC MISA.
// Luồng (tài liệu developer.misa.vn → Xử lý hóa đơn): validateuser → auth/jwttoken → subscribers/code/{MST} → {sub}/organizations → {sub}/{org}/invoices/v2/modified.
// Ghi vào kt_thue_hd (hkd CTY, chieu vao, mỗi HĐ 1 dòng — rpc kt_nap_misabot, thay nguyên tháng) rồi tự ghép phiếu chi chưa nhận HĐ (rpc kt_ghep_hd_vao).
// pg_cron 'kt-meinvoice-bot' mỗi đêm: tháng trước + tháng này. Body {"tu":"2026-01","den":"2026-10"} = nạp lại các tháng đó; thêm "thu":true = CHẠY THỬ
// (chỉ đếm, KHÔNG ghi). Bỏ: HĐ bị xoá trên MISA, HĐ đã bị thay thế (4), đã bị huỷ (6). Gọi bằng header x-kt-cron = secret KT_CRON_KEY.
// Secrets: KT_MEINVOICE_BOT_CLIENT_ID, KT_MEINVOICE_BOT_CLIENT_SECRET, KT_MEINVOICE_MST / USER / PASS (cùng tài khoản MISA với meInvoice). Monsieur Claude 14/10/2026
const MI = 'https://developer.misa.vn/apis/meinvoicebot/v1';
const CID = Deno.env.get('KT_MEINVOICE_BOT_CLIENT_ID')!, CSEC = Deno.env.get('KT_MEINVOICE_BOT_CLIENT_SECRET')!;
const MST = Deno.env.get('KT_MEINVOICE_BOT_MST') || Deno.env.get('KT_MEINVOICE_MST')!;
const USER = Deno.env.get('KT_MEINVOICE_BOT_USER') || Deno.env.get('KT_MEINVOICE_USER')!;
const PASS = Deno.env.get('KT_MEINVOICE_BOT_PASS') || Deno.env.get('KT_MEINVOICE_PASS')!;
const SB = Deno.env.get('SUPABASE_URL')!, SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const sbH = { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/json' };
const sb = (duong: string, body: unknown, prefer = 'return=minimal') => fetch(SB + '/rest/v1/' + duong, { method: 'POST', headers: { ...sbH, Prefer: prefer }, body: JSON.stringify(body) });
const TT: Record<string, string> = { '2': 'HĐ thay thế', '3': 'HĐ điều chỉnh', '5': 'Đã bị điều chỉnh', '7': 'Chưa xác định trạng thái' };
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
  const batDau = Date.now(); let body: any = {}; try { body = await req.json(); } catch (_) { /* cron gửi {} */ }
  const thu = !!body.thu, kq: any = { thu, thang: {} };
  try {
    const { tok, congTy } = await dangNhap();
    // header gửi 1 lần ClientId (gửi cả ClientID lẫn ClientId thì fetch gộp thành "id, id" → MISA báo không có quyền)
    const A = { ClientId: CID, Authorization: 'Bearer ' + tok };
    const sub = await goi('subscribers', MI + '/subscribers/code/' + encodeURIComponent(MST), { headers: A });
    // tài liệu ghi lẫn "Id" của subscribers và "CompanyID" → thử lần lượt, mã nào lấy được danh sách tổ chức thì dùng
    const ung = [...new Set([sub.Data?.Id, congTy].filter(Boolean).map(String))];
    let subId = '', og: any = null; const loiOrg: string[] = [];
    for (const u of ung) { try { og = await goi('organizations', `${MI}/${u}/organizations`, { headers: A }, 3); subId = u; break; } catch (e) { loiOrg.push(String(e)); } }
    if (!og) throw new Error('organizations lỗi: ' + loiOrg.join(' | '));
    const orgs = (Array.isArray(og.Data) ? og.Data : og.Data?.Items || []) as any[];
    for (let th = String(body.tu || thangVN(-1)); th <= String(body.den || thangVN(0)); th = sauThang(th)) {
      const gap = new Map<string, any>(); const m: any = { lay: 0, bo_xoa: 0, bo_thay_huy: 0, khac_thang: 0 };
      for (const o of orgs) {
        for (let sk = 0; ; sk += 100) {
          const p = await goi('invoices', `${MI}/${subId}/${o.Id}/invoices/v2/modified?take=100&skip=${sk}&from=${th}-01&to=${cuoiThang(th)}&IsFilterInvDate=true`, { headers: A });
          const dd = typeof p.Data === 'string' ? JSON.parse(p.Data) : p.Data;
          const it = (Array.isArray(dd) ? dd : dd?.Data || dd?.Items || []) as any[];
          for (const x of it) {
            m.lay++;
            const id = String(x.InvoiceId || x.Id || ''), st = String(x.StatusInvoice ?? x.InvoiceCodeStatus ?? '');
            if (x.IsDeleted) { m.bo_xoa++; continue; }
            if (st === '4' || st === '6') { m.bo_thay_huy++; continue; }
            const ngay = String(x.InvoiceDate || '').slice(0, 10);
            if (ngay.slice(0, 7) !== th) { m.khac_thang++; continue; }
            if (!id || gap.has(id)) continue;
            const ds = (x.Items || []) as any[];
            gap.set(id, { id, so_hd: x.InvoiceNo == null ? null : String(x.InvoiceNo), mau: x.TemplateNo ?? null, ky_hieu: x.Series ?? null, ngay,
              mst: x.SellerTaxCode || '', ncc: x.SellerName || '', so_dong: ds.length,
              ten: x.ItemNamesText || ds.map(d => d.ItemName).filter(Boolean).join('; ') || null,
              thanh_tien: +x.TotalAmountWithoutVat || 0, tien_thue: +x.TotalVATAmount || 0, tong: +x.TotalAmount || 0,
              ghi_chu: [TT[st], x.CcyCode && x.CcyCode !== 'VND' ? 'Ngoại tệ ' + x.CcyCode : ''].filter(Boolean).join(' · ') });
          }
          if (it.length < 100) break; await ngu(300);
        }
      }
      const dong = [...gap.values()];
      m.so_hd = dong.length; m.tong = Math.round(dong.reduce((a, x) => a + x.tong, 0)); m.ncc = new Set(dong.map(x => x.mst || x.ncc)).size;
      if (!thu) {
        const r = await sb('rpc/kt_nap_misabot', { p_thang: th, p_ds: dong }, 'return=representation');
        if (!r.ok) throw new Error(`nạp ${th} lỗi ${r.status} ${(await r.text()).slice(0, 200)}`);
        m.da_ghi = await r.json();
      }
      kq.thang[th] = m;
    }
    const g = await sb('rpc/kt_ghep_hd_vao', { p_ghi: !thu && body.ghep !== false }, 'return=representation');   // "ghep":false = ghi HĐ nhưng chỉ ĐẾM số phiếu sẽ ghép
    kq.ghep = g.ok ? await g.json() : 'lỗi ' + g.status;
    kq.giay = Math.round((Date.now() - batDau) / 1000);
    if (!thu) await sb('kt_nhat_ky', { nguoi: 'MISA Xử lý HĐ (tự kéo)', bang: 'kt_thue_hd', hanh_dong: 'keo_misabot', du_lieu: kq });
    return Response.json(kq);
  } catch (e) {
    if (!thu) await sb('kt_nhat_ky', { nguoi: 'MISA Xử lý HĐ (tự kéo)', bang: 'kt_thue_hd', hanh_dong: 'keo_misabot_loi', du_lieu: { loi: String(e), da_xong: kq } });
    return Response.json({ loi: String(e), da_xong: kq }, { status: 500 });
  }
});
