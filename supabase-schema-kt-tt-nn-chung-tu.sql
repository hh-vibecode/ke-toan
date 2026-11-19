-- CHỨNG TỪ CHO THANH TOÁN TRUNG GIAN — 19/11/2026. Monsieur Claude
-- Anh: "các phiếu thanh toán trung gian thêm cho t ô ảnh up chứng từ nữa" → kt_chung_tu nhận bang 'tt_nn' (quyền theo trang Nhà cung cấp 'ncc').
alter table kt_chung_tu drop constraint if exists kt_chung_tu_bang_check;
alter table kt_chung_tu add constraint kt_chung_tu_bang_check check (bang = any (array['thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung','bao_loi','ho_so','ncc','lo_nk','po','de_xuat','bao_gia','sao_ke','tt_nn']));
CREATE OR REPLACE FUNCTION public.kt_quyen_chung_tu(p_phien text, p_bang text, p_ghi boolean, p_ids bigint[])
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  if p_bang not in ('bao_loi','thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung','ho_so','ncc','lo_nk','po','de_xuat','bao_gia','sao_ke','tt_nn') then raise exception 'Bảng chứng từ không hợp lệ'; end if;
  u := kt_chan_dong(p_phien, p_bang, p_ids, p_ghi);
  return u.ho_ten;
end $function$
;
CREATE OR REPLACE FUNCTION public.kt_chan_dong(p_phien text, p_bang text, p_ids bigint[], p_ghi boolean)
 RETURNS kt_nguoi_dung
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  -- 24/10: ảnh báo lỗi — người báo (báo lỗi của chính mình) hoặc quyền trang Log
  if p_bang = 'bao_loi' then
    if kt_co_quyen(u, 'nhat_ky', false) then return u; end if;
    if cardinality(p_ids) > 0 and not exists (select 1 from unnest(p_ids) i where not exists (select 1 from kt_bao_loi b where b.id = i and b.nguoi = u.ho_ten)) then return u; end if;
    raise exception 'Tài khoản chưa được cấp quyền xem báo lỗi' using errcode = '42501';
  end if;
  -- 29/10: chứng từ hồ sơ NCC theo quyền trang Nhà cung cấp (người xác nhận phiếu chi cũng tải được ở bước 4)
  if p_bang = 'ho_so' then
    if kt_co_quyen(u, 'ncc', p_ghi) or kt_co_quyen(u, 'chi_duyet') then return u; end if;
    raise exception 'Tài khoản chưa được cấp quyền % hồ sơ NCC', case when p_ghi then 'sửa' else 'xem' end using errcode = '42501';
  end if;
  -- 14/10/2026: ảnh kiểm két theo quyền trang Sổ quỹ (dong_tien); 30/10: chứng từ hồ sơ nhập khẩu theo quyền trang Nhà cung cấp
  if kt_co_quyen(u, case p_bang when 'kiem_quy' then 'kiem_ket' when 'lo_nk' then 'ncc' when 'po' then 'ncc' when 'de_xuat' then 'ncc' when 'bao_gia' then 'ncc' when 'tt_nn' then 'ncc' when 'sao_ke' then 'hoa_don_thue' else p_bang end, p_ghi) then return u; end if;
  -- 16/10: thủ quỹ (chi_tt) — phiếu chờ chi tiền / đã thanh toán
  if p_bang = 'chi' and kt_co_quyen(u, 'chi_tt') and cardinality(p_ids) > 0
     and not exists (select 1 from unnest(p_ids) i where not exists (
       select 1 from kt_chi c join kt_tai_khoan t on t.id = c.tai_khoan_id where c.id = i and c.trang_thai in ('cho_tt','da_tt') and t.thu_quy_chi and not c.da_xoa)) then
    return u;
  end if;
  if p_bang = 'chi' and kt_co_quyen(u, 'chi_de_nghi') and cardinality(p_ids) > 0
     and not exists (select 1 from unnest(p_ids) i where not exists (
       select 1 from kt_chi c where c.id = i and c.tao_boi = u.ho_ten and not c.da_xoa)) then
    return u;
  end if;
  raise exception 'Tài khoản chưa được cấp quyền % trang này', case when p_ghi then 'sửa' else 'xem' end using errcode = '42501';
end $function$
;
