-- =========================================================================
-- APP KẾ TOÁN — bảng + hàm kt_* (Monsieur Claude, 05/10/2026)
-- Thay 2 Google Sheet: "Quản lý dòng tiền" (thu / chi / điều chuyển / công nợ / dashboard) và "Đề nghị thanh toán".
--
-- Bảo mật: trang nằm trên github.io công khai, dữ liệu tài chính nhạy cảm → bảng kt_* bật RLS, KHÔNG policy nào
-- (anon không đọc thẳng). Trang chỉ gọi hàm kt_* kèm MÃ TRUY CẬP; hàm kiểm mã (băm bcrypt) rồi mới đọc / ghi
-- bằng quyền chủ hàm. Mỗi người 1 mã riêng (để nhật ký ghi được ai làm gì).
-- Logic tính số nằm ở hàm kt_bao_cao / kt_dong_tien — trang "Cài đặt > Logic" diễn giải đúng các luật này,
-- sửa luật ở đây thì sửa luôn trang Logic.
-- =========================================================================

create extension if not exists pgcrypto with schema extensions;

-- ── Người dùng + cấu hình ───────────────────────────────────────────────────
create table if not exists public.kt_nguoi_dung (
  id         serial primary key,
  ten        text not null unique,
  vai_tro    text not null default 'quan_tri' check (vai_tro in ('quan_tri','ke_toan','xem')),
  ma_hash    text not null,
  hoat_dong  boolean not null default true,
  tao_luc    timestamptz not null default now(),
  doi_ma_luc timestamptz
);

-- ── Danh mục ───────────────────────────────────────────────────────────────
create table if not exists public.kt_tai_khoan (
  id           serial primary key,
  ten          text not null unique,             -- tên hiển thị, vd "VCB CTY - <số TK>"
  loai         text not null default 'ngan_hang' check (loai in ('ngan_hang','tien_mat','vay','khac')),
  ton_dau      numeric(16,0) not null default 0, -- tồn tại ngày mốc
  ngay_ton_dau date not null default date '2026-08-01',
  ten_cu       text[] not null default '{}',     -- các cách ghi cũ trên sheet (để chuyển dữ liệu cũ)
  kiot_ma      text[] not null default '{}',     -- tài khoản tương ứng bên Kiot (số TK / tên) — ghép phiếu thu Kiot
  thu_tu       int not null default 100,
  hoat_dong    boolean not null default true
);

create table if not exists public.kt_don_vi (       -- cơ sở / bộ phận
  id         serial primary key,
  ten        text not null unique,
  la_co_so   boolean not null default true,   -- hiện trong "đơn vị chịu chi phí" + báo cáo theo cơ sở
  la_bo_phan boolean not null default false,  -- hiện trong "bộ phận đề nghị"
  ten_cu     text[] not null default '{}',
  kiot_chi_nhanh text[] not null default '{}', -- chi nhánh Kiot tương ứng — ghép phiếu thu Kiot về cơ sở
  thu_tu     int not null default 100,
  hoat_dong  boolean not null default true
);

create table if not exists public.kt_loai (         -- loại thu / loại chi
  id        serial primary key,
  nhom      text not null check (nhom in ('thu','chi')),
  ten       text not null,
  nhom_bc   text,                                  -- nhóm trên báo cáo: Chi nhập hàng / Chi vận hành / ...
  cach_chia text not null default 'rieng' check (cach_chia in ('rieng','ty_le_thu')),
  thu_tu    int not null default 100,
  hoat_dong boolean not null default true,
  unique (nhom, ten)
);

-- ── Nghiệp vụ ──────────────────────────────────────────────────────────────
create table if not exists public.kt_thu (
  id           bigserial primary key,
  ngay         date not null,
  noi_dung     text not null,
  so_tien      numeric(16,0) not null check (so_tien > 0),
  don_vi_id    int references kt_don_vi(id),
  tai_khoan_id int not null references kt_tai_khoan(id),
  loai_id      int not null references kt_loai(id),
  ghi_chu      text,
  trang_thai   text not null default 'da_duyet' check (trang_thai in ('cho_duyet','da_duyet','tu_choi')),
  nguon        text not null default 'tay' check (nguon in ('tay','kiot','sheet_cu')),
  ma_nguon     text unique,                        -- mã phiếu Kiot / dòng sheet cũ (chống trùng khi đồng bộ)
  tao_boi      text, tao_luc timestamptz not null default now(),
  sua_boi      text, sua_luc timestamptz,
  da_xoa       boolean not null default false
);
create index if not exists kt_thu_ngay_idx on kt_thu(ngay) where not da_xoa;

create table if not exists public.kt_chi (
  id             bigserial primary key,
  -- Bước 1: đề nghị
  ngay_de_nghi   date not null default (now() at time zone 'Asia/Ho_Chi_Minh')::date,
  nguoi_de_nghi  text not null,
  bo_phan_id     int references kt_don_vi(id),
  noi_dung       text not null,
  ngay_su_dung   date,
  so_tien        numeric(16,0) not null check (so_tien > 0),
  thu_huong_ten  text, thu_huong_nh text, thu_huong_stk text,
  phan_bo        jsonb not null default '[]',      -- [{"don_vi_id":1,"so_tien":100}] — tổng = so_tien
  han_tt         date,
  co_hd_do       boolean not null default false,
  ghi_chu        text,
  chung_tu       text[] not null default '{}',     -- link hoá đơn / báo giá / hình ảnh
  -- Bước 3: duyệt · Bước 4: thanh toán
  trang_thai     text not null default 'cho_duyet'
                 check (trang_thai in ('cho_duyet','tu_choi','cho_tt','da_tt','tu_choi_tt')),
  nguoi_duyet    text, duyet_luc timestamptz,
  ngay_tt        date,
  tai_khoan_id   int references kt_tai_khoan(id),
  loai_id        int references kt_loai(id),
  unc            text,                             -- link uỷ nhiệm chi
  hd_do_nhan     boolean not null default false, ngay_nhan_hd date,
  kiot           text not null default 'khong' check (kiot in ('khong','da_tao','khong_tao')),
  kiot_ly_do     text,
  nguon          text not null default 'app' check (nguon in ('app','sheet_cu')),
  ma_nguon       text unique,
  tao_boi        text, tao_luc timestamptz not null default now(),
  sua_boi        text, sua_luc timestamptz,
  da_xoa         boolean not null default false,
  constraint kt_chi_tt_du check (trang_thai <> 'da_tt' or (ngay_tt is not null and tai_khoan_id is not null and loai_id is not null))
);
create index if not exists kt_chi_ngay_tt_idx on kt_chi(ngay_tt) where not da_xoa;
create index if not exists kt_chi_tt_idx on kt_chi(trang_thai) where not da_xoa;

