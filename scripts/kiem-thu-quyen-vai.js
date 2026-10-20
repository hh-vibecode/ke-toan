// Kiểm thử QUYỀN THEO VAI trên MÁY CHỦ (20/10/2026, anh: "rà lại 1 lượt quyền theo yêu cầu, test xem các quyền đã chạy được thật chưa").
// Tạo TK tạm theo vai (quyền chép từ TK thật: thủ quỹ, admin kế toán; + Admin, Giám đốc, nhân viên chỉ đề nghị, Supreme) → chạy mọi thao tác
// trong MỘT khối SQL, cuối khối raise lỗi để HUỶ TOÀN BỘ (phiếu, thông báo, nhật ký thử không còn gì) → xoá TK tạm.
// Chạy: node scripts/kiem-thu-quyen-vai.js   (máy anh: ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" scripts/kiem-thu-quyen-vai.js)
// Không in khoá / mật khẩu / phiên. Monsieur Claude
const { sql } = require('./sql');
const { taoTam, xoaTam } = require('./tk-tam');
const { docKhoa } = require('./khoa');

const lit = s => "'" + String(s).replace(/'/g, "''") + "'";
(async () => {
  const that = Object.fromEntries((await sql(`select ten_dang_nhap, quyen from kt_nguoi_dung where ten_dang_nhap in ('thuquy','admin.ketoan')`)).map(x => [x.ten_dang_nhap, x.quyen]));
  if (!that.thuquy || !that['admin.ketoan']) throw new Error('không thấy TK thuquy / admin.ketoan để chép quyền');
  const id = (await sql(`select (select id from kt_loai where nhom='chi' and hoat_dong order by id limit 1) lc, (select id from kt_loai where nhom='thu' and hoat_dong order by id limit 1) lt,
      (select min(id) from kt_don_vi where la_co_so and hoat_dong) dv, (select min(id) from kt_don_vi where la_bo_phan and hoat_dong) bp,
      (select id from kt_tai_khoan where hoat_dong and loai='tien_mat' and thu_quy_chi limit 1) ket,
      (select id from kt_tai_khoan where hoat_dong and loai='tien_mat' and not coalesce(thu_quy_chi,false) limit 1) quay,
      (select id from kt_tai_khoan where hoat_dong and loai='ngan_hang' and thu_quy_chi order by id limit 1) nh1,
      (select id from kt_tai_khoan where hoat_dong and loai='ngan_hang' and thu_quy_chi order by id offset 1 limit 1) nh2,
      (select id from kt_tai_khoan where hoat_dong and loai='ngan_hang' and not coalesce(thu_quy_chi,false) order by id limit 1) cn`))[0];
  const VAI = [
    ['tq', 'nhan_vien', that.thuquy, 'thủ quỹ (quyền như TK thuquy)'],
    ['tq2', 'nhan_vien', [...that.thuquy, 'dong_tien'], 'thủ quỹ + tick Sổ quỹ'],
    ['akt', 'nhan_vien', that['admin.ketoan'], 'admin kế toán (quyền như TK admin.ketoan)'],
    ['adm', 'admin', ['*'], 'vị trí Admin toàn quyền (như TK ketoan)'],
    ['gd', 'admin', ['chi_gd'], 'giám đốc (như TK giamdoc)'],
    ['nv', 'nhan_vien', ['chi_de_nghi'], 'nhân viên chỉ tạo đề nghị'],
    ['sup', 'supreme', [], 'Supreme'],
  ];
  const tk = {};
  try {
    for (const [k, vt, q] of VAI) tk[k] = await taoTam('tam-q' + k, vt, q);
    const P = k => lit(tk[k].phien), hom = new Date(Date.now() + 7 * 36e5).toISOString().slice(0, 10);
    const chiMoi = (ten, tien, tkId) => `jsonb_build_object('nguoi_de_nghi','THỬ HỆ THỐNG','bo_phan_id',${id.bp || 'null'},'noi_dung','THỬ HỆ THỐNG ${ten}','so_tien',${tien},
      'ngay_su_dung','${hom}','ngay_de_nghi','${hom}','thu_huong_ten','THỬ HỆ THỐNG','thu_huong_nh','Vietcombank','thu_huong_stk','0011001234567',
      'phan_bo',jsonb_build_array(jsonb_build_object('don_vi_id',${id.dv},'so_tien',${tien})),'co_hd_do',false,'loai_id',${id.lc}${tkId ? `,'tai_khoan_id',${tkId}` : ''})`;
    const dong = (bang, v, them) => `((select to_jsonb(x) from ${bang} x where id = ${v}) || ${them})`;
    const C = [];   // [mã, vai, mô tả, câu lệnh, mong 'OK'|'CHAN', kiểm thêm sau khi OK (biểu thức boolean, tuỳ chọn)]
    const ca = (ma, vai, mo, cau, mong, kiem) => C.push({ ma, vai, mo, cau, mong, kiem });
    // ── A. Tiền vào KÉT: chỉ thủ quỹ xác nhận (anh 20/10: đóng quyền admin)
    ca('A1', 'adm', 'Admin tạo điều chuyển quỹ cửa hàng → két', `v_dc := kt_luu_dieu_chuyen(${P('adm')}, jsonb_build_object('ngay','${hom}','so_tien',123000,'tk_di_id',${id.quay},'tk_nhan_id',${id.ket},'noi_dung','THỬ HỆ THỐNG','kiot','khong'))`, 'OK');
    ca('A2', 'adm', 'Admin bấm xác nhận điều chuyển vào két', `perform kt_luu_dieu_chuyen(${P('adm')}, ${dong('kt_dieu_chuyen', 'v_dc', `jsonb_build_object('da_xac_nhan',true)`)})`, 'CHAN');
    ca('A3', 'gd', 'Giám đốc bấm xác nhận điều chuyển vào két', `perform kt_luu_dieu_chuyen(${P('gd')}, ${dong('kt_dieu_chuyen', 'v_dc', `jsonb_build_object('da_xac_nhan',true)`)})`, 'CHAN');
    ca('A4', 'akt', 'Admin kế toán bấm xác nhận điều chuyển vào két', `perform kt_luu_dieu_chuyen(${P('akt')}, ${dong('kt_dieu_chuyen', 'v_dc', `jsonb_build_object('da_xac_nhan',true)`)})`, 'CHAN');
    ca('A5', 'adm', 'Admin bấm "Đã nhận tiền" điều chuyển vào két', `perform kt_tq_nhan(${P('adm')}, 'dieu_chuyen', v_dc, false)`, 'CHAN');
    ca('A6', 'tq', 'Thủ quỹ bấm "Đã nhận tiền" → điều chuyển thành đã xác nhận', `perform kt_tq_nhan(${P('tq')}, 'dieu_chuyen', v_dc, false)`, 'OK', `(select da_xac_nhan and tq_nhan_luc is not null from kt_dieu_chuyen where id = v_dc)`);
    ca('A7', 'adm', 'Admin tạo điều chuyển giữa 2 TK ngân hàng', `v_dc2 := kt_luu_dieu_chuyen(${P('adm')}, jsonb_build_object('ngay','${hom}','so_tien',50000,'tk_di_id',${id.nh1},'tk_nhan_id',${id.nh2},'noi_dung','THỬ HỆ THỐNG','kiot','khong'))`, 'OK');
    ca('A8', 'akt', 'Admin kế toán xác nhận điều chuyển ngân hàng (không vào két)', `perform kt_luu_dieu_chuyen(${P('akt')}, ${dong('kt_dieu_chuyen', 'v_dc2', `jsonb_build_object('da_xac_nhan',true)`)})`, 'OK');
    ca('A9', 'tq', 'Thủ quỹ tạo phiếu thu vào két', `v_thu := kt_luu_thu(${P('tq')}, jsonb_build_object('ngay','${hom}','so_tien',77000,'loai_id',${id.lt},'don_vi_id',${id.dv},'tai_khoan_id',${id.ket},'noi_dung','THỬ HỆ THỐNG','trang_thai','da_duyet'))`, 'OK');
    ca('A10', 'adm', 'Admin bấm "Đã nhận tiền" phiếu thu vào két', `perform kt_tq_nhan(${P('adm')}, 'thu', v_thu, false)`, 'CHAN');
    ca('A11', 'tq', 'Thủ quỹ bấm "Đã nhận tiền" phiếu thu vào két', `perform kt_tq_nhan(${P('tq')}, 'thu', v_thu, false)`, 'OK');
    // ── B. Luồng phiếu chi: đề nghị → xác nhận (kế toán / GĐ) → thủ quỹ chi / lập lệnh → duyệt lệnh
    ca('B1', 'nv', 'Nhân viên tạo đề nghị chi', `v_c1 := kt_luu_chi(${P('nv')}, ${chiMoi('B', 300000)})`, 'OK', `(select trang_thai = 'cho_duyet' from kt_chi where id = v_c1)`);
    ca('B2', 'nv', 'Nhân viên tự xác nhận phiếu của mình', `perform kt_luu_chi(${P('nv')}, ${dong('kt_chi', 'v_c1', `jsonb_build_object('trang_thai','cho_tt','tai_khoan_id',${id.nh1})`)})`, 'CHAN');
    ca('B3', 'akt', 'Admin kế toán (đã bỏ quyền xác nhận) xác nhận phiếu', `perform kt_luu_chi(${P('akt')}, ${dong('kt_chi', 'v_c1', `jsonb_build_object('trang_thai','cho_tt','tai_khoan_id',${id.nh1})`)})`, 'CHAN');
    ca('B4', 'adm', 'Admin (kế toán) xác nhận + chọn TK ngân hàng công ty', `perform kt_luu_chi(${P('adm')}, ${dong('kt_chi', 'v_c1', `jsonb_build_object('trang_thai','cho_tt','tai_khoan_id',${id.nh1})`)})`, 'OK');
    ca('B5', 'tq', 'Thủ quỹ bấm "Đã chi tiền" trên TK ngân hàng (phải lập lệnh)', `insert into kt_chung_tu (bang, dong_id, duong_dan, ten_file) values ('chi', v_c1, 'thu/unc-b5-' || v_c1, 'UNC-thu.png');
       perform kt_luu_chi(${P('tq')}, ${dong('kt_chi', 'v_c1', `jsonb_build_object('trang_thai','da_tt','ngay_tt','${hom}')`)})`, 'CHAN');
    ca('B6', 'akt', 'Admin kế toán bấm "Đã lập lệnh" (không phải thủ quỹ)', `perform kt_lap_lenh(${P('akt')}, v_c1, false)`, 'CHAN');
    ca('B7', 'tq', 'Thủ quỹ bấm "Đã lập lệnh" (có ảnh UNC)', `insert into kt_chung_tu (bang, dong_id, duong_dan, ten_file) values ('chi', v_c1, 'thu/unc-b7-' || v_c1, 'UNC-thu.png');
       perform kt_lap_lenh(${P('tq')}, v_c1, false)`, 'OK', `(select lap_lenh_luc is not null and trang_thai = 'cho_tt' from kt_chi where id = v_c1)`);
    ca('B8', 'tq', 'Thủ quỹ tự bấm "Đã duyệt lệnh"', `perform kt_luu_chi(${P('tq')}, ${dong('kt_chi', 'v_c1', `jsonb_build_object('trang_thai','da_tt','ngay_tt','${hom}')`)})`, 'CHAN');
    ca('B9', 'adm', 'Kế toán bấm "Đã duyệt lệnh" → Đã thanh toán', `perform kt_luu_chi(${P('adm')}, ${dong('kt_chi', 'v_c1', `jsonb_build_object('trang_thai','da_tt','ngay_tt','${hom}','loai_id',${id.lc})`)})`, 'OK', `(select trang_thai = 'da_tt' from kt_chi where id = v_c1)`);
    ca('B10', 'adm', 'Phiếu chi két: Admin xác nhận + chọn KÉT', `v_c2 := kt_luu_chi(${P('nv')}, ${chiMoi('B10', 200000)});
       perform kt_luu_chi(${P('adm')}, ${dong('kt_chi', 'v_c2', `jsonb_build_object('trang_thai','cho_tt','tai_khoan_id',${id.ket})`)})`, 'OK');
    ca('B10b', 'adm', 'Up ảnh giao dịch cho phiếu két', `insert into kt_chung_tu (bang, dong_id, duong_dan, ten_file) values ('chi', v_c2, 'thu/unc-' || v_c2, 'UNC-thu.png')`, 'OK');
    ca('B11', 'akt', 'Admin kế toán bấm "Đã chi tiền" từ két', `perform kt_luu_chi(${P('akt')}, ${dong('kt_chi', 'v_c2', `jsonb_build_object('trang_thai','da_tt','ngay_tt','${hom}','nguoi_nhan_tien','THỬ')`)})`, 'CHAN');
    ca('B12', 'tq', 'Thủ quỹ bấm "Đã chi tiền" từ két (có ảnh + người nhận)', `perform kt_luu_chi(${P('tq')}, ${dong('kt_chi', 'v_c2', `jsonb_build_object('trang_thai','da_tt','ngay_tt','${hom}','nguoi_nhan_tien','THỬ','loai_id',${id.lc})`)})`, 'OK');
    ca('B13', 'gd', 'Phiếu TK cá nhân: GĐ xác nhận + chọn TK cá nhân', `v_c3 := kt_luu_chi(${P('nv')}, ${chiMoi('B13', 150000)});
       perform kt_luu_chi(${P('gd')}, ${dong('kt_chi', 'v_c3', `jsonb_build_object('trang_thai','cho_tt','tai_khoan_id',${id.cn})`)})`, 'OK');
    ca('B13b', 'gd', 'Up ảnh giao dịch cho phiếu TK cá nhân', `insert into kt_chung_tu (bang, dong_id, duong_dan, ten_file) values ('chi', v_c3, 'thu/unc-' || v_c3, 'UNC-thu.png')`, 'OK');
    ca('B14', 'tq', 'Thủ quỹ chi từ TK cá nhân', `perform kt_luu_chi(${P('tq')}, ${dong('kt_chi', 'v_c3', `jsonb_build_object('trang_thai','da_tt','ngay_tt','${hom}')`)})`, 'CHAN');
    ca('B15', 'gd', 'Giám đốc chi từ TK cá nhân', `perform kt_luu_chi(${P('gd')}, ${dong('kt_chi', 'v_c3', `jsonb_build_object('trang_thai','da_tt','ngay_tt','${hom}','loai_id',${id.lc})`)})`, 'OK');
    // ── C. Tự chi không cần duyệt (chi_thang)
    ca('C1', 'akt', 'Admin kế toán (có "tự chi không cần duyệt") tạo phiếu Đã thanh toán luôn', `v_c4 := kt_luu_chi(${P('akt')}, ${chiMoi('C1', 10000, id.nh1)} || jsonb_build_object('trang_thai','da_tt','ngay_tt','${hom}'))`, 'OK', `(select trang_thai = 'da_tt' from kt_chi where id = v_c4)`);
    ca('C2', 'tq', 'Thủ quỹ (không có quyền đó) tạo phiếu Đã thanh toán luôn', `perform kt_luu_chi(${P('tq')}, ${chiMoi('C2', 10000, id.nh1)} || jsonb_build_object('trang_thai','da_tt','ngay_tt','${hom}'))`, 'CHAN');
    // ── D. Đổi người nhận sau khi GĐ xác nhận · GĐ lùi bước
    ca('D1', 'akt', 'Đổi STK sau khi đã xác nhận → phiếu tự về Chờ GĐ xác nhận lại', `v_c5 := kt_luu_chi(${P('nv')}, ${chiMoi('D1', 90000)});
       perform kt_luu_chi(${P('gd')}, ${dong('kt_chi', 'v_c5', `jsonb_build_object('trang_thai','cho_tt','tai_khoan_id',${id.nh1})`)});
       perform kt_luu_chi(${P('akt')}, ${dong('kt_chi', 'v_c5', `jsonb_build_object('thu_huong_stk','0011009999999')`)})`, 'OK', `(select trang_thai = 'cho_gd' from kt_chi where id = v_c5)`);
    ca('D2a', 'adm', 'Phiếu mới được Admin xác nhận (chuẩn bị lùi bước)', `v_c6 := kt_luu_chi(${P('nv')}, ${chiMoi('D2', 80000)});
       perform kt_luu_chi(${P('adm')}, ${dong('kt_chi', 'v_c6', `jsonb_build_object('trang_thai','cho_tt','tai_khoan_id',${id.nh1})`)})`, 'OK');
    ca('D2', 'adm', 'Admin (không phải GĐ) lùi phiếu Chờ chi tiền về Chờ xác nhận', `perform kt_luu_chi(${P('adm')}, ${dong('kt_chi', 'v_c6', `jsonb_build_object('trang_thai','cho_duyet')`)})`, 'CHAN');
    ca('D3', 'gd', 'Giám đốc lùi phiếu Chờ chi tiền về Chờ xác nhận', `perform kt_luu_chi(${P('gd')}, ${dong('kt_chi', 'v_c6', `jsonb_build_object('trang_thai','cho_duyet')`)})`, 'OK');
    // ── E. Quyền xem theo trang
    ca('E1', 'nv', 'Nhân viên chỉ thấy phiếu chi của mình', `v_n := (select count(*) from jsonb_array_elements(kt_ds(${P('nv')}, 'chi', '2026-01-01', '${hom}')) e where e->>'tao_boi' is distinct from 'THỬ NGHIỆM tam-qnv')`, 'OK', `v_n = 0`);
    ca('E2', 'nv', 'Nhân viên xem Tổng quan', `perform kt_bao_cao(${P('nv')}, '${hom}', '${hom}', null)`, 'CHAN');
    ca('E3', 'tq', 'Thủ quỹ (chưa tick Sổ quỹ) xem Sổ quỹ', `perform kt_so_du_tk(${P('tq')}, '${hom}', '${hom}')`, 'CHAN');
    ca('E4', 'tq2', 'Thủ quỹ (đã tick Sổ quỹ) xem Sổ quỹ', `perform kt_so_du_tk(${P('tq2')}, '${hom}', '${hom}')`, 'OK');
    ca('E5', 'tq', 'Thủ quỹ xem danh sách Thu', `perform kt_ds(${P('tq')}, 'thu', '${hom}', '${hom}')`, 'OK');
    ca('E6', 'tq', 'Thủ quỹ xem danh sách Điều chuyển', `perform kt_ds(${P('tq')}, 'dieu_chuyen', '${hom}', '${hom}')`, 'OK');
    ca('E7', 'tq', 'Thủ quỹ xem công nợ NCC', `perform kt_cong_no_dt(${P('tq')}, 'ncc')`, 'OK');
    ca('E8', 'tq', 'Thủ quỹ xem công nợ khách hàng', `perform kt_cong_no_dt(${P('tq')}, 'kh')`, 'CHAN');
    ca('E9', 'akt', 'Admin kế toán xem Sổ quỹ', `perform kt_so_du_tk(${P('akt')}, '${hom}', '${hom}')`, 'OK');
    ca('E10', 'akt', 'Admin kế toán xem P&L', `perform kt_bc_pl2(${P('akt')}, '${hom}', '${hom}')`, 'CHAN');
    ca('E11', 'akt', 'Admin kế toán mở Phân quyền (danh sách tài khoản)', `perform kt_ds_nguoi_dung(${P('akt')})`, 'CHAN');
    ca('E12', 'gd', 'Giám đốc mở Phân quyền', `perform kt_ds_nguoi_dung(${P('gd')})`, 'OK');
    ca('E13', 'tq', 'Thủ quỹ mở Phân quyền', `perform kt_ds_nguoi_dung(${P('tq')})`, 'CHAN');

    const body = C.map(c => `
  begin
    ${c.cau};
    r := r || jsonb_build_array(jsonb_build_object('ma', ${lit(c.ma)}, 'kq', 'OK'${c.kiem ? `, 'dung', coalesce(${c.kiem}, false)` : ''}));
  exception when others then
    r := r || jsonb_build_array(jsonb_build_object('ma', ${lit(c.ma)}, 'kq', 'CHAN', 'loi', left(sqlerrm, 160)));
  end;`).join('');
    const khoi = `do $kt$
declare r jsonb := '[]'; v_dc bigint; v_dc2 bigint; v_thu bigint; v_c1 bigint; v_c2 bigint; v_c3 bigint; v_c4 bigint; v_c5 bigint; v_c6 bigint; v_n bigint;
begin${body}
  raise exception 'KQTHU%', r::text;   -- HUỶ toàn bộ: không phiếu / thông báo / nhật ký thử nào được ghi
end $kt$;`;
    // gọi thẳng Management API (sql.js cắt lỗi 1.500 ký tự) — kết quả nằm trong câu lỗi cuối khối
    const r0 = await fetch('https://api.supabase.com/v1/projects/bcrpxfvvjsjpvbksqzls/database/query', { method: 'POST',
      headers: { Authorization: 'Bearer ' + docKhoa().SUPABASE_ACCESS_TOKEN, 'Content-Type': 'application/json' }, body: JSON.stringify({ query: khoi }) });
    const t0 = await r0.text(); let msg = t0; try { msg = JSON.parse(t0).message || t0; } catch (_) {}
    const m0 = String(msg).match(/KQTHU(\[.*\])/s); if (!m0) throw new Error('khối thử lỗi: ' + String(msg).slice(0, 800));
    const kq = JSON.parse(m0[1]);
    if (!kq) throw new Error('khối thử không trả kết quả');
    const vai = Object.fromEntries(VAI.map(v => [v[0], v[3]]));
    let dat = 0, truot = 0;
    for (const c of C) {
      const k = kq.find(x => x.ma === c.ma) || { kq: '?' };
      const ok = k.kq === c.mong && (k.dung === undefined || k.dung === true);
      ok ? dat++ : truot++;
      console.log(`${ok ? 'ĐẠT ' : 'TRƯỢT'} ${c.ma.padEnd(4)} [${vai[c.vai]}] ${c.mo} → ${k.kq === 'OK' ? 'cho phép' : 'bị chặn'}${k.dung === false ? ' (nhưng kết quả sai)' : ''}${k.loi ? ' · ' + k.loi : ''}`);
    }
    console.log(`\n${dat} đạt / ${truot} trượt`);
    const sot = await sql(`select (select count(*) from kt_chi where noi_dung like 'THỬ HỆ THỐNG%' and tao_luc > now() - interval '10 minutes') chi,
      (select count(*) from kt_dieu_chuyen where noi_dung = 'THỬ HỆ THỐNG' and tao_luc > now() - interval '10 minutes') dc,
      (select count(*) from kt_thu where noi_dung = 'THỬ HỆ THỐNG' and tao_luc > now() - interval '10 minutes') thu`);
    console.log('Dữ liệu thử còn sót (phải = 0):', JSON.stringify(sot[0]));
  } finally {
    for (const k of Object.keys(tk)) await xoaTam(tk[k].ten);
    console.log('Đã xoá TK tạm:', (await sql(`select count(*) n from kt_nguoi_dung where ten_dang_nhap like 'tam-q%'`))[0].n === 0 ? 'xong' : 'CÒN SÓT');
  }
})().catch(e => { console.error('DỪNG:', e.message.slice(0, 500)); process.exit(1); });
