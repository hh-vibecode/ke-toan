-- ════════════════════════════════════════════════════════════════════════════
-- NHẬT KÝ KÉO KIOT + SO KHỚP VỚI KIOT THEO THÁNG (14/10/2026)
-- Anh: "số liệu trên app không khớp Kiot (doanh thu, tồn kho) — trong cài đặt làm log lịch sử kéo + dash so sánh khớp Kiot từng tháng".
-- Soát 14/10: hoá đơn T1–T10 khớp từng mã (số, trạng thái, tiền). LỆCH THẬT ở TỒN KHO: Kiot trả mỗi đơn vị phụ của 1 mặt hàng
-- (thùng / tập / bịch... có masterUnitId, tồn = tồn gốc ÷ quy đổi, giá vốn = giá gốc × quy đổi) thành 1 dòng hàng riêng
-- → app cộng giá trị tồn 2 lần. Sửa: lưu dv_goc_id / quy_doi, báo cáo tồn chỉ cộng dòng đơn vị gốc.
-- Giá vốn hoá đơn (kt_tinh_gia_von) giữ nguyên: dòng hoá đơn bán theo đơn vị phụ dùng giá vốn của chính dòng đó (đã nhân quy đổi) — đúng.
-- Monsieur Claude
-- ════════════════════════════════════════════════════════════════════════════

alter table public.kt_kiot_hang add column if not exists dv_goc_id bigint, add column if not exists quy_doi numeric;
comment on column public.kt_kiot_hang.dv_goc_id is 'Kiot masterUnitId: dòng ĐƠN VỊ PHỤ của mặt hàng này (null = đơn vị gốc). Báo cáo tồn chỉ cộng dòng null.';

-- ── 4 hàm báo cáo tồn: chỉ cộng dòng đơn vị gốc ─────────────────────────────
CREATE OR REPLACE FUNCTION public.kt_bc_hang(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'hang_hoa');
  with ban as (select d->>'ma' ma, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1),
  nhap as (select d->>'ma' ma, sum((d->>'sl')::numeric) sl, sum((d->>'sl')::numeric * (d->>'gia')::numeric) gt from kt_kiot_nhap_hang h cross join lateral jsonb_array_elements(h.chi_tiet) d
                where coalesce(h.trang_thai,3) <> 4 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1),
  ton_cn as (select t->>'cn' cn, sum((t->>'ton')::numeric) sl, sum((t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric,0)) gt
               from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and (t->>'ton')::numeric > 0 group by 1)
  select jsonb_build_object(
    'so_mat_hang', (select count(*) from kt_kiot_hang where hoat_dong and dv_goc_id is null),
    'mat_hang_con', (select count(*) from kt_kiot_hang where tong_ton > 0 and dv_goc_id is null),
    'gia_tri_ton', (select coalesce(sum(gt),0) from ton_cn), 'sl_ton', (select coalesce(sum(sl),0) from ton_cn),
    'ton_am', (select count(*) from kt_kiot_hang where tong_ton < 0 and dv_goc_id is null),
    'ton_cn', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'sl', sl, 'gt', gt) order by gt desc), '[]') from ton_cn),
    'ton_nhom', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'sl', sl, 'gt', gt) order by gt desc), '[]')
       from (select coalesce(nhom,'(không nhóm)') nhom, sum(greatest(tong_ton,0)) sl, sum(greatest(gia_tri_ton,0)) gt from kt_kiot_hang where dv_goc_id is null group by 1 having sum(greatest(gia_tri_ton,0)) > 0) x),
    'nhap_ky', (select coalesce(sum(gt),0) from nhap), 'ban_ky', (select coalesce(sum(dt),0) from ban),
    'ban_chay', (select coalesce(jsonb_agg(x order by (x->>'sl')::numeric desc), '[]') from (select jsonb_build_object('ma', b.ma, 'ten', p.ten, 'nhom', p.nhom, 'sl', b.sl, 'dt', b.dt,
         'ton', p.tong_ton, 'nhap', coalesce(n.sl,0)) x from ban b left join kt_kiot_hang p on p.ma = b.ma left join nhap n on n.ma = b.ma order by b.sl desc limit 40) y),
    -- Bán chậm: còn tồn, giá trị tồn lớn, KHÔNG bán được cái nào trong kỳ
    'ban_cham', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'ton', tong_ton, 'gt', gia_tri_ton) order by gia_tri_ton desc), '[]')
       from (select * from kt_kiot_hang p where tong_ton > 0 and hoat_dong and p.dv_goc_id is null and not exists (select 1 from ban b where b.ma = p.ma) order by gia_tri_ton desc limit 40) x)
  ) into r;
  return r;
