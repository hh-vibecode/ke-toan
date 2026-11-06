// kt-hoa-hong-ma — nhân sự tra cứu hoa hồng của MÌNH bằng mã riêng (ô dưới khung Đăng nhập), không cần tài khoản app.
// 04/11/2026 anh: "mỗi nhân sự trong bảng hoa hồng 1 mã … mỗi mã gắn với dữ liệu 1 người".
// Một nguồn tính duy nhất: lấy đoạn code giữa 2 dấu <hh-tinh-chung> trong index.html đang chạy (GitHub Pages) — đúng hàm hhTinh của trang
// Hoa hồng — chạy trên dữ liệu kt_bc_hoa_hong_dl, rồi CHỈ trả phần của người có mã (không lộ số người khác). — Monsieur Claude
const SB = Deno.env.get('SUPABASE_URL')!, SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const APP = 'https://hh-vibecode.github.io/ke-toan/index.html';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'content-type' };
const traJ = (o: unknown, st = 200) => new Response(JSON.stringify(o), { status: st, headers: { ...CORS, 'Content-Type': 'application/json' } });
const rpc = async (fn: string, args: unknown) => {
  const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
  const t = await r.text(); if (!r.ok) { let m = t; try { m = JSON.parse(t).message || t; } catch (_) { /* giữ chữ gốc */ } throw new Error(m); }
  return JSON.parse(t);
};
let maTinh: { luc: number; f: any; ban: string } | null = null;
async function layTinh() {   // giữ 10 phút; app đổi bản (phien-ban.txt) thì lấy lại
  const ban = (await (await fetch(APP.replace('index.html', 'phien-ban.txt') + '?t=' + Date.now())).text()).trim();
  if (maTinh && maTinh.ban === ban && Date.now() - maTinh.luc < 6e5) return maTinh.f;
  const h = await (await fetch(APP + '?v=' + encodeURIComponent(ban))).text();
  const a = h.indexOf('// <hh-tinh-chung>'), b = h.indexOf('// </hh-tinh-chung>');
  const dong = (re: RegExp) => { const m = h.match(re); if (!m) throw new Error('Không đọc được cách tính trên app'); return m[0]; };
  if (a < 0 || b < a) throw new Error('Không đọc được cách tính trên app');
  const code = [dong(/^const sumBy=.*$/m), dong(/^const CS3=.*$/m), dong(/^const csCuaCN=.*$/m), h.slice(a, b), 'return hhTinh;'].join('\n');
  maTinh = { luc: Date.now(), f: new Function(code)(), ban };
  return maTinh.f;
}
const thangVN = () => new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 7);
const cuoiThang = (m: string) => new Date(Date.UTC(+m.slice(0, 4), +m.slice(5, 7), 0)).toISOString().slice(0, 10);
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const b = await req.json().catch(() => ({}));
    const ma = String(b.ma || '').trim(), nay = thangVN(), thang = /^\d{4}-\d{2}$/.test(b.thang || '') && b.thang <= nay && b.thang >= '2026-01' ? b.thang : nay;
    if (!/^[A-Za-z0-9 ]{6,16}$/.test(ma)) return traJ({ loi: 'Mã không đúng' }, 400);
    const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'khong-ro';
    const ten: string = await rpc('kt_hh_ma_tra', { p_ma: ma, p_ip: ip });
    const [hhTinh, d] = await Promise.all([layTinh(), rpc('kt_bc_hoa_hong_dl', { p_tu: thang + '-01', p_den: cuoiThang(thang) })]);
    const o = hhTinh(d, [thang]).NGs.find((x: any) => x.ten === ten);
    if (!o) return traJ({ ten, thang, o: null });
    // chỉ phần hiển thị cần: bỏ danh sách đơn + cấu hình của người khác (saleKy.H, chiaQuy.dsc)
    const ra = { ten: o.ten, bp: o.bp, vt: [...o.vt], sales: o.sales, quy: o.quy, dong: o.dong, giao: o.giao, tong: o.tong, cong: o.cong, soDon: o.soDon,
      saleKy: o.saleKy.map((x: any) => ({ m: x.m, dt: x.dt, thu: x.thu, hh: x.hh, ht: x.ht, tl: x.tl, moc: x.moc, cach: x.cach, dsDT: x.dsDT || [], p: { ten: x.p.ten, cs: x.p.cs, tl: x.p.tl, vt: x.p.vt, kiot: x.p.kiot, ho_tro: x.p.ho_tro, pv: x.p.pv, tu: x.p.tu } })),
      chiaQuy: o.chiaQuy.map((x: any) => ({ m: x.m, cs: x.cs, vt: x.vt, tl: x.tl, q: x.q, phan: x.phan, c: x.c, tc: x.tc, k: x.k, tien: x.tien })),
      ds: o.ds.map((x: any) => ({ h: { ...x.h, gc: undefined, nh: undefined }, vai: x.vai, tien: x.tien })) };
    return traJ({ ten, thang, o: ra });
  } catch (e) {
    return traJ({ loi: String((e as Error).message || e).slice(0, 200) }, 400);
  }
});
