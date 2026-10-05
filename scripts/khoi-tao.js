// Khởi tạo app kế toán (chạy 1 lần, chạy lại không sao — chỉ THÊM cái chưa có):
//   1) 3 tài khoản đầu (anh Hải = supreme, giám đốc + kế toán = admin) — mật khẩu ngẫu nhiên GHI VÀO kt-keys.local.txt,
//      KHÔNG in ra màn hình. Đăng nhập xong mỗi người tự đổi mật khẩu.
//   2) Danh mục từ kt-danh-muc.local.json (gitignore — có số tài khoản thật).
// Monsieur Claude
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const { sql } = require('./sql');
const q = v => v == null ? 'null' : "'" + String(v).replace(/'/g, "''") + "'";
const arr = a => 'array[' + (a || []).map(q).join(',') + ']::text[]';

(async () => {
  const TK = [['hai', 'Hoàng Hải', 'supreme'], ['giamdoc', 'Giám đốc', 'admin'], ['ketoan', 'Kế toán', 'admin']];
  const co = (await sql('select ten_dang_nhap from kt_nguoi_dung')).map(r => r.ten_dang_nhap);
  const moi = [];
  for (const [tdn, ten, vt] of TK) {
    if (co.includes(tdn)) continue;
    const mk = crypto.randomBytes(9).toString('base64').replace(/[+/=]/g, '').slice(0, 12);
    await sql(`insert into kt_nguoi_dung (ten_dang_nhap, ho_ten, vi_tri, quyen, mk_hash)
      values (${q(tdn)}, ${q(ten)}, ${q(vt)}, '{*}', extensions.crypt(${q(mk)}, extensions.gen_salt('bf')))`);
    moi.push(`KT_MK_${tdn.toUpperCase()} (tài khoản đăng nhập app kế toán: ${tdn}): ${mk}`);
  }
  if (moi.length) {
    fs.appendFileSync(path.join(__dirname, '..', 'kt-keys.local.txt'),
      `\n\n---- APP KẾ TOÁN — mật khẩu ban đầu (${new Date().toLocaleString('vi-VN')}). Đăng nhập xong tự đổi trong Cài đặt ----\n` + moi.join('\n') + '\n');
  }
  console.log('Tài khoản mới tạo:', moi.length ? moi.map(x => x.split(' ')[0]).join(', ') : 'không (đã có đủ)', '— mật khẩu ở kt-keys.local.txt');

  const dm = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'kt-danh-muc.local.json'), 'utf8'));
  const tk = dm.tai_khoan.map((t, i) => `(${q(t.ten)}, ${q(t.loai)}, ${arr(t.ten_cu)}, ${i * 10})`).join(',\n');
  const dv = dm.don_vi.map((d, i) => `(${q(d.ten)}, ${!!d.la_co_so}, ${!!d.la_bo_phan}, ${arr(d.ten_cu)}, ${i * 10})`).join(',\n');
  const lo = dm.loai.map((l, i) => `(${q(l.nhom)}, ${q(l.ten)}, ${q(l.nhom_bc)}, ${q(l.cach_chia || 'rieng')}, ${i * 10})`).join(',\n');
  const r = await sql(`
    with a as (insert into kt_tai_khoan (ten, loai, ten_cu, thu_tu) values ${tk} on conflict (ten) do nothing returning 1),
         b as (insert into kt_don_vi (ten, la_co_so, la_bo_phan, ten_cu, thu_tu) values ${dv} on conflict (ten) do nothing returning 1),
         c as (insert into kt_loai (nhom, ten, nhom_bc, cach_chia, thu_tu) values ${lo} on conflict (nhom, ten) do nothing returning 1)
    select (select count(*) from a) tai_khoan, (select count(*) from b) don_vi, (select count(*) from c) loai`);
  console.log('Danh mục thêm mới:', JSON.stringify(r[0]));
})().catch(e => { console.error(e.message); process.exit(1); });
