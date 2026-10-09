-- =========================================================================
-- APP KẾ TOÁN — LUỒNG MỚI 08/10/2026: báo cáo từ Kiot + nhập liệu bổ sung (Monsieur Claude)
-- Báo cáo: Bán hàng · Khách hàng · NCC · Hàng hoá · P&L (thực thu / thực chi) · Quỹ 3 cửa hàng (đối chiếu cuối ngày)
-- Nhập trên app (không có nguồn tự động): Vay & lãi vay · Tài sản.
-- Quyền trang: ban_hang · khach_hang · ncc · hang_hoa · pl · vay · tai_san (kiểm trong kt_chan).
-- =========================================================================

-- ── VAY & LÃI VAY ──────────────────────────────────────────────────────────
create table if not exists public.kt_vay (
  id           bigserial primary key,
  ten          text not null,                       -- vd "Vay VCB hạn mức 2026"
  ben_cho_vay  text,                                -- ngân hàng / cá nhân
  so_tien      numeric(16,0) not null check (so_tien > 0),
  ngay_vay     date not null,
  ngay_dao_han date,
  lai_suat     numeric(6,3),                        -- %/năm
  hinh_thuc    text not null default 'goc_cuoi_ky' check (hinh_thuc in ('goc_cuoi_ky','goc_deu','theo_lich')),
  tai_khoan_id int references kt_tai_khoan(id),     -- tài khoản nhận tiền vay
  ghi_chu      text,
  chung_tu     text[] not null default '{}',
  da_tat_toan  boolean not null default false,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz,
  da_xoa boolean not null default false
);
create table if not exists public.kt_vay_tra (       -- lịch trả / lần trả (gốc + lãi)
  id        bigserial primary key,
  vay_id    bigint not null references kt_vay(id),
  ngay      date not null,
  goc       numeric(16,0) not null default 0,
  lai       numeric(16,0) not null default 0,
  da_tra    boolean not null default false,        -- false = lịch dự kiến, true = đã trả
  ghi_chu   text,
  tao_boi text, tao_luc timestamptz not null default now(), da_xoa boolean not null default false
);

-- ── TÀI SẢN ────────────────────────────────────────────────────────────────
create table if not exists public.kt_tai_san (
  id            bigserial primary key,
  ten           text not null,
  nhom          text,                               -- vd Máy móc · Xe · Nội thất · Thiết bị · Phần mềm
  don_vi_id     int references kt_don_vi(id),        -- cơ sở / bộ phận sử dụng (phân bổ)
  nguyen_gia    numeric(16,0) not null check (nguyen_gia >= 0),
  ngay_mua      date not null,
  so_thang_kh   int not null default 36 check (so_thang_kh >= 0),   -- khấu hao đường thẳng; 0 = không khấu hao
  tinh_trang    text not null default 'dang_dung' check (tinh_trang in ('dang_dung','hong','thanh_ly')),
  ngay_thanh_ly date,
  ghi_chu       text,
  chung_tu      text[] not null default '{}',
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz,
  da_xoa boolean not null default false
);