end $function$;

CREATE OR REPLACE FUNCTION public.kt_tq_bo_sung(p_phien text, p_tu date, p_den date, p_tu0 date, p_den0 date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'tong_quan');
  with hd as (select * from kt_kiot_hoa_don where trang_thai = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
  hd0 as (select khach_id, sum(tong) dt from kt_kiot_hoa_don where trang_thai = 1 and khach_id is not null
            and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu0 and p_den0 group by 1),
  kh as (select khach_id, max(khach_ma) ma, max(khach_ten) ten, sum(tong) dt, count(*) so, mode() within group (order by chi_nhanh) cn
           from hd where khach_id is not null group by 1 order by sum(tong) desc limit 5),
  ct as (select hd.chi_nhanh, d from hd cross join lateral jsonb_array_elements(hd.chi_tiet) d),
  sp as (select d->>'ma' ma, max(d->>'ten') ten, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt, mode() within group (order by chi_nhanh) cn
           from ct group by 1 order by sum((d->>'tien')::numeric) desc limit 5),
  ban180 as (select distinct h.chi_nhanh cn, d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
               where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_den - 180 and p_den),
  ton as (select t->>'cn' cn, p.ma, (t->>'ton')::numeric sl, (t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0) gt
            from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and (t->>'ton')::numeric > 0)
  select jsonb_build_object(
    'top_kh', (select coalesce(jsonb_agg(jsonb_build_object('id', kh.khach_id, 'ma', kh.ma, 'ten', kh.ten, 'dt', kh.dt, 'so', kh.so, 'cn', kh.cn, 'dt0', coalesce(hd0.dt, 0)) order by kh.dt desc), '[]')
                 from kh left join hd0 on hd0.khach_id = kh.khach_id),
    'top_sp', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'sl', sl, 'dt', dt, 'cn', cn) order by dt desc), '[]') from sp),
    'ton_cs', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'gt', gt, 'so_ma', so_ma, 'lau_so', lau_so, 'lau_gt', lau_gt) order by gt desc), '[]') from (
                 select t.cn, sum(t.gt) gt, count(*) so_ma, count(*) filter (where b.ma is null) lau_so, coalesce(sum(t.gt) filter (where b.ma is null), 0) lau_gt
                   from ton t left join ban180 b on b.cn = t.cn and b.ma = t.ma group by 1) x)) into r;
  return r;
end $function$;

CREATE OR REPLACE FUNCTION public.kt_chup_ton_kho()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ngay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; v_n int; v_ct int := 0;
begin
  insert into kt_ton_kho_ngay (ngay, chi_nhanh, so_mat_hang, so_luong, gia_tri, chup_luc)
  select v_ngay, e->>'cn', count(*) filter (where (e->>'ton')::numeric <> 0), coalesce(sum((e->>'ton')::numeric), 0),
         coalesce(sum((e->>'ton')::numeric * coalesce((e->>'gia_von')::numeric, 0)), 0), now()
    from kt_kiot_hang h, jsonb_array_elements(h.ton) e where h.dv_goc_id is null and e->>'cn' is not null group by e->>'cn'
  on conflict (ngay, chi_nhanh) do update set so_mat_hang = excluded.so_mat_hang, so_luong = excluded.so_luong,
    gia_tri = excluded.gia_tri, chup_luc = excluded.chup_luc;
  get diagnostics v_n = row_count;
  if extract(day from v_ngay + 1) = 1 then   -- ngày cuối tháng → chụp chi tiết
    delete from kt_ton_kho_thang where thang = v_ngay;
    insert into kt_ton_kho_thang (thang, hang_id, ma, ten, chi_nhanh, ton, gia_von)
    select v_ngay, h.id, h.ma, h.ten, e->>'cn', (e->>'ton')::numeric, (e->>'gia_von')::numeric
      from kt_kiot_hang h, jsonb_array_elements(h.ton) e where h.dv_goc_id is null and e->>'cn' is not null and (e->>'ton')::numeric <> 0;
    get diagnostics v_ct = row_count;
  end if;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu)
  values ('Hệ thống', 'kt_ton_kho_ngay', 'chup_ton_kho', jsonb_build_object('ngay', v_ngay, 'chi_nhanh', v_n, 'chi_tiet_cuoi_thang', v_ct));
  return jsonb_build_object('ngay', v_ngay, 'chi_nhanh', v_n, 'chi_tiet_cuoi_thang', v_ct);
