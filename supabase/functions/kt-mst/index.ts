// kt-mst — tra mã số thuế người mua cho màn Lập hoá đơn (11/11/2026 kế toán: "đánh MST vào thì tự lấy thông tin trên trang thuế về fill người mua").
// Kiểm phiên app (kt_mst_lay → kt_chan quyền Hoá đơn & Thuế) → có bản lưu ≤ 30 ngày thì trả luôn; chưa có thì tra:
//   1) VietQR /v2/business/{mst} (dữ liệu doanh nghiệp từ cơ quan thuế)  2) cổng HĐĐT Tổng cục Thuế (dsdkts) — rồi lưu kt_mst_luu.
// Chỉ gửi đi MST (thông tin công khai). Không dùng nguồn esgoo (thử 11/11 trả SAI tên công ty cho MST công ty mình). — Monsieur Claude
const SB = Deno.env.get('SUPABASE_URL')!, SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'content-type' };
const traJ = (o: unknown, st = 200) => new Response(JSON.stringify(o), { status: st, headers: { ...CORS, 'Content-Type': 'application/json' } });
const rpc = async (fn: string, args: unknown) => {
  const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
  const t = await r.text(); if (!r.ok) { let m = t; try { m = JSON.parse(t).message || t; } catch (_) { /* giữ chữ gốc */ } throw new Error(m); }
  return t ? JSON.parse(t) : null;
};
const hoi = async (url: string, ms = 7000) => { const c = new AbortController(), t = setTimeout(() => c.abort(), ms);
  try { const r = await fetch(url, { signal: c.signal, headers: { 'User-Agent': 'ke-toan-app/1.0', Accept: 'application/json' } }); return { st: r.status, j: await r.json().catch(() => null) }; }
  finally { clearTimeout(t); } };
async function vietqr(mst: string) {
  let st = 0, j: any = null;
  for (let lan = 0; lan < 5; lan++) {   // VietQR giới hạn lượt (đo 11/11: cách ~15 giây thì được) → đợi 5 giây thử lại, tối đa 5 lần
    ({ st, j } = await hoi(`https://api.vietqr.io/v2/business/${mst}`));
    if (st !== 429) break; await new Promise(r => setTimeout(r, 5000));
  }
  if (st === 429) throw new Error('VietQR đang giới hạn lượt tra, thử lại sau ít giây');
  if (j && j.code === '00' && j.data && j.data.name) return { ten: j.data.name, dia_chi: j.data.address || '', nguon: 'VietQR (dữ liệu cơ quan thuế)', dl: j.data };
  return null;
}
async function gdt(mst: string) {
  const { j } = await hoi(`https://hoadondientu.gdt.gov.vn:30000/category/public/dsdkts/${mst}/manager`);
  if (j && (j.tennnt || j.ten)) return { ten: j.tennnt || j.ten, dia_chi: j.dctsdchi || j.diachi || '', nguon: 'Cổng HĐĐT Tổng cục Thuế', dl: j };
  return null;
}
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const b = await req.json().catch(() => ({}));
    const mst = String(b.mst || '').replace(/\s/g, '');
    if (!/^(\d{10}(-\d{3})?|\d{12})$/.test(mst)) return traJ({ loi: 'MST phải là 10 số, chi nhánh 10 số-3 số, hoặc 12 số (hộ kinh doanh / cá nhân)' }, 400);
    const cu = await rpc('kt_mst_lay', { p_phien: String(b.phien || ''), p_mst: mst });   // kiểm phiên + quyền
    if (cu) return traJ({ ...cu, luu: true });
    const loi: string[] = [];
    for (const f of [vietqr, gdt]) {
      try { const r = await f(mst); if (r) { await rpc('kt_mst_luu', { p_mst: mst, p_ten: r.ten, p_dia_chi: r.dia_chi, p_nguon: r.nguon, p_dl: r.dl }); return traJ({ mst, ten: r.ten, dia_chi: r.dia_chi, nguon: r.nguon }); } }
      catch (e) { loi.push(String((e as Error).message || e).slice(0, 120)); }
    }
    return traJ({ loi: 'Không tìm thấy MST ' + mst + (loi.length ? ' (' + loi.join('; ') + ')' : '') + ' — điền tay' }, 404);
  } catch (e) {
    return traJ({ loi: String((e as Error).message || e).slice(0, 200) }, 400);
  }
});
