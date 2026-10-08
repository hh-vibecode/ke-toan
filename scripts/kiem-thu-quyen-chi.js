// Kiểm thử quyền "chỉ tạo đề nghị chi" / "duyệt & thanh toán" + chuông thông báo + chứng từ theo dòng (08/10/2026). Monsieur Claude
// Tạo 1 tài khoản nhân viên TẠM (quyền chi_de_nghi), chạy các ca, rồi DỌN SẠCH (phiếu, thông báo, chứng từ, phiên, tài khoản).
// Không in khoá / mật khẩu. Chạy: ELECTRON_RUN_AS_NODE=1 Code.exe scripts/kiem-thu-quyen-chi.js
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co';
const H = { apikey: K.ANON_KEY, Authorization: 'Bearer ' + K.ANON_KEY, 'Content-Type': 'application/json' };
const rpc = async (fn, a) => { const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: H, body: JSON.stringify(a) });
  const t = await r.text(); const j = t ? JSON.parse(t) : null; if (!r.ok) throw new Error(j && j.message || t); return j; };
const ct = async b => { const r = await fetch(SB + '/functions/v1/kt-chung-tu', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b) }); return { ok: r.ok, j: await r.json() }; };
const TK = 'thu-nghiem-nv', TEN = 'THỬ NGHIỆM NV', MK = 'tn-' + Math.random().toString(36).slice(2) + 'X9';
let dat = 0, truot = 0; const kq = (ten, ok, them = '') => { ok ? dat++ : truot++; console.log((ok ? '  ĐẠT ' : '  TRƯỢT ') + ten + (them ? ' — ' + them : '')); };
const loi = async (f) => { try { await f(); return null; } catch (e) { return e.message; } };
(async () => {
  const ids = [];
  try {
    await sql(`delete from kt_nguoi_dung where ten_dang_nhap='${TK}'`);
    await sql(`insert into kt_nguoi_dung (ten_dang_nhap, ho_ten, vi_tri, quyen, mk_hash) values ('${TK}', '${TEN}', 'nhan_vien', '{chi_de_nghi}', extensions.crypt('${MK}', extensions.gen_salt('bf')))`);
    const NV = (await rpc('kt_dang_nhap', { p_tk: TK, p_mk: MK, p_nho: false })).phien;
    const AD = (await rpc('kt_dang_nhap', { p_tk: 'hai', p_mk: K.KT_MK_HAI, p_nho: false })).phien;
    const hai = (await sql(`select id from kt_nguoi_dung where ten_dang_nhap='hai'`))[0].id;
    const nv = (await sql(`select id from kt_nguoi_dung where ten_dang_nhap='${TK}'`))[0].id;
    // 1. nhân viên tạo đề nghị
    const id = await rpc('kt_luu_chi', { p_phien: NV, p_dong: { noi_dung: 'THU-NGHIEM quyền chi', so_tien: 12345, ngay_su_dung: '2026-10-08' } }); ids.push(id);
    const r1 = (await sql(`select trang_thai, tao_boi from kt_chi where id=${id}`))[0];
    kq('Nhân viên tạo được đề nghị, trạng thái chờ duyệt', r1.trang_thai === 'cho_duyet' && r1.tao_boi === TEN);
    // 2. nhân viên thử tự duyệt / tự thanh toán
    let e = await loi(() => rpc('kt_luu_chi', { p_phien: NV, p_dong: { id, noi_dung: 'THU-NGHIEM quyền chi', so_tien: 12345, trang_thai: 'cho_tt' } }));
    kq('Nhân viên KHÔNG tự duyệt được', !!e && /giám đốc/.test(e));
    e = await loi(() => rpc('kt_luu_chi', { p_phien: NV, p_dong: { noi_dung: 'THU-NGHIEM tt luôn', so_tien: 1000, trang_thai: 'da_tt', tai_khoan_id: 1, loai_id: 1 } }));
    kq('Nhân viên KHÔNG tạo được phiếu "đã thanh toán luôn"', !!e);
    // 3. danh sách chỉ phiếu mình
    const dsNV = await rpc('kt_ds', { p_phien: NV, p_bang: 'chi', p_tu: '2026-09-01', p_den: '2026-10-31' });
    kq('Nhân viên chỉ thấy phiếu mình tạo', dsNV.length >= 1 && dsNV.every(x => x.tao_boi === TEN), dsNV.length + ' phiếu');
    const dsAD = await rpc('kt_ds', { p_phien: AD, p_bang: 'chi', p_tu: '2026-09-01', p_den: '2026-10-31' });
    kq('Admin thấy mọi phiếu + có số chứng từ', dsAD.length > dsNV.length && 'so_ct' in dsAD[0], dsAD.length + ' phiếu');
    // 4. chuông: KẾ TOÁN nhận 'đề nghị chi mới' (luồng 2 lượt 08/10 — anh / giám đốc không nhận ở bước này)
    const tbK = await sql(`select n.ten_dang_nhap from kt_thong_bao t join kt_nguoi_dung n on n.id = t.nguoi_dung_id where t.bang = 'chi' and t.dong_id = ${id} and t.loai = 'chi_moi'`);
    kq('Kế toán (không phải anh / giám đốc) nhận thông báo đề nghị mới', tbK.length > 0 && tbK.every(x => x.ten_dang_nhap === 'ketoan'), tbK.map(x => x.ten_dang_nhap).join(','));
    kq('Người tạo KHÔNG tự nhận thông báo của mình', !(await rpc('kt_ds_thong_bao', { p_phien: NV })).some(x => x.dong_id === id && x.loai === 'chi_moi'));
    // 5. admin duyệt → nhân viên nhận thông báo; nhân viên không sửa được nữa
    // duyệt 2 lượt (08/10): lượt 1 rồi lượt 2 — tài khoản hai làm cả 2 nên giả lập người kiểm lượt 1 khác
    await rpc('kt_luu_chi', { p_phien: AD, p_dong: { id, noi_dung: 'THU-NGHIEM quyền chi', so_tien: 12345, ngay_su_dung: '2026-10-08', trang_thai: 'cho_gd' } });
    await sql(`update kt_chi set kiem_boi = 'THU-NGHIEM lượt 1' where id = ${id}`);
    await rpc('kt_luu_chi', { p_phien: AD, p_dong: { id, noi_dung: 'THU-NGHIEM quyền chi', so_tien: 12345, ngay_su_dung: '2026-10-08', trang_thai: 'cho_tt' } });
    const tbN = await rpc('kt_ds_thong_bao', { p_phien: NV });
    kq('Nhân viên nhận thông báo "đã được duyệt"', tbN.some(x => x.loai === 'chi_duyet' && x.dong_id === id));
    e = await loi(() => rpc('kt_luu_chi', { p_phien: NV, p_dong: { id, noi_dung: 'THU-NGHIEM sửa sau duyệt', so_tien: 1 } }));
    kq('Nhân viên KHÔNG sửa được phiếu đã duyệt', !!e);
    // 6. phiếu người khác
    const khac = dsAD.find(x => x.tao_boi !== TEN).id;
    e = await loi(() => rpc('kt_luu_chi', { p_phien: NV, p_dong: { id: khac, noi_dung: 'x', so_tien: 1 } }));
    kq('Nhân viên KHÔNG sửa được phiếu người khác', !!e);
    // 7. chứng từ theo dòng
    let c = await ct({ phien: NV, viec: 'tai_len', bang: 'chi', dong_id: id, ten: 'THU-NGHIEM.png' });
    kq('Nhân viên xin được link tải chứng từ phiếu mình', c.ok && !!c.j.url);
    c = await ct({ phien: NV, viec: 'tai_len', bang: 'chi', dong_id: khac, ten: 'THU-NGHIEM.png' });
    kq('Nhân viên KHÔNG tải chứng từ vào phiếu người khác', !c.ok);
    const ctKhac = await sql(`select id from kt_chung_tu where bang='chi' and dong_id<>${id} and not da_xoa limit 1`);
    if (ctKhac.length) { c = await ct({ phien: NV, viec: 'xem', ids: [ctKhac[0].id] }); kq('Nhân viên KHÔNG xem chứng từ phiếu người khác', !c.ok); }
    e = await loi(() => rpc('kt_ds_chung_tu', { p_phien: NV, p_bang: 'chi', p_dong_id: khac }));
    kq('Nhân viên KHÔNG liệt kê chứng từ phiếu người khác', !!e);
    c = await ct({ phien: AD, viec: 'tai_len', bang: 'thu', dong_id: 1, ten: 'THU-NGHIEM.png' });
    kq('Admin vẫn xin link chứng từ bình thường', c.ok);
    // 8. thông báo đọc
    await rpc('kt_doc_thong_bao', { p_phien: NV, p_id: null });
    kq('Đánh dấu đã đọc hết', await rpc('kt_dem_thong_bao', { p_phien: NV }) === 0);
    // 9. điều chuyển: tạo → người khác có quyền sửa điều chuyển nhận thông báo
    const dc = await rpc('kt_luu_dieu_chuyen', { p_phien: AD, p_dong: { ngay: '2026-10-08', so_tien: 1, tk_di_id: 1, tk_nhan_id: 2, noi_dung: 'THU-NGHIEM dc' } });
    const tbDc = await sql(`select nguoi_dung_id from kt_thong_bao where bang='dieu_chuyen' and dong_id=${dc}`);
    kq('Điều chuyển mới báo người có quyền sửa (trừ người tạo)', tbDc.length > 0 && !tbDc.some(x => x.nguoi_dung_id === hai) && !tbDc.some(x => x.nguoi_dung_id === nv), tbDc.length + ' người');
    await sql(`delete from kt_thong_bao where bang='dieu_chuyen' and dong_id=${dc}; delete from kt_nhat_ky where bang='kt_dieu_chuyen' and dong_id=${dc}; delete from kt_dieu_chuyen where id=${dc}`);
  } catch (x) { truot++; console.log('  DỪNG: ' + x.message); }
  finally {
    // dọn
    for (const id of ids) await sql(`delete from kt_thong_bao where bang='chi' and dong_id=${id}; delete from kt_chung_tu where bang='chi' and dong_id=${id}; delete from kt_nhat_ky where bang='kt_chi' and dong_id=${id}; delete from kt_chi where id=${id}`);
    await sql(`delete from kt_chi where noi_dung like 'THU-NGHIEM%'; delete from kt_phien where nguoi_dung_id in (select id from kt_nguoi_dung where ten_dang_nhap='${TK}'); delete from kt_thong_bao where nguoi_dung_id in (select id from kt_nguoi_dung where ten_dang_nhap='${TK}'); delete from kt_nguoi_dung where ten_dang_nhap='${TK}'; delete from kt_phien where tao_luc > now() - interval '5 minutes'`);
    console.log(`\n${dat} đạt · ${truot} trượt (đã dọn tài khoản / phiếu / thông báo thử)`);
  }
})();
