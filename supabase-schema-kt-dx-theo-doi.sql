-- TRANG THEO DÕI ĐƠN ĐẶT HÀNG CHO SALE / CỬA HÀNG (link #dx=…, không đăng nhập) — 18/11/2026. Monsieur Claude
-- Kế toán (anh chuyển): "hoàn thiện giao diện theo dõi đơn hàng cho cửa hàng và sales để các bạn vào link này cập nhật tình hình hàng đặt của mình" +
-- "chi tiết đơn đặt hàng không thấy hình ảnh sản phẩm, thiếu cột STT"; anh: "giao diện cho sale với cửa hàng nhìn, để họ biết đơn đặt hàng đang xử lý tới bước nào".
-- (1) kt_xem_de_xuat trả thêm anh_kiot {mã: link ảnh Kiot} + người xử lý; (2) kt_dx_anh_ma: ảnh tải lên của đúng đơn theo MÃ BÍ MẬT (Edge kt-chung-tu viec 'xem_dx' ký link 5 phút).

create or replace function public.kt_xem_de_xuat(p_ma text) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $function$
declare d kt_de_xuat_mua := kt_dx_theo_ma(p_ma, false);
begin
  return jsonb_build_object('id', d.id, 'loai', d.loai, 'nguoi', d.nguoi, 'tao_luc', d.tao_luc, 'ngay_can', d.ngay_can, 'uu_tien', d.uu_tien, 'dong', d.dong, 'khach', d.khach,
    'trang_thai', d.trang_thai, 'ly_do', d.ly_do, 'xu_ly_luc', d.xu_ly_luc, 'so_file', d.so_file, 'tai_them', d.tao_luc > now() - interval '3 hours',
    'po', (select so from kt_po where id = d.po_id), 'po_tt', (select trang_thai from kt_po where id = d.po_id), 'po_giao', (select ngay_giao from kt_po where id = d.po_id), 'ncc', d.ncc_ten,
    'po_dong', (select coalesce(jsonb_agg(jsonb_build_object('i', (x->>'dx_i')::int, 'so', p.so, 'tt', p.trang_thai, 'giao', p.ngay_giao)), '[]')
                  from kt_po p, jsonb_array_elements(p.dong) x where not p.da_xoa and p.trang_thai <> 'huy' and x->>'dx_id' = d.id::text and x ? 'dx_i'),
    -- 18/11: ảnh Kiot theo mã hàng (dòng không có ảnh tải lên)
    'anh_kiot', (select coalesce(jsonb_object_agg(h.ma, h.anh), '{}') from kt_kiot_hang h
                  where h.anh is not null and h.anh <> '' and h.ma in (select x->>'ma' from jsonb_array_elements(coalesce(d.dong, '[]')) x where coalesce(x->>'ma', '') <> '')));
end $function$;

-- ảnh / tệp tải lên của 1 đơn, kiểm bằng mã bí mật — CHỈ service_role (Edge kt-chung-tu ký link)
create or replace function public.kt_dx_anh_ma(p_ma text) returns table(id bigint, duong_dan text, ten text, mime text)
language plpgsql stable security definer set search_path to 'public' as $$
declare d kt_de_xuat_mua := kt_dx_theo_ma(p_ma, false);
begin
  return query select c.id, c.duong_dan, c.ten_file, c.mime from kt_chung_tu c where c.bang = 'de_xuat' and c.dong_id = d.id and not c.da_xoa order by c.id;
end $$;
revoke all on function public.kt_dx_anh_ma(text) from public, anon, authenticated;
grant execute on function public.kt_dx_anh_ma(text) to service_role;