create table if not exists public.kt_dieu_chuyen (
  id          bigserial primary key,
  ngay        date not null,
  noi_dung    text not null default 'Điều chuyển giữa các tài khoản',
  so_tien     numeric(16,0) not null check (so_tien > 0),
  tk_di_id    int not null references kt_tai_khoan(id),
  tk_nhan_id  int not null references kt_tai_khoan(id),
  ghi_chu     text,
  kiot        text not null default 'khong' check (kiot in ('khong','da_tao','khong_tao')),
  kiot_ly_do  text,
  da_xac_nhan boolean not null default false, xac_nhan_boi text, xac_nhan_luc timestamptz,
  nguon       text not null default 'app' check (nguon in ('app','sheet_cu')),
  ma_nguon    text unique,
  tao_boi     text, tao_luc timestamptz not null default now(),
  sua_boi     text, sua_luc timestamptz,
  da_xoa      boolean not null default false,
  constraint kt_dc_khac_tk check (tk_di_id <> tk_nhan_id)
);
create index if not exists kt_dc_ngay_idx on kt_dieu_chuyen(ngay) where not da_xoa;

create table if not exists public.kt_cong_no (
  id         bigserial primary key,
  ngay       date not null,                        -- ngày giao dịch cuối
  don_vi_id  int references kt_don_vi(id),
  khach      text not null,
  so_tien    numeric(16,0) not null default 0,     -- phát sinh
  tra_hang   numeric(16,0) not null default 0,
  phan_loai  text not null default 'no' check (phan_loai in ('cod','no','no_npp','cho_xu_ly','tra_hang')),
  ghi_chu    text,
  nguon      text not null default 'app' check (nguon in ('app','sheet_cu')),
  ma_nguon   text unique,
  tao_boi    text, tao_luc timestamptz not null default now(),
  sua_boi    text, sua_luc timestamptz,
  da_xoa     boolean not null default false
);
create table if not exists public.kt_cong_no_thu (
  id          bigserial primary key,
  cong_no_id  bigint not null references kt_cong_no(id),
  ngay        date not null,
  so_tien     numeric(16,0) not null check (so_tien > 0),
  ghi_chu     text,
  tao_boi     text, tao_luc timestamptz not null default now(),
  da_xoa      boolean not null default false
);

create table if not exists public.kt_ton_thuc_te (  -- số dư thực tế (sao kê / đếm két) để đối soát
  tai_khoan_id int not null references kt_tai_khoan(id),
  ngay         date not null,
  so_tien      numeric(16,0) not null,
  ghi_boi      text, ghi_luc timestamptz not null default now(),
  primary key (tai_khoan_id, ngay)
);

create table if not exists public.kt_sap_tra (      -- các khoản sắp phải trả (lương, vay, BHXH, NCC...)
  id       bigserial primary key,
  noi_dung text not null,
  so_tien  numeric(16,0) not null,
  han      date,
  da_tra   boolean not null default false,
  ghi_chu  text,
  tao_boi  text, tao_luc timestamptz not null default now(),
  da_xoa   boolean not null default false
);

create table if not exists public.kt_nhat_ky (
  id        bigserial primary key,
  luc       timestamptz not null default now(),
  nguoi     text,
  bang      text,
  dong_id   bigint,
  hanh_dong text,
  du_lieu   jsonb
);
create index if not exists kt_nhat_ky_luc_idx on kt_nhat_ky(luc desc);

-- Sổ quỹ Kiot — LUỒNG KÉO RIÊNG của app kế toán (anh chốt 05/10: không dùng chung luồng MKT/Sale; 3 tiếng / lần).
-- Job kt-kiot (GitHub Actions) ghi bảng này bằng khoá quản trị; phiếu THU hợp lệ được chép sang kt_thu (nguon='kiot').
-- Phiếu CHI bên Kiot KHÔNG chép sang kt_chi (khoản chi đã đi qua đề nghị trên app) — chỉ dùng đối chiếu nhánh 4A.
create table if not exists public.kt_kiot_so_quy (
  id           bigint primary key,                 -- id phiếu bên Kiot
  ma           text not null,                      -- mã phiếu (PT / PC / TT...)
  ngay         timestamptz not null,
  chi_nhanh    text,
  la_thu       boolean not null,
  so_tien      numeric(16,0) not null,
  phuong_thuc  text,                               -- Cash / Transfer / Card ...
  tai_khoan    text,                               -- tài khoản nhận / chi bên Kiot
  doi_tac      text,
  nhom         text,                               -- loại thu chi bên Kiot
  noi_dung     text,
  chung_tu_goc text,                               -- mã hoá đơn / đơn đặt liên quan
  trang_thai   text,
  goc          jsonb,                              -- bản ghi gốc Kiot (để soát khi cần)
  sua_luc_kiot timestamptz,
  keo_luc      timestamptz not null default now()
);
create index if not exists kt_kiot_so_quy_ngay_idx on kt_kiot_so_quy(ngay);

