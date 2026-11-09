-- 09/11/2026 anh: "xem có chỗ cho huỷ phiếu của nhân sự bên ngoài chưa, nhiều khi người ta muốn làm lại".
-- Người gửi phiếu đề nghị (link công khai, không tài khoản) tự huỷ bằng mã bí mật của phiếu — CHỈ khi kế toán chưa kiểm (Chờ kế toán kiểm, chưa có kiem_luc).
-- Huỷ = xoá mềm (da_xoa) + ghi chú lý do + nhật ký "tu_huy_de_nghi"; trả lại nội dung để form gửi mới điền sẵn (người gửi làm lại nhanh). — Monsieur Claude
create or replace function public.kt_huy_de_nghi(p_ma text, p_ly_do text default null) returns jsonb
  language plpgsql security definer set search_path = public as $f$
declare p kt_chi_phieu := kt_phieu_theo_ma(p_ma, false); c kt_chi; v_ly text := left(nullif(trim(coalesce(p_ly_do, '')), ''), 300);
begin
  select * into c from kt_chi where id = p.chi_id for update;
  if c.trang_thai <> 'cho_duyet' or c.kiem_luc is not null then
    raise exception 'Kế toán đã kiểm phiếu này — muốn huỷ hoặc sửa thì nhắn kế toán';
  end if;
  update kt_chi set da_xoa = true, sua_boi = coalesce(c.nguoi_de_nghi, 'Người đề nghị') || ' (tự huỷ)', sua_luc = now(),
         ghi_chu = concat_ws(' · ', nullif(c.ghi_chu, ''), 'Người đề nghị tự huỷ' || coalesce(': ' || v_ly, ''))
   where id = c.id;
  insert into kt_nhat_ky (nguoi, bang, dong_id, hanh_dong, du_lieu)
    values (coalesce(c.nguoi_de_nghi, 'Người đề nghị') || ' (link đề nghị)', 'kt_chi', c.id, 'tu_huy_de_nghi', jsonb_build_object('ly_do', v_ly, 'so_tien', c.so_tien));
  return jsonb_build_object('id', c.id, 'nguoi_de_nghi', c.nguoi_de_nghi, 'bo_phan_id', c.bo_phan_id, 'noi_dung', c.noi_dung, 'so_tien', c.so_tien,
    'ngay_su_dung', c.ngay_su_dung, 'han_tt', c.han_tt, 'co_hd_do', c.co_hd_do, 'hd_ve', c.hd_ve, 'thu_huong_ten', c.thu_huong_ten,
    'thu_huong_nh', c.thu_huong_nh, 'thu_huong_stk', c.thu_huong_stk, 'noi_dung_ck', c.noi_dung_ck, 'loai_dn', c.loai_dn);
end $f$;
revoke all on function public.kt_huy_de_nghi(text, text) from public;
grant execute on function public.kt_huy_de_nghi(text, text) to anon, authenticated;

-- trang theo dõi: báo nút huỷ được không
create or replace function public.kt_xem_de_nghi(p_ma text) returns jsonb language plpgsql stable security definer set search_path = public as $function$
declare p kt_chi_phieu := kt_phieu_theo_ma(p_ma, false); c kt_chi;
begin
  select * into c from kt_chi where id = p.chi_id;
  return jsonb_build_object('id', c.id, 'ngay_de_nghi', c.ngay_de_nghi, 'nguoi_de_nghi', c.nguoi_de_nghi,
    'bo_phan', (select ten from kt_don_vi where id = c.bo_phan_id), 'noi_dung', c.noi_dung, 'so_tien', c.so_tien,
    'thu_huong_ten', c.thu_huong_ten, 'trang_thai', c.trang_thai, 'ngay_tt', c.ngay_tt,
    'so_file', (select count(*) from kt_chung_tu where bang = 'chi' and dong_id = c.id and not da_xoa),
    'con_tai_len', p.tao_luc > now() - interval '3 hours' and p.so_file < 60,
    'huy_duoc', c.trang_thai = 'cho_duyet' and c.kiem_luc is null);
end $function$;
