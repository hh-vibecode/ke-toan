-- 09/11/2026 anh (ảnh ô sửa Nội dung CK của phiếu chi): "cho phép xoá cả mã phiếu chi đi, và không giới hạn số lượng ký tự".
-- Trước: số phiếu PCxxxxxx luôn gắn cứng ở đầu, phần gõ thêm tối đa 16 ký tự (app) / 50 (CSDL). Nay: ô sửa ở khung QR chứa TOÀN BỘ nội dung
-- (mặc định có sẵn số phiếu, xoá được) → lưu nd_ck_tron = true (app dùng nguyên văn, không tự gắn số phiếu); các form nhập giữ cách cũ (phần gõ thêm sau số phiếu).
-- Bỏ giới hạn: CSDL nhận tới 500 ký tự (thực tế không chạm); mã QR chứa tối đa 95 ký tự (giới hạn kỹ thuật chuẩn VietQR). — Monsieur Claude
alter table kt_chi add column if not exists nd_ck_tron boolean not null default false;

drop function if exists public.kt_sua_nd_ck(text, bigint, text);
create or replace function public.kt_sua_nd_ck(p_phien text, p_id bigint, p_nd text, p_tron boolean default false) returns text
  language plpgsql security definer set search_path = public as $function$
declare u kt_nguoi_dung; c kt_chi; v_nd text := nullif(left(trim(coalesce(p_nd, '')), 500), '');
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi'; end if;
  if c.trang_thai = 'da_tt' then raise exception 'Phiếu đã chi tiền — không sửa nội dung chuyển khoản nữa'; end if;
  if not (kt_co_quyen(u, 'chi', true) or kt_co_quyen(u, 'chi_tt') or kt_co_quyen(u, 'chi_duyet') or kt_co_quyen(u, 'chi_gd')
          or (c.tao_boi = u.ho_ten and c.trang_thai = 'cho_duyet')) then
    raise exception 'Tài khoản không có quyền sửa nội dung chuyển khoản' using errcode = '42501'; end if;
  if v_nd is not distinct from c.noi_dung_ck and coalesce(p_tron, false) = c.nd_ck_tron then return v_nd; end if;
  update kt_chi set noi_dung_ck = v_nd, nd_ck_tron = coalesce(p_tron, false) and v_nd is not null where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'doi_nd_ck', jsonb_build_object('tu', c.noi_dung_ck, 'sang', v_nd, 'tron', coalesce(p_tron, false)));
  return v_nd;
end $function$;
revoke all on function public.kt_sua_nd_ck(text, bigint, text, boolean) from public;
grant execute on function public.kt_sua_nd_ck(text, bigint, text, boolean) to anon, authenticated;

-- form phiếu chi app + form đề nghị công khai: bỏ cắt 50 ký tự
do $$ declare d text; f text; begin
  foreach f in array array['public.kt_luu_chi(text, jsonb)', 'public.kt_gui_de_nghi(jsonb)'] loop
    begin d := pg_get_functiondef(f::regprocedure); exception when others then continue; end;
    d := replace(replace(d, '''noi_dung_ck''), 50)', '''noi_dung_ck''), 500)'), '''noi_dung_ck'', '''')), 50)', '''noi_dung_ck'', '''')), 500)');
    execute d;
  end loop;
end $$;
