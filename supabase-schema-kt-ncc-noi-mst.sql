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

-- 16/11/2026: ô địa chỉ NCC nội địa nay là "Địa chỉ ĐKKD" kế toán nhập (hoặc tự điền theo MST) → đồng bộ Kiot chỉ ĐIỀN khi ô còn trống,
-- không ghi đè địa chỉ đã có (trước: mỗi lần kéo Kiot đè dia_chi theo Kiot nếu khác). Tên / mã / SĐT đồng bộ như cũ. Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_ncc_dong_bo()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_luc timestamptz; v_moi timestamptz;
begin
  select max(keo_luc) into v_moi from kt_kiot_ncc;
  select nullif(gia_tri, '')::timestamptz into v_luc from kt_cai_dat where khoa = 'kt_ncc_dong_bo_luc';
  if v_luc is not null and v_moi is not null and v_luc >= v_moi
     and not exists (select 1 from kt_kiot_ncc k where not exists (select 1 from kt_ncc n where n.kiot_id = k.id)) then return; end if;
  begin
    insert into kt_ncc (kiot_id, ma, ten, sdt, dia_chi, loai, tao_boi)
    select k.id, k.ma, k.ten, k.sdt, k.dia_chi, 'noi_dia', 'Hệ thống'
      from kt_kiot_ncc k where not exists (select 1 from kt_ncc n where n.kiot_id = k.id);
    update kt_ncc n set ma = k.ma, ten = k.ten, sdt = coalesce(k.sdt, n.sdt), dia_chi = coalesce(n.dia_chi, k.dia_chi)
      from kt_kiot_ncc k where k.id = kt_ncc_kiot(n.loai, n.kiot_id) and not n.sua_tay
       and (n.ma is distinct from k.ma or n.ten is distinct from k.ten or (k.sdt is not null and n.sdt is distinct from k.sdt) or (k.dia_chi is not null and n.dia_chi is null));
    update kt_cai_dat set gia_tri = coalesce(v_moi, now())::text, sua_luc = now() where khoa = 'kt_ncc_dong_bo_luc';
    if not found then insert into kt_cai_dat (khoa, gia_tri, sua_luc) values ('kt_ncc_dong_bo_luc', coalesce(v_moi, now())::text, now()); end if;
  exception when others then null;   -- phiên chỉ xem / tranh ghi: bỏ qua, lần sau đồng bộ
  end;
end $function$;
