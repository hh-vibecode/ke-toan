-- 26/10/2026 (anh): "thêm chỉnh sửa cho phần nội dung" — sửa NỘI DUNG CHUYỂN KHOẢN ngay ở khung mã QR của phiếu chi chưa trả
-- (kt_luu_chi không cho thủ quỹ đổi noi_dung_ck; người chuyển tiền cần sửa nhanh mà không mở cả form). Monsieur Claude
create or replace function kt_sua_nd_ck(p_phien text, p_id bigint, p_nd text) returns text
 language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; v_nd text := nullif(left(trim(coalesce(p_nd, '')), 50), '');
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi'; end if;
  if c.trang_thai = 'da_tt' then raise exception 'Phiếu đã chi tiền — không sửa nội dung chuyển khoản nữa'; end if;
  if not (kt_co_quyen(u, 'chi', true) or kt_co_quyen(u, 'chi_tt') or kt_co_quyen(u, 'chi_duyet') or kt_co_quyen(u, 'chi_gd')
          or (c.tao_boi = u.ho_ten and c.trang_thai = 'cho_duyet')) then
    raise exception 'Tài khoản không có quyền sửa nội dung chuyển khoản' using errcode = '42501'; end if;
  if v_nd is not distinct from c.noi_dung_ck then return v_nd; end if;
  update kt_chi set noi_dung_ck = v_nd where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'doi_nd_ck', jsonb_build_object('tu', c.noi_dung_ck, 'sang', v_nd));
  return v_nd;
end $$;
revoke all on function kt_sua_nd_ck(text, bigint, text) from public; grant execute on function kt_sua_nd_ck(text, bigint, text) to anon;
