-- 03/11/2026 anh: "kế toán nhập giá trị hoá đơn, nhặt các mã còn tồn cho đủ giá trị rồi copy sang MISA — làm tính năng đó;
-- highlight đề xuất mã tồn thực tế chênh nhiều so với tồn sổ sách; có ô tìm kiếm theo nhóm; có nút lưu, tách tab riêng".
-- Tồn sổ sách = file NXT / 3TShop kỳ mới nhất (kt_thue_xnt) − các đơn lập sau ngày chốt kỳ (kt_thue_don) [2 hộ: ± HĐ có mã sau kỳ].
-- Tồn thực tế = Kiot theo chi nhánh (công ty THT = Tổng kho sỉ Shidai: mã khác mã sổ thuế → so theo nhóm cha Kiot). — Monsieur Claude
create table if not exists public.kt_thue_don (
  id bigserial primary key,
  hkd text not null check (hkd in ('CTY', 'CT', 'HT')),
  ngay date not null default current_date,
  khach text, mst text,
  gia_tri numeric,               -- giá trị kế toán cần lập
  gom_thue boolean not null default true,
  thue_suat numeric,             -- 0.08 · 0.1 · null = không chịu thuế
  bien numeric default 0,        -- % cộng trên giá vốn để ra đơn giá bán mặc định
  dong jsonb not null default '[]',   -- [{ma, ten, dvt, sl, don_gia, thanh_tien}]
  tien_hang numeric, tien_thue numeric, tong numeric,
  trang_thai text not null default 'Nháp' check (trang_thai in ('Nháp', 'Đã xuất HĐ')),
  so_hd text, ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz
);
create index if not exists kt_thue_don_hkd on public.kt_thue_don (hkd, ngay);
alter table public.kt_thue_don enable row level security;
revoke all on public.kt_thue_don from anon, authenticated;

-- ngày cuối của kỳ sổ thuế ('2026-09' tháng · '2026-Q3' quý)
create or replace function public.kt_thue_ky_den(p_ky text) returns date language sql immutable as $$
  select case when p_ky ~ '^\d{4}-Q[1-4]$' then (make_date(left(p_ky, 4)::int, right(p_ky, 1)::int * 3, 1) + interval '1 month' - interval '1 day')::date
              when p_ky ~ '^\d{4}-\d{2}$' then ((p_ky || '-01')::date + interval '1 month' - interval '1 day')::date end
$$;

-- nguồn cho bảng tính: từng mã còn tồn sổ sách + tồn thực tế Kiot; bảng nhóm sổ sách vs thực tế
create or replace function public.kt_thue_lap_nguon(p_phien text, p_hkd text, p_bo_don bigint default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ky text; v_den date; v_cn text := case p_hkd when 'HT' then 'Đồ thờ Hiền Thủy' when 'CT' then 'Đồ Thờ Chánh Tâm' else 'Tổng kho sỉ Shidai' end; r jsonb;
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  select ky into v_ky from (select distinct ky from kt_thue_xnt where hkd = p_hkd) k order by kt_thue_ky_den(ky) desc nulls last limit 1;
  if v_ky is null then return jsonb_build_object('ky', null, 'ds', '[]'::jsonb, 'nhom', '[]'::jsonb); end if;
  v_den := kt_thue_ky_den(v_ky);
  with dung as (   -- đã dùng sau ngày chốt kỳ: đơn lập trong app (trừ đơn đang sửa) + 2 hộ: HĐ có mã hàng
         select upper(d->>'ma') ma, sum((d->>'sl')::numeric) sl from kt_thue_don o, jsonb_array_elements(o.dong) d
          where o.hkd = p_hkd and o.ngay > v_den and o.id is distinct from p_bo_don group by 1
         union all
         select upper(ma), sum(case chieu when 'ra' then sl else -sl end) from kt_thue_hd
          where hkd = p_hkd and p_hkd <> 'CTY' and ngay > v_den and ma is not null group by 1),
       kiot as (
         select upper(k.ma) ma, coalesce(p.ten, n.ten, k.nhom) cha, (e->>'ton')::numeric ton, (e->>'gia_von')::numeric gv
           from kt_kiot_hang k cross join lateral jsonb_array_elements(k.ton) e
           left join kt_kiot_nhom n on n.id = k.nhom_id left join kt_kiot_nhom p on p.id = n.cha_id
          where e->>'cn' = v_cn),
       ss as (
         select x.ma, x.ten, x.dvt, coalesce(nullif(x.gia_nhap, 0), round(x.cuoi_tien / nullif(x.cuoi_sl, 0))) gv,
                x.cuoi_sl - coalesce((select sum(sl) from dung where dung.ma = upper(x.ma)), 0) con,
                k.ton tt, coalesce(case when p_hkd <> 'CTY' then k.cha end, x.chung_loai, '(chưa có nhóm)') nhom
           from kt_thue_xnt x left join kiot k on k.ma = upper(x.ma)
          where x.hkd = p_hkd and x.ky = v_ky)
  select jsonb_build_object('ky', v_ky, 'den', v_den, 'cn', v_cn,
    'ds', coalesce((select jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'dvt', dvt, 'gv', gv, 'con', con, 'tt', tt, 'nhom', nhom) order by con * coalesce(gv, 0) desc) from ss), '[]'),
    'nhom', coalesce((select jsonb_agg(jsonb_build_object('nhom', g, 'ss', s, 'tt', t) order by s - t desc) from (
        select coalesce(a.g, b.g) g, coalesce(a.s, 0) s, coalesce(b.t, 0) t
          from (select nhom g, sum(greatest(con, 0) * coalesce(gv, 0)) s from ss group by 1) a
          full join (select cha g, sum(ton * coalesce(gv, 0)) t from kiot where ton > 0 group by 1) b on b.g = a.g) z
       where s > 0), '[]')) into r;
  return r;
