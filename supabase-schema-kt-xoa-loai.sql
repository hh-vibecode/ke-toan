-- 26/10/2026 (kế toán qua anh): "vừa tạo thử mục con nhưng tạo sai, giờ muốn xoá" — xoá hẳn loại thu / chi (mục con) TẠO NHẦM, CHƯA DÙNG.
-- Đang dùng ở phiếu chi / thu, ngân sách, luật phân loại, P&L định kỳ, hoặc có mục con → khoá ngoại chặn, báo dùng "Ngừng dùng". Monsieur Claude
create or replace function kt_xoa_loai(p_phien text, p_id int) returns void
 language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; l kt_loai;
begin
  u := kt_chan(p_phien, 'danh_muc', true);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  select * into l from kt_loai where id = p_id;
  if l.id is null then raise exception 'Không tìm thấy mục'; end if;
  if exists (select 1 from kt_loai where cha_id = p_id) then raise exception 'Mục "%" đang có mục con — xoá / chuyển mục con trước', l.ten; end if;
  begin
    delete from kt_loai where id = p_id;
  exception when foreign_key_violation then
    raise exception 'Mục "%" đã được dùng (phiếu, ngân sách hoặc luật phân loại) — không xoá được, dùng "Ngừng dùng" ở Cài đặt → Danh mục', l.ten;
  end;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_loai', p_id, 'xoa', to_jsonb(l));
end $$;
revoke all on function kt_xoa_loai(text, int) from public; grant execute on function kt_xoa_loai(text, int) to anon;
