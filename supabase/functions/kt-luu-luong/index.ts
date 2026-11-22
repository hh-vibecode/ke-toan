// Edge Function kt-luu-luong — cuối mỗi ngày chụp lưu lượng Supabase (anh 22/10/2026: "các cái nào bên usage Supabase lấy được lấy sang, sợ hết dung lượng;
// gắn cả thông tin máy chủ đang thuê"). CHỈ ĐỌC API quản trị: dự án (vùng, phiên bản), gói tổ chức, máy chủ (compute add-on), đĩa (cấu hình + đã dùng),
// lượt gọi theo giờ 24h (REST / Auth / Storage / Realtime), tình trạng dịch vụ, số Edge Function. Băng thông (egress) API không trả → xem Dashboard.
// Ghi bằng rpc kt_ghi_luu_luong (tự đo thêm CSDL, kho tệp, kết nối, lịch chạy). pg_cron 'kt-luu-luong' 23:55 VN, header x-kt-cron = secret KT_CRON_KEY.
// Secret KT_SB_PAT = token quản trị Supabase (không trả ra ngoài, không ghi log). Monsieur Claude 22/10/2026
const REF = 'bcrpxfvvjsjpvbksqzls', API = 'https://api.supabase.com/v1';
const SB = Deno.env.get('SUPABASE_URL')!, SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const g = async (p: string) => {
  const r = await fetch(API + p, { headers: { Authorization: 'Bearer ' + Deno.env.get('KT_SB_PAT') } });
  if (!r.ok) throw new Error(p.replace(REF, 'REF').split('?')[0] + ': HTTP ' + r.status);
  return r.json();
};
const thu = async (p: string, loi: string[]) => { try { return await g(p); } catch (e) { loi.push(String((e as Error).message)); return null; } };

Deno.serve(async (req) => {
  if (req.headers.get('x-kt-cron') !== Deno.env.get('KT_CRON_KEY')) return new Response('không có quyền', { status: 401 });
  const loi: string[] = [];
  const [du_an, addons, disk, util, dem, health, fns] = await Promise.all([
    thu(`/projects/${REF}`, loi), thu(`/projects/${REF}/billing/addons`, loi), thu(`/projects/${REF}/config/disk`, loi),
    thu(`/projects/${REF}/config/disk/util`, loi), thu(`/projects/${REF}/analytics/endpoints/usage.api-counts?interval=1day`, loi),
    thu(`/projects/${REF}/health?services=db,auth,rest,storage,realtime`, loi), thu(`/projects/${REF}/functions`, loi)]);
  const org = du_an?.organization_slug ? await thu(`/organizations/${du_an.organization_slug}`, loi) : null;
  const ci = (addons?.selected_addons || []).find((a: any) => a.type === 'compute_instance');
  const cong = (k: string) => (dem?.result || []).reduce((s: number, r: any) => s + (+r[k] || 0), 0);
  const api: Record<string, unknown> = {
    goi: org?.plan || null, vung: du_an?.region || null, trang_thai: du_an?.status || null, tao_luc: du_an?.created_at || null,
    postgres: du_an?.database?.version || null,
    may: ci ? { ten: ci.variant?.name, ma: ci.variant?.id, gia: ci.variant?.price?.description, cpu: ci.variant?.meta?.cpu_cores,
      cpu_rieng: ci.variant?.meta?.cpu_dedicated, ram_gb: ci.variant?.meta?.memory_gb, ket_noi_truc_tiep: ci.variant?.meta?.connections_direct,
      ket_noi_pooler: ci.variant?.meta?.connections_pooler, disk_io_mbs: ci.variant?.meta?.baseline_disk_io_mbs } : null,
    addon_khac: (addons?.selected_addons || []).filter((a: any) => a.type !== 'compute_instance').map((a: any) => ({ loai: a.type, ten: a.variant?.name, gia: a.variant?.price?.description })),
    disk: disk?.attributes || null, disk_util: util?.metrics || null,
    goi_24h: dem ? { rest: cong('total_rest_requests'), auth: cong('total_auth_requests'), storage: cong('total_storage_requests'), realtime: cong('total_realtime_requests'),
      theo_gio: (dem.result || []).map((r: any) => [r.timestamp, +r.total_rest_requests || 0, +r.total_auth_requests || 0, +r.total_storage_requests || 0]) } : null,
    dich_vu: (health || []).map((h: any) => ({ ten: h.name, ok: !!h.healthy, tt: h.status })),
    edge: fns ? { tong: fns.length, kt: fns.filter((f: any) => /^kt-/.test(f.name)).length } : null,
  };
  if (loi.length) api.loi = loi.join(' · ');
  const r = await fetch(SB + '/rest/v1/rpc/kt_ghi_luu_luong', { method: 'POST',
    headers: { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_api: api }) });
  const t = await r.text();
  return new Response(JSON.stringify({ ok: r.ok, loi, ghi: r.ok ? 'ok' : t.slice(0, 300) }), { status: r.ok ? 200 : 500, headers: { 'Content-Type': 'application/json' } });
});
