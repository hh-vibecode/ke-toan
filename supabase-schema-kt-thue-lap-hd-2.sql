-- 10/11/2026 kế toán (anh chuyển) — Lập hoá đơn từ kho:
-- (1) "thuế suất cho auto hệ thống tự tính theo đúng công văn thông tư của từng nhóm hàng — có nhóm 8% nhóm 10%" → bảng thuế suất THEO NHÓM
--     (kt_thue_nhom_ts; chưa đặt = mặc định trên trang: nhóm sản phẩm kim loại 10% theo NĐ 174/2025 Phụ lục I, còn lại 8% — kế toán soát, sửa từng nhóm);
-- (4) "file tồn đến hết T9.2026 — cần trừ tồn của toàn bộ hoá đơn đã xuất ra từ T10 đến giờ; khi dịch vụ gửi tồn hết T10 thì đối chiếu, cân lại"
--     → dòng hàng HĐ bán ra công ty THT lấy từ XML meInvoice (Edge kt-meinvoice) vào kt_thue_hd_dong; tồn sổ sách còn = tồn cuối kỳ file
--     − hàng trên HĐ MISA sau ngày chốt kỳ − đơn lập trên app CHƯA xuất HĐ (đơn "Đã xuất HĐ" đã nằm trong HĐ MISA, không trừ 2 lần). — Monsieur Claude

create table if not exists public.kt_thue_nhom_ts (
  hkd text not null, nhom text not null, thue_suat numeric,   -- null = không chịu thuế
  boi text, luc timestamptz default now(), primary key (hkd, nhom));
alter table public.kt_thue_nhom_ts enable row level security;
revoke all on public.kt_thue_nhom_ts from anon, authenticated;

alter table public.kt_thue_don add column if not exists ts_nhom boolean not null default false;   -- thuế suất từng dòng theo nhóm hàng

-- dòng hàng HĐ bán ra (XML meInvoice). tinh_chat: 1 hàng hoá · 2 khuyến mại · 3 chiết khấu · 4 ghi chú
create table if not exists public.kt_thue_hd_dong (
  hd_ma text not null, stt int not null, ngay date, ky_hieu text, so_hd text,
  tinh_chat int, ma text, ten text, dvt text, sl numeric, don_gia numeric, thanh_tien numeric, thue_suat text,
  primary key (hd_ma, stt));
create index if not exists kt_thue_hd_dong_ma on public.kt_thue_hd_dong (upper(ma), ngay);
create table if not exists public.kt_thue_hd_xml (hd_ma text primary key, luc timestamptz default now(), so_dong int, loi text);
alter table public.kt_thue_hd_dong enable row level security; alter table public.kt_thue_hd_xml enable row level security;
revoke all on public.kt_thue_hd_dong, public.kt_thue_hd_xml from anon, authenticated;

-- Edge: HĐ bán ra công ty (có mã MISA) từ p_tu chưa lấy XML (lỗi thì thử lại sau 6 giờ)
create or replace function public.kt_thue_hd_can_xml(p_tu date, p_n int) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('ma', h.ma_ngoai, 'ngay', h.ngay, 'ky_hieu', h.ky_hieu, 'so_hd', h.so_hd)), '[]')
    from (select * from kt_thue_hd h where h.hkd = 'CTY' and h.chieu = 'ra' and h.ngay >= p_tu and coalesce(h.ma_ngoai, '') <> ''
            and not exists (select 1 from kt_thue_hd_xml x where x.hd_ma = h.ma_ngoai and (x.loi is null or x.luc > now() - interval '6 hours'))
          order by h.ngay limit p_n) h
$$;
create or replace function public.kt_thue_hd_luu_dong(p_ma text, p_ds jsonb, p_loi text) returns void
language plpgsql security definer set search_path = public as $$
declare h kt_thue_hd;
begin
  select * into h from kt_thue_hd where ma_ngoai = p_ma limit 1;
  if p_loi is null then
    delete from kt_thue_hd_dong where hd_ma = p_ma;
    insert into kt_thue_hd_dong (hd_ma, stt, ngay, ky_hieu, so_hd, tinh_chat, ma, ten, dvt, sl, don_gia, thanh_tien, thue_suat)
      select p_ma, (d->>'stt')::int, h.ngay, h.ky_hieu, h.so_hd, (d->>'tc')::int, nullif(trim(d->>'ma'), ''), d->>'ten', d->>'dvt',
             (d->>'sl')::numeric, (d->>'dg')::numeric, (d->>'tt')::numeric, d->>'ts'
        from jsonb_array_elements(p_ds) d;
  end if;
  insert into kt_thue_hd_xml (hd_ma, luc, so_dong, loi) values (p_ma, now(), jsonb_array_length(coalesce(p_ds, '[]')), p_loi)
    on conflict (hd_ma) do update set luc = now(), so_dong = excluded.so_dong, loi = excluded.loi;
