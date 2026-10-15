// KIỂM THỬ NGHIỆP VỤ HẰNG NGÀY CỦA KẾ TOÁN (15/10/2026, anh: "tester hết app, trong vai kế toán, test hết chức năng theo đầu việc hàng ngày").
// Gọi đúng các hàm mà nút trên app gọi, bằng tài khoản TẠM (kế toán / giám đốc / nhân viên chỉ đề nghị). Mọi dữ liệu thử ghi "THỬ HỆ THỐNG";
// xong DỌN SẠCH (xoá hẳn phiếu, nhật ký, chuông, tài khoản tạm) và kiểm số dư các tài khoản quay về như trước. Monsieur Claude
const { docKhoa } = require('./khoa'), { sql } = require('./sql'), { taoTam, xoaTam } = require('./tk-tam');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co', ND = 'THỬ HỆ THỐNG';
const H = { apikey: K.ANON_KEY, Authorization: 'Bearer ' + K.ANON_KEY, 'Content-Type': 'application/json' };
const rpc = async (fn, a) => { const r = await fetch(`${SB}/rest/v1/rpc/${fn}`, { method: 'POST', headers: H, body: JSON.stringify(a) }); const t = await r.text(); const j = t ? JSON.parse(t) : null; if (!r.ok) throw new Error(j && j.message || t); return j; };
const loi = async f => { try { await f(); return null; } catch (e) { return e.message; } };
const KQ = []; let nhom = '';
const kq = (ten, ok, them = '', muc = 'lỗi') => { KQ.push({ nhom, ten, ok, them, muc }); console.log((ok ? '  ĐẠT   ' : muc === 'lưu ý' ? '  LƯU Ý ' : '  TRƯỢT ') + ten + (them ? ' — ' + them : '')); };
const HOM = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);
const T = { thu: [], chi: [], dc: [], tu: [], vay: [], kq: [], tt: [], ns: [], dct: [], dm: [], nd: [] };
const tamDs = [];
const sdTk = async id => +(await sql(`select tk.ton_dau + coalesce((select sum(b.vao-b.ra) from kt_v_bien_dong b where b.tai_khoan_id=tk.id and b.ngay>=tk.ngay_ton_dau),0) s from kt_tai_khoan tk where id=${id}`))[0].s;
const buoc = async (ten, f) => { nhom = ten; console.log('\n■ ' + ten); try { await f(); } catch (e) { kq('(dừng giữa chừng)', false, e.message); } };