-- RLS: bật, KHÔNG policy → anon / authenticated không đọc ghi thẳng được.
do $$ declare t text; begin
  foreach t in array array['kt_nguoi_dung','kt_tai_khoan','kt_don_vi','kt_loai','kt_thu','kt_chi','kt_dieu_chuyen',
    'kt_cong_no','kt_cong_no_thu','kt_ton_thuc_te','kt_sap_tra','kt_nhat_ky','kt_kiot_so_quy'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ── Kiểm mã ────────────────────────────────────────────────────────────────
-- Trả về người dùng khớp mã; sai mã thì chậm 0,8s (chống dò) rồi báo 28P01 (PostgREST trả 403).
-- p_can: 'xem' (mọi vai trò) · 'ghi' (quan_tri, ke_toan) · 'quan_tri'.
create or replace function public.kt_chan(p_ma text, p_can text default 'xem') returns kt_nguoi_dung
language plpgsql security definer set search_path = public, extensions as $$
declare u kt_nguoi_dung;
begin
  if coalesce(length(p_ma), 0) >= 6 then
    select * into u from kt_nguoi_dung where hoat_dong and crypt(p_ma, ma_hash) = ma_hash limit 1;
  end if;
  if u.id is null then
    perform pg_sleep(0.8);
    raise exception 'Sai mã truy cập' using errcode = '28P01';
  end if;
  if p_can = 'quan_tri' and u.vai_tro <> 'quan_tri'
     or p_can = 'ghi' and u.vai_tro not in ('quan_tri','ke_toan') then
    raise exception 'Mã này không có quyền làm việc này' using errcode = '42501';
  end if;
  return u;
end $$;

create or replace function public.kt_ghi_nhat_ky(p_nguoi text, p_bang text, p_id bigint, p_hd text, p_dl jsonb)
returns void language sql security definer set search_path = public as $$
  insert into kt_nhat_ky (nguoi, bang, dong_id, hanh_dong, du_lieu) values (p_nguoi, p_bang, p_id, p_hd, p_dl);
$$;

create or replace function public.kt_dang_nhap(p_ma text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_ma);
  return jsonb_build_object('ten', u.ten, 'vai_tro', u.vai_tro);
end $$;

create or replace function public.kt_doi_ma(p_ma text, p_ma_moi text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_ma);
  if length(coalesce(p_ma_moi, '')) < 8 then raise exception 'Mã mới phải từ 8 ký tự'; end if;
  if exists (select 1 from kt_nguoi_dung where id <> u.id and crypt(p_ma_moi, ma_hash) = ma_hash) then
    raise exception 'Mã này trùng mã người khác, chọn mã khác';
  end if;
  update kt_nguoi_dung set ma_hash = crypt(p_ma_moi, gen_salt('bf')), doi_ma_luc = now() where id = u.id;
  perform kt_ghi_nhat_ky(u.ten, 'kt_nguoi_dung', u.id, 'doi_ma', null);
end $$;

-- ── Người dùng (quản trị) ──────────────────────────────────────────────────
create or replace function public.kt_ds_nguoi_dung(p_ma text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_ma, 'quan_tri');
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'vai_tro', vai_tro, 'hoat_dong', hoat_dong,
    'tao_luc', tao_luc, 'doi_ma_luc', doi_ma_luc) order by id) from kt_nguoi_dung), '[]');
end $$;

-- p_dong: {id?, ten, vai_tro, hoat_dong, ma_moi?} — ma_moi để trống = giữ mã cũ (người mới bắt buộc có mã).
create or replace function public.kt_luu_nguoi_dung(p_ma text, p_dong jsonb) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare u kt_nguoi_dung; v_id int; v_ma text := nullif(trim(p_dong->>'ma_moi'), '');
begin
  u := kt_chan(p_ma, 'quan_tri');
  if v_ma is not null and length(v_ma) < 8 then raise exception 'Mã phải từ 8 ký tự'; end if;
  if v_ma is not null and exists (select 1 from kt_nguoi_dung where id is distinct from (p_dong->>'id')::int
      and crypt(v_ma, ma_hash) = ma_hash) then raise exception 'Mã này trùng mã người khác'; end if;
  if (p_dong->>'id') is null then
    if v_ma is null then raise exception 'Người mới cần mã truy cập'; end if;
    insert into kt_nguoi_dung (ten, vai_tro, ma_hash) values (trim(p_dong->>'ten'),
      coalesce(p_dong->>'vai_tro', 'xem'), crypt(v_ma, gen_salt('bf'))) returning id into v_id;
  else
    v_id := (p_dong->>'id')::int;
    if v_id = u.id and (coalesce((p_dong->>'hoat_dong')::boolean, true) = false or p_dong->>'vai_tro' <> 'quan_tri') then
      raise exception 'Không tự khoá hoặc tự hạ quyền của chính mình';
    end if;
    update kt_nguoi_dung set ten = trim(p_dong->>'ten'), vai_tro = p_dong->>'vai_tro',
      hoat_dong = coalesce((p_dong->>'hoat_dong')::boolean, true),
      ma_hash = case when v_ma is null then ma_hash else crypt(v_ma, gen_salt('bf')) end,
      doi_ma_luc = case when v_ma is null then doi_ma_luc else now() end
     where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ten, 'kt_nguoi_dung', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end,
    p_dong - 'ma_moi' || jsonb_build_object('doi_ma', v_ma is not null));
  return v_id;
end $$;

-- ── Danh mục ───────────────────────────────────────────────────────────────
create or replace function public.kt_danh_muc(p_ma text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_ma);
  return jsonb_build_object(
    'toi', jsonb_build_object('ten', u.ten, 'vai_tro', u.vai_tro),
    'tai_khoan', coalesce((select jsonb_agg(to_jsonb(t) order by t.thu_tu, t.id) from kt_tai_khoan t), '[]'),
    'don_vi',    coalesce((select jsonb_agg(to_jsonb(d) order by d.thu_tu, d.id) from kt_don_vi d), '[]'),
    'loai',      coalesce((select jsonb_agg(to_jsonb(l) order by l.nhom, l.thu_tu, l.id) from kt_loai l), '[]'));
end $$;

