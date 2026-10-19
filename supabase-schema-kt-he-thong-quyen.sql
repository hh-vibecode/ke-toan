-- Hệ thống & cài đặt = 1 quyền riêng "he_thong" (19/10/2026, anh: "hệ thống và cài đặt tách hẳn ra làm phân quyền riêng,
-- thay cho cái phân quyền tao bảo tách; ngoài admin và giám đốc ra gỡ hết ở tất cả các acc").
-- Có quyền: Supreme / Admin (toàn quyền, '*') / giám đốc (chi_gd) / ai được tick riêng "he_thong". Gộp quyền cũ phan_quyen, danh_muc, nhat_ky.
-- Đổi mật khẩu vẫn mở cho mọi tài khoản (giao diện).
-- Kèm (anh: "khi thay đổi cài đặt thì các TK liên quan tự động out, phải đăng nhập lại"): đổi quyền / vị trí / tên đăng nhập → đăng xuất mọi phiên người đó. — Monsieur Claude
create or replace function public.kt_co_quyen(u kt_nguoi_dung, p_trang text, p_ghi boolean default false)
returns boolean language sql immutable as $$
  select case when p_trang = 'chi_gd' then u.vi_tri = 'supreme' or 'chi_gd' = any(u.quyen)
    when p_trang in ('he_thong','phan_quyen','danh_muc','nhat_ky') then u.vi_tri in ('supreme','admin') or '*' = any(u.quyen)
      or 'chi_gd' = any(u.quyen) or 'he_thong' = any(u.quyen)
    else p_trang is null or u.vi_tri in ('supreme','admin') or '*' = any(u.quyen)
      or (p_trang = any(u.quyen) and (not p_ghi or (p_trang || ':ghi') = any(u.quyen))) end;
$$;

-- Cần giải đáp: chỉ người có quyền Hệ thống
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_ds_cau_hoi'::regproc); n := length(d);
  d := replace(d, 'perform kt_chan(p_phien);', $a$perform kt_chan(p_phien, 'he_thong');$a$);
  if length(d) = n then raise exception 'kt_ds_cau_hoi: khong thay cho'; end if; execute d;

  d := pg_get_functiondef('public.kt_tra_loi_cau_hoi'::regproc); n := length(d);
  d := replace(d, 'u := kt_chan(p_phien);', $a$u := kt_chan(p_phien, 'he_thong');$a$);
  if length(d) = n then raise exception 'kt_tra_loi_cau_hoi: khong thay cho'; end if; execute d;

  -- đếm câu chưa trả lời (chấm đỏ menu): người không có quyền Hệ thống → 0
  d := pg_get_functiondef('public.kt_dem_cau_hoi'::regproc); n := length(d);
  d := replace(d, $a$  perform kt_chan(p_phien);
  return (select count(*) from kt_cau_hoi where tra_loi is null);$a$, $a$  if not kt_co_quyen(kt_chan(p_phien), 'he_thong') then return 0; end if;
  return (select count(*) from kt_cau_hoi where tra_loi is null);$a$);
  if length(d) = n then raise exception 'kt_dem_cau_hoi: khong thay cho'; end if; execute d;

  -- lưu tài khoản: đổi quyền / vị trí / tên đăng nhập → đăng xuất người đó (trừ chính mình đang sửa)
  d := pg_get_functiondef('public.kt_luu_nguoi_dung'::regproc); n := length(d);
  d := replace(d, $a$  else
    update kt_nguoi_dung set ten_dang_nhap = lower(trim(p_dong->>'ten_dang_nhap')),$a$, $a$  else
    if v_id <> u.id and exists (select 1 from kt_nguoi_dung c where c.id = v_id
         and (c.quyen is distinct from v_q or c.vi_tri is distinct from v_vt or c.ten_dang_nhap is distinct from lower(trim(p_dong->>'ten_dang_nhap')))) then
      delete from kt_phien where nguoi_dung_id = v_id;
    end if;
    update kt_nguoi_dung set ten_dang_nhap = lower(trim(p_dong->>'ten_dang_nhap')),$a$);
  if length(d) = n then raise exception 'kt_luu_nguoi_dung: khong thay cho'; end if; execute d;
end $$;

-- Gỡ quyền cũ lẻ (không ai đang giữ lúc chạy) + đăng xuất các tài khoản nhân viên để nhận quyền mới
update kt_nguoi_dung set quyen = array(select q from unnest(quyen) q where q not in ('phan_quyen','phan_quyen:ghi','danh_muc','danh_muc:ghi','nhat_ky','nhat_ky:ghi'))
 where quyen && array['phan_quyen','phan_quyen:ghi','danh_muc','danh_muc:ghi','nhat_ky','nhat_ky:ghi'];
delete from kt_phien where nguoi_dung_id in (select id from kt_nguoi_dung where vi_tri = 'nhan_vien' and not ('chi_gd' = any(quyen)));