end $$;
revoke execute on function public.kt_thue_hd_can_xml(date, int) from public, anon, authenticated;
revoke execute on function public.kt_thue_hd_luu_dong(text, jsonb, text) from public, anon, authenticated;
grant execute on function public.kt_thue_hd_can_xml(date, int), public.kt_thue_hd_luu_dong(text, jsonb, text) to service_role;

-- thuế suất theo nhóm: p_ts '0.08' / '0.1' / '0.05' / '0' / 'kct' (không chịu thuế) / '' (bỏ, về mặc định)
create or replace function public.kt_thue_nhom_ts_luu(p_phien text, p_hkd text, p_nhom text, p_ts text) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  if coalesce(p_ts, '') = '' then delete from kt_thue_nhom_ts where hkd = p_hkd and nhom = p_nhom;
  else insert into kt_thue_nhom_ts (hkd, nhom, thue_suat, boi, luc) values (p_hkd, p_nhom, case when p_ts = 'kct' then null else p_ts::numeric end, coalesce(u.ho_ten, u.ten_dang_nhap), now())
         on conflict (hkd, nhom) do update set thue_suat = excluded.thue_suat, boi = excluded.boi, luc = now(); end if;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_thue_nhom_ts', null, 'sua', jsonb_build_object('hkd', p_hkd, 'nhom', p_nhom, 'thue_suat', p_ts));
end $$;
revoke execute on function public.kt_thue_nhom_ts_luu(text, text, text, text) from public;
grant execute on function public.kt_thue_nhom_ts_luu(text, text, text, text) to anon, authenticated;

-- mã hàng của dòng HĐ: ô mã MISA, trống thì từ cuối tên hàng (tên xuất app = nhóm + kích thước + mã)
create or replace function public.kt_thue_ma_dong(p_ma text, p_ten text) returns text language sql immutable as $$
  select upper(coalesce(nullif(trim(p_ma), ''), substring(trim(p_ten) from '([^ ]+)$')))
$$;

create or replace function public.kt_thue_lap_nguon(p_phien text, p_hkd text, p_bo_don bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ky text; v_den date; v_cn text := case p_hkd when 'HT' then 'Đồ thờ Hiền Thủy' when 'CT' then 'Đồ Thờ Chánh Tâm' else 'Tổng kho sỉ Shidai' end; r jsonb;
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  select ky into v_ky from (select distinct ky from kt_thue_xnt where hkd = p_hkd) k order by kt_thue_ky_den(ky) desc nulls last limit 1;
  if v_ky is null then return jsonb_build_object('ky', null, 'ds', '[]'::jsonb, 'nhom', '[]'::jsonb); end if;
  v_den := kt_thue_ky_den(v_ky);
  with dung as (   -- đã dùng sau ngày chốt kỳ
         -- đơn lập trong app CHƯA xuất HĐ (đơn đã xuất nằm trong HĐ bên dưới) — trừ đơn đang sửa
         select upper(d->>'ma') ma, sum((d->>'sl')::numeric) sl from kt_thue_don o, jsonb_array_elements(o.dong) d
          where o.hkd = p_hkd and o.ngay > v_den and o.id is distinct from p_bo_don and o.trang_thai <> 'Đã xuất HĐ' group by 1
         union all   -- 2 hộ: HĐ có mã hàng (3TShop)
         select upper(ma), sum(case chieu when 'ra' then sl else -sl end) from kt_thue_hd
          where hkd = p_hkd and p_hkd <> 'CTY' and ngay > v_den and ma is not null group by 1
         union all   -- công ty THT: dòng hàng HĐ bán ra MISA (XML); HĐ MISA không ghi mã → lấy mã ở cuối tên hàng ("… 155cm BTD0526-02")
         select kt_thue_ma_dong(ma, ten), sum(sl) from kt_thue_hd_dong
          where p_hkd = 'CTY' and ngay > v_den and tinh_chat in (1, 2) group by 1),
       kiot as (
         select upper(k.ma) ma, coalesce(p.ten, n.ten, k.nhom) cha, (e->>'ton')::numeric ton, (e->>'gia_von')::numeric gv
           from kt_kiot_hang k cross join lateral jsonb_array_elements(k.ton) e
           left join kt_kiot_nhom n on n.id = k.nhom_id left join kt_kiot_nhom p on p.id = n.cha_id
          where e->>'cn' = v_cn),
       ss as (
         select x.ma, x.ten, x.dvt, coalesce(nullif(x.gia_nhap, 0), round(x.cuoi_tien / nullif(x.cuoi_sl, 0))) gv,
                x.cuoi_sl - coalesce((select sum(sl) from dung where dung.ma = upper(x.ma)), 0) con,
                coalesce((select sum(sl) from dung where dung.ma = upper(x.ma)), 0) da_xuat,
                k.ton tt, coalesce(case when p_hkd <> 'CTY' then k.cha end, x.chung_loai, '(chưa có nhóm)') nhom
           from kt_thue_xnt x left join kiot k on k.ma = upper(x.ma)
          where x.hkd = p_hkd and x.ky = v_ky)
  select jsonb_build_object('ky', v_ky, 'den', v_den, 'cn', v_cn,
    'ds', coalesce((select jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'dvt', dvt, 'gv', gv, 'con', con, 'da_xuat', da_xuat, 'tt', tt, 'nhom', nhom) order by con * coalesce(gv, 0) desc) from ss), '[]'),
    'nhom', coalesce((select jsonb_agg(jsonb_build_object('nhom', g, 'ss', s, 'tt', t) order by s - t desc) from (
        select coalesce(a.g, b.g) g, coalesce(a.s, 0) s, coalesce(b.t, 0) t
          from (select nhom g, sum(greatest(con, 0) * coalesce(gv, 0)) s from ss group by 1) a
          full join (select cha g, sum(ton * coalesce(gv, 0)) t from kiot where ton > 0 group by 1) b on b.g = a.g) z
       where s > 0), '[]'),
    'ts', coalesce((select jsonb_object_agg(nhom, jsonb_build_object('ts', thue_suat, 'boi', boi, 'luc', luc)) from kt_thue_nhom_ts where hkd = p_hkd), '{}'),
    -- HĐ MISA đã trừ sau ngày chốt kỳ (công ty THT): số HĐ, số dòng, dòng có mã không có trong file tồn, HĐ chưa lấy được dòng hàng
    'hd_tru', case when p_hkd = 'CTY' then jsonb_build_object(
        'so_hd', (select count(distinct hd_ma) from kt_thue_hd_dong where ngay > v_den),
        'so_dong', (select count(*) from kt_thue_hd_dong where ngay > v_den and tinh_chat in (1, 2)),
        'khong_khop', (select count(*) from kt_thue_hd_dong d where ngay > v_den and tinh_chat in (1, 2)
                      and not exists (select 1 from kt_thue_xnt x where x.hkd = 'CTY' and x.ky = v_ky and upper(x.ma) = kt_thue_ma_dong(d.ma, d.ten))),
        'chua_xml', (select count(*) from kt_thue_hd h where h.hkd = 'CTY' and h.chieu = 'ra' and h.ngay > v_den
                      and not exists (select 1 from kt_thue_hd_xml x where x.hd_ma = h.ma_ngoai and x.loi is null))) end) into r;
  return r;