(async () => {
  let truoc = null;
  try {
    const KT = (await taoTam('tam-qa-kt', 'admin', ['*'], ND + ' Kế toán')).phien; tamDs.push('tam-qa-kt');
    const GD = (await taoTam('tam-qa-gd', 'admin', ['*', 'chi_gd'], ND + ' Giám đốc')).phien; tamDs.push('tam-qa-gd');
    const NV = (await taoTam('tam-qa-nv', 'nhan_vien', ['chi_de_nghi'], ND + ' Nhân viên')).phien; tamDs.push('tam-qa-nv');
    const tkTM = (await sql(`select id from kt_tai_khoan where hoat_dong and loai='tien_mat' and ngay_ton_dau<='${HOM}' order by id limit 1`))[0].id;
    const tkNH = (await sql(`select id from kt_tai_khoan where hoat_dong and loai='ngan_hang' and ngay_ton_dau<='${HOM}' order by id limit 1`))[0].id;
    const loThu = (await sql(`select id from kt_loai where nhom='thu' and ten='Thu khác'`))[0].id, loChi = (await sql(`select id from kt_loai where nhom='chi' and ten='OPEX - Khác'`))[0].id;
    const cs = (await sql(`select id from kt_don_vi where la_co_so and hoat_dong order by id limit 3`)).map(x => x.id), bp = (await sql(`select id from kt_don_vi where la_bo_phan and hoat_dong order by id limit 1`))[0].id;
    truoc = { tm: await sdTk(tkTM), nh: await sdTk(tkNH) };
    const daLuu = async (bang, id) => (await sql(`select * from kt_${bang} where id=${id}`))[0];
    const chiDong = async id => (await sql(`select to_jsonb(c) - 'tao_luc' - 'sua_luc' - 'duyet_luc' - 'kiem_luc' j from kt_chi c where id=${id}`))[0].j;

    await buoc('1. Phiếu thu', async () => {
      const t0 = await sdTk(tkTM);
      const id = await rpc('kt_luu_thu', { p_phien: KT, p_dong: { ngay: HOM, so_tien: 111000, loai_id: loThu, don_vi_id: cs[0], tai_khoan_id: tkTM, trang_thai: 'da_duyet', noi_dung: ND + ' thu' } }); T.thu.push(id);
      kq('Tạo phiếu thu Đã thu → số dư két +111.000', (await sdTk(tkTM)) - t0 === 111000);
      await rpc('kt_luu_thu', { p_phien: KT, p_dong: { id, ngay: HOM, so_tien: 150000, loai_id: loThu, don_vi_id: cs[0], tai_khoan_id: tkTM, trang_thai: 'da_duyet', noi_dung: ND + ' thu sửa' } });
      kq('Sửa số tiền 150.000 → số dư theo', (await sdTk(tkTM)) - t0 === 150000);
      await rpc('kt_luu_thu', { p_phien: KT, p_dong: { id, ngay: HOM, so_tien: 150000, loai_id: loThu, don_vi_id: cs[0], tai_khoan_id: tkTM, trang_thai: 'cho_duyet', noi_dung: ND + ' thu sửa' } });
      kq('Chuyển Chưa thu → không tính vào số dư', (await sdTk(tkTM)) === t0);
      const e = await loi(() => rpc('kt_luu_thu', { p_phien: KT, p_dong: { ngay: HOM, so_tien: 5000, noi_dung: ND + ' thiếu' } }));
      if (!e) { const x = (await sql(`select id from kt_thu where noi_dung='${ND} thiếu'`))[0]; if (x) T.thu.push(x.id); }
      kq('Máy chủ chặn phiếu thu thiếu tài khoản / loại', !!e, e ? '' : 'chỉ màn hình chặn (dấu *), gọi thẳng vẫn lưu được', 'lưu ý');
      const kiot = (await sql(`select id from kt_thu where nguon='kiot' and not da_xoa order by id desc limit 1`))[0];
      if (kiot) { const e2 = await loi(() => rpc('kt_luu_thu', { p_phien: KT, p_dong: { id: kiot.id, ngay: '2000-01-01', so_tien: 1 } }));
        if (!e2) kq('Khoản thu từ Kiot chỉ xem (máy chủ không cho sửa)', false, 'gọi thẳng sửa được phiếu thu Kiot — đã khôi phục', 'lưu ý'); else kq('Khoản thu từ Kiot không sửa được', true);
        if (!e2) await sql(`update kt_thu t set ngay=x.ngay, so_tien=x.so_tien, noi_dung=x.noi_dung from (select (du_lieu->>'ngay')::date ngay, (du_lieu->>'so_tien')::numeric so_tien, du_lieu->>'noi_dung' noi_dung from kt_nhat_ky where bang='kt_thu' and dong_id=${kiot.id} order by id limit 1) x where t.id=${kiot.id}`); }
      await rpc('kt_xoa', { p_phien: KT, p_bang: 'thu', p_id: id });
      kq('Xoá phiếu thu → ẩn, còn nhật ký', (await daLuu('thu', id)).da_xoa === true);
    });

    await buoc('2. Phiếu chi — đề nghị, duyệt 2 lượt, thanh toán', async () => {
      const id = await rpc('kt_luu_chi', { p_phien: KT, p_dong: { nguoi_de_nghi: ND, bo_phan_id: bp, noi_dung: ND + ' chi', so_tien: 222000, ngay_su_dung: HOM, ngay_de_nghi: HOM,
        thu_huong_ten: 'NGUOI THU', thu_huong_nh: 'Vietcombank', thu_huong_stk: '0123456789', co_hd_do: false, phan_bo: [{ don_vi_id: cs[0], so_tien: 222000 }], chung_tu: [] } }); T.chi.push(id);
      kq('Kế toán tạo đề nghị → Chờ kế toán kiểm', (await daLuu('chi', id)).trang_thai === 'cho_duyet', '#' + id);
      kq('Nhân viên (chỉ đề nghị) không duyệt được', !!(await loi(async () => rpc('kt_luu_chi', { p_phien: NV, p_dong: { ...(await chiDong(id)), trang_thai: 'cho_gd' } }))));
      const nvDs = await rpc('kt_ds', { p_phien: NV, p_bang: 'chi', p_tu: HOM, p_den: HOM });
      kq('Nhân viên không thấy phiếu của người khác', !nvDs.some(x => x.id === id));
      const nvId = await rpc('kt_luu_chi', { p_phien: NV, p_dong: { nguoi_de_nghi: ND + ' NV', bo_phan_id: bp, noi_dung: ND + ' chi NV', so_tien: 33000, ngay_su_dung: HOM, ngay_de_nghi: HOM,
        thu_huong_ten: 'NV', co_hd_do: false, phan_bo: [{ don_vi_id: cs[0], so_tien: 33000 }], chung_tu: [] } }).catch(e => { kq('Nhân viên tạo đề nghị', false, e.message); return null; });
      if (nvId) { T.chi.push(nvId); const ds2 = await rpc('kt_ds', { p_phien: NV, p_bang: 'chi', p_tu: HOM, p_den: HOM }); kq('Nhân viên tạo đề nghị + thấy phiếu của mình', ds2.some(x => x.id === nvId)); }
      await rpc('kt_luu_chi', { p_phien: KT, p_dong: { ...(await chiDong(id)), trang_thai: 'cho_gd' } });
      kq('Kế toán kiểm lượt 1 → Chờ GĐ', (await daLuu('chi', id)).trang_thai === 'cho_gd');
      kq('Kế toán không tự xác nhận lượt 2', !!(await loi(async () => rpc('kt_luu_chi', { p_phien: KT, p_dong: { ...(await chiDong(id)), trang_thai: 'cho_tt' } }))));
      await rpc('kt_luu_chi', { p_phien: GD, p_dong: { ...(await chiDong(id)), trang_thai: 'cho_tt' } });
      kq('Giám đốc xác nhận → Chờ thanh toán', (await daLuu('chi', id)).trang_thai === 'cho_tt');
      const e3 = await loi(async () => rpc('kt_luu_chi', { p_phien: KT, p_dong: { ...(await chiDong(id)), so_tien: 999000 } }));
      kq('GĐ đã xác nhận: kế toán không đổi được số tiền', !!e3 || +(await daLuu('chi', id)).so_tien === 222000, e3 ? '' : 'số tiền bị đổi');
      if (!e3) await sql(`update kt_chi set so_tien=222000 where id=${id}`);
      const n0 = await sdTk(tkNH);
      kq('Thanh toán thiếu tài khoản bị chặn', !!(await loi(async () => rpc('kt_luu_chi', { p_phien: KT, p_dong: { ...(await chiDong(id)), trang_thai: 'da_tt', ngay_tt: HOM, tai_khoan_id: null, loai_id: loChi } }))));
      await rpc('kt_luu_chi', { p_phien: KT, p_dong: { ...(await chiDong(id)), trang_thai: 'da_tt', ngay_tt: HOM, tai_khoan_id: tkNH, loai_id: loChi, kiot: 'khong' } });
      kq('Thanh toán → Đã TT, số dư ngân hàng −222.000', (await daLuu('chi', id)).trang_thai === 'da_tt' && n0 - (await sdTk(tkNH)) === 222000);
      // từ chối
      const id2 = await rpc('kt_luu_chi', { p_phien: KT, p_dong: { nguoi_de_nghi: ND, bo_phan_id: bp, noi_dung: ND + ' chi từ chối', so_tien: 44000, ngay_su_dung: HOM, ngay_de_nghi: HOM,
        thu_huong_ten: 'X', co_hd_do: false, phan_bo: [{ don_vi_id: cs[0], so_tien: 44000 }], chung_tu: [] } }); T.chi.push(id2);
      await rpc('kt_luu_chi', { p_phien: KT, p_dong: { ...(await chiDong(id2)), trang_thai: 'tu_choi' } });
      kq('Từ chối phiếu', (await daLuu('chi', id2)).trang_thai === 'tu_choi');
      // thanh toán luôn
      const n1 = await sdTk(tkNH);
      const id3 = await rpc('kt_luu_chi', { p_phien: KT, p_dong: { nguoi_de_nghi: ND, bo_phan_id: bp, noi_dung: ND + ' chi luôn', so_tien: 55000, ngay_su_dung: HOM, ngay_de_nghi: HOM,
        thu_huong_ten: 'X', co_hd_do: true, phan_bo: [{ don_vi_id: cs[0], so_tien: 55000 }], chung_tu: [], trang_thai: 'da_tt', ngay_tt: HOM, tai_khoan_id: tkNH, loai_id: loChi, kiot: 'khong' } }); T.chi.push(id3);
      kq('"Đã thanh toán luôn" không cần GĐ', (await daLuu('chi', id3)).trang_thai === 'da_tt' && n1 - (await sdTk(tkNH)) === 55000);
      // phân bổ
      kq('Phân bổ sai tổng bị chặn', !!(await loi(() => rpc('kt_luu_phan_bo', { p_phien: KT, p_id: id, p_phan_bo: [{ don_vi_id: cs[0], so_tien: 100000 }], p_phan_bo_thang: null }))));
      await rpc('kt_luu_phan_bo', { p_phien: KT, p_id: id, p_phan_bo: [{ don_vi_id: cs[0], so_tien: 111000 }, { don_vi_id: cs[1], so_tien: 111000 }],
        p_phan_bo_thang: [{ thang: '2026-10', so_tien: 74000 }, { thang: '2026-11', so_tien: 74000 }, { thang: '2026-12', so_tien: 74000 }] });
      const pl = await rpc('kt_bc_pl2', { p_phien: KT, p_tu: '2026-10-01', p_den: '2026-12-31' }).catch(e => ({ loi: e.message }));
      if (pl.loi) kq('P&L đọc được', false, pl.loi); else {
        const thg = [...new Set((pl.cp || []).filter(x => x.loai === loChi && Math.abs(+x.tien - 37000) < 2).map(x => x.thang))];
        kq('Phân bổ 2 cơ sở × 3 tháng hiện đúng trên P&L', thg.length === 3, thg.join(','));
      }
      await rpc('kt_dat_hoan_quy', { p_phien: KT, p_id: id3, p_cs: 'HT' });
      const qn = await rpc('kt_quy_ngoai_ct', { p_phien: KT, p_id: id3 });
      kq('Đánh dấu phiếu hoàn quỹ ngoài + bảng kê Kiot', qn && qn.cs === 'HT' && Array.isArray(qn.ds), (qn ? qn.ds.length : 0) + ' phiếu Kiot trong đợt');
      await rpc('kt_xoa', { p_phien: KT, p_bang: 'chi', p_id: id3 });
      kq('Xoá phiếu chi đã TT → số dư hoàn lại', n1 === await sdTk(tkNH));
    });

    await buoc('3. Điều chuyển tiền', async () => {
      const a0 = await sdTk(tkTM), b0 = await sdTk(tkNH);
      const id = await rpc('kt_luu_dieu_chuyen', { p_phien: KT, p_dong: { ngay: HOM, so_tien: 50000, tk_di_id: tkTM, tk_nhan_id: tkNH, noi_dung: ND + ' điều chuyển', kiot: 'khong' } }); T.dc.push(id);
      kq('Két −50.000, ngân hàng +50.000', a0 - (await sdTk(tkTM)) === 50000 && (await sdTk(tkNH)) - b0 === 50000);
      const e = await loi(() => rpc('kt_luu_dieu_chuyen', { p_phien: KT, p_dong: { ngay: HOM, so_tien: 1000, tk_di_id: tkTM, tk_nhan_id: tkTM, noi_dung: ND + ' cùng TK', kiot: 'khong' } }));
      if (!e) { const x = (await sql(`select id from kt_dieu_chuyen where noi_dung='${ND} cùng TK'`))[0]; if (x) T.dc.push(x.id); }
      kq('Máy chủ chặn điều chuyển cùng 1 tài khoản', !!e, e ? '' : 'chỉ màn hình chặn', 'lưu ý');
      const o = (await sql(`select to_jsonb(d) - 'tao_luc' - 'sua_luc' - 'xac_nhan_luc' j from kt_dieu_chuyen d where id=${id}`))[0].j;
      await rpc('kt_luu_dieu_chuyen', { p_phien: KT, p_dong: { ...o, da_xac_nhan: true } });
      kq('Xác nhận điều chuyển', (await daLuu('dieu_chuyen', id)).da_xac_nhan === true);
    });

    await buoc('4. Kiểm két cuối ngày', async () => {
      const ngay = (await sql(`select (date '${HOM}' - g)::date d from generate_series(1,20) g where not exists (select 1 from kt_kiem_quy where tai_khoan_id=${tkTM} and ngay=date '${HOM}'-g)
         and not exists (select 1 from kt_ton_thuc_te where tai_khoan_id=${tkTM} and ngay=date '${HOM}'-g) limit 1`))[0].d;
      const ss = +(await sql(`select kt_so_du_ngay(${tkTM}, '${ngay}') s`))[0].s;
      const id = await rpc('kt_luu_kiem_quy', { p_phien: KT, p_dong: { tai_khoan_id: tkTM, ngay, so_dem: ss + 1000, menh_gia: { '500000': 1 }, ghi_chu: ND } }); T.kq.push(id); T.tt.push([tkTM, ngay]);
      const ds = await rpc('kt_ds_kiem_quy', { p_phien: KT, p_tu: ngay, p_den: ngay });
      const x = ds.find(r => r.id === id); kq('Kiểm két lưu số đếm, tính lệch +1.000 so với sổ sách', x && +x.so_dem - +x.so_sach === 1000);
      const ds2 = await rpc('kt_doi_soat', { p_phien: KT }); const co = JSON.stringify(ds2).includes(String(ngay).slice(0, 10));
      kq('Đối soát lỗi báo lệch số dư thực tế', co, co ? '' : 'không thấy ngày này trong đối soát', 'lưu ý');
      kq('Không kiểm két ngày tương lai', !!(await loi(() => rpc('kt_luu_kiem_quy', { p_phien: KT, p_dong: { tai_khoan_id: tkTM, ngay: '2030-01-01', so_dem: 1 } }))));
    });

    await buoc('5. Tạm ứng & hoàn ứng', async () => {
      const id = await rpc('kt_luu_tam_ung', { p_phien: KT, p_dong: { ngay: HOM, nguoi_nhan: ND, so_tien: 500000, ly_do: ND, han_hoan: HOM } }); T.tu.push(id);
      await rpc('kt_luu_tam_ung_hoan', { p_phien: KT, p_dong: { tam_ung_id: id, ngay: HOM, hinh_thuc: 'chung_tu', so_tien: 200000 } });
      kq('Hoàn vượt số còn lại bị chặn', !!(await loi(() => rpc('kt_luu_tam_ung_hoan', { p_phien: KT, p_dong: { tam_ung_id: id, ngay: HOM, hinh_thuc: 'tien', so_tien: 400000 } }))));
      kq('Sửa số ứng nhỏ hơn đã hoàn bị chặn', !!(await loi(() => rpc('kt_luu_tam_ung', { p_phien: KT, p_dong: { id, ngay: HOM, nguoi_nhan: ND, so_tien: 100000 } }))));
      const ds = await rpc('kt_ds_tam_ung', { p_phien: KT }); const x = ds.find(r => r.id === id);
      kq('Còn phải hoàn = 300.000', x && +x.so_tien - +x.da_hoan === 300000);
    });

    await buoc('6. Vay & lãi vay', async () => {
      const n0 = await sdTk(tkNH);
      const id = await rpc('kt_luu_vay', { p_phien: KT, p_dong: { ten: ND + ' vay', ben_cho_vay: 'NH thử', so_tien: 0, ngay_vay: HOM, hinh_thuc: 'goc_cuoi_ky', tai_khoan_id: tkNH, chung_tu: [] } }); T.vay.push(id);
      await rpc('kt_luu_vay_nhan', { p_phien: KT, p_dong: { vay_id: id, ngay: HOM, so_tien: 1000000, tai_khoan_id: tkNH } });
      kq('Nhận tiền vay → số dư +1.000.000', (await sdTk(tkNH)) - n0 === 1000000);
      await rpc('kt_luu_vay_tra', { p_phien: KT, p_dong: { vay_id: id, ngay: HOM, goc: 300000, lai: 10000, da_tra: true, tai_khoan_id: tkNH } });
      kq('Trả gốc 300.000 + lãi 10.000 → số dư −310.000', (await sdTk(tkNH)) - n0 === 690000);
      const v = (await rpc('kt_ds_vay', { p_phien: KT })).find(x => x.id === id);
      kq('Dư nợ = 700.000', v && +v.tong_nhan - +v.goc_da_tra === 700000);
      const pl = await rpc('kt_bc_pl2', { p_phien: KT, p_tu: HOM.slice(0, 8) + '01', p_den: HOM });
      kq('Lãi vay vào P&L', (pl.lai_vay || []).some(x => +x.lai >= 10000));
      const lc = await rpc('kt_bc_lctt', { p_phien: KT, p_tu: HOM.slice(0, 8) + '01', p_den: HOM });
      kq('Dòng tiền có nhận / trả vay', (lc.vay || []).some(x => +x.nhan >= 1000000 && +x.tra >= 310000));
    });

    await buoc('7. Ngân sách & báo cáo', async () => {
      await rpc('kt_luu_ngan_sach', { p_phien: KT, p_thang: '2026-12', p_ds: [{ loai_id: loChi, so_tien: 5000000 }] }); T.ns.push('2026-12');
      const d = await rpc('kt_bc_qt', { p_phien: KT, p_loai: 'ngan_sach', p_tu: '2026-12-01', p_den: '2026-12-31' });
      kq('Nhập ngân sách T12 → báo cáo đọc lại đúng', d.ns.some(x => x.loai_id === loChi && +x.so_tien === 5000000));
      for (const l of ['don', 'du_kien', 'ton', 'vay', 'cs']) { const e = await loi(() => rpc('kt_bc_qt', { p_phien: KT, p_loai: l, p_tu: '2026-09-01', p_den: '2026-09-30' })); kq('Báo cáo ' + l + ' chạy', !e, e || ''); }
      // khớp số: doanh thu P&L T9 = báo cáo cơ sở T9
      const pl = await rpc('kt_bc_pl2', { p_phien: KT, p_tu: '2026-09-01', p_den: '2026-09-30' }), cs9 = await rpc('kt_bc_qt', { p_phien: KT, p_loai: 'cs', p_tu: '2026-09-01', p_den: '2026-09-30' });
      const a = (pl.dt || []).reduce((s, x) => s + +x.dt, 0) - (pl.tra || []).reduce((s, x) => s + +x.tra, 0), b = cs9.dt.reduce((s, x) => s + +x.dt, 0) - cs9.tra.reduce((s, x) => s + +x.tra, 0);
      kq('Doanh thu thuần T9: P&L = báo cáo theo cơ sở', Math.abs(a - b) < 2, `${Math.round(a)} / ${Math.round(b)}`);
      const bc = await rpc('kt_bao_cao', { p_phien: KT, p_tu: '2026-09-01', p_den: '2026-09-30' }).catch(e => ({ loi: e.message }));
      const thuV = +(await sql(`select coalesce(sum(vao),0) s from kt_v_bien_dong where kieu='thu' and ngay between '2026-09-01' and '2026-09-30'`))[0].s;
      kq('Tổng quan đọc được, tiền vào T9 khớp sổ', !bc.loi && Math.abs(+bc.tien_vao - thuV) < 2, bc.loi || `${bc.tien_vao} / ${thuV}`, 'lưu ý');
    });

    await buoc('8. Kho sổ thuế', async () => {
      const d0 = await rpc('kt_thue_doi_chieu', { p_phien: KT, p_hkd: 'CT', p_ky: '2026-Q3' });
      if (!d0.ds.length) return kq('Có mã lệch để thử điều chỉnh', false, 'không có', 'lưu ý');
      const m = d0.ds[0]; const id = await rpc('kt_thue_luu_dc', { p_phien: KT, p_dong: { hkd: 'CT', ky: '2026-Q3', ma: m.ma, sl: m.lech, ly_do: 'Kiểm kê thừa / thiếu', ghi_chu: ND } }); T.dct.push(id);
      const d1 = await rpc('kt_thue_doi_chieu', { p_phien: KT, p_hkd: 'CT', p_ky: '2026-Q3' });
      kq('Điều chỉnh đúng số lệch → hết lệch mã đó', d1.so_lech === d0.so_lech - 1, `${d0.so_lech} → ${d1.so_lech}`);
      kq('Nhập file tồn rỗng bị chặn', !!(await loi(() => rpc('kt_nap_ton_thue', { p_phien: KT, p_hkd: 'CT', p_ngay_chot: '2026-09-30', p_ten_file: 'x', p_ds: [] }))));
    });

    await buoc('9. Khoá sổ tháng', async () => {
      const co = (await sql(`select count(*)::int n from kt_khoa_ky where thang='2026-01'`))[0].n;
      if (co) return kq('Tháng 1 đang khoá thật — bỏ qua thử', true, '', 'lưu ý');
      kq('Không khoá được tháng chưa hết', !!(await loi(() => rpc('kt_khoa_thang', { p_phien: KT, p_thang: HOM.slice(0, 7), p_khoa: true }))));
      kq('Nhân viên không khoá được', !!(await loi(() => rpc('kt_khoa_thang', { p_phien: NV, p_thang: '2026-01', p_khoa: true }))));
      await rpc('kt_khoa_thang', { p_phien: KT, p_thang: '2026-01', p_khoa: true, p_ghi_chu: ND });
      try {
        const e = await loi(() => rpc('kt_luu_thu', { p_phien: KT, p_dong: { ngay: '2026-01-15', so_tien: 1000, loai_id: loThu, don_vi_id: cs[0], tai_khoan_id: tkTM, noi_dung: ND + ' tháng khoá' } }));
        if (!e) { const x = (await sql(`select id from kt_thu where noi_dung='${ND} tháng khoá'`))[0]; if (x) T.thu.push(x.id); }
        kq('Tháng đã khoá: chặn thêm phiếu thu', !!e && /khoá sổ/.test(e), e || 'lưu được');
        const ds = await rpc('kt_ds_khoa_ky', { p_phien: KT, p_tu: '2026-01', p_den: '2026-01' });
        kq('Trang khoá kỳ: chụp số lúc khoá', ds[0] && ds[0].khoa && ds[0].luc_khoa && +ds[0].luc_khoa.thu === +ds[0].hien_tai.thu);
      } finally { await rpc('kt_khoa_thang', { p_phien: KT, p_thang: '2026-01', p_khoa: false }); }
      kq('Mở khoá (admin)', (await sql(`select count(*)::int n from kt_khoa_ky where thang='2026-01'`))[0].n === 0);
    });

    await buoc('10. Phân quyền & tài khoản', async () => {
      for (const [fn, a] of [['kt_ds', { p_bang: 'thu', p_tu: HOM, p_den: HOM }], ['kt_ds_vay', {}], ['kt_bc_pl2', { p_tu: HOM, p_den: HOM }], ['kt_ds_tam_ung', {}], ['kt_ds_nguoi_dung', {}]])
        kq('Nhân viên bị chặn: ' + fn, !!(await loi(() => rpc(fn, { p_phien: NV, ...a }))));
      kq('Phiên sai bị chặn', !!(await loi(() => rpc('kt_ds', { p_phien: 'sai', p_bang: 'chi', p_tu: HOM, p_den: HOM }))));
      kq('Đổi mật khẩu: sai mật khẩu cũ bị chặn', !!(await loi(() => rpc('kt_doi_mat_khau', { p_phien: KT, p_mk_cu: 'sai-sai-sai', p_mk_moi: 'Moi-12345678' }))));
      const idU = await rpc('kt_luu_nguoi_dung', { p_phien: KT, p_dong: { ten_dang_nhap: 'tam-qa-moi', ho_ten: ND + ' mới', vi_tri: 'nhan_vien', quyen: ['thu'], mk_moi: 'Thu-12345678', hoat_dong: true } }).catch(e => { kq('Admin tạo tài khoản', false, e.message); return null; });
      if (idU) { tamDs.push('tam-qa-moi'); const dn = await rpc('kt_dang_nhap', { p_tk: 'tam-qa-moi', p_mk: 'Thu-12345678', p_nho: false });
        kq('Admin tạo tài khoản → đăng nhập được, chỉ xem trang được cấp', !!dn.phien && !(await loi(() => rpc('kt_ds', { p_phien: dn.phien, p_bang: 'thu', p_tu: HOM, p_den: HOM }))) && !!(await loi(() => rpc('kt_ds_vay', { p_phien: dn.phien })))); }
      kq('Mật khẩu ngắn bị chặn', !!(await loi(() => rpc('kt_luu_nguoi_dung', { p_phien: KT, p_dong: { ten_dang_nhap: 'tam-qa-x', ho_ten: 'x', mk_moi: '123' } }))));
    });
  } catch (e) { kq('(lỗi chuẩn bị)', false, e.message); }
  finally {
    console.log('\n■ Dọn dữ liệu thử');
    const L = a => a.length ? a.join(',') : '0';
    await sql(`delete from kt_tam_ung_hoan where tam_ung_id in (${L(T.tu)}); delete from kt_tam_ung where id in (${L(T.tu)});
      delete from kt_vay_nhan where vay_id in (${L(T.vay)}); delete from kt_vay_tra where vay_id in (${L(T.vay)}); delete from kt_vay where id in (${L(T.vay)});
      delete from kt_kiem_quy where id in (${L(T.kq)}); ${T.tt.map(([t, d]) => `delete from kt_ton_thuc_te where tai_khoan_id=${t} and ngay='${d}';`).join('')}
      delete from kt_thue_dieu_chinh where id in (${L(T.dct)}); delete from kt_ngan_sach where thang='2026-12' and sua_boi like '${ND}%';
      delete from kt_thong_bao where bang='chi' and dong_id in (${L(T.chi)});
      delete from kt_nhat_ky where (bang='kt_chi' and dong_id in (${L(T.chi)})) or (bang='kt_thu' and dong_id in (${L(T.thu)})) or (bang='kt_dieu_chuyen' and dong_id in (${L(T.dc)}))
        or (bang in ('kt_tam_ung','kt_tam_ung_hoan','kt_vay','kt_vay_nhan','kt_vay_tra','kt_kiem_quy','kt_thue_dieu_chinh','kt_ngan_sach','kt_khoa_ky','kt_nguoi_dung') and nguoi like '${ND}%');
      delete from kt_chi where id in (${L(T.chi)}); delete from kt_thu where id in (${L(T.thu)}); delete from kt_dieu_chuyen where id in (${L(T.dc)});`).catch(e => console.log('  lỗi dọn:', e.message));
    for (const t of tamDs) await xoaTam(t).catch(() => {});
    const con = (await sql(`select (select count(*) from kt_chi where noi_dung like '${ND}%')+(select count(*) from kt_thu where noi_dung like '${ND}%')+(select count(*) from kt_dieu_chuyen where noi_dung like '${ND}%')
      +(select count(*) from kt_tam_ung where nguoi_nhan like '${ND}%')+(select count(*) from kt_vay where ten like '${ND}%')+(select count(*) from kt_nguoi_dung where ten_dang_nhap like 'tam-qa%') n`))[0].n;
    if (truoc) { const tkTM = (await sql(`select id from kt_tai_khoan where hoat_dong and loai='tien_mat' and ngay_ton_dau<='${HOM}' order by id limit 1`))[0].id, tkNH = (await sql(`select id from kt_tai_khoan where hoat_dong and loai='ngan_hang' and ngay_ton_dau<='${HOM}' order by id limit 1`))[0].id;
      console.log(`  số dư sau dọn: két ${(await sdTk(tkTM)) === truoc.tm ? 'như cũ' : 'LỆCH'}, ngân hàng ${(await sdTk(tkNH)) === truoc.nh ? 'như cũ' : 'LỆCH'} · còn ${con} bản ghi thử`); }
    const d = KQ.filter(x => x.ok).length, t = KQ.filter(x => !x.ok && x.muc !== 'lưu ý').length, l = KQ.filter(x => !x.ok && x.muc === 'lưu ý').length;
    console.log(`\nKẾT QUẢ: ${d} đạt · ${t} trượt · ${l} lưu ý`);
  }
})();
