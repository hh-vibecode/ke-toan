// KIỂM THỬ ĐẦU-CUỐI LUỒNG ĐỀ NGHỊ THANH TOÁN (15/10/2026, anh: "test luôn luồng đề nghị thanh toán" + "tự test, báo cáo, xong xoá đi").
// Đi đúng đường người dùng: gửi phiếu công khai (không đăng nhập) → tải hồ sơ (ảnh + Excel) → xem trạng thái bằng mã → chuông kế toán
// → kế toán kiểm lượt 1 → (chặn tự duyệt lượt 2) → giám đốc xác nhận → kế toán thanh toán → số dư tài khoản → gửi trùng bị chặn.
// Tài khoản kế toán / giám đốc TẠM; xong DỌN SẠCH: phiếu, hồ sơ (cả file trong kho), chuông, nhật ký, giới hạn gửi, tài khoản tạm. Monsieur Claude
const { docKhoa } = require('./khoa'), { sql } = require('./sql'), { taoTam, xoaTam } = require('./tk-tam');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co', ND = 'THỬ HỆ THỐNG — kiểm luồng đề nghị ' + Date.now();
const H = { apikey: K.ANON_KEY, Authorization: 'Bearer ' + K.ANON_KEY, 'Content-Type': 'application/json' };
const rpc = async (fn, a) => { const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: H, body: JSON.stringify(a) }); const t = await r.text(); const j = t ? JSON.parse(t) : null; if (!r.ok) throw new Error(j && j.message || t); return j; };
const loi = async f => { try { await f(); return null; } catch (e) { return e.message; } };
let dat = 0, truot = 0; const kq = (ten, ok, them = '') => { ok ? dat++ : truot++; console.log((ok ? '  ĐẠT   ' : '  TRƯỢT ') + ten + (them ? ' — ' + them : '')); };
const HOM = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
(async () => {
  let id = null, ma = null; const tam = [];
  try {
    const KT = (await taoTam('tam-dn-kt', 'admin', ['*'], 'THỬ HỆ THỐNG Kế toán')).phien; tam.push('tam-dn-kt');
    const GDt = await taoTam('tam-dn-gd', 'admin', ['*', 'chi_gd'], 'THỬ HỆ THỐNG Giám đốc'); tam.push('tam-dn-gd'); const GD = GDt.phien;
    const dm = await rpc('kt_dm_de_nghi', {});
    const bp = (dm.bo_phan || dm.bp || [])[0], cs = (dm.co_so || dm.don_vi || [])[0];
    kq('Danh mục phiếu công khai (không đăng nhập)', !!bp && !!cs, `bộ phận ${(dm.bo_phan || dm.bp || []).length}, đơn vị ${(dm.co_so || dm.don_vi || []).length}`);
    const p = { nguoi_de_nghi: 'THỬ HỆ THỐNG', bo_phan_id: bp.id, noi_dung: ND, ngay_su_dung: HOM, so_tien: 123000, hinh_thuc: 'ck', thu_huong_ten: 'NGUOI THU',
      thu_huong_nh: 'Vietcombank', thu_huong_stk: '0123456789', phan_bo: [{ don_vi_id: cs.id, so_tien: 123000 }], han_tt: null, co_hd_do: false, ghi_chu: null, web: '' };
    kq('Chặn thiếu số tài khoản khi chuyển khoản', !!(await loi(() => rpc('kt_gui_de_nghi', { p_dong: { ...p, thu_huong_stk: '' } }))));
    kq('Chặn ô bẫy máy tự điền', !!(await loi(() => rpc('kt_gui_de_nghi', { p_dong: { ...p, web: 'x' } }))));
    const r = await rpc('kt_gui_de_nghi', { p_dong: p }); id = r.id; ma = r.ma;
    const c = (await sql(`select trang_thai, nguon, thu_huong_nh, thu_huong_stk, phan_bo from kt_chi where id = ${id}`))[0];
    kq('Gửi phiếu → Chờ kế toán kiểm, nguồn Phiếu đề nghị', c.trang_thai === 'cho_duyet' && c.nguon === 'phieu', `#${id}`);
    kq('Giữ ngân hàng + số TK (để có QR)', c.thu_huong_nh === 'Vietcombank' && c.thu_huong_stk === '0123456789');
    kq('Gửi trùng (cùng người + tiền + nội dung) bị chặn', /vừa được gửi/.test(await loi(() => rpc('kt_gui_de_nghi', { p_dong: p })) || ''));
    // hồ sơ: ảnh + Excel qua Edge Function (đường như trình duyệt)
    const tai = async (ten, mime, buf) => { const r1 = await fetch(`${SB}/functions/v1/kt-chung-tu`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ viec: 'tai_len_phieu', ma, ten }) });
      const j = await r1.json(); if (!r1.ok) throw new Error(j.loi || r1.status);
      const r2 = await fetch(j.url, { method: 'PUT', headers: { 'Content-Type': mime }, body: buf }); if (!r2.ok) throw new Error('PUT ' + r2.status);
      await rpc('kt_them_ct_phieu', { p_ma: ma, p_duong_dan: j.duong_dan, p_ten: ten, p_mime: mime, p_kich_thuoc: buf.length }); return j.duong_dan; };
    const e1 = await loi(() => tai('anh_thu.png', 'image/png', PNG)); kq('Tải hồ sơ ảnh', !e1, e1 || '');
    const e2 = await loi(() => tai('bang_thu.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', Buffer.from('PK thu'))); kq('Tải hồ sơ Excel (phiếu ghi nhận Excel / Word)', !e2, e2 || '');
    const x = await rpc('kt_xem_de_nghi', { p_ma: ma });
    kq('Người gửi xem trạng thái bằng mã', x && x.trang_thai === 'cho_duyet', x.so_file + ' hồ sơ');
    kq('Mã sai không xem được', !!(await loi(() => rpc('kt_xem_de_nghi', { p_ma: '0'.repeat(32) }))));
    const tb = await sql(`select count(*)::int n from kt_thong_bao where bang = 'chi' and dong_id = ${id}`);
    kq('Chuông báo kế toán có phiếu mới', tb[0].n > 0, tb[0].n + ' thông báo');
    // duyệt 2 lượt + thanh toán qua kt_luu_chi (như nút trên app)
    const dong = async () => { const o = (await sql(`select to_jsonb(c) - 'tao_luc' - 'sua_luc' - 'duyet_luc' j from kt_chi c where id = ${id}`))[0].j; return o; };
    await rpc('kt_luu_chi', { p_phien: KT, p_dong: { ...(await dong()), trang_thai: 'cho_gd' } });
    kq('Kế toán kiểm lượt 1 → Chờ GĐ', (await sql(`select trang_thai from kt_chi where id=${id}`))[0].trang_thai === 'cho_gd');
    kq('Người kiểm lượt 1 không tự duyệt lượt 2', !!(await loi(async () => rpc('kt_luu_chi', { p_phien: KT, p_dong: { ...(await dong()), trang_thai: 'cho_tt' } }))));
    await rpc('kt_luu_chi', { p_phien: GD, p_dong: { ...(await dong()), trang_thai: 'cho_tt' } });
    kq('Giám đốc xác nhận → Chờ thanh toán', (await sql(`select trang_thai from kt_chi where id=${id}`))[0].trang_thai === 'cho_tt');
    const tk = (await sql(`select id from kt_tai_khoan where hoat_dong and loai = 'ngan_hang' order by id limit 1`))[0].id, lo = (await sql(`select id from kt_loai where nhom='chi' and ten like 'OPEX - Khác'`))[0].id;
    const sd = async () => +(await sql(`select tk.ton_dau + coalesce((select sum(b.vao-b.ra) from kt_v_bien_dong b where b.tai_khoan_id=tk.id and b.ngay>=tk.ngay_ton_dau),0) s from kt_tai_khoan tk where id=${tk}`))[0].s;
    const truoc = await sd();
    kq('Thanh toán thiếu TK / loại bị chặn', !!(await loi(async () => rpc('kt_luu_chi', { p_phien: KT, p_dong: { ...(await dong()), trang_thai: 'da_tt', tai_khoan_id: null, ngay_tt: HOM } }))));
    await rpc('kt_luu_chi', { p_phien: KT, p_dong: { ...(await dong()), trang_thai: 'da_tt', tai_khoan_id: tk, loai_id: lo, ngay_tt: HOM, kiot: 'khong' } });
    kq('Kế toán thanh toán → Đã thanh toán', (await sql(`select trang_thai from kt_chi where id=${id}`))[0].trang_thai === 'da_tt');
    const sau = await sd(); kq('Số dư tài khoản chi giảm đúng 123.000', truoc - sau === 123000, `${truoc - sau}`);
    const x2 = await rpc('kt_xem_de_nghi', { p_ma: ma }); kq('Người gửi thấy Đã thanh toán', x2.trang_thai === 'da_tt');
  } catch (e) { truot++; console.log('  LỖI GIỮA CHỪNG:', e.message); }
  finally {
    // DỌN SẠCH
    if (id) {
      const ds = await sql(`select name duong_dan from storage.objects where bucket_id = 'kt-chung-tu' and name like 'chi/${id}/%'`);   // cả file tải lên mà bị từ chối ghi
      for (const d of ds) await fetch(`${SB}/storage/v1/object/kt-chung-tu/${d.duong_dan}`, { method: 'DELETE', headers: { apikey: K.SERVICE_ROLE_KEY, Authorization: 'Bearer ' + K.SERVICE_ROLE_KEY } });
      await sql(`delete from kt_chung_tu where bang = 'chi' and dong_id = ${id}; delete from kt_thong_bao where bang = 'chi' and dong_id = ${id};
        delete from kt_nhat_ky where bang = 'kt_chi' and dong_id = ${id}; delete from kt_chi_phieu where chi_id = ${id}; delete from kt_chi where id = ${id}`);
    }
    await sql(`delete from kt_chi where noi_dung like 'THỬ HỆ THỐNG — kiểm luồng đề nghị%'`);
    for (const t of tam) await xoaTam(t);
    const con = await sql(`select (select count(*) from kt_chi where noi_dung like 'THỬ HỆ THỐNG%') chi, (select count(*) from kt_nguoi_dung where ten_dang_nhap like 'tam-dn-%') tk`);
    console.log(`\nKẾT QUẢ: ${dat} đạt · ${truot} trượt · dọn xong (còn ${con[0].chi} phiếu thử, ${con[0].tk} tài khoản tạm)`);
  }
})();
