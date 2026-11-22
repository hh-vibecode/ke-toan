-- 21/10/2026 (admin kế toán Trang qua anh): "phiếu đang trừ tiền sai ngày nên lệch quỹ cuối ngày, có sửa được ngày thanh toán không" → "không có chỗ sửa".
-- Ngày thanh toán chỉ người xác nhận chi / giám đốc / thủ quỹ đổi được (kt_luu_chi) — admin.ketoan bị bỏ quyền xác nhận 19/10 nên mất luôn chỗ sửa ngày.
-- Hàm riêng: người có quyền SỬA Chi (hoặc xác nhận / giám đốc) đổi NGÀY THANH TOÁN của phiếu ĐÃ CHI. Tháng đã khoá sổ → trigger khoá kỳ chặn. Monsieur Claude
create or replace function public.kt_doi_ngay_tt(p_phien text, p_id bigint, p_ngay date) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; v_hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  if not (kt_co_quyen(u, 'chi', true) or kt_co_quyen(u, 'chi_duyet') or kt_co_quyen(u, 'chi_gd')) then
    raise exception 'Tài khoản chưa được cấp quyền sửa phiếu chi' using errcode = '42501'; end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi'; end if;
  if c.trang_thai <> 'da_tt' then raise exception 'Chỉ đổi ngày thanh toán của phiếu đã chi'; end if;
  if p_ngay is null or p_ngay > v_hom or p_ngay < date '2026-01-01' then raise exception 'Ngày thanh toán không hợp lệ'; end if;
  if p_ngay = c.ngay_tt then return; end if;
  update kt_chi set ngay_tt = p_ngay, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'doi_ngay_tt', jsonb_build_object('tu', c.ngay_tt, 'sang', p_ngay));
end $$;
revoke execute on function public.kt_doi_ngay_tt(text, bigint, date) from public;
grant execute on function public.kt_doi_ngay_tt(text, bigint, date) to anon, authenticated;
