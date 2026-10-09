// Kiểm thử DUYỆT CHI 2 LƯỢT + ĐỀ XUẤT CHI TỪ KIOT (08/10/2026). Monsieur Claude
// Đăng nhập kế toán thật (mật khẩu trong kt-keys.local.txt, không in) + 1 tài khoản GIÁM ĐỐC TẠM (quyền chi_gd) tạo trong lúc thử
// (không dùng mật khẩu giám đốc thật — giám đốc có thể đã đổi), chạy các ca, đăng xuất, DỌN SẠCH dữ liệu thử
// (phiếu chi "THU-NGHIEM 2 luot", dòng sổ quỹ Kiot giả id âm, thông báo, nhật ký). Không đụng phiếu thật.
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co';
const H = { apikey: K.ANON_KEY, Authorization: 'Bearer ' + K.ANON_KEY, 'Content-Type': 'application/json' };
const rpc = async (fn, a) => { const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: H, body: JSON.stringify(a) });
  const t = await r.text(); const j = t ? JSON.parse(t) : null; if (!r.ok) throw new Error(j && j.message || t); return j; };
const loi = async f => { try { await f(); return null; } catch (e) { return e.message; } };
let dat = 0, truot = 0; const kq = (ten, ok, them = '') => { ok ? dat++ : truot++; console.log((ok ? '  ĐẠT ' : '  TRƯỢT ') + ten + (them ? ' — ' + them : '')); };
const TK_GD = 'thu-nghiem-gd', MK_GD = 'tn-' + Math.random().toString(36).slice(2) + 'X9', ND = 'THU-NGHIEM 2 luot', HOM = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);
(async () => {
  const phien = [];
  try {
    const KT = (await require('./tk-tam').taoTam('tam-ke-toan', 'admin', ['*'], 'THỬ NGHIỆM Kế toán')).phien; phien.push(KT);   // kế toán tạm (09/10)
    await sql(`delete from kt_nguoi_dung where ten_dang_nhap='${TK_GD}'; insert into kt_nguoi_dung (ten_dang_nhap, ho_ten, vi_tri, quyen, mk_hash) values ('${TK_GD}', 'THỬ NGHIỆM GĐ', 'admin', '{*,chi_gd}', extensions.crypt('${MK_GD}', extensions.gen_salt('bf')))`);
    const GD = (await rpc('kt_dang_nhap', { p_tk: TK_GD, p_mk: MK_GD, p_nho: false })).phien; phien.push(GD);
    const id = Object.fromEntries((await sql(`select ten_dang_nhap, id from kt_nguoi_dung where ten_dang_nhap in ('tam-ke-toan','${TK_GD}')`)).map(x => [x.ten_dang_nhap === 'tam-ke-toan' ? 'kt' : 'gd', x.id]));
    const tk = (await sql(`select id from kt_tai_khoan where hoat_dong order by id limit 1`))[0].id;
    const lc = (await sql(`select id from kt_loai where nhom='chi' and hoat_dong order by id limit 1`))[0].id;
    const tb = async (nd, chi) => (await sql(`select loai from kt_thong_bao where nguoi_dung_id=${nd} and bang='chi' and dong_id=${chi}`)).map(x => x.loai);
    const tt = async c => (await sql(`select trang_thai, kiem_boi, nguoi_duyet from kt_chi where id=${c}`))[0];
    const luu = (P, o) => rpc('kt_luu_chi', { p_phien: P, p_dong: { noi_dung: ND, so_tien: 77777, ...o } });
    // 1. kế toán tạo → chờ kế toán kiểm; không tự báo mình, không báo giám đốc
    const c1 = await luu(KT, {});
    kq('Tạo phiếu → "Chờ kế toán kiểm"', (await tt(c1)).trang_thai === 'cho_duyet');
    kq('Kế toán tự tạo: không báo giám đốc', !(await tb(id.gd, c1)).length);
    // 2. bỏ lượt
    kq('Kế toán KHÔNG nhảy thẳng sang chờ thanh toán', !!await loi(() => luu(KT, { id: c1, trang_thai: 'cho_tt' })));
    // 3. lượt 1
    await luu(KT, { id: c1, trang_thai: 'cho_gd' });
    const s3 = await tt(c1);
    kq('Kế toán xác nhận lượt 1 → "Chờ GĐ xác nhận"', s3.trang_thai === 'cho_gd' && !!s3.kiem_boi, s3.kiem_boi);
    kq('Giám đốc nhận thông báo chờ xác nhận', (await tb(id.gd, c1)).includes('chi_cho_gd'));
    // 4. kế toán không xác nhận lượt 2
    kq('Kế toán KHÔNG xác nhận lượt 2', !!await loi(() => luu(KT, { id: c1, trang_thai: 'cho_tt' })));
    // 5. giám đốc xác nhận
    await luu(GD, { id: c1, trang_thai: 'cho_tt' });
    const s5 = await tt(c1);
    kq('Giám đốc xác nhận → "Chờ thanh toán"', s5.trang_thai === 'cho_tt' && !!s5.nguoi_duyet, s5.nguoi_duyet);
    kq('Kế toán nhận thông báo chờ thanh toán', (await tb(id.kt, c1)).includes('chi_cho_tt'));
    kq('Kế toán KHÔNG đổi số tiền sau khi GĐ xác nhận', !!await loi(() => luu(KT, { id: c1, so_tien: 88888 })));
    // 6. thanh toán
    await luu(KT, { id: c1, trang_thai: 'da_tt', ngay_tt: HOM, tai_khoan_id: tk, loai_id: lc, kiot: 'khong' });
    kq('Kế toán thanh toán → "Đã thanh toán"', (await tt(c1)).trang_thai === 'da_tt');
    // 7. 1 người làm cả 2 lượt
    const c2 = await luu(GD, {});
    await luu(GD, { id: c2, trang_thai: 'cho_gd' });
    const e7 = await loi(() => luu(GD, { id: c2, trang_thai: 'cho_tt' }));
    kq('Người đã kiểm lượt 1 KHÔNG tự xác nhận lượt 2', !!e7 && /lượt 1/.test(e7));
    // 8. giám đốc trả lại kế toán
    await luu(GD, { id: c2, trang_thai: 'cho_duyet' });
    const s8 = await tt(c2);
    kq('Trả lại kế toán → về "Chờ kế toán kiểm", xoá người kiểm', s8.trang_thai === 'cho_duyet' && !s8.kiem_boi);
    // 9. Kiot: đề xuất mới / ghép 4A / nghi trùng / huỷ
    const kiot = (k, tien, nhom, ttk = '0', nd = 'THU-NGHIEM kiot') => `(${k}, 'THUNGHIEM${-k}', now(), 'Đồ thờ Hiền Thủy', false, ${-tien}, 'Transfer', null, null, ${nhom ? `'${nhom}'` : 'null'}, '${nd}', null, '${ttk}', '{"user":"Thử Nghiệm Kiot"}'::jsonb, now(), now())`;
    const c4a = await luu(KT, { trang_thai: 'da_tt', so_tien: 55511, ngay_tt: HOM, tai_khoan_id: tk, loai_id: lc, kiot: 'da_tao' });   // phiếu app đã tạo phiếu Kiot 4A
    const c9 = await luu(KT, { so_tien: 44411 });                                                                                         // phiếu app chưa đánh dấu 4A
    await sql(`insert into kt_kiot_so_quy (id, ma, ngay, chi_nhanh, la_thu, so_tien, phuong_thuc, tai_khoan, doi_tac, nhom, noi_dung, chung_tu_goc, trang_thai, goc, sua_luc_kiot, keo_luc)
      values ${kiot(-901, 33311, 'Chi phí vận chuyển')}, ${kiot(-902, 55511, null)}, ${kiot(-903, 44411, 'Tiền trả NCC')}, ${kiot(-904, 22211, 'Chuyển rút')}`);
    const r9 = (await sql(`select kt_dong_bo_kiot_chi(current_date - 1) r`))[0].r;
    kq('Kiot: 2 đề xuất mới, 1 ghép 4A, bỏ "Chuyển rút"', r9.them === 2 && r9.ghep_4a === 1, JSON.stringify(r9));
    const m = await sql(`select kiot_so_quy_id k, id, trang_thai, nguon, nghi_trung, nguoi_de_nghi from kt_chi where kiot_so_quy_id in (-901,-902,-903) order by kiot_so_quy_id desc`);
    kq('Đề xuất Kiot vào "Chờ kế toán kiểm", người đề nghị = người tạo trên Kiot', m.find(x => x.k == -901)?.trang_thai === 'cho_duyet' && m.find(x => x.k == -901)?.nguoi_de_nghi === 'Thử Nghiệm Kiot');
    kq('Phiếu Kiot trùng phiếu 4A → ghép, không tạo mới', m.find(x => x.k == -902)?.id == c4a);
    kq('Phiếu Kiot trùng số tiền phiếu app khác → gắn "nghi trùng"', (m.find(x => x.k == -903)?.nghi_trung || '').includes('#' + c9), m.find(x => x.k == -903)?.nghi_trung);
    kq('Kế toán nhận 1 thông báo gộp', (await sql(`select count(*)::int n from kt_thong_bao where nguoi_dung_id=${id.kt} and loai='chi_kiot' and tao_luc > now() - interval '2 minutes'`))[0].n === 1);
    kq('Chạy lại không nhân đôi', ((await sql(`select kt_dong_bo_kiot_chi(current_date - 1) r`))[0].r).them === 0);
    await sql(`update kt_kiot_so_quy set trang_thai='1' where id=-901`);
    await sql(`select kt_dong_bo_kiot_chi(current_date - 1)`);
    kq('Phiếu Kiot bị huỷ → phiếu app tự "Từ chối"', (await sql(`select trang_thai from kt_chi where kiot_so_quy_id=-901`))[0].trang_thai === 'tu_choi');
    kq('Báo cáo không cộng phiếu chưa thanh toán', (await sql(`select count(*)::int n from kt_v_bien_dong where kieu='chi' and ra in (33311,44411)`))[0].n === 0);
  } catch (x) { truot++; console.log('  DỪNG: ' + x.message); }
  finally {
    await sql(`delete from kt_thong_bao where bang='chi' and dong_id in (select id from kt_chi where noi_dung like 'THU-NGHIEM%' or kiot_so_quy_id < 0);
      delete from kt_thong_bao where loai='chi_kiot' and noi_dung like 'Thử Nghiệm Kiot%';
      delete from kt_nhat_ky where bang='kt_chi' and dong_id in (select id from kt_chi where noi_dung like 'THU-NGHIEM%' or kiot_so_quy_id < 0);
      delete from kt_chi where noi_dung like 'THU-NGHIEM%' or kiot_so_quy_id < 0 or noi_dung like '%THU-NGHIEM kiot%';
      delete from kt_kiot_so_quy where id < 0`);
    await sql(`delete from kt_thong_bao where nguoi_dung_id in (select id from kt_nguoi_dung where ten_dang_nhap='${TK_GD}'); delete from kt_phien where nguoi_dung_id in (select id from kt_nguoi_dung where ten_dang_nhap='${TK_GD}'); delete from kt_nguoi_dung where ten_dang_nhap='${TK_GD}'`);
    for (const P of phien) await rpc('kt_dang_xuat', { p_phien: P }).catch(() => {});
    await require('./tk-tam').xoaTam('tam-ke-toan');
    const con = (await sql(`select (select count(*) from kt_chi where noi_dung like '%THU-NGHIEM%') chi, (select count(*) from kt_kiot_so_quy where id<0) sq`))[0];
    console.log(`\n${dat} đạt · ${truot} trượt · đã dọn (còn sót: chi ${con.chi}, sổ quỹ giả ${con.sq})`);
  }
})();