-- p_bang: 'tai_khoan' | 'don_vi' | 'loai'. Không xoá danh mục (đã có phiếu dùng) — chỉ tắt hoat_dong.
create or replace function public.kt_luu_danh_muc(p_ma text, p_bang text, p_dong jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id int := (p_dong->>'id')::int;
begin
  u := kt_chan(p_ma, 'quan_tri');
  if coalesce(trim(p_dong->>'ten'), '') = '' then raise exception 'Thiếu tên'; end if;
  if p_bang = 'tai_khoan' then
    if v_id is null then
      insert into kt_tai_khoan (ten, loai, ton_dau, ngay_ton_dau, thu_tu, hoat_dong)
      values (trim(p_dong->>'ten'), coalesce(p_dong->>'loai','ngan_hang'), coalesce((p_dong->>'ton_dau')::numeric,0),
        coalesce((p_dong->>'ngay_ton_dau')::date, date '2026-08-01'), coalesce((p_dong->>'thu_tu')::int,100),
        coalesce((p_dong->>'hoat_dong')::boolean,true)) returning id into v_id;
    else
      update kt_tai_khoan set ten = trim(p_dong->>'ten'), loai = coalesce(p_dong->>'loai', loai),
        ton_dau = coalesce((p_dong->>'ton_dau')::numeric, ton_dau),
        ngay_ton_dau = coalesce((p_dong->>'ngay_ton_dau')::date, ngay_ton_dau),
        thu_tu = coalesce((p_dong->>'thu_tu')::int, thu_tu), hoat_dong = coalesce((p_dong->>'hoat_dong')::boolean, hoat_dong),
        kiot_ma = case when p_dong ? 'kiot_ma' then array(select jsonb_array_elements_text(p_dong->'kiot_ma')) else kiot_ma end
       where id = v_id;
    end if;
  elsif p_bang = 'don_vi' then
    if v_id is null then
      insert into kt_don_vi (ten, la_co_so, la_bo_phan, thu_tu, hoat_dong)
      values (trim(p_dong->>'ten'), coalesce((p_dong->>'la_co_so')::boolean,true), coalesce((p_dong->>'la_bo_phan')::boolean,false),
        coalesce((p_dong->>'thu_tu')::int,100), coalesce((p_dong->>'hoat_dong')::boolean,true)) returning id into v_id;
    else
      update kt_don_vi set ten = trim(p_dong->>'ten'), la_co_so = coalesce((p_dong->>'la_co_so')::boolean, la_co_so),
        la_bo_phan = coalesce((p_dong->>'la_bo_phan')::boolean, la_bo_phan),
        thu_tu = coalesce((p_dong->>'thu_tu')::int, thu_tu), hoat_dong = coalesce((p_dong->>'hoat_dong')::boolean, hoat_dong),
        kiot_chi_nhanh = case when p_dong ? 'kiot_chi_nhanh'
          then array(select jsonb_array_elements_text(p_dong->'kiot_chi_nhanh')) else kiot_chi_nhanh end
       where id = v_id;
    end if;
  elsif p_bang = 'loai' then
    if v_id is null then
      insert into kt_loai (nhom, ten, nhom_bc, cach_chia, thu_tu, hoat_dong)
      values (p_dong->>'nhom', trim(p_dong->>'ten'), nullif(trim(p_dong->>'nhom_bc'),''), coalesce(p_dong->>'cach_chia','rieng'),
        coalesce((p_dong->>'thu_tu')::int,100), coalesce((p_dong->>'hoat_dong')::boolean,true)) returning id into v_id;
    else
      update kt_loai set ten = trim(p_dong->>'ten'), nhom_bc = nullif(trim(p_dong->>'nhom_bc'),''),
        cach_chia = coalesce(p_dong->>'cach_chia', cach_chia), thu_tu = coalesce((p_dong->>'thu_tu')::int, thu_tu),
        hoat_dong = coalesce((p_dong->>'hoat_dong')::boolean, hoat_dong)
       where id = v_id;
    end if;
  else
    raise exception 'Danh mục không hợp lệ';
  end if;
  perform kt_ghi_nhat_ky(u.ten, 'kt_' || p_bang, v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

-- ── Đọc danh sách phiếu theo khoảng ngày ───────────────────────────────────
-- p_bang: 'thu' | 'chi' | 'dieu_chuyen' | 'cong_no' | 'sap_tra'. Chi lọc theo ngày đề nghị HOẶC ngày thanh toán
-- (để phiếu đề nghị tháng trước, trả tháng này vẫn hiện); phiếu chưa xong (chờ duyệt / chờ TT) luôn hiện.
-- Công nợ: hiện mọi khoản còn nợ + khoản phát sinh trong kỳ.
create or replace function public.kt_ds(p_ma text, p_bang text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_ma);
  if p_bang = 'thu' then
    return coalesce((select jsonb_agg(to_jsonb(t) order by t.ngay desc, t.id desc) from kt_thu t
      where not da_xoa and ngay between p_tu and p_den), '[]');
  elsif p_bang = 'chi' then
    return coalesce((select jsonb_agg(to_jsonb(c) order by coalesce(c.ngay_tt, c.ngay_de_nghi) desc, c.id desc) from kt_chi c
      where not da_xoa and (ngay_de_nghi between p_tu and p_den or ngay_tt between p_tu and p_den
        or trang_thai in ('cho_duyet','cho_tt'))), '[]');
  elsif p_bang = 'dieu_chuyen' then
    return coalesce((select jsonb_agg(to_jsonb(d) order by d.ngay desc, d.id desc) from kt_dieu_chuyen d
      where not da_xoa and ngay between p_tu and p_den), '[]');
  elsif p_bang = 'cong_no' then
    return coalesce((select jsonb_agg(x order by x->>'ngay' desc) from (
      select to_jsonb(n) || jsonb_build_object('da_thu', coalesce(t.da_thu, 0), 'lan_thu', coalesce(t.lan, '[]'::jsonb),
        'con_no', n.so_tien - n.tra_hang - coalesce(t.da_thu, 0)) x
      from kt_cong_no n
      left join lateral (select sum(so_tien) da_thu, jsonb_agg(jsonb_build_object('id', id, 'ngay', ngay, 'so_tien', so_tien,
          'ghi_chu', ghi_chu) order by ngay) lan from kt_cong_no_thu where cong_no_id = n.id and not da_xoa) t on true
      where not n.da_xoa and (n.ngay between p_tu and p_den or n.so_tien - n.tra_hang - coalesce(t.da_thu, 0) <> 0)) s), '[]');
  elsif p_bang = 'sap_tra' then
    return coalesce((select jsonb_agg(to_jsonb(s) order by s.da_tra, s.han nulls last) from kt_sap_tra s where not da_xoa), '[]');
  end if;
  raise exception 'Bảng không hợp lệ';
end $$;

-- ── Ghi phiếu ──────────────────────────────────────────────────────────────
create or replace function public.kt_luu_thu(p_ma text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint;
begin
  u := kt_chan(p_ma, 'ghi');
  if v_id is null then
    insert into kt_thu (ngay, noi_dung, so_tien, don_vi_id, tai_khoan_id, loai_id, ghi_chu, trang_thai, tao_boi)
    values ((p_dong->>'ngay')::date, trim(p_dong->>'noi_dung'), (p_dong->>'so_tien')::numeric, (p_dong->>'don_vi_id')::int,
      (p_dong->>'tai_khoan_id')::int, (p_dong->>'loai_id')::int, nullif(trim(p_dong->>'ghi_chu'),''),
      coalesce(p_dong->>'trang_thai','da_duyet'), u.ten) returning id into v_id;
  else
    update kt_thu set ngay = (p_dong->>'ngay')::date, noi_dung = trim(p_dong->>'noi_dung'), so_tien = (p_dong->>'so_tien')::numeric,
      don_vi_id = (p_dong->>'don_vi_id')::int, tai_khoan_id = (p_dong->>'tai_khoan_id')::int, loai_id = (p_dong->>'loai_id')::int,
      ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''), trang_thai = coalesce(p_dong->>'trang_thai', trang_thai),
      sua_boi = u.ten, sua_luc = now()
     where id = v_id and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ten, 'kt_thu', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

-- Chi: lưu cả đề nghị lẫn duyệt / thanh toán trong 1 hàm. Luật:
--   · phan_bo trống → gán 100% cho bộ phận đề nghị (nếu bộ phận đó cũng là cơ sở) — trang bắt chọn nên hiếm.
--   · da_tt bắt buộc có ngày TT + tài khoản chi + loại chi (ràng buộc kt_chi_tt_du).
--   · kiot = 'khong_tao' bắt buộc có lý do.
create or replace function public.kt_luu_chi(p_ma text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_cu kt_chi; v_tt text := p_dong->>'trang_thai';
  v_pb jsonb := coalesce(p_dong->'phan_bo', '[]'::jsonb); v_tong numeric;
begin
  u := kt_chan(p_ma, 'ghi');
  if jsonb_array_length(v_pb) > 0 then
    select sum((x->>'so_tien')::numeric) into v_tong from jsonb_array_elements(v_pb) x;
    if v_tong <> (p_dong->>'so_tien')::numeric then
      raise exception 'Tổng phân bổ (%) khác số tiền chi (%)', v_tong, p_dong->>'so_tien';
    end if;
  end if;
  if p_dong->>'kiot' = 'khong_tao' and coalesce(trim(p_dong->>'kiot_ly_do'), '') = '' then
    raise exception 'Không tạo phiếu Kiot thì phải ghi lý do';
  end if;
  if v_id is not null then select * into v_cu from kt_chi where id = v_id and not da_xoa; end if;
  if v_id is null then
    insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, thu_huong_nh,
      thu_huong_stk, phan_bo, han_tt, co_hd_do, ghi_chu, chung_tu, tao_boi)
    values (coalesce((p_dong->>'ngay_de_nghi')::date, (now() at time zone 'Asia/Ho_Chi_Minh')::date),
      coalesce(nullif(trim(p_dong->>'nguoi_de_nghi'),''), u.ten), (p_dong->>'bo_phan_id')::int, trim(p_dong->>'noi_dung'),
      (p_dong->>'ngay_su_dung')::date, (p_dong->>'so_tien')::numeric, nullif(trim(p_dong->>'thu_huong_ten'),''),
      nullif(trim(p_dong->>'thu_huong_nh'),''), nullif(trim(p_dong->>'thu_huong_stk'),''), v_pb, (p_dong->>'han_tt')::date,
      coalesce((p_dong->>'co_hd_do')::boolean,false), nullif(trim(p_dong->>'ghi_chu'),''),
      coalesce(array(select jsonb_array_elements_text(p_dong->'chung_tu')), '{}'), u.ten)
    returning id into v_id;
    v_tt := coalesce(v_tt, 'cho_duyet');
  else
    if v_cu.id is null then raise exception 'Không tìm thấy phiếu chi %', v_id; end if;
    update kt_chi set ngay_de_nghi = coalesce((p_dong->>'ngay_de_nghi')::date, ngay_de_nghi),
      nguoi_de_nghi = coalesce(nullif(trim(p_dong->>'nguoi_de_nghi'),''), nguoi_de_nghi), bo_phan_id = (p_dong->>'bo_phan_id')::int,
      noi_dung = trim(p_dong->>'noi_dung'), ngay_su_dung = (p_dong->>'ngay_su_dung')::date, so_tien = (p_dong->>'so_tien')::numeric,
      thu_huong_ten = nullif(trim(p_dong->>'thu_huong_ten'),''), thu_huong_nh = nullif(trim(p_dong->>'thu_huong_nh'),''),
      thu_huong_stk = nullif(trim(p_dong->>'thu_huong_stk'),''), phan_bo = v_pb, han_tt = (p_dong->>'han_tt')::date,
      co_hd_do = coalesce((p_dong->>'co_hd_do')::boolean,false), ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''),
      chung_tu = coalesce(array(select jsonb_array_elements_text(p_dong->'chung_tu')), '{}'),
      sua_boi = u.ten, sua_luc = now()
     where id = v_id;
  end if;
  -- Phần duyệt / thanh toán
  update kt_chi set
    trang_thai   = coalesce(v_tt, trang_thai),
    nguoi_duyet  = case when v_tt in ('tu_choi','cho_tt','da_tt') and (v_cu.id is null or v_cu.trang_thai = 'cho_duyet') then u.ten else nguoi_duyet end,
    duyet_luc    = case when v_tt in ('tu_choi','cho_tt','da_tt') and (v_cu.id is null or v_cu.trang_thai = 'cho_duyet') then now() else duyet_luc end,
    ngay_tt      = coalesce((p_dong->>'ngay_tt')::date, case when v_tt = 'da_tt' then ngay_tt end),
    tai_khoan_id = coalesce((p_dong->>'tai_khoan_id')::int, tai_khoan_id),
    loai_id      = coalesce((p_dong->>'loai_id')::int, loai_id),
    unc          = coalesce(nullif(trim(p_dong->>'unc'),''), unc),
    hd_do_nhan   = coalesce((p_dong->>'hd_do_nhan')::boolean, hd_do_nhan),
    ngay_nhan_hd = coalesce((p_dong->>'ngay_nhan_hd')::date, ngay_nhan_hd),
    kiot         = coalesce(p_dong->>'kiot', kiot),
    kiot_ly_do   = coalesce(nullif(trim(p_dong->>'kiot_ly_do'),''), kiot_ly_do)
   where id = v_id;
  perform kt_ghi_nhat_ky(u.ten, 'kt_chi', v_id, case when (p_dong->>'id') is null then 'them' else coalesce('trang_thai:' || v_tt, 'sua') end, p_dong);
  return v_id;
end $$;

create or replace function public.kt_luu_dieu_chuyen(p_ma text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_xn boolean := (p_dong->>'da_xac_nhan')::boolean;
begin
  u := kt_chan(p_ma, 'ghi');
  if p_dong->>'kiot' = 'khong_tao' and coalesce(trim(p_dong->>'kiot_ly_do'), '') = '' then
    raise exception 'Không tạo phiếu Kiot thì phải ghi lý do';
  end if;
  if v_id is null then
    insert into kt_dieu_chuyen (ngay, noi_dung, so_tien, tk_di_id, tk_nhan_id, ghi_chu, kiot, kiot_ly_do, tao_boi)
    values ((p_dong->>'ngay')::date, coalesce(nullif(trim(p_dong->>'noi_dung'),''), 'Điều chuyển giữa các tài khoản'),
      (p_dong->>'so_tien')::numeric, (p_dong->>'tk_di_id')::int, (p_dong->>'tk_nhan_id')::int, nullif(trim(p_dong->>'ghi_chu'),''),
      coalesce(p_dong->>'kiot','khong'), nullif(trim(p_dong->>'kiot_ly_do'),''), u.ten) returning id into v_id;
  else
    update kt_dieu_chuyen set ngay = (p_dong->>'ngay')::date, noi_dung = coalesce(nullif(trim(p_dong->>'noi_dung'),''), noi_dung),
      so_tien = (p_dong->>'so_tien')::numeric, tk_di_id = (p_dong->>'tk_di_id')::int, tk_nhan_id = (p_dong->>'tk_nhan_id')::int,
      ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''), kiot = coalesce(p_dong->>'kiot', kiot),
      kiot_ly_do = nullif(trim(p_dong->>'kiot_ly_do'),''), sua_boi = u.ten, sua_luc = now()
     where id = v_id and not da_xoa;
  end if;
  if v_xn is not null then
    update kt_dieu_chuyen set da_xac_nhan = v_xn, xac_nhan_boi = case when v_xn then u.ten end,
      xac_nhan_luc = case when v_xn then now() end where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ten, 'kt_dieu_chuyen', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

create or replace function public.kt_luu_cong_no(p_ma text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint;
begin
  u := kt_chan(p_ma, 'ghi');
  if v_id is null then
    insert into kt_cong_no (ngay, don_vi_id, khach, so_tien, tra_hang, phan_loai, ghi_chu, tao_boi)
    values ((p_dong->>'ngay')::date, (p_dong->>'don_vi_id')::int, trim(p_dong->>'khach'), coalesce((p_dong->>'so_tien')::numeric,0),
      coalesce((p_dong->>'tra_hang')::numeric,0), coalesce(p_dong->>'phan_loai','no'), nullif(trim(p_dong->>'ghi_chu'),''), u.ten)
    returning id into v_id;
  else
    update kt_cong_no set ngay = (p_dong->>'ngay')::date, don_vi_id = (p_dong->>'don_vi_id')::int, khach = trim(p_dong->>'khach'),
      so_tien = coalesce((p_dong->>'so_tien')::numeric,0), tra_hang = coalesce((p_dong->>'tra_hang')::numeric,0),
      phan_loai = coalesce(p_dong->>'phan_loai', phan_loai), ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''),
      sua_boi = u.ten, sua_luc = now()
     where id = v_id and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ten, 'kt_cong_no', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

create or replace function public.kt_thu_hoi_no(p_ma text, p_cong_no_id bigint, p_ngay date, p_so_tien numeric, p_ghi_chu text)
returns bigint language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint;
begin
  u := kt_chan(p_ma, 'ghi');
  insert into kt_cong_no_thu (cong_no_id, ngay, so_tien, ghi_chu, tao_boi)
  values (p_cong_no_id, p_ngay, p_so_tien, nullif(trim(p_ghi_chu),''), u.ten) returning id into v_id;
  perform kt_ghi_nhat_ky(u.ten, 'kt_cong_no_thu', v_id, 'them',
    jsonb_build_object('cong_no_id', p_cong_no_id, 'ngay', p_ngay, 'so_tien', p_so_tien));
  return v_id;
end $$;

create or replace function public.kt_luu_sap_tra(p_ma text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint;
begin
  u := kt_chan(p_ma, 'ghi');
  if v_id is null then
    insert into kt_sap_tra (noi_dung, so_tien, han, da_tra, ghi_chu, tao_boi)
    values (trim(p_dong->>'noi_dung'), (p_dong->>'so_tien')::numeric, (p_dong->>'han')::date,
      coalesce((p_dong->>'da_tra')::boolean,false), nullif(trim(p_dong->>'ghi_chu'),''), u.ten) returning id into v_id;
  else
    update kt_sap_tra set noi_dung = trim(p_dong->>'noi_dung'), so_tien = (p_dong->>'so_tien')::numeric, han = (p_dong->>'han')::date,
      da_tra = coalesce((p_dong->>'da_tra')::boolean,false), ghi_chu = nullif(trim(p_dong->>'ghi_chu'),'') where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ten, 'kt_sap_tra', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

-- Xoá = đánh dấu da_xoa (không xoá thật, còn trong nhật ký).
create or replace function public.kt_xoa(p_ma text, p_bang text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_ma, 'ghi');
  if p_bang not in ('thu','chi','dieu_chuyen','cong_no','cong_no_thu','sap_tra') then raise exception 'Bảng không hợp lệ'; end if;
  execute format('update public.%I set da_xoa = true where id = $1', 'kt_' || p_bang) using p_id;
  perform kt_ghi_nhat_ky(u.ten, 'kt_' || p_bang, p_id, 'xoa', null);
end $$;

create or replace function public.kt_luu_ton_thuc_te(p_ma text, p_tai_khoan_id int, p_ngay date, p_so_tien numeric)
returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_ma, 'ghi');
  if p_so_tien is null then
    delete from kt_ton_thuc_te where tai_khoan_id = p_tai_khoan_id and ngay = p_ngay;
  else
    insert into kt_ton_thuc_te (tai_khoan_id, ngay, so_tien, ghi_boi) values (p_tai_khoan_id, p_ngay, p_so_tien, u.ten)
    on conflict (tai_khoan_id, ngay) do update set so_tien = excluded.so_tien, ghi_boi = excluded.ghi_boi, ghi_luc = now();
  end if;
  perform kt_ghi_nhat_ky(u.ten, 'kt_ton_thuc_te', p_tai_khoan_id, 'ghi',
    jsonb_build_object('ngay', p_ngay, 'so_tien', p_so_tien));
end $$;

-- ── Báo cáo ────────────────────────────────────────────────────────────────
-- Biến động tiền của mọi tài khoản dưới dạng 1 bảng "dòng" (dùng chung cho tồn + dòng tiền theo ngày).
--   Thu đã duyệt (+, theo ngày thu) · Chi đã thanh toán (−, theo NGÀY THANH TOÁN) · Điều chuyển (− TK đi, + TK nhận).
--   Chỉ tính phát sinh TỪ ngày mốc tồn đầu của tài khoản (phát sinh trước mốc đã nằm trong số tồn đầu).
create or replace view public.kt_v_bien_dong with (security_invoker = true) as
  select t.tai_khoan_id, t.ngay, 'thu'::text as kieu, t.so_tien as vao, 0::numeric as ra from kt_thu t
   where not t.da_xoa and t.trang_thai = 'da_duyet'
  union all
  select c.tai_khoan_id, c.ngay_tt, 'chi', 0, c.so_tien from kt_chi c
   where not c.da_xoa and c.trang_thai = 'da_tt'
  union all
  select d.tk_di_id, d.ngay, 'dc', 0, d.so_tien from kt_dieu_chuyen d where not d.da_xoa
  union all
  select d.tk_nhan_id, d.ngay, 'dc', d.so_tien, 0 from kt_dieu_chuyen d where not d.da_xoa;
revoke all on public.kt_v_bien_dong from anon, authenticated;

create or replace function public.kt_bao_cao(p_ma text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform kt_chan(p_ma);
  with
  bd as (select b.*, tk.ngay_ton_dau from kt_v_bien_dong b join kt_tai_khoan tk on tk.id = b.tai_khoan_id
          where b.ngay >= tk.ngay_ton_dau),
  ton as (
    select tk.id, tk.ten, tk.loai, tk.hoat_dong, tk.thu_tu,
      tk.ton_dau + coalesce(sum(b.vao - b.ra) filter (where b.ngay < p_tu), 0) as dau_ky,
      coalesce(sum(b.vao) filter (where b.ngay between p_tu and p_den and b.kieu = 'thu'), 0) as thu,
      coalesce(sum(b.ra)  filter (where b.ngay between p_tu and p_den and b.kieu = 'chi'), 0) as chi,
      coalesce(sum(b.vao - b.ra) filter (where b.ngay between p_tu and p_den and b.kieu = 'dc'), 0) as dc,
      tk.ton_dau + coalesce(sum(b.vao - b.ra) filter (where b.ngay <= p_den), 0) as cuoi_ky
    from kt_tai_khoan tk left join bd b on b.tai_khoan_id = tk.id
    group by tk.id),
  thu_ky as (select t.*, l.ten loai_ten from kt_thu t join kt_loai l on l.id = t.loai_id
              where not t.da_xoa and t.trang_thai = 'da_duyet' and t.ngay between p_tu and p_den),
  chi_ky as (select c.*, l.ten loai_ten, l.nhom_bc, l.cach_chia from kt_chi c join kt_loai l on l.id = c.loai_id
              where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between p_tu and p_den),
  -- Tỉ lệ chia chi phí chung = thu (đã duyệt) của từng cơ sở / tổng thu trong kỳ
  thu_dv as (select don_vi_id, sum(so_tien) thu from thu_ky where don_vi_id is not null group by don_vi_id),
  tong_thu as (select nullif(sum(thu), 0) tong from thu_dv),
  chi_rieng as (   -- chi phí riêng: theo phân bổ của phiếu; phiếu không phân bổ → "Chưa phân bổ" (don_vi_id null)
    select (x->>'don_vi_id')::int don_vi_id, c.loai_id, c.loai_ten, (x->>'so_tien')::numeric so_tien
      from chi_ky c cross join lateral jsonb_array_elements(c.phan_bo) x where c.cach_chia = 'rieng'
    union all
    select null, c.loai_id, c.loai_ten, c.so_tien from chi_ky c
     where c.cach_chia = 'rieng' and jsonb_array_length(c.phan_bo) = 0),
  chi_chung as (   -- chi phí chung: chia theo tỉ lệ thu; kỳ không có thu → "Chưa phân bổ"
    select d.don_vi_id, c.loai_id, c.loai_ten, round(c.so_tien * d.thu / tt.tong) so_tien
      from chi_ky c cross join thu_dv d cross join tong_thu tt where c.cach_chia = 'ty_le_thu' and tt.tong is not null
    union all
    select null, c.loai_id, c.loai_ten, c.so_tien from chi_ky c, tong_thu tt where c.cach_chia = 'ty_le_thu' and tt.tong is null),
  chi_dv as (select * from chi_rieng union all select * from chi_chung),
  no as (select n.*, n.so_tien - n.tra_hang - coalesce((select sum(so_tien) from kt_cong_no_thu
           where cong_no_id = n.id and not da_xoa and ngay <= p_den), 0) con_no
         from kt_cong_no n where not n.da_xoa and n.ngay <= p_den)
  select jsonb_build_object(
    'tu', p_tu, 'den', p_den,
    'tien_vao', (select coalesce(sum(so_tien), 0) from thu_ky),
    'tien_ra',  (select coalesce(sum(so_tien), 0) from chi_ky),
    'dieu_chuyen', (select coalesce(sum(so_tien), 0) from kt_dieu_chuyen where not da_xoa and ngay between p_tu and p_den),
    'ton_dau_ky', (select coalesce(sum(dau_ky), 0) from ton),
    'ton_cuoi_ky', (select coalesce(sum(cuoi_ky), 0) from ton),
    'tai_khoan', (select coalesce(jsonb_agg(to_jsonb(ton) order by thu_tu, id), '[]') from ton
                   where hoat_dong or dau_ky <> 0 or cuoi_ky <> 0 or thu <> 0 or chi <> 0 or dc <> 0),
    'thu_theo_loai', (select coalesce(jsonb_agg(jsonb_build_object('loai', loai_ten, 'so_tien', s) order by s desc), '[]')
                       from (select loai_ten, sum(so_tien) s from thu_ky group by loai_ten) x),
    'chi_theo_loai', (select coalesce(jsonb_agg(jsonb_build_object('loai', loai_ten, 'nhom_bc', nhom_bc, 'cach_chia', cach_chia,
                        'so_tien', s, 'so_phieu', n) order by s desc), '[]')
                       from (select loai_ten, nhom_bc, cach_chia, sum(so_tien) s, count(*) n from chi_ky
                             group by loai_ten, nhom_bc, cach_chia) x),
    'thu_theo_dv', (select coalesce(jsonb_agg(jsonb_build_object('don_vi_id', don_vi_id, 'loai', loai_ten, 'so_tien', s)), '[]')
                     from (select don_vi_id, loai_ten, sum(so_tien) s from thu_ky group by 1, 2) x),
    'chi_theo_dv', (select coalesce(jsonb_agg(jsonb_build_object('don_vi_id', don_vi_id, 'loai', loai_ten, 'so_tien', s)), '[]')
                     from (select don_vi_id, loai_ten, sum(so_tien) s from chi_dv group by 1, 2) x),
    'cong_no', (select coalesce(jsonb_agg(jsonb_build_object('phan_loai', phan_loai, 'con_no', s, 'so_khach', n)), '[]')
                 from (select phan_loai, sum(con_no) s, count(*) n from no where con_no <> 0 group by phan_loai) x),
    'top_no', (select coalesce(jsonb_agg(jsonb_build_object('khach', khach, 'con_no', s) order by s desc), '[]')
                from (select khach, sum(con_no) s from no where con_no > 0 group by khach order by 2 desc limit 10) x),
    'dem', jsonb_build_object(
       'cho_duyet', (select count(*) from kt_chi where not da_xoa and trang_thai = 'cho_duyet'),
       'cho_tt',    (select count(*) from kt_chi where not da_xoa and trang_thai = 'cho_tt'),
       'hd_do_chua_nhan', (select count(*) from kt_chi where not da_xoa and trang_thai = 'da_tt' and co_hd_do and not hd_do_nhan),
       'dc_chua_xac_nhan', (select count(*) from kt_dieu_chuyen where not da_xoa and not da_xac_nhan),
       'thu_cho_duyet', (select count(*) from kt_thu where not da_xoa and trang_thai = 'cho_duyet'),
       'tk_am', (select count(*) from ton where cuoi_ky < 0)),
    'sap_tra', (select coalesce(jsonb_agg(to_jsonb(s) order by s.han nulls last), '[]') from kt_sap_tra s
                 where not s.da_xoa and not s.da_tra),
    'kiot_keo_luc', (select max(keo_luc) from kt_kiot_so_quy)
  ) into r;
  return r;
end $$;

-- Dòng tiền theo ngày × tài khoản (trang "Dòng tiền"): tồn đầu kỳ từng TK + phát sinh từng ngày + tồn thực tế đã nhập.
create or replace function public.kt_dong_tien(p_ma text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_ma);
  return jsonb_build_object(
    'dau_ky', (select coalesce(jsonb_object_agg(tk.id, tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b
                 where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau and b.ngay < p_tu), 0)), '{}') from kt_tai_khoan tk),
    'phat_sinh', (select coalesce(jsonb_agg(jsonb_build_object('tk', b.tai_khoan_id, 'ngay', b.ngay, 'kieu', b.kieu,
                   'vao', b.vao, 'ra', b.ra)), '[]')
                  from (select b.tai_khoan_id, b.ngay, b.kieu, sum(b.vao) vao, sum(b.ra) ra from kt_v_bien_dong b
                          join kt_tai_khoan tk on tk.id = b.tai_khoan_id
                         where b.ngay between p_tu and p_den and b.ngay >= tk.ngay_ton_dau
                         group by 1, 2, 3) b),
    'thuc_te', (select coalesce(jsonb_agg(jsonb_build_object('tk', tai_khoan_id, 'ngay', ngay, 'so_tien', so_tien)), '[]')
                 from kt_ton_thuc_te where ngay between p_tu and p_den));
