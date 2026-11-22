// Kiểm thử chứng từ đầu–cuối như trình duyệt (khoá anon + phiên). Tải 1 ảnh PNG nhỏ lên phiếu chi đầu tiên rồi XOÁ CỨNG. Monsieur Claude
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co', FN = SB + '/functions/v1/kt-chung-tu';
const H = { apikey: K.ANON_KEY, Authorization: 'Bearer ' + K.ANON_KEY, 'Content-Type': 'application/json' };
const rpc = async (fn, a) => { const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: H, body: JSON.stringify(a) }); const t = await r.text(); return { s: r.status, j: t ? JSON.parse(t) : null }; };
const fn = async b => { const r = await fetch(FN, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b) }); return { s: r.status, j: await r.json() }; };
let ok = 0, loi = 0; const kq = (t, d, g) => { d ? ok++ : loi++; console.log((d ? 'ĐẠT ' : 'LỖI ') + t + (g ? ' — ' + g : '')); };
(async () => {
  const TAM = await require('./tk-tam').taoTam('tam-chung-tu', 'supreme', ['*']); const P = TAM.phien;   // tài khoản tạm (09/10)
  const chiId = (await sql(`select id from kt_chi where not da_xoa order by id limit 1`))[0].id;
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
  const a = await fn({ phien: 'phien-gia', viec: 'tai_len', bang: 'chi', dong_id: chiId, ten: 'x.png' });
  kq('phiên giả KHÔNG xin được link tải lên', a.s === 403, a.j.loi);
  const u = await fn({ phien: P, viec: 'tai_len', bang: 'chi', dong_id: chiId, ten: 'KIỂM THỬ hoá đơn.png' });
  kq('xin link tải lên', u.s === 200 && u.j.url, u.j.loi || u.j.duong_dan);
  const put = await fetch(u.j.url, { method: 'PUT', headers: { 'Content-Type': 'image/png' }, body: png });
  kq('tải file lên bằng link ký tên', put.ok, 'HTTP ' + put.status);
  const g = await rpc('kt_them_chung_tu', { p_phien: P, p_bang: 'chi', p_dong_id: chiId, p_duong_dan: u.j.duong_dan, p_ten: 'KIỂM THỬ hoá đơn.png', p_mime: 'image/png', p_kich_thuoc: png.length });
  kq('ghi thông tin chứng từ', g.s === 200, JSON.stringify(g.j).slice(0, 100));
  const g2 = await rpc('kt_them_chung_tu', { p_phien: P, p_bang: 'chi', p_dong_id: chiId, p_duong_dan: 'thu/1/gia.png', p_ten: 'x', p_mime: 'image/png', p_kich_thuoc: 1 });
  kq('chặn đường dẫn sai bảng / phiếu', g2.s >= 400, g2.j && g2.j.message);
  const ds = await rpc('kt_ds_chung_tu', { p_phien: P, p_bang: 'chi', p_dong_id: chiId });
  kq('danh sách chứng từ của phiếu', ds.s === 200 && ds.j.some(x => x.id === g.j));
  const x = await fn({ phien: P, viec: 'xem', ids: [g.j] });
  const xem = x.j.ds && x.j.ds[0] && await fetch(x.j.ds[0].url);
  kq('xem bằng link ký tên', xem && xem.ok && (await xem.arrayBuffer()).byteLength === png.length, x.j.loi);
  const t = await fn({ phien: P, viec: 'xem', ids: [g.j], tai_ve: true });
  const tv = await fetch(t.j.ds[0].url);
  kq('tải về có tên file', tv.ok && /attachment/i.test(tv.headers.get('content-disposition') || ''), tv.headers.get('content-disposition'));
  const x2 = await fn({ phien: 'phien-gia', viec: 'xem', ids: [g.j] });
  kq('phiên giả KHÔNG xem được', x2.s === 403, x2.j.loi);
  const cong = await fetch(`${SB}/storage/v1/object/public/kt-chung-tu/${u.j.duong_dan}`);
  kq('link công khai KHÔNG mở được (bucket riêng tư)', !cong.ok, 'HTTP ' + cong.status);
  const ky = await rpc('kt_ds_chung_tu_ky', { p_phien: P, p_tu: '2026-01-01', p_den: '2026-12-31' });
  kq('danh sách chứng từ theo kỳ', ky.s === 200 && ky.j.some(z => z.id === g.j));
  const xo = await rpc('kt_xoa_chung_tu', { p_phien: P, p_id: g.j });
  kq('xoá (ẩn) chứng từ', xo.s === 200 || xo.s === 204);
  // dọn: xoá file thật + dòng + nhật ký thử
  await fetch(`${SB}/storage/v1/object/kt-chung-tu`, { method: 'DELETE', headers: { apikey: K.SERVICE_ROLE_KEY, Authorization: 'Bearer ' + K.SERVICE_ROLE_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ prefixes: [u.j.duong_dan] }) });
  await sql(`delete from kt_chung_tu where ten_file like 'KIỂM THỬ%'; delete from kt_nhat_ky where bang='kt_chung_tu' and (du_lieu::text like '%KIỂM THỬ%' or dong_id=${g.j})`);
  await rpc('kt_dang_xuat', { p_phien: P }); await require('./tk-tam').xoaTam('tam-chung-tu');
  console.log(`\nKẾT QUẢ: ${ok} đạt · ${loi} lỗi (đã xoá file + dữ liệu thử)`);
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
