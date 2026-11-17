-- MÃ KIOT KHÔNG CÓ TIỀN THU = BÁO GIÁ, BỎ QUA — 17/11/2026. Monsieur Claude
-- Anh: "bảo nó sau không cần để ý, và m cũng thế, mã không có tiền thu thì clear đi, khác gì phiếu tạm báo giá đâu" (về 9 mã đơn đặt đã xoá trên Kiot
-- mà trang so khớp app MKT báo "kế toán còn giữ"). Đơn đặt có tiền = trả trên đơn (Kiot, theo bảng kế toán hoặc bảng app MKT) / phiếu cọc TTDH còn hiệu lực /
-- hoá đơn của đơn đã thu tiền. Không có cái nào → không đưa vào lệch / "Kiot không còn" của So khớp 3 bên (kt_dc3_tinh).
create or replace function public.kt_dh_co_tien(p_ma text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from kt_kiot_dat_hang o where o.ma = p_ma and coalesce(o.da_tra, 0) > 0)
      or exists (select 1 from kiot_orders k where k.code = p_ma and coalesce(k.total_payment, 0) > 0)
      or exists (select 1 from kt_kiot_so_quy q where q.ma like 'TT' || p_ma || '%' and q.la_thu and q.trang_thai = '0')
      or exists (select 1 from kt_kiot_dat_hang o join kt_kiot_hoa_don h on (h.dat_hang_id = o.id or (h.dat_hang_id is null and h.ma_dat_hang = o.ma))
                  where o.ma = p_ma and h.trang_thai in (1, 3) and coalesce(h.da_tra, 0) > 0);
$$;
revoke all on function public.kt_dh_co_tien(text) from public, anon, authenticated;

