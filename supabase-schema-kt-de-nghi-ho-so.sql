-- Phiếu đề nghị công khai: hồ sơ nhận cả Excel / Word / CSV như phiếu ghi "Chọn ảnh / PDF / Excel / Word" (15/10/2026 — kiểm thử đầu-cuối phát hiện chỉ nhận ảnh / PDF). Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_them_ct_phieu(p_ma text, p_duong_dan text, p_ten text, p_mime text, p_kich_thuoc bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p kt_chi_phieu := kt_phieu_theo_ma(p_ma, true); v_id bigint; v_ten text;
begin
  if p_duong_dan !~ ('^chi/' || p.chi_id || '/[0-9]+_[A-Za-z0-9._-]+$') then raise exception 'Đường dẫn hồ sơ không hợp lệ'; end if;
  if coalesce(p_mime, '') !~ '^(image/(jpeg|png|webp|heic|heif)|application/pdf|application/vnd\.openxmlformats-officedocument\.(spreadsheetml\.sheet|wordprocessingml\.document)|application/vnd\.ms-excel|application/msword|text/csv)$' then
    raise exception 'Chỉ nhận ảnh, PDF, Excel, Word, CSV'; end if;
  if coalesce(p_kich_thuoc, 0) <= 0 or p_kich_thuoc > 15 * 1024 * 1024 then raise exception 'File tối đa 15 MB'; end if;
  if exists (select 1 from kt_chung_tu where duong_dan = p_duong_dan) then raise exception 'Hồ sơ này đã ghi'; end if;
  select nguoi_de_nghi into v_ten from kt_chi where id = p.chi_id;
  insert into kt_chung_tu (bang, dong_id, duong_dan, ten_file, mime, kich_thuoc, tao_boi)
  values ('chi', p.chi_id, p_duong_dan, left(coalesce(p_ten, 'tep'), 200), p_mime, p_kich_thuoc, 'Phiếu đề nghị: ' || v_ten) returning id into v_id;
  update kt_chi_phieu set so_file = so_file + 1 where chi_id = p.chi_id;
  return v_id;
end $function$;
