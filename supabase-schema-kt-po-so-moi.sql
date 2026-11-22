-- SỐ PO TỰ CẤP THEO QUY TẮC MỚI — 19/11/2026. Monsieur Claude
-- Kế toán: "quy tắc mã PO: THTPO-MMYY (tháng năm phát sinh PO)-tên viết tắt NCC + STT nếu có nhiều PO trong tháng (VD THTPO-1126-TSF01)".
-- Viết tắt NCC: kt_ncc.them->>'viet_tat' (ô "Viết tắt (mã PO)" ở form NCC); chưa có → lấy từ số PO kế toán đặt gần nhất của NCC đó (PO-MMYY-XXX),
-- chưa có nữa → chữ đầu các từ trong tên (bỏ "NCC", "TQ"), tối đa 4 chữ. STT 2 số đếm trong cùng tháng + cùng NCC. Số PO đã có giữ nguyên.
create or replace function public.kt_po_viet_tat(p_ncc bigint, p_ten text) returns text language plpgsql stable set search_path to 'public' as $f$
declare v text; t text;
begin
  select nullif(upper(regexp_replace(them->>'viet_tat', '[^A-Za-z0-9]', '', 'g')), ''), ten into v, t from kt_ncc where id = p_ncc;
  if v is not null then return v; end if;
  select substring(so from '^(?:THT)?-?PO-[0-9]{4}-([A-Za-z]+)') into v from kt_po
   where not da_xoa and ncc_id = p_ncc and so ~ '^(THT)?-?PO-[0-9]{4}-[A-Za-z]+' order by ngay desc, id desc limit 1;
  if v is not null then return upper(v); end if;
  t := upper(translate(coalesce(t, p_ten, 'NCC'), 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ',
    'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD'));
  select string_agg(left(w, 1), '') into v from (select w from regexp_split_to_table(regexp_replace(t, '[^A-Z0-9 ]', ' ', 'g'), '\s+') w
    where w <> '' and w not in ('NCC', 'TQ')) x;
  return coalesce(nullif(left(v, 4), ''), 'NCC');
end $f$;
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
    -- 19/11 kế toán: THTPO-MMYY (tháng năm PO)-viết tắt NCC + STT 2 số trong tháng (VD THTPO-1126-TSF01)
    pre := 'THTPO-' || to_char(coalesce(nullif(p_dong->>'ngay', '')::date, current_date), 'MMYY') || '-' || kt_po_viet_tat(nullif(p_dong->>'ncc_id', '')::bigint, p_dong->>'ncc_ten');
    select count(*) + 1 into n from kt_po where not da_xoa and so like pre || '%';
    while so_tay is null and exists (select 1 from kt_po where not da_xoa and so = pre || lpad(n::text, 2, '0')) loop n := n + 1; end loop;
    insert into kt_po (so, loai, ncc_id, ncc_ten, ngay, so_pi, tien_te, ty_gia, noi_giao, ngay_giao, vat, dat_coc, ngay_coc, trang_thai, dong, khach, ghi_chu, tao_boi)
    values (coalesce(nullif(btrim(p_dong->>'so'), ''), pre || lpad(n::text, 2, '0')),
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
end $function$
;

-- điền sẵn viết tắt cho NCC đã có PO kế toán tự đặt mã (để form NCC hiện đúng, sửa được)
update kt_ncc n set them = coalesce(n.them, '{}'::jsonb) || jsonb_build_object('viet_tat', kt_po_viet_tat(n.id, n.ten))
 where coalesce(n.them->>'viet_tat', '') = '' and exists (select 1 from kt_po p where not p.da_xoa and p.ncc_id = n.id and p.so ~ '^(THT)?-?PO-[0-9]{4}-[A-Za-z]+');