-- kt_dc3_tinh: bản đang chạy + lọc mã không có tiền
CREATE OR REPLACE FUNCTION public.kt_dc3_tinh()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with th as (select to_char(d, 'YYYY-MM') m from generate_series(date '2026-01-01', date_trunc('month', now() at time zone 'Asia/Ho_Chi_Minh')::date, interval '1 month') d),
t0 as (select timestamp '2026-01-01' at time zone 'Asia/Ho_Chi_Minh' tu),
a_hd as (select to_char(ngay at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM') m, ma, trang_thai tt, tong::numeric tong from kt_kiot_hoa_don, t0 where ngay >= t0.tu and coalesce(trang_thai_ten, '') <> 'Đã xoá trên Kiot'),   -- 10/11: bỏ phiếu đã đánh dấu xoá trên Kiot
b_hd as (select to_char(purchase_date at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM') m, code ma, status tt, total::numeric tong from kiot_invoices, t0 where purchase_date >= t0.tu and kiot_da_xoa is null),   -- 17/11: bỏ phiếu app MKT đã đánh dấu xoá trên Kiot
a_dh as (select to_char(ngay at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM') m, ma, trang_thai tt, tong::numeric tong from kt_kiot_dat_hang, t0 where ngay >= t0.tu and coalesce(trang_thai_ten, '') <> 'Đã xoá trên Kiot'),
b_dh as (select to_char(purchase_date at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM') m, code ma, status tt, total::numeric tong from kiot_orders, t0 where purchase_date >= t0.tu and kiot_da_xoa is null),
x_hd as (select ma from kt_kiot_hoa_don where trang_thai_ten = 'Đã xoá trên Kiot'),
x_dh as (select ma from kt_kiot_dat_hang where trang_thai_ten = 'Đã xoá trên Kiot'),
dc as (select distinct on (thang) thang m, luc, so_lech, so_sua, ket_qua k from kt_kiot_doi_chieu where loai = 'thang' order by thang, id desc),
lech0 as (
  select coalesce(a.m, b.m) m, 'hd' loai, coalesce(a.ma, b.ma) ma, a.tt a_tt, a.tong a_tien, b.tt b_tt, b.tong b_tien, exists (select 1 from x_hd where x_hd.ma = coalesce(a.ma, b.ma)) a_xoa
    from a_hd a full join b_hd b on b.ma = a.ma where a.ma is null or b.ma is null or a.tt <> b.tt or a.tong <> b.tong
  union all
  select coalesce(a.m, b.m), 'dh', coalesce(a.ma, b.ma), a.tt, a.tong, b.tt, b.tong, exists (select 1 from x_dh where x_dh.ma = coalesce(a.ma, b.ma))
    from a_dh a full join b_dh b on b.ma = a.ma where a.ma is null or b.ma is null or a.tt <> b.tt or a.tong <> b.tong),
-- 17/11 anh: "mã không có tiền thu thì clear đi, khác gì phiếu tạm báo giá" → bỏ đơn đặt không có tiền + HĐ đã xoá chưa thu đồng nào
lech as (select l.* from lech0 l where not ((l.loai = 'dh' and not kt_dh_co_tien(l.ma))
           or (l.loai = 'hd' and l.a_xoa and not exists (select 1 from kt_kiot_hoa_don h where h.ma = l.ma and coalesce(h.da_tra, 0) > 0)))),
so as (
  select th.m,
    (select jsonb_build_object('so_hd', count(*), 'tien_hd', coalesce(sum(tong), 0)) from a_hd where a_hd.m = th.m and tt in (1, 3)) a1,
    (select jsonb_build_object('so_dh', count(*), 'tien_dh', coalesce(sum(tong), 0)) from a_dh where a_dh.m = th.m) a2,
    (select jsonb_build_object('so_hd', count(*), 'tien_hd', coalesce(sum(tong), 0)) from b_hd where b_hd.m = th.m and tt in (1, 3)) b1,
    (select jsonb_build_object('so_dh', count(*), 'tien_dh', coalesce(sum(tong), 0)) from b_dh where b_dh.m = th.m) b2
  from th)
select jsonb_build_object('luc', now(), 'thang', coalesce(jsonb_agg(jsonb_build_object(
    'm', so.m,
    'kiot', (select jsonb_build_object('luc', dc.luc, 'so_lech', dc.so_lech, 'so_sua', dc.so_sua,
               'so_hd', (select coalesce(sum((v->>'so_hd')::numeric), 0) from jsonb_each(dc.k->'kiot') e(c, v)),
               'tien_hd', (select coalesce(sum((v->>'doanh_thu')::numeric), 0) from jsonb_each(dc.k->'kiot') e(c, v)),
               'so_dh', (dc.k->'dh'->>'kiot')::numeric, 'tien_dh', (dc.k->'dh'->>'tien_kiot')::numeric,
               -- phiếu app còn mà Kiot không còn (đã xoá / đổi) — lần so không tự xoá, chỉ báo
               'thua', (select coalesce(jsonb_agg(v), '[]') from (select jsonb_array_elements_text(coalesce(dc.k->g->'thua', '[]')) v from unnest(array['hd','dh','th','sq','nh']) g) z
                 where not exists (select 1 from kt_kiot_dat_hang d where d.ma = z.v and d.trang_thai_ten = 'Đã xoá trên Kiot')
                   and not exists (select 1 from kt_kiot_hoa_don d where d.ma = z.v and d.trang_thai_ten = 'Đã xoá trên Kiot')
                   and not (z.v like 'DH%' and not kt_dh_co_tien(z.v))),   -- 17/11: đơn đặt không có tiền = báo giá, không báo
               -- đơn đặt báo giá (không tiền) đã xoá trên Kiot: không tính lệch (anh 09/11) nhưng app vẫn đếm → trừ khi so
               'bo', (select coalesce(jsonb_agg(v), '[]') from jsonb_array_elements_text(coalesce(dc.k->'dh'->'thua_bo', '[]')) v
                 where not exists (select 1 from kt_kiot_dat_hang d where d.ma = v and d.trang_thai_ten = 'Đã xoá trên Kiot'))) from dc where dc.m = so.m),
    'kt', so.a1 || so.a2, 'mkt', so.b1 || so.b2,
    'lech', (select coalesce(jsonb_agg(jsonb_build_object('loai', l.loai, 'ma', l.ma, 'a_tt', l.a_tt, 'a_tien', l.a_tien, 'b_tt', l.b_tt, 'b_tien', l.b_tien, 'a_xoa', l.a_xoa) order by l.loai, l.ma), '[]')
               from (select * from lech where lech.m = so.m order by loai, ma limit 100) l),
    'so_lech', (select count(*) from lech where lech.m = so.m)) order by so.m desc), '[]'))
from so
$function$
;
