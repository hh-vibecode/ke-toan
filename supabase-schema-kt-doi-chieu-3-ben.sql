-- 10/11/2026 anh: "tạo 1 log so khớp 3 bên: app MKT, Kiot, app kế toán — làm sao mở link đó xong đưa link cho MKT check định kỳ" + "sửa lại cái đối chiếu Kiot".
-- Mỗi tháng 2026: KIOT = số lần so khớp gần nhất (Edge kt-kiot doi_chieu kéo lại cả tháng từ Kiot: kt_kiot_doi_chieu.ket_qua);
-- APP KẾ TOÁN = kt_kiot_hoa_don / kt_kiot_dat_hang (tính ngay); APP MKT = kiot_invoices / kiot_orders của app MKT (CHỈ ĐỌC, tính ngay).
-- Chỉ số cùng cách lần so Kiot: hoá đơn Hoàn thành + Đang xử lý (trạng thái 1, 3) — số HĐ + tổng tiền; đơn đặt mọi trạng thái — số đơn + tổng tiền.
-- Danh sách mã lệch giữa 2 app (thiếu bên nào / khác trạng thái / khác tiền). Link xem không đăng nhập (#doi-chieu=<mã>) bật / tắt được. — Monsieur Claude
create table if not exists public.kt_dc3_link (
  id int primary key default 1 check (id = 1),
  token text unique, boi text, luc timestamptz
);
alter table public.kt_dc3_link enable row level security;
revoke all on public.kt_dc3_link from anon, authenticated;

create or replace function public.kt_dc3_tinh() returns jsonb
language sql stable security definer set search_path = public as $$
with th as (select to_char(d, 'YYYY-MM') m from generate_series(date '2026-01-01', date_trunc('month', now() at time zone 'Asia/Ho_Chi_Minh')::date, interval '1 month') d),
t0 as (select timestamp '2026-01-01' at time zone 'Asia/Ho_Chi_Minh' tu),
a_hd as (select to_char(ngay at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM') m, ma, trang_thai tt, tong::numeric tong from kt_kiot_hoa_don, t0 where ngay >= t0.tu),
b_hd as (select to_char(purchase_date at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM') m, code ma, status tt, total::numeric tong from kiot_invoices, t0 where purchase_date >= t0.tu),
a_dh as (select to_char(ngay at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM') m, ma, trang_thai tt, tong::numeric tong from kt_kiot_dat_hang, t0 where ngay >= t0.tu),
b_dh as (select to_char(purchase_date at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM') m, code ma, status tt, total::numeric tong from kiot_orders, t0 where purchase_date >= t0.tu),
dc as (select distinct on (thang) thang m, luc, so_lech, so_sua, ket_qua k from kt_kiot_doi_chieu where loai = 'thang' order by thang, id desc),
lech as (
  select coalesce(a.m, b.m) m, 'hd' loai, coalesce(a.ma, b.ma) ma, a.tt a_tt, a.tong a_tien, b.tt b_tt, b.tong b_tien
    from a_hd a full join b_hd b on b.ma = a.ma where a.ma is null or b.ma is null or a.tt <> b.tt or a.tong <> b.tong
  union all
  select coalesce(a.m, b.m), 'dh', coalesce(a.ma, b.ma), a.tt, a.tong, b.tt, b.tong
    from a_dh a full join b_dh b on b.ma = a.ma where a.ma is null or b.ma is null or a.tt <> b.tt or a.tong <> b.tong),
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
               'thua', (select coalesce(jsonb_agg(v), '[]') from (select jsonb_array_elements_text(coalesce(dc.k->g->'thua', '[]')) v from unnest(array['hd','dh','th','sq','nh']) g) z),
               -- đơn đặt báo giá (không tiền) đã xoá trên Kiot: không tính lệch (anh 09/11) nhưng app vẫn đếm → trừ khi so
               'bo', coalesce(dc.k->'dh'->'thua_bo', '[]')) from dc where dc.m = so.m),
    'kt', so.a1 || so.a2, 'mkt', so.b1 || so.b2,
    'lech', (select coalesce(jsonb_agg(jsonb_build_object('loai', l.loai, 'ma', l.ma, 'a_tt', l.a_tt, 'a_tien', l.a_tien, 'b_tt', l.b_tt, 'b_tien', l.b_tien) order by l.loai, l.ma), '[]')
               from (select * from lech where lech.m = so.m order by loai, ma limit 100) l),
    'so_lech', (select count(*) from lech where lech.m = so.m)) order by so.m desc), '[]'))
from so
$$;
revoke execute on function public.kt_dc3_tinh() from public, anon, authenticated;

-- trong app: trang Log so khớp (quyền nhật ký)
create or replace function public.kt_dc3_xem(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l kt_dc3_link;
begin
  perform kt_chan(p_phien, 'nhat_ky');
  select * into l from kt_dc3_link where id = 1;
  return kt_dc3_tinh() || jsonb_build_object('token', l.token, 'token_boi', l.boi, 'token_luc', l.luc);
end $$;

-- bật (tạo mã mới) / tắt link xem online
create or replace function public.kt_dc3_link(p_phien text, p_bat boolean) returns text
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v text;
begin
  u := kt_chan(p_phien, 'nhat_ky', true);
  v := case when p_bat then encode(extensions.gen_random_bytes(18), 'hex') end;
  insert into kt_dc3_link (id, token, boi, luc) values (1, v, case when p_bat then coalesce(u.ho_ten, u.ten_dang_nhap) end, case when p_bat then now() end)
    on conflict (id) do update set token = excluded.token, boi = excluded.boi, luc = excluded.luc;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_dc3_link', 1, case when p_bat then 'mo_link_doi_chieu_3' else 'tat_link_doi_chieu_3' end, null);
  return v;
end $$;

-- link online (không đăng nhập): đúng mã đang bật mới xem được
create or replace function public.kt_dc3_cong_khai(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(length(p_token), 0) < 30 or not exists (select 1 from kt_dc3_link where id = 1 and token = p_token) then
    raise exception 'Link đã bị tắt hoặc không đúng'; end if;
  return kt_dc3_tinh();
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_dc3_xem(text)', 'kt_dc3_link(text,boolean)', 'kt_dc3_cong_khai(text)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop; end $$;
