-- 26/10/2026 anh (trả lời kế toán): "xử lý riêng cho P&L thôi — add các khoản định kỳ vào và phân loại nó vào riêng P&L để theo dõi hiệu quả, không ảnh hưởng luồng chính".
-- THAY bản "Chi phí tạm tính" sáng 26/10 (supabase-schema-kt-chi-tam-tinh.sql — 0 dòng dữ liệu): bản đó nằm menu Thu chi, nối vào view chung kt_v_chi_ht
-- (Tổng quan / chi phí cơ sở / ngân sách cũng cộng) và Tất toán sửa tháng hạch toán phiếu chi thật → đụng luồng chính. Gỡ hết, làm lại:
--  · KHOẢN ĐỊNH KỲ P&L (kt_pl_dinh_ky): thiết lập 1 lần — tên, loại chi P&L (+ mục con), số tiền / tháng, phân bổ đơn vị, từ tháng – đến tháng.
--      'luon'     : luôn tính (thuê nhà không chi tiền…)
--      'uoc_tinh' : ước tính, bù cho đủ (lương chi tháng sau…): P&L = phiếu thật cùng mục + phần thiếu so với ước tính (= lấy số lớn hơn);
--                   kế toán "Chốt số thật" tháng đó (kt_pl_dinh_ky_chot) → chỉ lấy phiếu thật.
--  · CHỈ trang P&L đọc (kt_pl_dinh_ky_thang) — không phiếu chi, sổ quỹ, số dư, dòng tiền, Tổng quan, ngân sách. Chỉ áp từ T9/2026 (T1–T8 P&L theo 4 file kế toán).
-- — Monsieur Claude

-- 1) gỡ bản tạm tính
select cron.unschedule('kt-tam-tinh-lap') where exists (select 1 from cron.job where jobname = 'kt-tam-tinh-lap');
create or replace view public.kt_v_chi_ht as
 SELECT c.id AS chi_id,
    COALESCE(c.loai_con_id, c.loai_id) AS loai_id,
    COALESCE((pt.value ->> 'thang'::text), c.thang_ht, to_char((COALESCE(c.ngay_su_dung, c.ngay_de_nghi, c.ngay_tt))::timestamp with time zone, 'YYYY-MM'::text)) AS thang,
    ((pb.value ->> 'don_vi_id'::text))::integer AS don_vi_id,
    (COALESCE(((pt.value ->> 'so_tien'::text))::numeric, c.so_tien) * COALESCE((((pb.value ->> 'so_tien'::text))::numeric / NULLIF(c.so_tien, (0)::numeric)), (1)::numeric)) AS tien
   FROM ((kt_chi c
     LEFT JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN ((jsonb_typeof(c.phan_bo_thang) = 'array'::text) AND (jsonb_array_length(c.phan_bo_thang) > 0)) THEN c.phan_bo_thang
            ELSE NULL::jsonb
        END) pt(value) ON (true))
     LEFT JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN ((jsonb_typeof(c.phan_bo) = 'array'::text) AND (jsonb_array_length(c.phan_bo) > 0)) THEN c.phan_bo
            ELSE NULL::jsonb
        END) pb(value) ON (true))
  WHERE ((NOT c.da_xoa) AND (c.trang_thai = ANY (ARRAY['cho_tt'::text, 'da_tt'::text])) AND (NOT c.la_tam_ung) AND (NOT c.khong_hach_toan) AND (c.loai_dn = 'thanh_toan'::text));
create or replace function public.kt_pl_ct(p_phien text, p_loai integer[], p_tu date, p_den date) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
declare v_t0 text := to_char(p_tu, 'YYYY-MM'); v_t1 text := to_char(p_den, 'YYYY-MM');
begin
  perform kt_chan(p_phien, 'pl');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ngay', ngay, 'so', so, 'nd', noi_dung, 'th', thu_huong_ten, 'loai', loai_id,
           'dv', dv, 'tien', tien, 'thang', thang, 'tt', trang_thai) order by ngay desc nulls last, id desc), '[]') from (
    select c.id, coalesce(c.ngay_tt, c.ngay_de_nghi) ngay, coalesce(c.kiot_ma, 'PC' || lpad(c.id::text, 6, '0')) so, c.noi_dung, c.thu_huong_ten, h.loai_id,
           h.don_vi_id dv, h.thang, c.trang_thai, round(sum(h.tien)) tien
      from kt_v_chi_ht h join kt_chi c on c.id = h.chi_id
     where h.loai_id = any(p_loai) and h.thang between v_t0 and v_t1
     group by 1, 2, 3, 4, 5, 6, 7, 8, 9 limit 3000) x);
