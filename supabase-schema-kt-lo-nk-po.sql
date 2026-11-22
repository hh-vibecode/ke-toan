-- HỒ SƠ NHẬP KHẨU ↔ PO — 12/11/2026. AI kế toán soát lỗi (anh chuyển): "Hồ sơ nhập khẩu → Thêm đơn hàng bắt nhập lại NCC, mã PO, hàng hoá, tỷ giá → mất truy vết
-- PO ↔ lô ↔ giá vốn". → đơn hàng trong lô lưu po_id (PO có sẵn); trang chọn PO thì tự điền NCC / mã PO / tiền tệ / tỷ giá / hàng hoá. — Monsieur Claude
alter table public.kt_lo_nk_don add column if not exists po_id bigint references kt_po(id);
create index if not exists kt_lo_nk_don_po on public.kt_lo_nk_don (po_id) where po_id is not null;

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
    insert into kt_lo_nk_don (lo_id, ncc_id, ma_po, ngay, tien_te, ty_gia, gia_tri, trang_thai, nhap_id, ho_so_id, hang, ghi_chu, tao_boi, po_id)
    values (v_lo, n.id, nullif(trim(p_dong->>'ma_po'), ''), nullif(p_dong->>'ngay', '')::date, nullif(p_dong->>'tien_te', ''), nullif(p_dong->>'ty_gia', '')::numeric, v_gt,
      coalesce(nullif(p_dong->>'trang_thai', ''), 'san_xuat'), nullif(p_dong->>'nhap_id', '')::bigint, nullif(p_dong->>'ho_so_id', '')::bigint, v_hang, nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten, nullif(p_dong->>'po_id', '')::bigint)
    returning id into v_id;
  else
    update kt_lo_nk_don set ncc_id = n.id, ma_po = nullif(trim(p_dong->>'ma_po'), ''), ngay = nullif(p_dong->>'ngay', '')::date, tien_te = nullif(p_dong->>'tien_te', ''),
      ty_gia = nullif(p_dong->>'ty_gia', '')::numeric, gia_tri = v_gt, trang_thai = coalesce(nullif(p_dong->>'trang_thai', ''), trang_thai),
      nhap_id = nullif(p_dong->>'nhap_id', '')::bigint, ho_so_id = nullif(p_dong->>'ho_so_id', '')::bigint, hang = v_hang, ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), po_id = nullif(p_dong->>'po_id', '')::bigint,
      sua_boi = u.ho_ten, sua_luc = now() where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk_don', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong - 'hang' || jsonb_build_object('so_hang', jsonb_array_length(v_hang)));
  return v_id;
end $function$;