do $$ declare t text; begin
  foreach t in array array['kt_vay','kt_vay_tra','kt_tai_san'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

create or replace function public.kt_ds_vay(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'vay');
  return coalesce((select jsonb_agg(to_jsonb(v) || jsonb_build_object(
      'lan_tra', coalesce((select jsonb_agg(to_jsonb(t) order by t.ngay) from kt_vay_tra t where t.vay_id = v.id and not t.da_xoa), '[]'),
      'goc_da_tra', coalesce((select sum(goc) from kt_vay_tra t where t.vay_id = v.id and not t.da_xoa and t.da_tra), 0),
      'lai_da_tra', coalesce((select sum(lai) from kt_vay_tra t where t.vay_id = v.id and not t.da_xoa and t.da_tra), 0))
    order by v.da_tat_toan, v.ngay_vay desc) from kt_vay v where not v.da_xoa), '[]');
end $$;

create or replace function public.kt_luu_vay(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint;
begin
  u := kt_chan(p_phien, 'vay', true);
  if v_id is null then
    insert into kt_vay (ten, ben_cho_vay, so_tien, ngay_vay, ngay_dao_han, lai_suat, hinh_thuc, tai_khoan_id, ghi_chu, chung_tu, tao_boi)
    values (trim(p_dong->>'ten'), nullif(trim(p_dong->>'ben_cho_vay'),''), (p_dong->>'so_tien')::numeric, (p_dong->>'ngay_vay')::date,
      (p_dong->>'ngay_dao_han')::date, (p_dong->>'lai_suat')::numeric, coalesce(p_dong->>'hinh_thuc','goc_cuoi_ky'), (p_dong->>'tai_khoan_id')::int,
      nullif(trim(p_dong->>'ghi_chu'),''), coalesce(array(select jsonb_array_elements_text(p_dong->'chung_tu')), '{}'), u.ho_ten) returning id into v_id;
  else
    update kt_vay set ten = trim(p_dong->>'ten'), ben_cho_vay = nullif(trim(p_dong->>'ben_cho_vay'),''), so_tien = (p_dong->>'so_tien')::numeric,
      ngay_vay = (p_dong->>'ngay_vay')::date, ngay_dao_han = (p_dong->>'ngay_dao_han')::date, lai_suat = (p_dong->>'lai_suat')::numeric,
      hinh_thuc = coalesce(p_dong->>'hinh_thuc', hinh_thuc), tai_khoan_id = (p_dong->>'tai_khoan_id')::int, ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''),
      chung_tu = coalesce(array(select jsonb_array_elements_text(p_dong->'chung_tu')), '{}'),
      da_tat_toan = coalesce((p_dong->>'da_tat_toan')::boolean, da_tat_toan), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vay', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

create or replace function public.kt_luu_vay_tra(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint;
begin
  u := kt_chan(p_phien, 'vay', true);
  if v_id is null then
    insert into kt_vay_tra (vay_id, ngay, goc, lai, da_tra, ghi_chu, tao_boi)
    values ((p_dong->>'vay_id')::bigint, (p_dong->>'ngay')::date, coalesce((p_dong->>'goc')::numeric,0), coalesce((p_dong->>'lai')::numeric,0),
      coalesce((p_dong->>'da_tra')::boolean,false), nullif(trim(p_dong->>'ghi_chu'),''), u.ho_ten) returning id into v_id;
  else
    update kt_vay_tra set ngay = (p_dong->>'ngay')::date, goc = coalesce((p_dong->>'goc')::numeric,0), lai = coalesce((p_dong->>'lai')::numeric,0),
      da_tra = coalesce((p_dong->>'da_tra')::boolean,false), ghi_chu = nullif(trim(p_dong->>'ghi_chu'),'') where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vay_tra', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

create or replace function public.kt_ds_tai_san(p_phien text, p_den date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d date := coalesce(p_den, (now() at time zone 'Asia/Ho_Chi_Minh')::date);
begin
  perform kt_chan(p_phien, 'tai_san');
  -- Khấu hao đường thẳng theo tháng: số tháng đã dùng tới ngày d (tối đa so_thang_kh); giá trị còn lại = nguyên giá − khấu hao luỹ kế
  return coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object(
      'kh_thang', case when t.so_thang_kh > 0 then round(t.nguyen_gia / t.so_thang_kh) else 0 end,
      'kh_luy_ke', case when t.so_thang_kh > 0 then least(t.nguyen_gia, round(t.nguyen_gia / t.so_thang_kh *
          least(t.so_thang_kh, greatest(0, (extract(year from age(d, t.ngay_mua)) * 12 + extract(month from age(d, t.ngay_mua)))::int)))) else 0 end)
    order by t.tinh_trang, t.ngay_mua desc) from kt_tai_san t where not t.da_xoa), '[]');
end $$;

