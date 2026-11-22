-- Phiếu chi khớp số phiếu GG Sheet đề nghị thanh toán (16/10/2026, anh Hải: "bên thu chi chỉ cần đầy đủ số lượng phiếu giống trên gg sheet") — Monsieur Claude
-- Xoá MỀM (da_xoa = true, khôi phục được), ghi nhật ký. Đã đối chiếu từng dòng với file sheet tải 16/10 15:06.
--  · #181 cọc chị Phương Hương: dòng sheet r804 (cùng dấu thời gian form) đã sửa số tiền → bản đúng là #378 (đã thanh toán)
--  · #407 vận chuyển TQ 08/10: bản cũ của dòng r834 (đã sửa số tiền) → bản đúng là #1581 (đã thanh toán)
--  · #160 vận chuyển TQ 30/9: dòng đã xoá khỏi sheet
--  · #1623 (gửi qua form app 16/10) trùng #1615 (sheet 15/10) cùng nội dung + số tiền → gộp vào #1615, chuyển chứng từ sang
update kt_chi set da_xoa = true, sua_boi = 'Hệ thống', sua_luc = now(),
  ghi_chu = concat_ws(' ', ghi_chu, '[16/10: không còn trên sheet đề nghị (đã xoá / đã sửa thành phiếu khác) — xoá theo sheet]')
 where id in (160, 181, 407) and not da_xoa and nguon = 'sheet_cu' and trang_thai in ('cho_duyet','cho_gd','cho_tt');
select kt_ghi_nhat_ky('Hệ thống', 'kt_chi', id, 'xoa_theo_sheet', jsonb_build_object('ly_do', 'Không còn trên sheet đề nghị thanh toán (16/10)'))
  from kt_chi where id in (160, 181, 407) and da_xoa;

update kt_chung_tu set dong_id = 1615 where bang = 'chi' and dong_id = 1623 and not da_xoa;
update kt_chi set da_xoa = true, nghi_trung = null, sua_boi = 'Hệ thống', sua_luc = now(),
  ghi_chu = concat_ws(' ', ghi_chu, '[16/10: trùng #1615 (sheet) — gộp vào #1615, chứng từ chuyển sang]')
 where id = 1623 and not da_xoa;
select kt_ghi_nhat_ky('Hệ thống', 'kt_chi', 1623, 'gop_trung', jsonb_build_object('gop_vao', 1615));
update kt_thong_bao set da_doc = true where bang = 'chi' and dong_id in (160, 181, 407, 1623);

-- Sửa hàm gộp trùng: chỉ chép thông tin Kiot sang phiếu gốc khi phiếu bị gộp thật sự có phiếu Kiot
-- (trước đây gộp phiếu không có Kiot vẫn đánh dấu phiếu gốc "đã cập nhật Kiot").
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_xu_ly_trung'::regproc);
  n := length(d);
  d := replace(d, $a$update kt_chi set kiot_so_quy_id = c.kiot_so_quy_id, kiot_ma = c.kiot_ma, kiot = 'da_tao' where id = p_gop_vao;$a$,
                  $a$if c.kiot_so_quy_id is not null then update kt_chi set kiot_so_quy_id = c.kiot_so_quy_id, kiot_ma = c.kiot_ma, kiot = 'da_tao' where id = p_gop_vao; end if;$a$);
  if length(d) = n then raise exception 'khong thay cho chep kiot'; end if;
  execute d;
end $$;