end $function$;

CREATE OR REPLACE FUNCTION public.kt_drill(p_phien text, p_loai text, p_khoa text, p_tu date, p_den date, p_cn text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  -- quyền theo trang tương ứng: chi phí → Chi · khách / hoá đơn → Khách hàng · tồn → Hàng hoá · nhóm / mặt hàng → Bán hàng
  perform kt_chan(p_phien, case p_loai when 'cp' then 'chi' when 'kh' then 'khach_hang' when 'hd' then 'khach_hang' when 'ton_lau' then 'hang_hoa' else 'ban_hang' end);
  if p_loai = 'nhom' then
    with ct as (select h.chi_nhanh, d from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                 where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
                   and coalesce(d->>'nhom', '(không nhóm)') = p_khoa and (p_cn is null or h.chi_nhanh = p_cn))
    select coalesce(jsonb_agg(jsonb_build_object('ma', g.ma, 'ten', g.ten, 'sl', g.sl, 'dt', g.dt, 'ton', (select tong_ton from kt_kiot_hang p where p.ma = g.ma limit 1)) order by g.dt desc), '[]') into r
      from (select ct.d->>'ma' ma, max(ct.d->>'ten') ten, sum((ct.d->>'sl')::numeric) sl, sum((ct.d->>'tien')::numeric) dt from ct group by 1 order by 4 desc limit 200) g;
  elsif p_loai = 'sp' then
    select jsonb_build_object(
      'sp', (select jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'dvt', don_vi, 'gia_ban', gia_ban, 'tong_ton', tong_ton, 'gia_tri_ton', gia_tri_ton, 'ton', ton) from kt_kiot_hang where ma = p_khoa limit 1),
      'ban_cs', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'sl', sl, 'dt', dt) order by dt desc), '[]') from (
          select h.chi_nhanh cn, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
           where h.trang_thai = 1 and d->>'ma' = p_khoa and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1) x),
      'hd', (select coalesce(jsonb_agg(x order by x->>'ngay' desc), '[]') from (
          select jsonb_build_object('ma', h.ma, 'ngay', (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', h.chi_nhanh, 'khach', h.khach_ten, 'sl', (d->>'sl')::numeric, 'tien', (d->>'tien')::numeric) x
            from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d where h.trang_thai = 1 and d->>'ma' = p_khoa order by h.ngay desc limit 15) t)) into r;
  elsif p_loai = 'kh' then
    select jsonb_build_object(
      'kh', (select jsonb_build_object('id', id, 'ma', ma, 'ten', ten, 'sdt', sdt, 'cong_no', cong_no, 'tong_mua', tong_mua) from kt_kiot_khach where id = p_khoa::bigint),
      'hd', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'tong', tong, 'da_tra', da_tra, 'nv', nv_ban,
          'so_mh', jsonb_array_length(chi_tiet)) order by ngay desc), '[]') from kt_kiot_hoa_don
         where khach_id = p_khoa::bigint and trang_thai = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den)) into r;
  elsif p_loai = 'hd' then
    select jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'khach', khach_ten, 'khach_id', khach_id, 'nv', nv_ban,
      'tong', tong, 'da_tra', da_tra, 'gia_von', gia_von, 'trang_thai', trang_thai_ten, 'dong', chi_tiet) into r from kt_kiot_hoa_don where ma = p_khoa limit 1;
  elsif p_loai = 'ton_lau' then
    with ban as (select distinct d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai = 1 and h.chi_nhanh = p_cn and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_den - 180 and p_den),
    ton as (select p.ma, p.ten, p.nhom, (t->>'ton')::numeric sl, (t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0) gt
              from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and t->>'cn' = p_cn and (t->>'ton')::numeric > 0)
    select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'sl', sl, 'gt', gt,
        'ban_cuoi', (select max((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date) from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                      where h.trang_thai = 1 and h.chi_nhanh = p_cn and d->>'ma' = ton.ma)) order by gt desc), '[]') into r
      from (select * from ton where ma not in (select ma from ban where ma is not null) order by gt desc limit 100) ton;
  elsif p_loai = 'cp' then
    select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ngay', c.ngay_tt, 'nd', c.noi_dung, 'th', c.thu_huong_ten, 'loai', l.ten, 'tien', coalesce(pb.tien, c.so_tien), 'dv', dv.ten)
        order by coalesce(pb.tien, c.so_tien) desc), '[]') into r
      from kt_chi c join kt_loai l on l.id = c.loai_id
      left join lateral (select (p->>'don_vi_id')::int dv_id, (p->>'so_tien')::numeric tien from jsonb_array_elements(coalesce(c.phan_bo, '[]'::jsonb)) p) pb on true
      left join kt_don_vi dv on dv.id = pb.dv_id
     where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between p_tu and p_den and l.nhom_bc = 'Chi vận hành & quản lí'
       and (coalesce(p_khoa, '') = '' or l.ten = p_khoa)
       and (p_cn is null or (p_cn = '_chung' and coalesce(array_length(dv.kiot_chi_nhanh, 1), 0) = 0) or p_cn = any(dv.kiot_chi_nhanh));
  end if;
  return coalesce(r, 'null'::jsonb);
