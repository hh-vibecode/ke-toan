// Edge Function kt-kiot — LUỒNG KÉO KIOT RIÊNG của app kế toán (anh chốt 05/10/2026: không dùng chung MKT/Sale, 3 tiếng / lần).
// pg_cron 'kt-kiot' gọi hàm này (header x-kt-cron = secret KT_CRON_KEY). CHỈ ĐỌC Kiot (GET).
// Mỗi lần: kéo sổ quỹ Kiot 10 ngày gần nhất → upsert kt_kiot_so_quy → kt_dong_bo_kiot() chép phiếu thu sang kt_thu → ghi nhật ký.
// Secrets (tiền tố KT_): KT_KIOT_CLIENT_ID, KT_KIOT_CLIENT_SECRET, KT_KIOT_RETAILER, KT_CRON_KEY. Monsieur Claude
const SB = Deno.env.get('SUPABASE_URL')!, SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SO_NGAY = 10;

async function kiotToken() {
  const r = await fetch('https://id.kiotviet.vn/connect/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ scopes: 'PublicApi.Access', grant_type: 'client_credentials',
      client_id: Deno.env.get('KT_KIOT_CLIENT_ID')!, client_secret: Deno.env.get('KT_KIOT_CLIENT_SECRET')! }) });
  if (!r.ok) throw new Error('Kiot token lỗi ' + r.status);
  return (await r.json()).access_token as string;
}
async function soQuy(tok: string, tu: string, den: string) {
  const all: any[] = []; let off = 0, total = Infinity;
  while (off < total) {
    const qs = new URLSearchParams({ startDate: tu, endDate: den, includeAccount: 'true', includeBranch: 'true', includeUser: 'true', pageSize: '100', currentItem: String(off) });
    let r: Response | null = null;
    for (let lan = 0; lan < 4; lan++) {
      r = await fetch('https://public.kiotapi.com/cashflow?' + qs, { headers: { Retailer: Deno.env.get('KT_KIOT_RETAILER')!, Authorization: 'Bearer ' + tok } });
      if (r.status !== 429 && r.status < 500) break;
      await new Promise(s => setTimeout(s, 1500 * (lan + 1)));
    }
    if (!r || !r.ok) throw new Error('Kiot cashflow lỗi ' + (r && r.status));
    const j = await r.json(); total = j.total || 0; const d = j.data || [];
    all.push(...d); if (!d.length) break; off += d.length;
  }
  return all;
}
const sb = (duong: string, body: unknown, prefer = 'return=minimal') => fetch(SB + '/rest/v1/' + duong, { method: 'POST',
  headers: { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/json', Prefer: prefer }, body: JSON.stringify(body) });

Deno.serve(async req => {
  if (req.headers.get('x-kt-cron') !== Deno.env.get('KT_CRON_KEY')) return new Response('không có quyền', { status: 401 });
  const batDau = Date.now();
  try {
    const vn = new Date(Date.now() + 7 * 3600e3);
    // endDate của Kiot KHÔNG gồm chính ngày đó → lấy tới ngày mai để có phiếu hôm nay
    const den = new Date(vn.getTime() + 864e5).toISOString().slice(0, 10), tuD = new Date(vn.getTime() - SO_NGAY * 864e5).toISOString().slice(0, 10);
    const tu = tuD < '2026-09-01' ? '2026-09-01' : tuD;
    const cf = await soQuy(await kiotToken(), tu, den);
    const rows = cf.map(x => ({ id: x.id, ma: x.code, ngay: String(x.transDate).slice(0, 19) + '+07:00', chi_nhanh: x.branch ?? null, la_thu: x.amount > 0,
      so_tien: Math.abs(Math.round(x.amount)), phuong_thuc: x.method ?? null, tai_khoan: x.accountId ? String(x.accountId) : null, doi_tac: x.partnerName ?? null,
      nhom: x.cashGroup ?? null, noi_dung: x.description ?? null, chung_tu_goc: x.origin ?? null, trang_thai: String(x.status), goc: x, keo_luc: new Date().toISOString() }));
    for (let i = 0; i < rows.length; i += 500) {
      const r = await sb('kt_kiot_so_quy?on_conflict=id', rows.slice(i, i + 500), 'resolution=merge-duplicates,return=minimal');
      if (!r.ok) throw new Error('Ghi kt_kiot_so_quy lỗi ' + r.status + ' ' + (await r.text()).slice(0, 200));
    }
    const d = await sb('rpc/kt_dong_bo_kiot', { p_tu: tu }, 'return=representation');
    const kq = { tu, den, so_phieu: rows.length, dong_bo: d.ok ? await d.json() : 'lỗi ' + d.status, giay: Math.round((Date.now() - batDau) / 1000) };
    await sb('kt_nhat_ky', { nguoi: 'Kiot (tự kéo)', bang: 'kt_kiot_so_quy', hanh_dong: 'keo_kiot', du_lieu: kq });
    return Response.json(kq);
  } catch (e) {
    await sb('kt_nhat_ky', { nguoi: 'Kiot (tự kéo)', bang: 'kt_kiot_so_quy', hanh_dong: 'keo_kiot_loi', du_lieu: { loi: String(e) } });
    return Response.json({ loi: String(e) }, { status: 500 });
  }
});