end $f$;
drop function if exists public.kt_ds_tam_tinh(text, text, text);
drop function if exists public.kt_luu_tam_tinh(text, jsonb);
drop function if exists public.kt_xoa_tam_tinh(text, bigint);
drop function if exists public.kt_tat_toan_goi_y(text, bigint);
drop function if exists public.kt_tat_toan_tam_tinh(text, bigint, bigint);
drop function if exists public.kt_tam_tinh_lap(text);
drop table if exists public.kt_chi_tam_tinh;

-- 2) khoản định kỳ P&L
create table if not exists kt_pl_dinh_ky (
  id bigserial primary key, ten text not null,
  loai_id int not null references kt_loai(id), loai_con_id int references kt_loai(id),
  so_tien numeric not null check (so_tien > 0), phan_bo jsonb not null default '[]',
  tu_thang text not null check (tu_thang ~ '^20[0-9]{2}-(0[1-9]|1[0-2])$'), den_thang text check (den_thang ~ '^20[0-9]{2}-(0[1-9]|1[0-2])$'),
  kieu text not null default 'luon' check (kieu in ('luon', 'uoc_tinh')),
  ghi_chu text, da_xoa boolean not null default false, tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz);
create table if not exists kt_pl_dinh_ky_chot (
  dinh_ky_id bigint not null references kt_pl_dinh_ky(id), thang text not null, chot_boi text, chot_luc timestamptz not null default now(),
  primary key (dinh_ky_id, thang));
alter table kt_pl_dinh_ky enable row level security; alter table kt_pl_dinh_ky_chot enable row level security;
revoke all on kt_pl_dinh_ky, kt_pl_dinh_ky_chot from anon, authenticated;

create or replace function public.kt_pl_dinh_ky_ds(p_phien text) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'pl');
  return (select coalesce(jsonb_agg(to_jsonb(d) || jsonb_build_object('chot', (select coalesce(jsonb_agg(c.thang order by c.thang), '[]') from kt_pl_dinh_ky_chot c where c.dinh_ky_id = d.id))
            order by d.kieu, d.ten), '[]') from kt_pl_dinh_ky d where not d.da_xoa);
end $f$;

-- số định kỳ từng tháng (chỉ từ 2026-09) — dòng theo đơn vị phân bổ; uoc_tinh: thuc = phiếu thật cùng mục (mục con nếu có, không thì cả nhóm loại), them = phần bù
-- mục + mọi cấp con (cây loại chi có mục con nhiều cấp, vd 5.1 → 5.1.x)
create or replace function public.kt_loai_cay(p_id int) returns setof int language sql stable set search_path = public as $f$
  with recursive c as (select p_id id union all select l.id from kt_loai l join c on l.cha_id = c.id) select id from c $f$;

create or replace function public.kt_pl_dinh_ky_thang(p_phien text, p_tu text, p_den text) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'pl');
  return (select coalesce(jsonb_agg(z), '[]') from (
    with th as (select to_char(g, 'YYYY-MM') thang from generate_series((greatest(p_tu, '2026-09') || '-01')::date, (p_den || '-01')::date, interval '1 month') g),
    k as (select d.*, th.thang, coalesce(d.loai_con_id, d.loai_id) muc,
                 exists (select 1 from kt_pl_dinh_ky_chot c where c.dinh_ky_id = d.id and c.thang = th.thang) chot
            from kt_pl_dinh_ky d join th on th.thang >= d.tu_thang and (d.den_thang is null or th.thang <= d.den_thang) where not d.da_xoa),
    t as (select k.*, case when k.kieu = 'uoc_tinh' then coalesce((select sum(h.tien) from kt_v_chi_ht h
                   where h.thang = k.thang and h.loai_id in (select kt_loai_cay(k.muc))), 0) end thuc from k),
    s as (select t.*, case when kieu = 'luon' then so_tien when chot then 0 else greatest(so_tien - thuc, 0) end them from t)
    select s.id, s.ten, s.kieu, s.thang, s.muc loai, s.so_tien, round(s.thuc) thuc, s.chot, round(s.them) them,
           (pb->>'don_vi_id')::int dv, round(case when pb is null then s.them else s.them * (pb->>'so_tien')::numeric / s.so_tien end) tien
      from s left join lateral jsonb_array_elements(case when jsonb_array_length(s.phan_bo) > 0 then s.phan_bo end) pb on true) z);
