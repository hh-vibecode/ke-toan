-- ĐƠN KHÁCH ĐẶT TRÊN KIOT ĐÃ CỌC NHƯNG CHƯA GỬI FORM — 18/11/2026. Monsieur Claude
-- Kế toán (anh chuyển): "cái phiếu 12tr ngày 23/10 sale làm trên Kiot rồi mà không thấy kéo sang link theo dõi" (TTDH002972 / DH002972); anh: "link theo dõi là app".
-- Trang Đơn hàng khách đặt trước chỉ có đơn gửi qua form Đặt hàng (DX…) + khách gắn tay trong PO → đơn tạo thẳng trên Kiot đã cọc không hiện.
-- kt_kd_kiot: đơn đặt Kiot còn mở (không Hoàn thành / Huỷ / Đã xoá), tạo từ 01/09/2026, có cọc (trả trên đơn · phiếu TTDH còn hiệu lực · phiếu thu sổ quỹ gắn đơn kt_coc_tt).
-- Trang lọc bỏ đơn đã có DX (khach.ma_don) / đã gắn tay trong PO. Quyền: trang Nhà cung cấp (ncc) như trang Đơn hàng khách đặt.
create or replace function public.kt_kd_kiot(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(jsonb_build_object('ma', o.ma, 'ngay', (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'nv', o.nv_ban, 'khach', o.khach_ten, 'khach_ma', o.khach_ma,
      'cn', o.chi_nhanh, 'tong', o.tong, 'so_mh', o.so_mh, 'gc', o.ghi_chu, 'tt', o.trang_thai_ten,
      'coc', greatest(coalesce(o.da_tra, 0), coalesce(c.t, 0) + coalesce(ct.t, 0)), 'phieu', concat_ws(', ', c.ds, ct.ds)) order by o.ngay desc)
    from kt_kiot_dat_hang o
    left join lateral (select sum(q.so_tien) t, string_agg(q.ma, ', ') ds from kt_kiot_so_quy q
                        where q.ma like 'TT' || o.ma || '%' and q.la_thu and q.trang_thai = '0') c on true
    left join lateral (select sum(q.so_tien) t, string_agg(q.ma, ', ') ds from kt_coc_tt() x join kt_kiot_so_quy q on q.ma = x.ma where x.dat_id = o.id) ct on true
   where o.trang_thai not in (3, 4) and o.ngay >= timestamptz '2026-09-01 00:00+07'
     and greatest(coalesce(o.da_tra, 0), coalesce(c.t, 0) + coalesce(ct.t, 0)) > 0), '[]');
end $$;
revoke all on function public.kt_kd_kiot(text) from public;
grant execute on function public.kt_kd_kiot(text) to anon, authenticated;