end $$;

-- Gợi ý để HẠN CHẾ NHẬP TAY (anh chốt 05/10): người thụ hưởng đã từng chi (gõ tên → tự điền ngân hàng + STK),
-- người đề nghị, khách công nợ, nội dung hay dùng.
create or replace function public.kt_goi_y(p_ma text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_ma);
  return jsonb_build_object(
    'thu_huong', coalesce((select jsonb_agg(jsonb_build_object('ten', ten, 'nh', nh, 'stk', stk) order by n desc)
       from (select thu_huong_ten ten, thu_huong_nh nh, thu_huong_stk stk, count(*) n from kt_chi
              where not da_xoa and thu_huong_ten is not null and thu_huong_stk is not null
              group by 1, 2, 3 order by 4 desc limit 500) x), '[]'),
    'nguoi_de_nghi', coalesce((select jsonb_agg(ten order by n desc) from (select nguoi_de_nghi ten, count(*) n from kt_chi
       where not da_xoa group by 1 order by 2 desc limit 200) x), '[]'),
    'khach_no', coalesce((select jsonb_agg(khach order by khach) from (select distinct khach from kt_cong_no where not da_xoa) x), '[]'),
    'noi_dung_thu', coalesce((select jsonb_agg(noi_dung order by n desc) from (select noi_dung, count(*) n from kt_thu
       where not da_xoa and nguon = 'tay' group by 1 order by 2 desc limit 50) x), '[]'));