create or replace function public.kt_luu_tai_san(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint;
begin
  u := kt_chan(p_phien, 'tai_san', true);
  if v_id is null then
    insert into kt_tai_san (ten, nhom, don_vi_id, nguyen_gia, ngay_mua, so_thang_kh, tinh_trang, ngay_thanh_ly, ghi_chu, chung_tu, tao_boi)
    values (trim(p_dong->>'ten'), nullif(trim(p_dong->>'nhom'),''), (p_dong->>'don_vi_id')::int, (p_dong->>'nguyen_gia')::numeric, (p_dong->>'ngay_mua')::date,
      coalesce((p_dong->>'so_thang_kh')::int,36), coalesce(p_dong->>'tinh_trang','dang_dung'), (p_dong->>'ngay_thanh_ly')::date, nullif(trim(p_dong->>'ghi_chu'),''),
      coalesce(array(select jsonb_array_elements_text(p_dong->'chung_tu')), '{}'), u.ho_ten) returning id into v_id;
  else
    update kt_tai_san set ten = trim(p_dong->>'ten'), nhom = nullif(trim(p_dong->>'nhom'),''), don_vi_id = (p_dong->>'don_vi_id')::int,
      nguyen_gia = (p_dong->>'nguyen_gia')::numeric, ngay_mua = (p_dong->>'ngay_mua')::date, so_thang_kh = coalesce((p_dong->>'so_thang_kh')::int, so_thang_kh),
      tinh_trang = coalesce(p_dong->>'tinh_trang', tinh_trang), ngay_thanh_ly = (p_dong->>'ngay_thanh_ly')::date, ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''),
      chung_tu = coalesce(array(select jsonb_array_elements_text(p_dong->'chung_tu')), '{}'), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_tai_san', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

-- ── BÁO CÁO BÁN HÀNG (Kiot) ────────────────────────────────────────────────
-- Doanh thu = hoá đơn Kiot trạng thái Hoàn thành (1), theo ngày bán; trả hàng trừ riêng. Giá vốn = kt_kiot_hoa_don.gia_von.
create or replace function public.kt_bc_ban_hang(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'ban_hang');
  with hd as (select * from kt_kiot_hoa_don where trang_thai = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
  ct as (select hd.chi_nhanh, hd.nv_ban, d from hd cross join lateral jsonb_array_elements(hd.chi_tiet) d),
  th as (select * from kt_kiot_tra_hang where coalesce(trang_thai,1) = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den)
  select jsonb_build_object(
    'doanh_thu', (select coalesce(sum(tong),0) from hd), 'so_hd', (select count(*) from hd), 'gia_von', (select coalesce(sum(gia_von),0) from hd),
    'tra_hang', (select coalesce(sum(tong_tra),0) from th), 'so_tra', (select count(*) from th),
    'da_thu_hd', (select coalesce(sum(da_tra),0) from hd),
    'theo_cn', (select coalesce(jsonb_agg(jsonb_build_object('cn', chi_nhanh, 'dt', dt, 'gv', gv, 'so', n, 'tra', coalesce((select sum(tong_tra) from th where th.chi_nhanh = x.chi_nhanh),0)) order by dt desc), '[]')
       from (select chi_nhanh, sum(tong) dt, sum(gia_von) gv, count(*) n from hd group by 1) x),
    'theo_ngay', (select coalesce(jsonb_agg(jsonb_build_object('ngay', ng, 'cn', chi_nhanh, 'dt', dt) order by ng), '[]')
       from (select (ngay at time zone 'Asia/Ho_Chi_Minh')::date ng, chi_nhanh, sum(tong) dt from hd group by 1, 2) x),
    'top_sp', (select coalesce(jsonb_agg(x order by x->>'dt' desc), '[]') from (select jsonb_build_object('ma', d->>'ma', 'ten', max(d->>'ten'), 'nhom', max(d->>'nhom'),
         'sl', sum((d->>'sl')::numeric), 'dt', sum((d->>'tien')::numeric)) x from ct group by d->>'ma' order by sum((d->>'tien')::numeric) desc limit 30) y),
    'theo_nhom', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'dt', dt, 'sl', sl) order by dt desc), '[]')
       from (select coalesce(d->>'nhom','(không nhóm)') nhom, sum((d->>'tien')::numeric) dt, sum((d->>'sl')::numeric) sl from ct group by 1) x),
    'theo_nv', (select coalesce(jsonb_agg(jsonb_build_object('nv', nv_ban, 'dt', dt, 'so', n) order by dt desc), '[]')
       from (select coalesce(nv_ban,'(không rõ)') nv_ban, sum(tong) dt, count(*) n from hd group by 1) x),
    -- Phương thức thanh toán: phiếu thu khách trên sổ quỹ Kiot (tiền khách trả + cọc) trong kỳ
    'thanh_toan', (select coalesce(jsonb_agg(jsonb_build_object('pt', pt, 'tien', s, 'so', n) order by s desc), '[]')
       from (select coalesce(phuong_thuc,'Khác') pt, sum(so_tien) s, count(*) n from kt_kiot_so_quy
              where la_thu and trang_thai = '0' and nhom in ('Tiền khách trả','Thu tiền đặt cọc')
                and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1) x),
    'hoa_don', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', ngay, 'cn', chi_nhanh, 'khach', khach_ten, 'nv', nv_ban, 'tong', tong, 'da_tra', da_tra, 'gv', gia_von,
         'so_mat_hang', jsonb_array_length(chi_tiet)) order by ngay desc), '[]') from (select * from hd order by ngay desc limit 300) z)
  ) into r;
  return r;
