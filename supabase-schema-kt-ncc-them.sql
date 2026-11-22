-- THÔNG TIN NCC MỞ RỘNG (29/10/2026, ảnh mẫu "giao diện thông tin NCC thiết kế như này"). Monsieur Claude
-- kt_ncc.them (jsonb): quoc_gia, loai_hinh, nganh_hang, ten_giao_dich, ten_goc (tên tiếng nước ngoài), chuc_vu, dieu_kien_tt, dieu_kien_giao,
-- tien_te (VND / USD / CNY…), ty_gia (tỷ giá quy đổi kế toán nhập — chỉ để hiện số theo tiền tệ NCC, số gốc vẫn là VND).
alter table public.kt_ncc add column if not exists them jsonb not null default '{}';

CREATE OR REPLACE FUNCTION public.kt_luu_ncc(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_stk text[];
begin
  u := kt_chan(p_phien, 'ncc', true);
  select coalesce(array_agg(distinct s), '{}') into v_stk from (select kt_so_tk(x) s from jsonb_array_elements_text(coalesce(p_dong->'stk', '[]')) x) z where s is not null;
  if v_id is null then
    if nullif(trim(p_dong->>'ten'), '') is null then raise exception 'Nhập tên nhà cung cấp'; end if;
    insert into kt_ncc (ten, loai, mst, sdt, email, dia_chi, lien_he, stk, ghi_chu, them, tao_boi)
    values (trim(p_dong->>'ten'), coalesce(nullif(p_dong->>'loai', ''), 'nuoc_ngoai'), nullif(trim(p_dong->>'mst'), ''), nullif(trim(p_dong->>'sdt'), ''), nullif(trim(p_dong->>'email'), ''),
      nullif(trim(p_dong->>'dia_chi'), ''), nullif(trim(p_dong->>'lien_he'), ''), v_stk, nullif(trim(p_dong->>'ghi_chu'), ''), coalesce(p_dong->'them', '{}'), u.ho_ten) returning id into v_id;
    update kt_ncc set ma = 'NCCA' || lpad(v_id::text, 4, '0') where id = v_id;
  else
    update kt_ncc set sua_tay = sua_tay or (kiot_id is not null and (coalesce(nullif(trim(p_dong->>'ten'), ''), ten) is distinct from ten or nullif(trim(p_dong->>'sdt'), '') is distinct from sdt))
     where id = v_id and not da_xoa;
    update kt_ncc set ten = coalesce(nullif(trim(p_dong->>'ten'), ''), ten),
      loai = coalesce(nullif(p_dong->>'loai', ''), loai), mst = nullif(trim(p_dong->>'mst'), ''), email = nullif(trim(p_dong->>'email'), ''), dia_chi = nullif(trim(p_dong->>'dia_chi'), ''),
      lien_he = nullif(trim(p_dong->>'lien_he'), ''), sdt = nullif(trim(p_dong->>'sdt'), ''),
      stk = v_stk, ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), them = coalesce(p_dong->'them', them), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_ncc', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $function$;