end $function$;

-- ── Bảng kết quả so khớp (Edge Function kt-kiot ghi bằng service_role) ─────────
-- loai 'thang': thang = 'YYYY-MM'; ket_qua = {kiot:{chi nhánh:{so_hd,tien_hang,doanh_thu,so_tra,tra_hang}}, app:{...},
--               hd:{kiot,app,thieu[],thua[],lech[]}, th:{...}}   (thiếu / lệch đã tự ghi bù ngay sau khi so; thừa chỉ báo)
-- loai 'ton'  : thang = ngày 'YYYY-MM-DD'; ket_qua = {kiot:{cn:{sl,gt,so_ma,am}}, app:{...}, dv_phu, thieu, lech[{ma,cn,app,kiot,gt}], so_dong_lech}
create table if not exists public.kt_kiot_doi_chieu (
  id bigserial primary key,
  luc timestamptz not null default now(),
  nguoi text,
  loai text not null check (loai in ('thang', 'ton')),
  thang text not null,
  khop boolean,
  so_lech int not null default 0,
  so_sua int not null default 0,
  ket_qua jsonb
);
create index if not exists kt_kiot_doi_chieu_loai_thang on public.kt_kiot_doi_chieu (loai, thang, luc desc);
alter table public.kt_kiot_doi_chieu enable row level security;
revoke all on public.kt_kiot_doi_chieu from anon, authenticated;

-- ── Dữ liệu app để so (chỉ Edge Function / service_role) ───────────────────────
create or replace function public.kt_kiot_dc_db(p_tu date, p_den date) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'hd', (select coalesce(jsonb_agg(jsonb_build_array(id, trang_thai, tong,
              (select coalesce(sum((d->>'tien')::numeric), 0) from jsonb_array_elements(chi_tiet) d), chi_nhanh, ma)), '[]')
             from kt_kiot_hoa_don where ngay >= (p_tu::timestamp at time zone 'Asia/Ho_Chi_Minh') and ngay < (p_den::timestamp at time zone 'Asia/Ho_Chi_Minh')),
    'th', (select coalesce(jsonb_agg(jsonb_build_array(id, trang_thai, tong_tra, chi_nhanh, ma)), '[]')
             from kt_kiot_tra_hang where ngay >= (p_tu::timestamp at time zone 'Asia/Ho_Chi_Minh') and ngay < (p_den::timestamp at time zone 'Asia/Ho_Chi_Minh')));
