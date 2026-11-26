-- 26/11/2026 — Đơn đặt Kiot "Chưa gửi đơn": kế toán hỏi đơn Kiot chỉ giữ hàng có sẵn (ghi chú "Mã hàng sẵn: SP…") thì sao lại hiện trong Đơn đặt hàng.
-- Lưu từng dòng hàng đơn đặt (Edge kt-kiot kéo orderDetails) + trả tồn từng dòng → app chỉ hiện đơn còn mặt hàng phải đặt NCC. — Monsieur Claude
alter table kt_kiot_dat_hang add column if not exists chi_tiet jsonb;
notify pgrst, 'reload schema';

-- kt_kd_kiot: thêm 'ct' = từng dòng hàng {ma, ten, sl, ton (tổng tồn 3 cơ sở), tcn (tồn từng cơ sở ≠ 0)}. Trình duyệt: dòng "hàng sẵn" = mã ghi trong dòng ghi chú
-- có chữ "sẵn" hoặc tổng tồn ≥ SL; đơn không còn dòng nào phải đặt → không hiện trong Đơn đặt hàng. Đơn chưa kéo dòng hàng (ct null) giữ như cũ.
create or replace function public.kt_kd_kiot(p_phien text) returns jsonb language plpgsql stable security definer set search_path = public as $function$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(jsonb_build_object('ma', o.ma, 'ngay', (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'nv', o.nv_ban, 'khach', o.khach_ten, 'khach_ma', o.khach_ma,
      'cn', o.chi_nhanh, 'tong', o.tong, 'so_mh', o.so_mh, 'gc', o.ghi_chu, 'tt', o.trang_thai_ten,
      'coc', greatest(coalesce(o.da_tra, 0), coalesce(c.t, 0) + coalesce(ct.t, 0)), 'phieu', concat_ws(', ', c.ds, ct.ds),
      'ct', (select jsonb_agg(jsonb_build_object('ma', e->>'ma', 'ten', e->>'ten', 'sl', (e->>'sl')::numeric, 'ton', h.tong_ton,
                 'tcn', (select jsonb_agg(jsonb_build_object('cn', z->>'cn', 'ton', (z->>'ton')::numeric)) from jsonb_array_elements(coalesce(h.ton, '[]')) z where coalesce((z->>'ton')::numeric, 0) <> 0)) order by n)
               from jsonb_array_elements(o.chi_tiet) with ordinality d(e, n)
               left join lateral (select h.tong_ton, h.ton from kt_kiot_hang h where upper(h.ma) = upper(e->>'ma') limit 1) h on true)) order by o.ngay desc)
    from kt_kiot_dat_hang o
    left join lateral (select sum(q.so_tien) t, string_agg(q.ma, ', ') ds from kt_kiot_so_quy q
                        where q.ma like 'TT' || o.ma || '%' and q.la_thu and q.trang_thai = '0') c on true
    left join lateral (select sum(q.so_tien) t, string_agg(q.ma, ', ') ds from kt_coc_tt() x join kt_kiot_so_quy q on q.ma = x.ma where x.dat_id = o.id) ct on true
   where o.trang_thai not in (3, 4) and o.ngay >= timestamptz '2026-09-01 00:00+07'
     and greatest(coalesce(o.da_tra, 0), coalesce(c.t, 0) + coalesce(ct.t, 0)) > 0), '[]');
end $function$;
