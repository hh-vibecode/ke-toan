// Tài khoản TẠM cho kiểm thử (09/10/2026): tạo bằng SQL với mật khẩu ngẫu nhiên (không lưu đâu cả), đăng nhập lấy phiên,
// xoá sạch khi xong (phiên, thông báo, tài khoản). Để kiểm thử KHÔNG cần mật khẩu thật của anh / kế toán / giám đốc
// (họ đổi mật khẩu thoải mái) và không đụng phiên đăng nhập thật. Monsieur Claude
const { docKhoa } = require('./khoa'); const { sql } = require('./sql');
const K = docKhoa(), SB = 'https://bcrpxfvvjsjpvbksqzls.supabase.co';
// vi_tri: 'supreme' | 'admin' | 'nhan_vien'; quyen: mảng quyền (vd ['*'], ['*','chi_gd'], ['chi_de_nghi'])
async function taoTam(ten, viTri = 'supreme', quyen = ['*'], hoTen) {
  if (!/^tam-[a-z0-9-]{2,30}$/.test(ten)) throw new Error('tên tài khoản tạm phải dạng tam-...');
  const mk = 'Tam-' + require('crypto').randomBytes(9).toString('hex');
  await xoaTam(ten);
  await sql(`insert into kt_nguoi_dung (ten_dang_nhap, ho_ten, vi_tri, quyen, mk_hash) values ('${ten}', $kt$${hoTen || 'THỬ NGHIỆM ' + ten}$kt$, '${viTri}',
    array[${quyen.map(q => `'${q}'`).join(',')}]::text[], extensions.crypt('${mk}', extensions.gen_salt('bf')))`);
  const r = await fetch(`${SB}/rest/v1/rpc/kt_dang_nhap`, { method: 'POST',
    headers: { apikey: K.ANON_KEY, Authorization: 'Bearer ' + K.ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_tk: ten, p_mk: mk, p_nho: false }) });
  const j = await r.json();
  if (!j.phien) throw new Error('đăng nhập tài khoản tạm lỗi: ' + (j.loi || j.message || r.status));
  const id = (await sql(`select id from kt_nguoi_dung where ten_dang_nhap = '${ten}'`))[0].id;
  return { ten, mk, phien: j.phien, id };
}
async function xoaTam(ten) {
  await sql(`delete from kt_nhat_ky where hanh_dong in ('dang_nhap','dang_xuat') and nguoi in (select ho_ten from kt_nguoi_dung where ten_dang_nhap = '${ten}');
    delete from kt_thong_bao where nguoi_dung_id in (select id from kt_nguoi_dung where ten_dang_nhap = '${ten}');
    delete from kt_phien where nguoi_dung_id in (select id from kt_nguoi_dung where ten_dang_nhap = '${ten}');
    delete from kt_nguoi_dung where ten_dang_nhap = '${ten}'`);
}
module.exports = { taoTam, xoaTam };
