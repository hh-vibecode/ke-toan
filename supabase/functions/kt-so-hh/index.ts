// kt-so-hh — chia sẻ hoa hồng + quy tắc hoa hồng sang app MKT để so đơn hằng đêm (17/11/2026).
// Anh (qua phiên MKT): "bảo kế toán share phần hoa hồng, hỗ trợ check cuối mỗi ngày xem các đơn đã được ghi nhận đúng đủ cho các sale chưa,
// share cả phần quy tắc hoa hồng xem hoa hồng của sale đã đúng chưa". Một nguồn tính duy nhất: đoạn <hh-tinh-chung> (hhTinh) trong index.html đang chạy —
// đúng như trang Hoa hồng và Edge kt-hoa-hong-ma. Ghi: so_dt_2app.hh / hh_ly (dòng ben='kt', vai "Bán" của sale) + so_dt_2app_quy_tac (ben='kt').
// Lịch kt-so-hh 21:40 VN (sau kt-so-dt-2app 21:30), header x-kt-cron = secret KT_CRON_KEY. Từ tháng 11/2026. — Monsieur Claude
const SB = Deno.env.get('SUPABASE_URL')!, SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const APP = 'https://hh-vibecode.github.io/ke-toan/index.html';
const H = { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/json' };
const rpc = async (fn: string, args: unknown) => {
  const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: H, body: JSON.stringify(args) });
  const t = await r.text(); if (!r.ok) { let m = t; try { m = JSON.parse(t).message || t; } catch (_) { /* giữ chữ gốc */ } throw new Error(fn + ': ' + m); }
  return t ? JSON.parse(t) : null;
};
async function docMa(thang: string): Promise<string[]> {   // mã dòng ben='kt' của tháng (phân trang 1000)
  const out: string[] = [];
  for (let tu = 0; ; tu += 1000) {
    const r = await fetch(`${SB}/rest/v1/so_dt_2app?select=ma&ben=eq.kt&thang=eq.${thang}&order=ma`, { headers: { ...H, Range: `${tu}-${tu + 999}` } });
    if (!r.ok) throw new Error('đọc so_dt_2app: ' + await r.text());
    const a = await r.json(); out.push(...a.map((x: any) => x.ma)); if (a.length < 1000) break;
  }
  return out;
}
async function layTinh() {
  const ban = (await (await fetch(APP.replace('index.html', 'phien-ban.txt') + '?t=' + Date.now())).text()).trim();
  const h = await (await fetch(APP + '?v=' + encodeURIComponent(ban))).text();
  const a = h.indexOf('// <hh-tinh-chung>'), b = h.indexOf('// </hh-tinh-chung>');
  const dong = (re: RegExp) => { const m = h.match(re); if (!m) throw new Error('Không đọc được cách tính trên app'); return m[0]; };
  if (a < 0 || b < a) throw new Error('Không đọc được cách tính trên app');
  const code = [dong(/^const sumBy=.*$/m), dong(/^const fmt=.*$/m), dong(/^const CS3=.*$/m), dong(/^const csCuaCN=.*$/m), h.slice(a, b), 'return {hhTinh, HH_MOC_LE, HH_MOC_SI, HH_HTDS};'].join('\n');
  const f = new Function(code)();
  // dòng trang Logic về hoa hồng: [nghiệp vụ, mục, quy tắc, ghi chú, ngày]
  const logic: any[] = [];
  for (const m of h.matchAll(/^ \['bao_cao','Hoa hồng[^\n]*$/gm)) { try { logic.push(new Function('return ' + m[0].trim().replace(/,\s*$/, ''))()); } catch (_) { /* bỏ dòng đọc lỗi */ } }
  return { ...f, logic, ban };
}
const thangVN = () => new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 7);
const cuoiThang = (m: string) => new Date(Date.UTC(+m.slice(0, 4), +m.slice(5, 7), 0)).toISOString().slice(0, 10);
const tr = (v: number) => (v / 1e6).toLocaleString('vi-VN', { maximumFractionDigits: 0 }) + 'tr';
const pt = (v: number) => (Math.round(v * 1e4) / 100).toLocaleString('vi-VN') + '%';
const ngayLogic = (s: string) => { const m = String(s || '').match(/^(\d{1,2})\/(\d{1,2})$/); return m ? `2026-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}` : null; };
Deno.serve(async (req) => {
  if (req.headers.get('x-kt-cron') !== Deno.env.get('KT_CRON_KEY')) return new Response('không có quyền', { status: 401 });
  const ra: any = { thang: {}, loi: [] as string[] };
  try {
    const T = await layTinh(); ra.ban = T.ban;
    const quyTac = new Map<string, any>();
    const them = (khoa: string, noi_dung: string, ap_tu: string | null = null, ap_den: string | null = null) => quyTac.set(khoa, { khoa, noi_dung, ap_tu, ap_den });
    them('moc_le', 'Sales lẻ — mốc theo DOANH THU xét mốc tháng: ' + T.HH_MOC_LE.map((x: any) => (x[1] === Infinity ? 'từ ' + tr(x[0]) : tr(x[0]) + '–' + tr(x[1])) + ' ' + pt(x[2])).join(' · ') + '; giật cấp ra tỷ lệ bình quân; hoa hồng = thực thu (tiền về trong tháng) × tỷ lệ.');
    them('moc_si', 'Sales sỉ — đạt mốc mới tính (mốc mặc định 600tr, người có mốc hỗ trợ theo cấu hình riêng): ' + T.HH_MOC_SI.map((x: any) => (x[1] === Infinity ? 'trên ' + tr(x[0]) : 'đến ' + tr(x[1])) + ' ' + pt(x[2])).join(' · ') + '; giật cấp ra tỷ lệ bình quân; hoa hồng = thực thu × tỷ lệ.');
    them('ho_tro_ds', 'Hỗ trợ doanh số (theo doanh thu phạm vi): ' + T.HH_HTDS.filter((x: any) => x[1]).map((x: any) => 'từ ' + tr(x[0]) + ' → ' + x[1].toLocaleString('vi-VN') + 'đ').join(' · ') + '.');
    T.logic.forEach((x: any, i: number) => them('logic_' + (i + 1), `${x[1]}: ${x[2]}${x[3] ? ' — ' + x[3] : ''}`, ngayLogic(x[4])));
    const nay = thangVN();
    for (let m = '2026-11'; m <= nay; m = new Date(Date.UTC(+m.slice(0, 4), +m.slice(5, 7), 1)).toISOString().slice(0, 7)) {
      const [d, ds] = await Promise.all([rpc('kt_bc_hoa_hong_dl', { p_tu: m + '-01', p_den: cuoiThang(m) }), docMa(m)]);
      const co = new Set(ds), acc: Record<string, { hh: number; ly: Set<string> }> = {};
      const r = T.hhTinh(d, [m]); let le = 0, leTien = 0;
      for (const o of r.NGs) {
        for (const x of (o.saleKy || []).filter((z: any) => z.m === m)) {
          const p = x.p || {};
          them('nguoi:' + o.ten, `${o.ten}: ${p.cs === 'si' ? 'Sales sỉ' : p.cs === 'le' ? 'Sales lẻ' : p.cs === 'online' ? 'Online' : p.cs === 'ht_ds' ? 'Hỗ trợ doanh số' : p.cs || '?'}`
            + (p.kiot && p.kiot.length ? ' · tài khoản Kiot tính cho người này: ' + p.kiot.join(', ') : '')
            + (p.ho_tro && p.ho_tro.tu ? ` · mốc hỗ trợ ${tr(+p.ho_tro.moc || 6e8)} từ ${p.ho_tro.tu}${p.ho_tro.den ? ' đến ' + p.ho_tro.den : ''}` : '')
            + (+p.tl ? ' · tỷ lệ ' + pt(+p.tl) : ''), p.tu ? (String(p.tu).length === 7 ? p.tu + '-01' : String(p.tu).slice(0, 10)) : null);
        }
        const cach = ((o.saleKy || []).find((z: any) => z.m === m) || {}).cach || '';
        for (const e of o.ds || []) {
          const vai: string[] = Array.isArray(e.vai) ? e.vai : [e.vai]; if (!vai.includes('Bán')) continue;   // vai = danh sách vai trò của người trên đơn (thamGia); tien = tổng các vai
          const h = e.h || {}, k = h.ma_don && co.has(h.ma_don) ? h.ma_don : h.ma;
          if (!co.has(k)) { le++; leTien += +e.tien || 0; continue; }   // tiền về tháng này của đơn tính doanh thu tháng khác
          (acc[k] = acc[k] || { hh: 0, ly: new Set() }).hh += +e.tien || 0;
          acc[k].ly.add(`kt:nguoi:${o.ten} — ${cach}`);
        }
      }
      const p_ds = Object.entries(acc).map(([ma, v]) => ({ ma, hh: Math.round(v.hh), hh_ly: [...v.ly].join(' | ') }));
      const n = await rpc('kt_so_dt_2app_hh', { p_thang: m, p_ds });
      ra.thang[m] = { ma: ds.length, co_hh: n, tong_hh: Math.round(Object.values(acc).reduce((s, v) => s + v.hh, 0)), ngoai_thang: le, ngoai_thang_tien: Math.round(leTien) };
    }
    ra.quy_tac = await rpc('kt_so_dt_2app_quy_tac_ghi', { p_ds: [...quyTac.values()] });
  } catch (e) { ra.loi.push(String((e as Error).message || e).slice(0, 300)); }
  return new Response(JSON.stringify(ra), { status: ra.loi.length ? 500 : 200, headers: { 'Content-Type': 'application/json' } });
});