end $$;

-- lưu đơn: thêm ts_nhom (thuế suất từng dòng theo nhóm hàng)
CREATE OR REPLACE FUNCTION public.kt_thue_don_luu(p_phien text, p_don jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
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
      insert into kt_thue_don (hkd, ngay, khach, mst, gia_tri, gom_thue, thue_suat, bien, dong, tien_hang, tien_thue, tong, trang_thai, so_hd, ghi_chu, tao_boi, ts_nhom)
      select p_don->>'hkd', coalesce((p_don->>'ngay')::date, current_date), nullif(trim(p_don->>'khach'), ''), nullif(trim(p_don->>'mst'), ''),
             (p_don->>'gia_tri')::numeric, coalesce((p_don->>'gom_thue')::boolean, true), (p_don->>'thue_suat')::numeric, coalesce((p_don->>'bien')::numeric, 0),
             p_don->'dong', (p_don->>'tien_hang')::numeric, (p_don->>'tien_thue')::numeric, (p_don->>'tong')::numeric,
             coalesce(nullif(p_don->>'trang_thai', ''), 'Nháp'), nullif(trim(p_don->>'so_hd'), ''), nullif(trim(p_don->>'ghi_chu'), ''), u.ho_ten, coalesce((p_don->>'ts_nhom')::boolean, false)
      returning id into v_id;
    else
      update kt_thue_don set hkd = p_don->>'hkd', ngay = coalesce((p_don->>'ngay')::date, ngay), khach = nullif(trim(p_don->>'khach'), ''), mst = nullif(trim(p_don->>'mst'), ''),
             gia_tri = (p_don->>'gia_tri')::numeric, gom_thue = coalesce((p_don->>'gom_thue')::boolean, true), thue_suat = (p_don->>'thue_suat')::numeric,
             bien = coalesce((p_don->>'bien')::numeric, 0), dong = p_don->'dong', tien_hang = (p_don->>'tien_hang')::numeric, tien_thue = (p_don->>'tien_thue')::numeric,
             tong = (p_don->>'tong')::numeric, trang_thai = coalesce(nullif(p_don->>'trang_thai', ''), trang_thai), so_hd = nullif(trim(p_don->>'so_hd'), ''),
             ghi_chu = nullif(trim(p_don->>'ghi_chu'), ''), ts_nhom = coalesce((p_don->>'ts_nhom')::boolean, false), sua_boi = u.ho_ten, sua_luc = now()
       where id = v_id;
      if not found then raise exception 'Không thấy đơn'; end if;
    end if;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_thue_don', v_id, case when v_xoa then 'xoa' when (p_don->>'id') is null then 'them' else 'sua' end, p_don - 'dong');
  return v_id;
end $$;
