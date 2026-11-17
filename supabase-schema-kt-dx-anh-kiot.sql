-- ẢNH SẢN PHẨM KIOT CHO PO TẠO TỪ ĐƠN KHÁCH ĐẶT (17/11/2026, kế toán: "đơn khách hàng đặt khi tạo PO … không thấy được ảnh sản phẩm"). Monsieur Claude
-- kt_kiot_hang.anh = ảnh đầu tiên của mã trên Kiot (Edge kt-kiot ghi khi kéo hàng; lịch kéo đầy đủ hàng đêm điền cho mọi mã).
-- kt_dx_ds trả thêm anh_kiot từng dòng → nút Tạo PO gắn ảnh Kiot vào dòng PO khi cửa hàng không tải ảnh mẫu.
alter table public.kt_kiot_hang add column if not exists anh text;

CREATE OR REPLACE FUNCTION public.kt_dx_ds(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'loai', d.loai, 'nguoi', d.nguoi, 'ncc', d.ncc_ten, 'bo_phan', (select ten from kt_don_vi where id = d.bo_phan_id), 'ngay_can', d.ngay_can,
      'uu_tien', d.uu_tien, 'khach', d.khach, 'ghi_chu', d.ghi_chu, 'trang_thai', d.trang_thai, 'ly_do', d.ly_do, 'xu_ly_boi', d.xu_ly_boi, 'xu_ly_luc', d.xu_ly_luc, 'tao_luc', d.tao_luc,
      'po_id', d.po_id, 'po', (select so from kt_po where id = d.po_id),
      'po_dong', (select coalesce(jsonb_agg(jsonb_build_object('i', (x->>'dx_i')::int, 'po_id', p.id, 'so', p.so, 'tt', p.trang_thai, 'ncc', p.ncc_ten, 'giao', p.ngay_giao,
          'lo', (select jsonb_build_object('id', l.id, 'ma', l.ma, 'cont', l.so_cont, 'tt', l.trang_thai, 've', coalesce(l.ngay_ve, l.ngay_du_kien)) from kt_lo_nk_don ld join kt_lo_nk l on l.id = ld.lo_id
                  where ld.po_id = p.id and not ld.da_xoa and not l.da_xoa order by l.id desc limit 1))), '[]')
         from kt_po p, jsonb_array_elements(p.dong) x where not p.da_xoa and p.trang_thai <> 'huy' and x->>'dx_id' = d.id::text and x ? 'dx_i'),
      'anh', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ten', c.ten_file, 'mime', c.mime) order by c.id), '[]') from kt_chung_tu c where c.bang = 'de_xuat' and c.dong_id = d.id and not c.da_xoa),
      'dong', (select coalesce(jsonb_agg(e || jsonb_build_object('ton', (select h.ton from kt_kiot_hang h where h.ma = e->>'ma' limit 1), 'ten_kiot', (select h.ten from kt_kiot_hang h where h.ma = e->>'ma' limit 1), 'anh_kiot', (select h.anh from kt_kiot_hang h where h.ma = e->>'ma' and h.anh is not null limit 1),
        'ncc_gy', case when coalesce(e->>'ma', '') <> '' then (select jsonb_build_object('ten', n.ncc_ten, 'ma', n.ncc_ma, 'gia', (c->>'gia')::numeric, 'ngay', (n.ngay at time zone 'Asia/Ho_Chi_Minh')::date)
          from kt_kiot_nhap_hang n, jsonb_array_elements(n.chi_tiet) c where n.chi_tiet @> jsonb_build_array(jsonb_build_object('ma', e->>'ma')) and c->>'ma' = e->>'ma'
           and n.trang_thai is distinct from 4 and n.ncc_ten is not null order by n.ngay desc limit 1) end)), '[]')
               from jsonb_array_elements(d.dong) e)) order by (d.trang_thai = 'cho_duyet') desc, (d.uu_tien = 'gap') desc, d.id desc)
    from kt_de_xuat_mua d where not d.da_xoa and (d.trang_thai = 'cho_duyet' or d.tao_luc > now() - interval '120 days')), '[]');
end $function$;
