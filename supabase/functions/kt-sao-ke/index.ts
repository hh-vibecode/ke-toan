// kt-sao-ke — tự tính lại báo cáo Đối chiếu sao kê (phiếu thu / chi – hoá đơn đỏ – sao kê) hằng ngày, để LINK ONLINE luôn mới
// dù không ai mở trang trên app. 10/11/2026 anh: "kế toán vẫn thêm HĐ như cũ trên MISA, app tự kéo về — set lịch định kỳ check bổ sung".
// Một nguồn tính duy nhất: lấy đoạn code giữa 2 dấu <sk-tinh-chung> trong index.html đang chạy (GitHub Pages) — đúng hàm skKQ của trang —
// chạy trên kt_sao_ke_du_lieu, lưu bằng kt_sao_ke_luu_kq_ht (chỉ ghi khi kết quả đổi). pg_cron 'kt-sao-ke', header x-kt-cron = secret KT_CRON_KEY.
// Tính lại các kỳ có ngày cuối trong 6 tháng gần nhất. — Monsieur Claude
const SB = Deno.env.get('SUPABASE_URL')!, SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const APP = 'https://hh-vibecode.github.io/ke-toan/index.html';
const rpc = async (fn: string, args: unknown) => {
  const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
  const t = await r.text(); if (!r.ok) { let m = t; try { m = JSON.parse(t).message || t; } catch (_) { /* giữ chữ gốc */ } throw new Error(m); }
  return t ? JSON.parse(t) : null;
};
const doc = async (path: string) => {
  const r = await fetch(`${SB}/rest/v1/${path}`, { headers: { apikey: SK, Authorization: 'Bearer ' + SK } });
  if (!r.ok) throw new Error(await r.text()); return r.json();
};
async function layTinh() {
  const ban = (await (await fetch(APP.replace('index.html', 'phien-ban.txt') + '?t=' + Date.now())).text()).trim();
  const h = await (await fetch(APP + '?v=' + encodeURIComponent(ban))).text();
  const a = h.indexOf('// <sk-tinh-chung>'), b = h.indexOf('// </sk-tinh-chung>');
  const dong = (re: RegExp) => { const m = h.match(re); if (!m) throw new Error('Không đọc được cách tính trên app'); return m[0]; };
  if (a < 0 || b < a) throw new Error('Không đọc được cách tính trên app');
  const code = [dong(/^const fmt=.*$/m), dong(/^const fmtD=.*$/m), dong(/^const sumBy=.*$/m), dong(/^const soHD=.*$/m), h.slice(a, b), 'return skKQ;'].join('\n');
  return { skKQ: new Function(code)(), ban };
}
Deno.serve(async (req) => {
  if (req.headers.get('x-kt-cron') !== Deno.env.get('KT_CRON_KEY')) return new Response('không có quyền', { status: 401 });
  const ra: any = { doi: 0, giu: 0, loi: [] as string[] };
  try {
    const { skKQ, ban } = await layTinh(); ra.ban = ban;
    const tu = new Date(Date.now() - 183 * 864e5).toISOString().slice(0, 10);
    const ky: { id: number }[] = await doc(`kt_sao_ke_ky?select=id&den=gte.${tu}&order=den.desc&limit=60`);
    for (const k of ky) {
      try { const kq = skKQ(await rpc('kt_sao_ke_du_lieu', { p_ky: k.id })); if (await rpc('kt_sao_ke_luu_kq_ht', { p_ky: k.id, p_kq: kq })) ra.doi++; else ra.giu++; }
      catch (e) { ra.loi.push(k.id + ': ' + String((e as Error).message || e).slice(0, 150)); }
    }
  } catch (e) { ra.loi.push(String((e as Error).message || e).slice(0, 200)); }
  return new Response(JSON.stringify(ra), { status: ra.loi.length ? 500 : 200, headers: { 'Content-Type': 'application/json' } });
});
