-- TRANG THEO DÕI ĐƠN ĐẶT HÀNG CHO SALE / CỬA HÀNG (link #dx=…, không đăng nhập) — 18/11/2026. Monsieur Claude
-- Kế toán (anh chuyển): "hoàn thiện giao diện theo dõi đơn hàng cho cửa hàng và sales để các bạn vào link này cập nhật tình hình hàng đặt của mình" +
-- "chi tiết đơn đặt hàng không thấy hình ảnh sản phẩm, thiếu cột STT"; anh: "giao diện cho sale với cửa hàng nhìn, để họ biết đơn đặt hàng đang xử lý tới bước nào".
-- 18/11 anh: "dự kiến hàng về đang lấy sai ngày — 18/11 là ngày NCC có thể gửi hàng từ kho của nó, còn về VN là ngày khác" → po_dong thêm loại PO + lô / cont (ngày về, dự kiến về VN).
-- (1) kt_xem_de_xuat trả thêm anh_kiot {mã: link ảnh Kiot} + người xử lý; (2) kt_dx_anh_ma: ảnh tải lên của đúng đơn theo MÃ BÍ MẬT (Edge kt-chung-tu viec 'xem_dx' ký link 5 phút).

create or replace function public.kt_xem_de_xuat(p_ma text) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $function$
declare d kt_de_xuat_mua := kt_dx_theo_ma(p_ma, false);
begin
  return jsonb_build_object('id', d.id, 'loai', d.loai, 'nguoi', d.nguoi, 'tao_luc', d.tao_luc, 'ngay_can', d.ngay_can, 'uu_tien', d.uu_tien, 'dong', d.dong, 'khach', d.khach,
    'trang_thai', d.trang_thai, 'ly_do', d.ly_do, 'xu_ly_luc', d.xu_ly_luc, 'so_file', d.so_file, 'tai_them', d.tao_luc > now() - interval '3 hours',
    'po', (select so from kt_po where id = d.po_id), 'po_tt', (select trang_thai from kt_po where id = d.po_id), 'po_giao', (select ngay_giao from kt_po where id = d.po_id), 'ncc', d.ncc_ten,
    'po_dong', (select coalesce(jsonb_agg(jsonb_build_object('i', (x->>'dx_i')::int, 'so', p.so, 'tt', p.trang_thai, 'giao', p.ngay_giao, 'loai', p.loai, 'lo', (select jsonb_build_object('ma', l.ma, 'cont', l.so_cont, 'tt', l.trang_thai, 've', l.ngay_ve, 'du_kien', l.ngay_du_kien) from kt_lo_nk_don ld join kt_lo_nk l on l.id = ld.lo_id where ld.po_id = p.id and not ld.da_xoa and not l.da_xoa order by l.id desc limit 1))), '[]')
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

-- 18/11 anh: "đặt nhiều đơn thì trông như nào — làm thành các dòng, ấn ra popup" → danh sách đơn của sale trả thêm số mặt hàng + tình trạng PO từng dòng
-- (bước trên dòng tính cùng cách với popup: mặt hàng chậm nhất), mức gấp, ngày cần.
create or replace function public.kt_xem_de_xuat_ds(p_ds text[]) returns jsonb
language plpgsql stable security definer set search_path to 'public', 'extensions' as $function$
begin
  if coalesce(array_length(p_ds, 1), 0) > 300 then raise exception 'Tối đa 300 mã'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('ma', m, 'id', d.id, 'loai', d.loai, 'tao_luc', d.tao_luc, 'ncc', d.ncc_ten, 'khach', d.khach->>'ten', 'tt', d.trang_thai, 'ly_do', d.ly_do,
      'po', p.so, 'po_tt', p.trang_thai, 'po_giao', p.ngay_giao, 'hang', (select string_agg(coalesce(nullif(e->>'ten', ''), e->>'ma'), ', ') from jsonb_array_elements(d.dong) e),
      'so_dong', jsonb_array_length(coalesce(d.dong, '[]')), 'uu_tien', d.uu_tien, 'ngay_can', d.ngay_can,
      'po_dong', (select coalesce(jsonb_agg(jsonb_build_object('i', (x->>'dx_i')::int, 'tt', p2.trang_thai, 'giao', p2.ngay_giao, 'loai', p2.loai, 'lo', (select jsonb_build_object('ma', l.ma, 'cont', l.so_cont, 've', l.ngay_ve, 'du_kien', l.ngay_du_kien) from kt_lo_nk_don ld join kt_lo_nk l on l.id = ld.lo_id where ld.po_id = p2.id and not ld.da_xoa and not l.da_xoa order by l.id desc limit 1))), '[]')
                    from kt_po p2, jsonb_array_elements(p2.dong) x where not p2.da_xoa and p2.trang_thai <> 'huy' and x->>'dx_id' = d.id::text and x ? 'dx_i')) order by d.id desc)
    from unnest(p_ds) m join kt_de_xuat_mua d on d.ma_hash = encode(digest(m, 'sha256'), 'hex') and not d.da_xoa left join kt_po p on p.id = d.po_id), '[]');
end $function$;
