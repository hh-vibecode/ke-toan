-- HỒ SƠ NHẬP KHẨU: GIÁ TRỊ KHAI BÁO HẢI QUAN + ĐƠN VỊ NHẬN TIỀN CHI PHÍ — 12/11/2026. Kế toán (anh chuyển): "giá trị trên hồ sơ không khớp với giá trị giao dịch
-- thực tế đâu nhé" + "phần bên thứ 3 thanh toán và các phần dịch vụ ví dụ như kê khai hải quan phải trả cho đơn vị dịch vụ thì sẽ nằm ở phần nào?".
-- (1) Đơn hàng trong lô có thêm giá trị KHAI BÁO hải quan (nguyên tệ + tỷ giá tờ khai) riêng — chỉ để đối chiếu thuế / tờ khai; giá vốn vẫn tính theo giá trị THỰC TẾ.
-- (2) Chi phí nhập khẩu ghi đơn vị nhận tiền (đơn vị dịch vụ khai hải quan, vận chuyển…); chưa gắn phiếu chi = CHƯA TRẢ (còn nợ đơn vị đó). — Monsieur Claude
alter table public.kt_lo_nk_don add column if not exists gia_tri_kk numeric, add column if not exists ty_gia_kk numeric;
alter table public.kt_lo_nk_cp add column if not exists don_vi_nhan text;

CREATE OR REPLACE FUNCTION public.kt_luu_lo_nk_don(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; n kt_ncc; v_hang jsonb := coalesce(p_dong->'hang', '[]'); v_gt numeric; v_lo bigint := (p_dong->>'lo_id')::bigint;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if v_id is not null then select lo_id into v_lo from kt_lo_nk_don where id = v_id and not da_xoa; if v_lo is null then raise exception 'Không thấy đơn hàng'; end if; end if;
  if not exists (select 1 from kt_lo_nk where id = v_lo and not da_xoa) then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  select * into n from kt_ncc where id = (p_dong->>'ncc_id')::bigint and not da_xoa;
  if n.id is null then raise exception 'Chọn nhà cung cấp'; end if;
  if jsonb_typeof(v_hang) <> 'array' then raise exception 'Danh sách hàng không hợp lệ'; end if;
  if nullif(p_dong->>'nhap_id', '') is not null and (n.kiot_id is null or not exists (select 1 from kt_kiot_nhap_hang h where h.id = (p_dong->>'nhap_id')::bigint and h.ncc_id = n.kiot_id)) then
    raise exception 'Phiếu nhập Kiot không thuộc NCC này'; end if;
  if nullif(p_dong->>'ho_so_id', '') is not null and not exists (select 1 from kt_ho_so s where s.id = (p_dong->>'ho_so_id')::bigint and s.ncc_id = n.id and not s.da_xoa) then
    raise exception 'Hợp đồng không thuộc NCC này'; end if;
  v_gt := coalesce(nullif(p_dong->>'gia_tri', '')::numeric, (select nullif(sum(coalesce((h->>'sl')::numeric, 0) * coalesce((h->>'gia')::numeric, 0)), 0) from jsonb_array_elements(v_hang) h));
  if v_id is null then
    insert into kt_lo_nk_don (lo_id, ncc_id, ma_po, ngay, tien_te, ty_gia, gia_tri, trang_thai, nhap_id, ho_so_id, hang, ghi_chu, tao_boi, po_id, gia_tri_kk, ty_gia_kk)
    values (v_lo, n.id, nullif(trim(p_dong->>'ma_po'), ''), nullif(p_dong->>'ngay', '')::date, nullif(p_dong->>'tien_te', ''), nullif(p_dong->>'ty_gia', '')::numeric, v_gt,
      coalesce(nullif(p_dong->>'trang_thai', ''), 'san_xuat'), nullif(p_dong->>'nhap_id', '')::bigint, nullif(p_dong->>'ho_so_id', '')::bigint, v_hang, nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten, nullif(p_dong->>'po_id', '')::bigint, nullif(p_dong->>'gia_tri_kk', '')::numeric, nullif(p_dong->>'ty_gia_kk', '')::numeric)
    returning id into v_id;
  else
    update kt_lo_nk_don set ncc_id = n.id, ma_po = nullif(trim(p_dong->>'ma_po'), ''), ngay = nullif(p_dong->>'ngay', '')::date, tien_te = nullif(p_dong->>'tien_te', ''),
      ty_gia = nullif(p_dong->>'ty_gia', '')::numeric, gia_tri = v_gt, trang_thai = coalesce(nullif(p_dong->>'trang_thai', ''), trang_thai),
      nhap_id = nullif(p_dong->>'nhap_id', '')::bigint, ho_so_id = nullif(p_dong->>'ho_so_id', '')::bigint, hang = v_hang, ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), po_id = nullif(p_dong->>'po_id', '')::bigint, gia_tri_kk = nullif(p_dong->>'gia_tri_kk', '')::numeric, ty_gia_kk = nullif(p_dong->>'ty_gia_kk', '')::numeric,
      sua_boi = u.ho_ten, sua_luc = now() where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk_don', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong - 'hang' || jsonb_build_object('so_hang', jsonb_array_length(v_hang)));
  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.kt_luu_lo_nk_cp(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_lo bigint := (p_dong->>'lo_id')::bigint; v_chi bigint := nullif(p_dong->>'chi_id', '')::bigint;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if v_id is not null then select lo_id into v_lo from kt_lo_nk_cp where id = v_id and not da_xoa; if v_lo is null then raise exception 'Không thấy khoản chi phí'; end if; end if;
  if not exists (select 1 from kt_lo_nk where id = v_lo and not da_xoa) then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  if not (nullif(p_dong->>'so_tien', '')::numeric >= 0) then raise exception 'Nhập số tiền'; end if;
  if v_chi is not null and not exists (select 1 from kt_chi where id = v_chi and not da_xoa) then raise exception 'Không thấy phiếu chi PC%', lpad(v_chi::text, 6, '0'); end if;
  if v_id is null then
    insert into kt_lo_nk_cp (lo_id, loai, noi_dung, so_tien, tinh_gv, chi_id, ngay, ghi_chu, tao_boi, don_vi_nhan)
    values (v_lo, coalesce(nullif(p_dong->>'loai', ''), 'khac'), nullif(trim(p_dong->>'noi_dung'), ''), (p_dong->>'so_tien')::numeric,
      coalesce((p_dong->>'tinh_gv')::boolean, true), v_chi, nullif(p_dong->>'ngay', '')::date, nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten, nullif(trim(p_dong->>'don_vi_nhan'), '')) returning id into v_id;
  else
    update kt_lo_nk_cp set loai = coalesce(nullif(p_dong->>'loai', ''), loai), noi_dung = nullif(trim(p_dong->>'noi_dung'), ''), so_tien = (p_dong->>'so_tien')::numeric,
      tinh_gv = coalesce((p_dong->>'tinh_gv')::boolean, tinh_gv), chi_id = v_chi, ngay = nullif(p_dong->>'ngay', '')::date, ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), don_vi_nhan = nullif(trim(p_dong->>'don_vi_nhan'), ''),
      sua_boi = u.ho_ten, sua_luc = now() where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk_cp', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $function$;
