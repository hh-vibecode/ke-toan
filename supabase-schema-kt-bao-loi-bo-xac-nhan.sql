-- 27/10/2026 anh: "không cần họ ấn xác nhận nữa, bỏ phần ấy đi" + "lỗi fix rồi clear trong chuông của t nữa".
-- Lỗi xử lý xong = hoàn thành luôn (không còn bước người báo bấm Hoàn thành / Phản hồi); thông báo "báo lỗi" trong chuông người quản trị
-- tự xoá khi lỗi đã xử lý. Người báo vẫn nhận chuông kết quả xử lý. Monsieur Claude
create or replace function kt_bao_loi_bao_kq(p_id bigint, p_ai text) returns void
 language plpgsql security definer set search_path = public as $$
declare b kt_bao_loi;
begin
  select * into b from kt_bao_loi where id = p_id;
  if b.id is null or not b.da_xu_ly then return; end if;
  update kt_bao_loi set xac_nhan = 'hoan_thanh',
         lich_su = lich_su || jsonb_build_array(jsonb_build_object('loai', 'xu_ly', 'ai', p_ai, 'luc', now(), 'noi_dung', coalesce(b.xu_ly_ghi, 'Đã xử lý')))
   where id = p_id;
  delete from kt_thong_bao where loai = 'bao_loi' and bang = 'bao_loi' and dong_id = p_id;   -- dọn chuông người quản trị
  insert into kt_thong_bao (nguoi_dung_id, tu, loai, tieu_de, noi_dung, bang, dong_id)
  select n.id, p_ai, 'bao_loi_kq', 'Lỗi đã báo' || coalesce(' · ' || nullif(b.so_phieu, ''), '') || ': đã xử lý',
         left(coalesce(b.xu_ly_ghi, 'Đã xử lý'), 300), 'bao_loi_kq', b.id
    from kt_nguoi_dung n where n.ho_ten = b.nguoi and n.hoat_dong;
end $$;

-- bỏ hẳn bước người báo xác nhận
drop function if exists kt_bao_loi_xac_nhan(text, bigint, boolean, text);

-- dọn dữ liệu cũ: lỗi đã xử lý → hoàn thành; thông báo báo lỗi của lỗi đã xử lý → xoá khỏi chuông
update kt_bao_loi set xac_nhan = 'hoan_thanh' where da_xu_ly and coalesce(xac_nhan, '') <> 'hoan_thanh';
delete from kt_thong_bao t where t.loai = 'bao_loi' and t.bang = 'bao_loi' and exists (select 1 from kt_bao_loi b where b.id = t.dong_id and b.da_xu_ly);