end $$;
revoke execute on function public.kt_thue_lap_nguon(text, text, bigint) from public, anon;
grant execute on function public.kt_thue_lap_nguon(text, text, bigint) to anon, authenticated;

create or replace function public.kt_thue_don_ds(p_phien text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  return coalesce((select jsonb_agg(to_jsonb(d) order by d.ngay desc, d.id desc) from (select * from kt_thue_don order by ngay desc, id desc limit 1000) d), '[]');
end $$;
revoke execute on function public.kt_thue_don_ds(text) from public, anon;
grant execute on function public.kt_thue_don_ds(text) to anon, authenticated;

create or replace function public.kt_thue_don_luu(p_phien text, p_don jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_don->>'id')::bigint; v_xoa boolean := coalesce((p_don->>'xoa')::boolean, false);
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  if v_xoa then
    delete from kt_thue_don where id = v_id;
  else
    if coalesce(p_don->>'hkd', '') not in ('CTY', 'CT', 'HT') then raise exception 'Đơn vị không hợp lệ'; end if;
    if jsonb_typeof(p_don->'dong') <> 'array' or jsonb_array_length(p_don->'dong') = 0 then raise exception 'Đơn chưa có dòng hàng nào'; end if;
    if exists (select 1 from jsonb_array_elements(p_don->'dong') d where coalesce(trim(d->>'ma'), '') = '' or coalesce((d->>'sl')::numeric, 0) <= 0) then
      raise exception 'Mỗi dòng cần mã hàng và số lượng > 0'; end if;
    if v_id is null then
      insert into kt_thue_don (hkd, ngay, khach, mst, gia_tri, gom_thue, thue_suat, bien, dong, tien_hang, tien_thue, tong, trang_thai, so_hd, ghi_chu, tao_boi)
      select p_don->>'hkd', coalesce((p_don->>'ngay')::date, current_date), nullif(trim(p_don->>'khach'), ''), nullif(trim(p_don->>'mst'), ''),
             (p_don->>'gia_tri')::numeric, coalesce((p_don->>'gom_thue')::boolean, true), (p_don->>'thue_suat')::numeric, coalesce((p_don->>'bien')::numeric, 0),
             p_don->'dong', (p_don->>'tien_hang')::numeric, (p_don->>'tien_thue')::numeric, (p_don->>'tong')::numeric,
             coalesce(nullif(p_don->>'trang_thai', ''), 'Nháp'), nullif(trim(p_don->>'so_hd'), ''), nullif(trim(p_don->>'ghi_chu'), ''), u.ho_ten
      returning id into v_id;
    else
      update kt_thue_don set hkd = p_don->>'hkd', ngay = coalesce((p_don->>'ngay')::date, ngay), khach = nullif(trim(p_don->>'khach'), ''), mst = nullif(trim(p_don->>'mst'), ''),
             gia_tri = (p_don->>'gia_tri')::numeric, gom_thue = coalesce((p_don->>'gom_thue')::boolean, true), thue_suat = (p_don->>'thue_suat')::numeric,
             bien = coalesce((p_don->>'bien')::numeric, 0), dong = p_don->'dong', tien_hang = (p_don->>'tien_hang')::numeric, tien_thue = (p_don->>'tien_thue')::numeric,
             tong = (p_don->>'tong')::numeric, trang_thai = coalesce(nullif(p_don->>'trang_thai', ''), trang_thai), so_hd = nullif(trim(p_don->>'so_hd'), ''),
             ghi_chu = nullif(trim(p_don->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
       where id = v_id;
      if not found then raise exception 'Không thấy đơn'; end if;
    end if;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_thue_don', v_id, case when v_xoa then 'xoa' when (p_don->>'id') is null then 'them' else 'sua' end, p_don - 'dong');
  return v_id;
end $$;
revoke execute on function public.kt_thue_don_luu(text, jsonb) from public, anon;
grant execute on function public.kt_thue_don_luu(text, jsonb) to anon, authenticated;

-- sửa kèm: kt_thue_luu_dc chỉ nhận kỳ quý → kho THT (kỳ tháng) không ghi được điều chỉnh
do $$ declare d text := pg_get_functiondef('public.kt_thue_luu_dc'::regproc); begin
  if position('v_ky !~ ''^\d{4}-Q[1-4]$''' in d) > 0 then
    execute replace(d, 'v_ky !~ ''^\d{4}-Q[1-4]$''', 'v_ky !~ ''^\d{4}-(Q[1-4]|\d{2})$''');
  end if;
end $$;