end $$;

-- ── BÁO CÁO KHÁCH HÀNG (Kiot) ──────────────────────────────────────────────
-- Công nợ = số Kiot đang ghi cho từng khách (dương = khách còn nợ, âm = khách trả trước / mình còn nợ khách).
create or replace function public.kt_bc_khach(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'khach_hang');
  with hd as (select * from kt_kiot_hoa_don where trang_thai = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
  mua as (select khach_id, max(khach_ten) ten, max(khach_ma) ma, sum(tong) dt, count(*) n from hd where khach_id is not null group by 1)
  select jsonb_build_object(
    'tong_khach', (select count(*) from kt_kiot_khach),
    'khach_mua', (select count(*) from mua),
    'khach_moi', (select count(*) from kt_kiot_khach where (tao_kiot at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
    'khach_moi_mua', (select count(*) from mua join kt_kiot_khach k on k.id = mua.khach_id where (k.tao_kiot at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
    'khach_le_dt', (select coalesce(sum(tong),0) from hd where khach_id is null),
    'no_phai_thu', (select coalesce(sum(cong_no),0) from kt_kiot_khach where cong_no > 0),
    'so_khach_no', (select count(*) from kt_kiot_khach where cong_no > 0),
    'tra_truoc', (select coalesce(-sum(cong_no),0) from kt_kiot_khach where cong_no < 0),
    'so_tra_truoc', (select count(*) from kt_kiot_khach where cong_no < 0),
    'top_mua', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'dt', dt, 'so', n,
        'no', (select cong_no from kt_kiot_khach k where k.id = mua.khach_id)) order by dt desc), '[]') from (select * from mua order by dt desc limit 50) mua),
    'top_no', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'sdt', sdt, 'no', cong_no, 'tong_mua', tong_mua) order by cong_no desc), '[]')
        from (select * from kt_kiot_khach where cong_no > 0 order by cong_no desc limit 100) x)
  ) into r;
  return r;
end $$;

-- ── BÁO CÁO NHÀ CUNG CẤP (Kiot) ────────────────────────────────────────────
-- Công nợ NCC lấy nguyên số Kiot (dấu theo Kiot — CHƯA xác nhận âm = mình nợ NCC, xem Cần giải đáp).
create or replace function public.kt_bc_ncc(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'ncc');
  with nh as (select * from kt_kiot_nhap_hang where coalesce(trang_thai,3) <> 4 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den)
  select jsonb_build_object(
    'tong_ncc', (select count(*) from kt_kiot_ncc where hoat_dong),
    'nhap', (select coalesce(sum(tong),0) from nh), 'so_phieu', (select count(*) from nh), 'da_tra', (select coalesce(sum(da_tra),0) from nh),
    'cong_no_tong', (select coalesce(sum(cong_no),0) from kt_kiot_ncc),
    -- anh chốt 09/10/2026: công nợ NCC trên Kiot DƯƠNG = mình nợ NCC; ÂM = NCC nợ mình / mình trả trước
    'no_phai_tra', (select coalesce(sum(cong_no),0) from kt_kiot_ncc where cong_no > 0), 'so_ncc_no', (select count(*) from kt_kiot_ncc where cong_no > 0),
    'tra_truoc', (select coalesce(-sum(cong_no),0) from kt_kiot_ncc where cong_no < 0), 'so_ncc_tra_truoc', (select count(*) from kt_kiot_ncc where cong_no < 0),
    'theo_ncc', (select coalesce(jsonb_agg(jsonb_build_object('ncc', ncc_ten, 'ma', ncc_ma, 'nhap', s, 'so', n, 'da_tra', dt,
        'no', (select cong_no from kt_kiot_ncc c where c.id = x.ncc_id)) order by s desc), '[]')
       from (select ncc_id, max(ncc_ten) ncc_ten, max(ncc_ma) ncc_ma, sum(tong) s, count(*) n, sum(da_tra) dt from nh group by 1) x),
    'cong_no', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'sdt', sdt, 'no', cong_no, 'tong_nhap', tong_nhap) order by abs(cong_no) desc), '[]')
       from (select * from kt_kiot_ncc where cong_no <> 0 order by abs(cong_no) desc limit 100) x),
    'phieu', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', ngay, 'cn', chi_nhanh, 'ncc', ncc_ten, 'tong', tong, 'da_tra', da_tra) order by ngay desc), '[]') from nh)
  ) into r;
  return r;