end $f$;

create or replace function public.kt_pl_dinh_ky_luu(p_phien text, p jsonb) returns bigint
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung; v_id bigint := nullif(p->>'id', '')::bigint; pb jsonb := coalesce(p->'phan_bo', '[]'::jsonb);
begin
  u := kt_chan(p_phien, 'pl', true);
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Nhập số tiền mỗi tháng'; end if;
  if nullif(p->>'loai_id', '') is null then raise exception 'Chọn loại chi'; end if;
  if coalesce(trim(p->>'ten'), '') = '' then raise exception 'Đặt tên khoản'; end if;
  if nullif(p->>'den_thang', '') is not null and p->>'den_thang' < p->>'tu_thang' then raise exception 'Đến tháng phải sau từ tháng'; end if;
  if jsonb_array_length(pb) > 0 and abs((select sum((x->>'so_tien')::numeric) from jsonb_array_elements(pb) x) - (p->>'so_tien')::numeric) > 1 then
    raise exception 'Tổng phân bổ phải bằng số tiền'; end if;
  if v_id is null then
    insert into kt_pl_dinh_ky (ten, loai_id, loai_con_id, so_tien, phan_bo, tu_thang, den_thang, kieu, ghi_chu, tao_boi)
    values (trim(p->>'ten'), (p->>'loai_id')::int, nullif(p->>'loai_con_id', '')::int, (p->>'so_tien')::numeric, pb, p->>'tu_thang', nullif(p->>'den_thang', ''),
            coalesce(nullif(p->>'kieu', ''), 'luon'), nullif(p->>'ghi_chu', ''), u.ho_ten) returning id into v_id;
  else
    update kt_pl_dinh_ky set ten = trim(p->>'ten'), loai_id = (p->>'loai_id')::int, loai_con_id = nullif(p->>'loai_con_id', '')::int, so_tien = (p->>'so_tien')::numeric,
           phan_bo = pb, tu_thang = p->>'tu_thang', den_thang = nullif(p->>'den_thang', ''), kieu = coalesce(nullif(p->>'kieu', ''), kieu),
           ghi_chu = nullif(p->>'ghi_chu', ''), sua_boi = u.ho_ten, sua_luc = now() where id = v_id and not da_xoa;
  end if;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_pl_dinh_ky', case when p->>'id' is null then 'them' else 'sua' end, p || jsonb_build_object('id', v_id));
  return v_id;
end $f$;

create or replace function public.kt_pl_dinh_ky_xoa(p_phien text, p_id bigint) returns void
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'pl', true);
  update kt_pl_dinh_ky set da_xoa = true, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_pl_dinh_ky', 'xoa', jsonb_build_object('id', p_id));
end $f$;

-- chốt / bỏ chốt số thật 1 tháng (khoản ước tính)
create or replace function public.kt_pl_dinh_ky_chot(p_phien text, p_id bigint, p_thang text, p_bo boolean default false) returns void
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'pl', true);
  if p_bo then delete from kt_pl_dinh_ky_chot where dinh_ky_id = p_id and thang = p_thang;
  else insert into kt_pl_dinh_ky_chot (dinh_ky_id, thang, chot_boi) values (p_id, p_thang, u.ho_ten) on conflict do nothing; end if;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_pl_dinh_ky', case when p_bo then 'bo_chot' else 'chot' end, jsonb_build_object('id', p_id, 'thang', p_thang));
end $f$;
