-- 26/10/2026 (anh): "khi xử lý xong, người gửi phiếu (không tài khoản) thấy được bill chuyển khoản ở bước cuối cùng".
-- Trang theo dõi phiếu (#phieu=<mã bí mật>) → Edge kt-chung-tu việc 'bill_phieu' {ma} gọi hàm này bằng service role → ký link xem 5 phút.
-- Chỉ khi phiếu ĐÃ THANH TOÁN; chỉ ảnh giao dịch (tên file UNC_… — ô "Ảnh giao dịch (uỷ nhiệm chi / phiếu chi ký nhận)" của phiếu), không trả hồ sơ khác.
-- — Monsieur Claude
create or replace function public.kt_bill_phieu(p_ma text) returns jsonb
  language plpgsql stable security definer set search_path = public, extensions as $f$
declare p kt_chi_phieu := kt_phieu_theo_ma(p_ma, false); c kt_chi;
begin
  select * into c from kt_chi where id = p.chi_id and not da_xoa;
  if c.id is null or c.trang_thai <> 'da_tt' then return '[]'; end if;
  -- 26/10 anh "cần bill chuyển khoản": kèm tm = chi tiền mặt (nhãn "Phiếu chi ký nhận"), còn lại nhãn "Bill chuyển khoản"
  return (select coalesce(jsonb_agg(jsonb_build_object('duong_dan', k.duong_dan, 'ten', k.ten_file, 'mime', k.mime,
            'tm', coalesce((select t.loai = 'tien_mat' from kt_tai_khoan t where t.id = c.tai_khoan_id), false)) order by k.id), '[]')
            from kt_chung_tu k where k.bang = 'chi' and k.dong_id = c.id and not k.da_xoa and k.ten_file ~* '^UNC_');
end $f$;
revoke all on function public.kt_bill_phieu(text) from anon, authenticated, public;