end $$;

-- ── BÁO CÁO HÀNG HOÁ / TỒN KHO (Kiot) ──────────────────────────────────────
-- Tồn = số Kiot HIỆN TẠI (không phải tồn tại ngày cuối kỳ). Nhập = phiếu nhập trong kỳ; Xuất bán = hoá đơn hoàn thành trong kỳ.
create or replace function public.kt_bc_hang(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'hang_hoa');
  with ban as (select d->>'ma' ma, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1),
  nhap as (select d->>'ma' ma, sum((d->>'sl')::numeric) sl, sum((d->>'sl')::numeric * (d->>'gia')::numeric) gt from kt_kiot_nhap_hang h cross join lateral jsonb_array_elements(h.chi_tiet) d
                where coalesce(h.trang_thai,3) <> 4 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1),
  ton_cn as (select t->>'cn' cn, sum((t->>'ton')::numeric) sl, sum((t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric,0)) gt
               from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where (t->>'ton')::numeric > 0 group by 1)
  select jsonb_build_object(
    'so_mat_hang', (select count(*) from kt_kiot_hang where hoat_dong),
    'mat_hang_con', (select count(*) from kt_kiot_hang where tong_ton > 0),
    'gia_tri_ton', (select coalesce(sum(gt),0) from ton_cn), 'sl_ton', (select coalesce(sum(sl),0) from ton_cn),
    'ton_am', (select count(*) from kt_kiot_hang where tong_ton < 0),
    'ton_cn', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'sl', sl, 'gt', gt) order by gt desc), '[]') from ton_cn),
    'ton_nhom', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'sl', sl, 'gt', gt) order by gt desc), '[]')
       from (select coalesce(nhom,'(không nhóm)') nhom, sum(greatest(tong_ton,0)) sl, sum(greatest(gia_tri_ton,0)) gt from kt_kiot_hang group by 1 having sum(greatest(gia_tri_ton,0)) > 0) x),
    'nhap_ky', (select coalesce(sum(gt),0) from nhap), 'ban_ky', (select coalesce(sum(dt),0) from ban),
    'ban_chay', (select coalesce(jsonb_agg(x order by (x->>'sl')::numeric desc), '[]') from (select jsonb_build_object('ma', b.ma, 'ten', p.ten, 'nhom', p.nhom, 'sl', b.sl, 'dt', b.dt,
         'ton', p.tong_ton, 'nhap', coalesce(n.sl,0)) x from ban b left join kt_kiot_hang p on p.ma = b.ma left join nhap n on n.ma = b.ma order by b.sl desc limit 40) y),
    -- Bán chậm: còn tồn, giá trị tồn lớn, KHÔNG bán được cái nào trong kỳ
    'ban_cham', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'ton', tong_ton, 'gt', gia_tri_ton) order by gia_tri_ton desc), '[]')
       from (select * from kt_kiot_hang p where tong_ton > 0 and hoat_dong and not exists (select 1 from ban b where b.ma = p.ma) order by gia_tri_ton desc limit 40) x)
  ) into r;
  return r;
end $$;

