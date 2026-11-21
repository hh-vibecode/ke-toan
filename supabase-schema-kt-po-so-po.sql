-- SỐ PO BỎ "THT" — 21/11/2026. Monsieur Claude
-- Kế toán (ảnh danh sách PO): "cho nó chạy lại hết mã PO này, chốt bỏ THT đi, dài dòng quá, chốt lại là PO-.... thôi".
-- Quy tắc: PO-MMYY-<viết tắt NCC>[STT 2 số khi tháng đó NCC có nhiều PO]. Chạy lại toàn bộ PO đang có:
--   MMYY: GIỮ tháng-năm kế toán đã ghi trong mã (PO-0826-TSF ngày PO 15/09 vẫn 0826); mã kiểu cũ THT-PO-0xx/2026 → tháng-năm của ngày PO.
--   Viết tắt: theo NCC (ô "Viết tắt (mã PO)" ở form NCC) — PO-0126-TC → PO-0126-TSF (NCC TƯỢNG CỔ viết tắt TSF).
--   Nhiều PO cùng tháng + cùng NCC → 01, 02… theo ngày PO. Mã cũ lưu cột so_cu (ô tìm PO tìm được mã cũ). Hồ sơ nhập khẩu (kt_lo_nk_don.ma_po) đổi theo.
-- Chạy thử 21/11: 22 PO — 10 đổi, 12 giữ nguyên, 0 trùng.
alter table public.kt_po add column if not exists so_cu text;
do $do$ declare r record; v_doi jsonb := '[]';
begin
  for r in
    with b as (select p.id, p.so, p.ngay, coalesce(substring(p.so from '^(?:THT)?-?PO-([0-9]{4})-'), to_char(p.ngay, 'MMYY')) mmyy, kt_po_viet_tat(p.ncc_id, p.ncc_ten) vt from kt_po p where not p.da_xoa),
         g as (select b.*, count(*) over (partition by mmyy, vt) n, row_number() over (partition by mmyy, vt order by ngay, id) stt from b)
    select id, so, 'PO-' || mmyy || '-' || vt || case when n > 1 then lpad(stt::text, 2, '0') else '' end moi from g
  loop
    if r.moi is distinct from r.so then
      update kt_po set so_cu = coalesce(so_cu, r.so), so = r.moi where id = r.id;
      update kt_lo_nk_don set ma_po = r.moi where po_id = r.id and not da_xoa;
      v_doi := v_doi || jsonb_build_object('id', r.id, 'cu', r.so, 'moi', r.moi);
    end if;
  end loop;
  perform kt_ghi_nhat_ky('Hệ thống', 'kt_po', null, 'doi_so_po', jsonb_build_object('ly_do', 'Bỏ THT — số PO chốt PO-MMYY-viết tắt NCC (+ STT khi nhiều PO trong tháng)', 'doi', v_doi));
end $do$;

CREATE OR REPLACE FUNCTION public.kt_po_luu(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v bigint := nullif(p_dong->>'id', '')::bigint; ten text; n int; so_tay text := nullif(btrim(p_dong->>'so'), ''); pre text;
begin
  u := kt_chan(p_phien, 'ncc', true); ten := coalesce(u.ho_ten, u.ten_dang_nhap);
  if jsonb_typeof(coalesce(p_dong->'dong', '[]')) <> 'array' then raise exception 'Dòng hàng không hợp lệ'; end if;
  -- 17/11 kế toán: "để chị tự đặt mã" — số PO gõ tay không được trùng PO khác (chưa xoá); để trống = tự cấp số chưa dùng
  if so_tay is not null and exists (select 1 from kt_po where not da_xoa and lower(btrim(so)) = lower(so_tay) and id is distinct from v) then
    raise exception 'Số PO "%" đã có ở PO khác — đặt số khác', so_tay;
  end if;
  if v is null then
    -- 19/11 kế toán: MMYY (tháng năm PO)-viết tắt NCC + STT nếu nhiều PO trong tháng. 21/11 kế toán: "bỏ THT, dài dòng quá, chốt là PO-…"
    -- → PO-MMYY-<viết tắt>; tháng đó NCC đã có PO thì thêm STT 2 số tiếp theo (PO đầu không số = 01) — PO đã có không bị đổi số khi có PO sau.
    pre := 'PO-' || to_char(coalesce(nullif(p_dong->>'ngay', '')::date, current_date), 'MMYY') || '-' || kt_po_viet_tat(nullif(p_dong->>'ncc_id', '')::bigint, p_dong->>'ncc_ten');
    select coalesce(max(case when so = pre then 1 else substring(so from '([0-9]{2})$')::int end), 0) into n from kt_po where not da_xoa and (so = pre or so ~ ('^' || pre || '[0-9]{2}$'));
    insert into kt_po (so, loai, ncc_id, ncc_ten, ngay, so_pi, tien_te, ty_gia, noi_giao, ngay_giao, vat, dat_coc, ngay_coc, trang_thai, dong, khach, ghi_chu, tao_boi)
    values (coalesce(nullif(btrim(p_dong->>'so'), ''), pre || case when n = 0 then '' else lpad((n + 1)::text, 2, '0') end),
      coalesce(p_dong->>'loai', 'noi_dia'), nullif(p_dong->>'ncc_id', '')::bigint, p_dong->>'ncc_ten', coalesce(nullif(p_dong->>'ngay', '')::date, current_date), p_dong->>'so_pi',
      coalesce(nullif(p_dong->>'tien_te', ''), 'VND'), nullif(p_dong->>'ty_gia', '')::numeric, p_dong->>'noi_giao', nullif(p_dong->>'ngay_giao', '')::date,
      nullif(p_dong->>'vat', '')::numeric, nullif(p_dong->>'dat_coc', '')::numeric, nullif(p_dong->>'ngay_coc', '')::date, coalesce(nullif(p_dong->>'trang_thai', ''), 'nhap'),
      coalesce(p_dong->'dong', '[]'), p_dong->'khach', p_dong->>'ghi_chu', ten) returning id into v;
    update kt_po set chi_ids = coalesce(p_dong->'chi_ids', '[]'), chi_phi = coalesce(p_dong->'chi_phi', '[]') where id = v;
  else
    update kt_po set so = coalesce(nullif(btrim(p_dong->>'so'), ''), so), loai = coalesce(p_dong->>'loai', loai), ncc_id = nullif(p_dong->>'ncc_id', '')::bigint, ncc_ten = p_dong->>'ncc_ten',
      ngay = coalesce(nullif(p_dong->>'ngay', '')::date, ngay), so_pi = p_dong->>'so_pi', tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te),
      ty_gia = nullif(p_dong->>'ty_gia', '')::numeric, noi_giao = p_dong->>'noi_giao', ngay_giao = nullif(p_dong->>'ngay_giao', '')::date, vat = nullif(p_dong->>'vat', '')::numeric,
      dat_coc = nullif(p_dong->>'dat_coc', '')::numeric, ngay_coc = nullif(p_dong->>'ngay_coc', '')::date, trang_thai = coalesce(nullif(p_dong->>'trang_thai', ''), trang_thai),
      dong = coalesce(p_dong->'dong', dong), khach = p_dong->'khach', chi_ids = coalesce(p_dong->'chi_ids', chi_ids), chi_phi = coalesce(p_dong->'chi_phi', chi_phi), ghi_chu = p_dong->>'ghi_chu', la_mau = false, sua_boi = ten, sua_luc = now()
    where id = v and not da_xoa;
    if not found then raise exception 'Không tìm thấy PO'; end if;
  end if;
  perform kt_ghi_nhat_ky(ten, 'kt_po', v, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v;
end $function$;
