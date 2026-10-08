// Edge Function kt-chung-tu — cấp link ký tên (5 phút) để TẢI LÊN / XEM / TẢI VỀ chứng từ trong bucket riêng tư 'kt-chung-tu'.
// Trang web gửi phiên đăng nhập; hàm kiểm phiên + quyền theo trang / dòng (kt_quyen_chung_tu) bằng service_role rồi mới ký link.
// Body: {phien, viec:'tai_len', bang, dong_id, ten}  → {duong_dan, url}   (trình duyệt PUT file vào url)
//       {phien, viec:'xem', ids:[...], tai_ve?:bool} → {ds:[{id, url}]}
// Monsieur Claude
const SB = Deno.env.get('SUPABASE_URL')!, SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const BUCKET = 'kt-chung-tu', HAN = 300;
const H = { apikey: SK, Authorization: 'Bearer ' + SK, 'Content-Type': 'application/json' };
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type, apikey, authorization', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const tra = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });

async function quyen(phien: string, bang: string, ghi: boolean, ids: number[]) {
  const r = await fetch(`${SB}/rest/v1/rpc/kt_quyen_chung_tu`, { method: 'POST', headers: H, body: JSON.stringify({ p_phien: phien, p_bang: bang, p_ghi: ghi, p_ids: ids }) });
  if (!r.ok) { const j = await r.json().catch(() => ({})); throw new Error(j.message || 'Không có quyền'); }
  return await r.json();
}
const sach = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D')
  .replace(/[^A-Za-z0-9._-]+/g, '-').replace(/-+/g, '-').slice(-80) || 'tep';

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const b = await req.json();
    if (b.viec === 'tai_len') {
      await quyen(b.phien, b.bang, true, [Number(b.dong_id)]);
      const duong = `${b.bang}/${Number(b.dong_id)}/${Date.now()}_${sach(String(b.ten || 'tep'))}`;
      const r = await fetch(`${SB}/storage/v1/object/upload/sign/${BUCKET}/${duong}`, { method: 'POST', headers: H, body: '{}' });
      if (!r.ok) throw new Error('Ký link tải lên lỗi ' + r.status);
      const j = await r.json();
      return tra({ duong_dan: duong, url: `${SB}/storage/v1${j.url}` });
    }
    if (b.viec === 'xem') {
      const ids = (b.ids || []).map(Number).filter(Boolean).slice(0, 500);
      if (!ids.length) return tra({ ds: [] });
      const r = await fetch(`${SB}/rest/v1/kt_chung_tu?select=id,bang,dong_id,duong_dan,ten_file&da_xoa=eq.false&id=in.(${ids.join(',')})`, { headers: H });
      const rows: any[] = await r.json();
      for (const bang of [...new Set(rows.map(x => x.bang))]) await quyen(b.phien, bang, false, rows.filter(x => x.bang === bang).map(x => Number(x.dong_id)));   // phải được xem MỌI dòng liên quan (người chỉ đề nghị chi: chỉ phiếu mình)
      const s = await fetch(`${SB}/storage/v1/object/sign/${BUCKET}`, { method: 'POST', headers: H, body: JSON.stringify({ expiresIn: HAN, paths: rows.map(x => x.duong_dan) }) });
      if (!s.ok) throw new Error('Ký link xem lỗi ' + s.status);
      const sj: any[] = await s.json();
      return tra({ ds: rows.map(x => { const k = sj.find(y => y.path === x.duong_dan); const u = k && k.signedURL ? `${SB}/storage/v1${k.signedURL}` : null;
        return { id: x.id, url: u && b.tai_ve ? u + '&download=' + encodeURIComponent(x.ten_file) : u }; }) });
    }
    return tra({ loi: 'Việc không hợp lệ' }, 400);
  } catch (e) { return tra({ loi: String((e as Error).message || e) }, 403); }
});
