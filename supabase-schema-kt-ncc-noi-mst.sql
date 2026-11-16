-- FORM NCC NỘI ĐỊA — TRA MST TỰ ĐIỀN (16/11/2026, kế toán chị Jaycie: "bổ sung luôn nếu đánh MST sẽ tự động ra thông tin"). Monsieur Claude
-- Dùng lại Edge kt-mst (VietQR / cổng HĐĐT Tổng cục Thuế, lưu đệm kt_mst 30 ngày). Trước: chỉ tài khoản có quyền xem Hoá đơn & Thuế tra được
-- → nay thêm người có quyền xem trang NCC (form Thêm / Sửa NCC nội địa). Chỉ trả tên + địa chỉ đăng ký thuế (thông tin công khai).
create or replace function public.kt_mst_lay(p_phien text, p_mst text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  begin
    perform kt_chan(p_phien, 'hoa_don_thue');
  exception when others then
    perform kt_chan(p_phien, 'ncc');   -- không có quyền NCC thì báo lỗi của kt_chan (hết phiên / chưa cấp quyền)
  end;
  return (select jsonb_build_object('mst', mst, 'ten', ten, 'dia_chi', dia_chi, 'nguon', nguon, 'luc', luc) from kt_mst
           where mst = p_mst and luc > now() - interval '30 days');
end $$;
revoke all on function public.kt_mst_lay(text, text) from public;
grant execute on function public.kt_mst_lay(text, text) to anon, authenticated, service_role;