-- ── P&L — THEO THỰC THU / THỰC CHI (anh chốt 08/10) ────────────────────────
-- Từng tháng trong khoảng: thu theo loại thu (đã duyệt, theo ngày thu) · chi theo loại chi (đã thanh toán, theo ngày trả).
-- Kèm số THAM CHIẾU từ Kiot: doanh thu hoá đơn + giá vốn hàng bán (hoá đơn hoàn thành) để so.
create or replace function public.kt_bc_pl(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'pl');
  select jsonb_build_object(
    'thu', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai, 'tien', s)), '[]') from (
        select to_char(t.ngay, 'YYYY-MM') th, l.ten loai, sum(t.so_tien) s from kt_thu t join kt_loai l on l.id = t.loai_id
         where not t.da_xoa and t.trang_thai = 'da_duyet' and t.ngay between p_tu and p_den group by 1, 2) x),
    'chi', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai, 'nhom_bc', nhom_bc, 'tien', s)), '[]') from (
        select to_char(c.ngay_tt, 'YYYY-MM') th, l.ten loai, l.nhom_bc, sum(c.so_tien) s from kt_chi c join kt_loai l on l.id = c.loai_id
         where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between p_tu and p_den group by 1, 2, 3) x),
    'lai_vay', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'lai', s)), '[]') from (
        select to_char(ngay, 'YYYY-MM') th, sum(lai) s from kt_vay_tra where not da_xoa and da_tra and ngay between p_tu and p_den group by 1) x),
    'kiot', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'dt', dt, 'gv', gv)), '[]') from (
        select to_char((ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, sum(tong) dt, sum(gia_von) gv from kt_kiot_hoa_don
         where trang_thai = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1) x),
    'kiot_tra', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'tra', s)), '[]') from (
        select to_char((ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, sum(tong_tra) s from kt_kiot_tra_hang
         where coalesce(trang_thai,1) = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1) x)
  ) into r;
  return r;
end $$;

-- ── QUỸ TIỀN MẶT 3 CỬA HÀNG — đối chiếu cuối ngày (từ sổ quỹ Kiot) ───────────
-- Mỗi chi nhánh, mỗi ngày: thu tiền mặt tại quầy · chi tiền mặt tại quầy · nộp về két / quỹ khác (chuyển rút đi) · nhận thêm (chuyển rút về).
-- Quỹ cuối ngày (phát sinh) = thu − chi − nộp + nhận. Lệch ≠ 0 kéo dài nghĩa là tiền còn giữ ở quầy chưa nộp.
create or replace function public.kt_quy_cua_hang(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'dong_tien');
  return coalesce((select jsonb_agg(jsonb_build_object('ngay', ng, 'cn', chi_nhanh, 'thu', thu, 'chi', chi, 'nop', nop, 'nhan', nhan) order by ng, chi_nhanh) from (
    select (ngay at time zone 'Asia/Ho_Chi_Minh')::date ng, chi_nhanh,
      sum(so_tien) filter (where la_thu and coalesce(nhom,'') <> 'Chuyển rút' and ma !~ '^(TTD_|CTD_)') thu,
      sum(so_tien) filter (where not la_thu and coalesce(nhom,'') <> 'Chuyển rút' and ma !~ '^(TTD_|CTD_)') chi,
      sum(so_tien) filter (where not la_thu and (nhom = 'Chuyển rút' or ma ~ '^CTD_|^CTM|^CNH') and (nhom = 'Chuyển rút')) nop,
      sum(so_tien) filter (where la_thu and nhom = 'Chuyển rút') nhan
    from kt_kiot_so_quy where trang_thai = '0' and phuong_thuc = 'Cash' and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
    group by 1, 2) x), '[]');
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_ds_vay(text)','kt_luu_vay(text,jsonb)','kt_luu_vay_tra(text,jsonb)','kt_ds_tai_san(text,date)','kt_luu_tai_san(text,jsonb)',
    'kt_bc_ban_hang(text,date,date)','kt_bc_khach(text,date,date)','kt_bc_ncc(text,date,date)','kt_bc_hang(text,date,date)','kt_bc_pl(text,date,date)',
    'kt_quy_cua_hang(text,date,date)'] loop
    execute 'revoke execute on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;

-- kt_xoa nhận thêm bảng vay / vay_tra / tai_san (quyền trang vay / tai_san)
create or replace function public.kt_xoa(p_phien text, p_bang text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, case when p_bang = 'cong_no_thu' then 'cong_no' when p_bang = 'vay_tra' then 'vay' else p_bang end, true);
  if p_bang not in ('thu','chi','dieu_chuyen','cong_no','cong_no_thu','sap_tra','vay','vay_tra','tai_san') then raise exception 'Bảng không hợp lệ'; end if;
  execute format('update public.%I set da_xoa = true where id = $1', 'kt_' || p_bang) using p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, 'xoa', null);
end $$;
