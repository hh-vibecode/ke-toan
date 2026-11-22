// Kiểm 31/10/2026: NCC nước ngoài / trung gian không lấy Kiot; NCC nội địa vẫn lấy Kiot như cũ (VIEC 208). Monsieur Claude
const { taoTam, xoaTam } = require('./tk-tam'); const { sql } = require('./sql'); const { docKhoa } = require('./khoa');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co';
const rpc = async (f, b) => { const r = await fetch(`${SB}/rest/v1/rpc/${f}`, { method: 'POST', headers: { apikey: K.ANON_KEY, Authorization: 'Bearer ' + K.ANON_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify(b) }); const j = await r.json(); if (!r.ok) throw new Error(f + ': ' + JSON.stringify(j)); return j; };
let dat = 0, hong = 0; const ok = (d, t) => { d ? dat++ : hong++; console.log((d ? 'ĐẠT ' : 'HỎNG') + ' ' + t); };
(async () => {
  const T = await taoTam('tam-ncc-nn');
  try {
    const ds = (await rpc('kt_ds_ncc', { p_phien: T.phien })).ncc;
    const nn = ds.filter(x => x.loai === 'nuoc_ngoai'), nd = ds.filter(x => x.loai === 'noi_dia' || x.loai === 'dich_vu');
    ok(nn.length === 45, `45 NCC nước ngoài vẫn còn (${nn.length})`);
    ok(nn.every(x => x.nguon === 'app' && x.cong_no == null && x.so_nhap === 0), 'nước ngoài: nguồn app, không công nợ Kiot, 0 phiếu nhập Kiot');
    ok(nd.length === 310 && nd.every(x => x.nguon === 'kiot'), `nội địa / dịch vụ: ${nd.length} NCC vẫn nguồn Kiot`);
    ok(nd.filter(x => x.so_nhap > 0).length > 50 && nd.some(x => x.cong_no != null), 'nội địa vẫn có phiếu nhập + công nợ Kiot');
    const sv = (await sql(`select id from kt_ncc where ma = 'NCC000354'`))[0].id;   // NCC TQ TƯỢNG CỔ — trước có 13 phiếu nhập Kiot
    const c = await rpc('kt_ncc_ct', { p_phien: T.phien, p_id: sv });
    ok(c.ncc.nguon === 'app' && c.nhap.length === 0 && c.no == null && c.ncc.cong_no === undefined && c.pb.length === 0, 'popup NCC TQ TƯỢNG CỔ: không phiếu nhập / công nợ / phân bổ Kiot');
    const d1 = nd.find(x => x.so_nhap > 0), c2 = await rpc('kt_ncc_ct', { p_phien: T.phien, p_id: d1.id });
    ok(c2.ncc.nguon === 'kiot' && c2.nhap.filter(x => x.trang_thai === 3).length === d1.so_nhap && c2.no != null, `popup nội địa ${d1.ma}: ${c2.nhap.length} phiếu nhập Kiot + công nợ`);
    const tg = await sql(`select kt_ncc_tu_gan(false) r`);
    ok(true, 'tự gắn (chạy thử, không ghi): ' + JSON.stringify(tg[0].r));
    const pbnn = await sql(`select count(*) n from kt_ncc_phan_bo b join kt_ncc n on n.id = b.ncc_id where kt_ncc_kiot(n.loai, n.kiot_id) is null`);
    ok(+pbnn[0].n === 0, 'không còn phân bổ phiếu nhập Kiot cho NCC nước ngoài');
  } finally { await xoaTam('tam-ncc-nn'); }
  console.log(`${dat}/${dat + hong} đạt`); process.exit(hong ? 1 : 0);
})().catch(e => { console.error(e.message); xoaTam('tam-ncc-nn').finally(() => process.exit(1)); });