end $$;

create or replace function public.kt_ds_nhat_ky(p_ma text, p_truoc bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_ma, 'quan_tri');
  return coalesce((select jsonb_agg(to_jsonb(n) order by n.id desc) from (select * from kt_nhat_ky
    where p_truoc is null or id < p_truoc order by id desc limit 200) n), '[]');
end $$;

-- ── Quyền gọi hàm ──────────────────────────────────────────────────────────
-- Hàm nội bộ: không ai gọi thẳng. Hàm có kiểm mã: anon gọi được (trang web dùng khoá anon công khai).
revoke execute on function public.kt_chan(text, text), public.kt_ghi_nhat_ky(text, text, bigint, text, jsonb)
  from public, anon, authenticated;
do $$ declare f text; begin
  foreach f in array array[
    'kt_dang_nhap(text)', 'kt_doi_ma(text,text)', 'kt_ds_nguoi_dung(text)', 'kt_luu_nguoi_dung(text,jsonb)',
    'kt_danh_muc(text)', 'kt_luu_danh_muc(text,text,jsonb)', 'kt_ds(text,text,date,date)',
    'kt_luu_thu(text,jsonb)', 'kt_luu_chi(text,jsonb)', 'kt_luu_dieu_chuyen(text,jsonb)', 'kt_luu_cong_no(text,jsonb)',
    'kt_thu_hoi_no(text,bigint,date,numeric,text)', 'kt_luu_sap_tra(text,jsonb)', 'kt_xoa(text,text,bigint)',
    'kt_luu_ton_thuc_te(text,int,date,numeric)', 'kt_bao_cao(text,date,date)', 'kt_dong_tien(text,date,date)',
    'kt_ds_nhat_ky(text,bigint)', 'kt_goi_y(text)'] loop
    execute 'revoke execute on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;

-- Người dùng đầu tiên + danh mục ban đầu: tạo bằng script riêng (scripts/khoi-tao.js), KHÔNG ghi mã rõ vào file này.
