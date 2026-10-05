// Kiểm thử đầu-cuối app kế toán, gọi Y NHƯ TRÌNH DUYỆT (khoá anon công khai + phiên đăng nhập).
// Ghi thử rồi XOÁ CỨNG dữ liệu thử ở cuối (qua Management API). Không in mật khẩu / token. Monsieur Claude
const { docKhoa } = require('./khoa');
const { sql } = require('./sql');
const SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co';
const K = docKhoa(), ANON = K.ANON_KEY;
const H = { apikey: ANON, Authorization: 'Bearer ' + ANON, 'Content-Type': 'application/json' };
let ok = 0, sai = 0;
const kq = (ten, dung, ghi = '') => { dung ? ok++ : sai++; console.log((dung ? 'ĐẠT ' : 'LỖI ') + ten + (ghi ? ' — ' + ghi : '')); };
async function rpc(fn, args) {
  const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: H, body: JSON.stringify(args) });
  const t = await r.text(); let j = null; try { j = JSON.parse(t); } catch (e) {}
  return { s: r.status, j, msg: j && j.message };
}
(async () => {
  const MK = K.KT_MK_HAI; if (!MK || !ANON) throw new Error('thiếu KT_MK_HAI / ANON_KEY trong kt-keys.local.txt');
  // 1. Đăng nhập
  const d1 = await rpc('kt_dang_nhap', { p_tk: 'hai', p_mk: MK + 'x', p_nho: false });
  kq('sai mật khẩu bị từ chối', d1.s === 200 && d1.j && d1.j.loi, d1.j && d1.j.loi);
  const d2 = await rpc('kt_dang_nhap', { p_tk: 'hai', p_mk: MK, p_nho: false });
  kq('đăng nhập đúng', d2.s === 200 && d2.j && d2.j.phien, d2.j && d2.j.toi && d2.j.toi.vi_tri);
  const P = d2.j.phien;
  // 2. Chặn
  const r1 = await fetch(`${SB}/rest/v1/kt_nguoi_dung?select=*`, { headers: H });
  kq('anon KHÔNG đọc thẳng bảng kt_nguoi_dung', r1.status >= 400, 'HTTP ' + r1.status);
  const r2 = await fetch(`${SB}/rest/v1/kt_thu?select=*`, { headers: H });
  kq('anon KHÔNG đọc thẳng bảng kt_thu', r2.status >= 400, 'HTTP ' + r2.status);
  const r3 = await rpc('kt_chan', { p_phien: P });
  kq('anon KHÔNG gọi hàm nội bộ kt_chan', r3.s >= 400, 'HTTP ' + r3.s);
  const r4 = await rpc('kt_danh_muc', { p_phien: 'token-bia' });
  kq('phiên giả bị chặn', r4.s === 403, 'HTTP ' + r4.s);
  // 3. Đọc mọi trang
  const dm = await rpc('kt_danh_muc', { p_phien: P });
  kq('danh mục', dm.s === 200 && dm.j.tai_khoan.length > 0, `${dm.j.tai_khoan.length} TK · ${dm.j.don_vi.length} đơn vị · ${dm.j.loai.length} loại`);
  for (const [fn, a] of [['kt_goi_y', {}], ['kt_bao_cao', { p_tu: '2026-08-01', p_den: '2026-10-05' }], ['kt_dong_tien', { p_tu: '2026-08-01', p_den: '2026-10-05' }],
    ['kt_ds_nguoi_dung', {}], ['kt_ds_nhat_ky', {}], ...['thu', 'chi', 'dieu_chuyen', 'cong_no', 'sap_tra'].map(b => ['kt_ds', { p_bang: b, p_tu: '2026-08-01', p_den: '2026-10-05' }])]) {
    const r = await rpc(fn, { p_phien: P, ...a });
    kq('đọc ' + fn + (a.p_bang ? '(' + a.p_bang + ')' : ''), r.s === 200, r.s === 200 ? '' : r.msg);
  }
  // 4. Ghi thử (đánh dấu nội dung "KIỂM THỬ" để xoá)
  const tk1 = dm.j.tai_khoan[0].id, tk2 = dm.j.tai_khoan[1].id, dv = dm.j.don_vi.find(x => x.la_co_so).id;
  const lt = dm.j.loai.find(x => x.nhom === 'thu').id, lc = dm.j.loai.find(x => x.nhom === 'chi' && x.cach_chia === 'rieng').id;
  const t = await rpc('kt_luu_thu', { p_phien: P, p_dong: { ngay: '2026-10-05', noi_dung: 'KIỂM THỬ thu', so_tien: 1000000, don_vi_id: dv, tai_khoan_id: tk1, loai_id: lt, ghi_chu: null } });
  kq('ghi khoản thu', t.s === 200, t.msg);
  const c = await rpc('kt_luu_chi', { p_phien: P, p_dong: { nguoi_de_nghi: 'KIỂM THỬ', noi_dung: 'KIỂM THỬ chi', so_tien: 400000, phan_bo: [{ don_vi_id: dv, so_tien: 400000 }], ngay_su_dung: null, han_tt: null } });
  kq('tạo đề nghị chi', c.s === 200, c.msg);
  const c2 = await rpc('kt_luu_chi', { p_phien: P, p_dong: { id: c.j, nguoi_de_nghi: 'KIỂM THỬ', noi_dung: 'KIỂM THỬ chi', so_tien: 400000, phan_bo: [{ don_vi_id: dv, so_tien: 400000 }], trang_thai: 'cho_tt' } });
  kq('duyệt chi', c2.s === 200, c2.msg);
  const c3 = await rpc('kt_luu_chi', { p_phien: P, p_dong: { id: c.j, nguoi_de_nghi: 'KIỂM THỬ', noi_dung: 'KIỂM THỬ chi', so_tien: 400000, phan_bo: [{ don_vi_id: dv, so_tien: 400000 }], trang_thai: 'da_tt', ngay_tt: '2026-10-05', tai_khoan_id: tk1, loai_id: lc, kiot: 'khong' } });
  kq('thanh toán chi', c3.s === 200, c3.msg);
  const c4 = await rpc('kt_luu_chi', { p_phien: P, p_dong: { nguoi_de_nghi: 'KIỂM THỬ', noi_dung: 'KIỂM THỬ sai phân bổ', so_tien: 500, phan_bo: [{ don_vi_id: dv, so_tien: 400 }] } });
  kq('chặn phân bổ lệch số tiền', c4.s >= 400, c4.msg);
  const dc = await rpc('kt_luu_dieu_chuyen', { p_phien: P, p_dong: { ngay: '2026-10-05', noi_dung: 'KIỂM THỬ điều chuyển', so_tien: 200000, tk_di_id: tk1, tk_nhan_id: tk2, kiot: 'khong' } });
  kq('ghi điều chuyển', dc.s === 200, dc.msg);
  const bc = await rpc('kt_bao_cao', { p_phien: P, p_tu: '2026-10-05', p_den: '2026-10-05' });
  const t1 = bc.j && bc.j.tai_khoan.find(x => x.id === tk1), t2 = bc.j && bc.j.tai_khoan.find(x => x.id === tk2);
  kq('báo cáo: tiền vào 1.000.000, tiền ra 400.000 (không gồm điều chuyển)', bc.j && +bc.j.tien_vao === 1000000 && +bc.j.tien_ra === 400000, `vào ${bc.j && bc.j.tien_vao} · ra ${bc.j && bc.j.tien_ra}`);
  kq('báo cáo: TK1 = +1tr −400k −200k = 400.000; TK2 = +200.000', t1 && +t1.cuoi_ky === 400000 && t2 && +t2.cuoi_ky === 200000, `TK1 ${t1 && t1.cuoi_ky} · TK2 ${t2 && t2.cuoi_ky}`);
  const pdv = bc.j && bc.j.chi_theo_dv.find(x => x.don_vi_id === dv);
  kq('báo cáo: chi riêng về đúng cơ sở', pdv && +pdv.so_tien === 400000, JSON.stringify(bc.j && bc.j.chi_theo_dv));
  // 5. Phân quyền: tài khoản nhân viên chỉ xem Thu
  await sql(`insert into kt_nguoi_dung (ten_dang_nhap, ho_ten, vi_tri, quyen, mk_hash) values ('kiemthu.nv', 'KIỂM THỬ', 'nhan_vien', '{thu}', extensions.crypt('KiemThu-12345', extensions.gen_salt('bf'))) on conflict (ten_dang_nhap) do nothing`);
  const n = await rpc('kt_dang_nhap', { p_tk: 'kiemthu.nv', p_mk: 'KiemThu-12345', p_nho: false });
  const PN = n.j.phien;
  kq('nhân viên xem được Thu', (await rpc('kt_ds', { p_phien: PN, p_bang: 'thu', p_tu: '2026-08-01', p_den: '2026-10-05' })).s === 200);
  const n2 = await rpc('kt_ds', { p_phien: PN, p_bang: 'chi', p_tu: '2026-08-01', p_den: '2026-10-05' });
  kq('nhân viên KHÔNG xem được Chi', n2.s >= 400, n2.msg);
  const n3 = await rpc('kt_luu_thu', { p_phien: PN, p_dong: { ngay: '2026-10-05', noi_dung: 'KIỂM THỬ nv', so_tien: 1, tai_khoan_id: tk1, loai_id: lt } });
  kq('nhân viên chỉ xem KHÔNG ghi được Thu', n3.s >= 400, n3.msg);
  const n4 = await rpc('kt_ds_nguoi_dung', { p_phien: PN });
  kq('nhân viên KHÔNG xem được danh sách tài khoản', n4.s >= 400, n4.msg);
  // 6. Sai 5 lần → khoá
  for (let i = 0; i < 5; i++) await rpc('kt_dang_nhap', { p_tk: 'kiemthu.nv', p_mk: 'sai', p_nho: false });
  const k = await rpc('kt_dang_nhap', { p_tk: 'kiemthu.nv', p_mk: 'KiemThu-12345', p_nho: false });
  kq('sai 5 lần → khoá dù mật khẩu đúng', k.j && k.j.loi && /khoá/.test(k.j.loi), k.j && k.j.loi);
  // 7. Đăng xuất
  await rpc('kt_dang_xuat', { p_phien: P });
  kq('đăng xuất xong phiên hết hiệu lực', (await rpc('kt_danh_muc', { p_phien: P })).s === 403);
  // Dọn dữ liệu thử
  const don = await sql(`
    with a as (delete from kt_thu where noi_dung like 'KIỂM THỬ%' returning 1), b as (delete from kt_chi where nguoi_de_nghi = 'KIỂM THỬ' returning 1),
         c as (delete from kt_dieu_chuyen where noi_dung like 'KIỂM THỬ%' returning 1),
         d as (delete from kt_phien where nguoi_dung_id in (select id from kt_nguoi_dung where ten_dang_nhap = 'kiemthu.nv') returning 1)
    select (select count(*) from a) thu, (select count(*) from b) chi, (select count(*) from c) dc`);
  await sql(`delete from kt_nguoi_dung where ten_dang_nhap = 'kiemthu.nv'; delete from kt_nhat_ky where nguoi = 'KIỂM THỬ' or du_lieu::text like '%KIỂM THỬ%' or du_lieu::text like '%kiemthu.nv%'`);
  console.log('Đã xoá dữ liệu thử:', JSON.stringify(don[0]));
  console.log(`\nKẾT QUẢ: ${ok} đạt · ${sai} lỗi`);
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