$$;
create or replace function public.kt_kiot_ton_db() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_array(id, dv_goc_id, ton)), '[]') from kt_kiot_hang;
$$;
-- Trang web bấm "Kéo ngay" / "So lại": Edge Function gọi hàm này kiểm phiên + quyền Nhật ký (sửa) → trả họ tên để ghi nhật ký
create or replace function public.kt_quyen_keo(p_phien text) returns text
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'nhat_ky', true);
  return coalesce(u.ho_ten, u.ten_dang_nhap);
end $$;
revoke execute on function public.kt_kiot_dc_db(date, date), public.kt_kiot_ton_db(), public.kt_quyen_keo(text) from public, anon, authenticated;
grant execute on function public.kt_kiot_dc_db(date, date), public.kt_kiot_ton_db(), public.kt_quyen_keo(text) to service_role;

-- ── Trang Cài đặt → Nhật ký kéo Kiot ───────────────────────────────────────────
-- lich: các lịch pg_cron kt-* · chay: 150 lần chạy gần nhất (kéo Kiot / so khớp / chụp tồn / meInvoice) ·
-- thang: lần so mới nhất của từng tháng · ton: 30 lần so tồn gần nhất
create or replace function public.kt_ds_keo_kiot(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'nhat_ky');
  return jsonb_build_object(
    'lich', (select coalesce(jsonb_agg(jsonb_build_object('ten', jobname, 'lich', schedule, 'bat', active, 'than', command ~ 'x-kt-cron') order by jobname), '[]')
               from (select jobname, schedule, active, command::text command from cron.job where jobname like 'kt-%') j),
    'chay', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'luc', luc, 'nguoi', nguoi, 'viec', hanh_dong, 'kq', du_lieu) order by id desc), '[]')
               from (select * from kt_nhat_ky where hanh_dong in ('keo_kiot', 'keo_kiot_loi', 'doi_chieu_kiot', 'chup_ton_kho', 'keo_meinvoice')
                     order by id desc limit 150) n),
    'thang', (select coalesce(jsonb_agg(to_jsonb(d) order by d.thang desc), '[]')
               from (select distinct on (thang) * from kt_kiot_doi_chieu where loai = 'thang' order by thang, luc desc) d),
    'ton', (select coalesce(jsonb_agg(to_jsonb(d) order by d.luc desc), '[]')
               from (select * from kt_kiot_doi_chieu where loai = 'ton' order by luc desc limit 30) d));
end $$;
-- Dải trạng thái (banner) trên các trang dùng số Kiot: lần kéo gần nhất + lần so khớp gần nhất. Ai đăng nhập cũng xem được.
create or replace function public.kt_kiot_trang_thai(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien);
  return jsonb_build_object(
    'keo', (select jsonb_build_object('luc', luc, 'loi', hanh_dong = 'keo_kiot_loi', 'thong_bao', du_lieu->>'loi') from kt_nhat_ky
             where hanh_dong in ('keo_kiot', 'keo_kiot_loi') order by id desc limit 1),
    'keo_ok', (select max(luc) from kt_nhat_ky where hanh_dong = 'keo_kiot'),
    'thang', (select coalesce(jsonb_agg(jsonb_build_object('thang', thang, 'luc', luc, 'khop', khop, 'so_lech', so_lech, 'so_sua', so_sua) order by thang desc), '[]')
               from (select distinct on (thang) * from kt_kiot_doi_chieu where loai = 'thang' order by thang, luc desc) d),
    'ton', (select jsonb_build_object('luc', luc, 'khop', khop, 'so_lech', so_lech) from kt_kiot_doi_chieu where loai = 'ton' order by luc desc limit 1));
end $$;
revoke execute on function public.kt_ds_keo_kiot(text), public.kt_kiot_trang_thai(text) from public;
grant execute on function public.kt_ds_keo_kiot(text), public.kt_kiot_trang_thai(text) to anon, authenticated;

-- ── Lịch so khớp tự động: 23:50 VN mỗi ngày (sau kéo đầy đủ hàng 23:20 + chụp tồn 23:40) — tháng này + tháng trước ──
-- (chạy bằng scripts/trien-khai-doi-chieu.js — khoá KT_CRON_KEY không nằm trong file này)
