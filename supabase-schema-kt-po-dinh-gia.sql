-- KHUNG NCC TRONG NƯỚC / NƯỚC NGOÀI / ĐỊNH GIÁ BÁN — 12/11/2026. Anh: "dựng trước khung, tự tạo dữ liệu giả lập hoặc dựa trên có sẵn, nào cần gì t update
-- thêm sau, note rõ các phần dữ liệu cần bổ sung" + gửi mẫu PO "THT - Mẫu PO (Nội địa & Nhập khẩu).xlsx". Kế toán: "cần luôn để làm lại giá".
-- (1) kt_po: đơn đặt hàng NCC (nội địa + nhập khẩu, cùng 1 mẫu song ngữ), dòng hàng jsonb; la_mau = dữ liệu mẫu (xoá 1 nút).
-- (2) Định giá bán: giá vốn + giá bán lấy từ Kiot (kt_kiot_hang), quy tắc biên lãi theo nhóm hàng (kt_gia_quy_tac), phân khúc / biên riêng / giá đã duyệt từng mã
--     (kt_gia_sp). Không ghi gì vào Kiot — xuất Excel để kế toán tự nhập. Quyền trang mới 'dinh_gia'. — Monsieur Claude

-- ── (1) ĐƠN ĐẶT HÀNG ─────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.kt_po (
  id bigserial primary key, so text not null, loai text not null default 'noi_dia' check (loai in ('noi_dia', 'nhap_khau')),
  ncc_id bigint references kt_ncc(id), ncc_ten text, ngay date not null default current_date, so_pi text,
  tien_te text not null default 'VND' check (tien_te in ('VND', 'USD', 'CNY')), ty_gia numeric, noi_giao text,
  ngay_giao date, vat numeric, dat_coc numeric, ngay_coc date,
  trang_thai text not null default 'nhap' check (trang_thai in ('nhap', 'da_gui', 'dang_giao', 'da_nhan', 'huy')),
  dong jsonb not null default '[]',          -- [{ma_tht, ma_ncc, anh, ten, mau, kt, quy_cach, dvt, sl, don_gia, ghi_chu, sl_nhan}]
  khach jsonb,                                -- đơn khách đặt riêng gắn vào PO: [{ten, sdt, ma_don, coc, hen_giao}]
  ghi_chu text, la_mau boolean not null default false,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, da_xoa boolean not null default false);
alter table public.kt_po enable row level security;
revoke all on public.kt_po from anon, authenticated;

create or replace function public.kt_po_ds(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'ncc');
  return jsonb_build_object(
    'po', coalesce((select jsonb_agg(to_jsonb(p) - 'da_xoa' order by p.ngay desc, p.id desc) from kt_po p where not p.da_xoa), '[]'),
    'ben_mua', (select gia_tri from kt_cai_dat where khoa = 'po_ben_mua'));
end $$;

create or replace function public.kt_po_luu(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v bigint := nullif(p_dong->>'id', '')::bigint; ten text; n int;
begin
  u := kt_chan(p_phien, 'ncc', true); ten := coalesce(u.ho_ten, u.ten_dang_nhap);
  if jsonb_typeof(coalesce(p_dong->'dong', '[]')) <> 'array' then raise exception 'Dòng hàng không hợp lệ'; end if;
  if v is null then
    select count(*) + 1 into n from kt_po where extract(year from ngay) = extract(year from coalesce(nullif(p_dong->>'ngay', '')::date, current_date));
    insert into kt_po (so, loai, ncc_id, ncc_ten, ngay, so_pi, tien_te, ty_gia, noi_giao, ngay_giao, vat, dat_coc, ngay_coc, trang_thai, dong, khach, ghi_chu, tao_boi)
    values (coalesce(nullif(btrim(p_dong->>'so'), ''), 'THT-PO-' || lpad(n::text, 3, '0') || '/' || extract(year from coalesce(nullif(p_dong->>'ngay', '')::date, current_date))),
      coalesce(p_dong->>'loai', 'noi_dia'), nullif(p_dong->>'ncc_id', '')::bigint, p_dong->>'ncc_ten', coalesce(nullif(p_dong->>'ngay', '')::date, current_date), p_dong->>'so_pi',
      coalesce(nullif(p_dong->>'tien_te', ''), 'VND'), nullif(p_dong->>'ty_gia', '')::numeric, p_dong->>'noi_giao', nullif(p_dong->>'ngay_giao', '')::date,
      nullif(p_dong->>'vat', '')::numeric, nullif(p_dong->>'dat_coc', '')::numeric, nullif(p_dong->>'ngay_coc', '')::date, coalesce(nullif(p_dong->>'trang_thai', ''), 'nhap'),
      coalesce(p_dong->'dong', '[]'), p_dong->'khach', p_dong->>'ghi_chu', ten) returning id into v;
  else
    update kt_po set so = coalesce(nullif(btrim(p_dong->>'so'), ''), so), loai = coalesce(p_dong->>'loai', loai), ncc_id = nullif(p_dong->>'ncc_id', '')::bigint, ncc_ten = p_dong->>'ncc_ten',
      ngay = coalesce(nullif(p_dong->>'ngay', '')::date, ngay), so_pi = p_dong->>'so_pi', tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te),
      ty_gia = nullif(p_dong->>'ty_gia', '')::numeric, noi_giao = p_dong->>'noi_giao', ngay_giao = nullif(p_dong->>'ngay_giao', '')::date, vat = nullif(p_dong->>'vat', '')::numeric,
      dat_coc = nullif(p_dong->>'dat_coc', '')::numeric, ngay_coc = nullif(p_dong->>'ngay_coc', '')::date, trang_thai = coalesce(nullif(p_dong->>'trang_thai', ''), trang_thai),
      dong = coalesce(p_dong->'dong', dong), khach = p_dong->'khach', ghi_chu = p_dong->>'ghi_chu', la_mau = false, sua_boi = ten, sua_luc = now()
    where id = v and not da_xoa;
    if not found then raise exception 'Không tìm thấy PO'; end if;
  end if;
  perform kt_ghi_nhat_ky(ten, 'kt_po', v, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v;
end $$;

-- xoá 1 PO, hoặc p_id null = xoá toàn bộ dữ liệu mẫu
create or replace function public.kt_po_xoa(p_phien text, p_id bigint) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; n int;
begin
  u := kt_chan(p_phien, 'ncc', true);
  update kt_po set da_xoa = true, sua_boi = coalesce(u.ho_ten, u.ten_dang_nhap), sua_luc = now() where not da_xoa and (id = p_id or (p_id is null and la_mau));
  get diagnostics n = row_count;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_po', p_id, 'xoa', jsonb_build_object('so_dong', n, 'mau', p_id is null));
  return n;
end $$;

-- đối chiếu giá nhập (NCC nội địa): dòng phiếu nhập Kiot gần đây — trang ghép với dòng PO cùng NCC + mã hàng
create or replace function public.kt_po_gia_nhap(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(jsonb_build_object('ma_pn', n.ma, 'ngay', (n.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', n.chi_nhanh, 'ncc', n.ncc_ten, 'ncc_ma', n.ncc_ma,
            'ma', e->>'ma', 'ten', e->>'ten', 'sl', (e->>'sl')::numeric, 'gia', (e->>'gia')::numeric, 'giam', (e->>'giam')::numeric) order by n.ngay desc)
    from kt_kiot_nhap_hang n, jsonb_array_elements(coalesce(n.chi_tiet, '[]')) e
    where (n.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den and n.trang_thai is distinct from 4), '[]');   -- 4 = phiếu nhập đã huỷ trên Kiot
end $$;

-- ── (2) ĐỊNH GIÁ BÁN ────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.kt_gia_quy_tac (
  nhom text primary key, bien numeric not null, bien_min numeric not null, ck numeric not null default 0, buoc numeric not null default 10000,
  la_mau boolean not null default false, sua_boi text, sua_luc timestamptz not null default now());
create table if not exists public.kt_gia_sp (
  ma text primary key, phan_khuc text check (phan_khuc in ('pho_thong', 'chon_loc', 'doc_dao', 'rieng')), bien_rieng numeric, ly_do text,
  gia_duyet numeric, gia_von_luc_duyet numeric, duyet_boi text, duyet_luc timestamptz, sua_boi text, sua_luc timestamptz not null default now());
alter table public.kt_gia_quy_tac enable row level security;
alter table public.kt_gia_sp enable row level security;
revoke all on public.kt_gia_quy_tac, public.kt_gia_sp from anon, authenticated;

-- mã hàng đang bán: giá vốn (bình quân tồn; hết hàng → giá vốn Kiot từng chi nhánh; chưa có → giá nhập gần nhất), giá bán Kiot hiện tại
create or replace function public.kt_gia_ds(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'dinh_gia');
  return jsonb_build_object(
    -- [mã, tên, nhóm, giá bán Kiot, tồn, giá vốn bình quân tồn, giá vốn Kiot (chi nhánh cao nhất), giá nhập gần nhất (đã trừ giảm giá), ngày phiếu nhập, NCC, mã phiếu nhập]
    -- 12/11 kế toán: "toàn bộ giá vốn đối chiếu từ phiếu nhập hàng của các NCC trước mắt" → trang dùng giá nhập gần nhất làm giá vốn
    'hang', coalesce((with nh as (select distinct on (e->>'ma') e->>'ma' ma, (e->>'gia')::numeric - coalesce((e->>'giam')::numeric, 0) gia, (n.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, n.ncc_ten, n.ma pn from kt_kiot_nhap_hang n, jsonb_array_elements(coalesce(n.chi_tiet, '[]')) e
                                   where n.trang_thai is distinct from 4 order by e->>'ma', n.ngay desc)
      select jsonb_agg(jsonb_build_array(h.ma, h.ten, h.nhom, h.gia_ban, h.tong_ton,
        case when h.tong_ton > 0 and h.gia_tri_ton > 0 then round(h.gia_tri_ton / h.tong_ton) end,
        (select max((t->>'gia_von')::numeric) from jsonb_array_elements(case when jsonb_typeof(h.ton) = 'array' then h.ton else '[]' end) t), nh.gia, nh.ngay, nh.ncc_ten, nh.pn))
      from kt_kiot_hang h left join nh on nh.ma = h.ma where h.hoat_dong), '[]'),
    'quy_tac', coalesce((select jsonb_agg(to_jsonb(q) order by q.nhom) from kt_gia_quy_tac q), '[]'),
    'sp', coalesce((select jsonb_agg(to_jsonb(s)) from kt_gia_sp s), '[]'),
    'cai_dat', (select gia_tri from kt_cai_dat where khoa = 'gia_cai_dat'),
    'keo_luc', (select max(keo_luc) from kt_kiot_hang));
end $$;

create or replace function public.kt_gia_quy_tac_luu(p_phien text, p_ds jsonb, p_cai_dat jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; r jsonb; ten text;
begin
  u := kt_chan(p_phien, 'dinh_gia', true); ten := coalesce(u.ho_ten, u.ten_dang_nhap);
  for r in select e from jsonb_array_elements(coalesce(p_ds, '[]')) e loop
    if (r->>'bien')::numeric >= 100 or (r->>'bien_min')::numeric >= 100 or (r->>'ck')::numeric >= 100 or (r->>'bien')::numeric < 0 then raise exception 'Biên / chiết khấu phải từ 0 đến dưới 100%%'; end if;
    insert into kt_gia_quy_tac (nhom, bien, bien_min, ck, buoc, la_mau, sua_boi) values (r->>'nhom', (r->>'bien')::numeric, (r->>'bien_min')::numeric, coalesce((r->>'ck')::numeric, 0),
      coalesce(nullif(r->>'buoc', '')::numeric, 10000), false, ten)
    on conflict (nhom) do update set bien = excluded.bien, bien_min = excluded.bien_min, ck = excluded.ck, buoc = excluded.buoc, la_mau = false, sua_boi = ten, sua_luc = now();
  end loop;
  if p_cai_dat is not null then
    insert into kt_cai_dat (khoa, gia_tri) values ('gia_cai_dat', p_cai_dat) on conflict (khoa) do update set gia_tri = excluded.gia_tri, sua_luc = now();
  end if;
  perform kt_ghi_nhat_ky(ten, 'kt_gia_quy_tac', null, 'sua', jsonb_build_object('so_nhom', jsonb_array_length(coalesce(p_ds, '[]')), 'cai_dat', p_cai_dat));
end $$;

-- từng mã: phân khúc / biên riêng / duyệt giá (p_ds: [{ma, phan_khuc?, bien_rieng?, ly_do?, gia_duyet?, gia_von?}]; gia_duyet = 0 → bỏ duyệt)
create or replace function public.kt_gia_sp_luu(p_phien text, p_ds jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; r jsonb; ten text; n int := 0;
begin
  u := kt_chan(p_phien, 'dinh_gia', true); ten := coalesce(u.ho_ten, u.ten_dang_nhap);
  for r in select e from jsonb_array_elements(coalesce(p_ds, '[]')) e loop
    insert into kt_gia_sp (ma, sua_boi) values (r->>'ma', ten) on conflict (ma) do nothing;
    update kt_gia_sp set
      phan_khuc = case when r ? 'phan_khuc' then nullif(r->>'phan_khuc', '') else phan_khuc end,
      bien_rieng = case when r ? 'bien_rieng' then nullif(r->>'bien_rieng', '')::numeric else bien_rieng end,
      ly_do = case when r ? 'ly_do' then r->>'ly_do' else ly_do end,
      gia_duyet = case when r ? 'gia_duyet' then nullif((r->>'gia_duyet')::numeric, 0) else gia_duyet end,
      gia_von_luc_duyet = case when r ? 'gia_duyet' then nullif(r->>'gia_von', '')::numeric else gia_von_luc_duyet end,
      duyet_boi = case when r ? 'gia_duyet' then case when nullif((r->>'gia_duyet')::numeric, 0) is null then null else ten end else duyet_boi end,
      duyet_luc = case when r ? 'gia_duyet' then case when nullif((r->>'gia_duyet')::numeric, 0) is null then null else now() end else duyet_luc end,
      sua_boi = ten, sua_luc = now()
    where ma = r->>'ma';
    n := n + 1;
  end loop;
  perform kt_ghi_nhat_ky(ten, 'kt_gia_sp', null, 'sua', jsonb_build_object('so_ma', n, 'ds', p_ds));
  return n;
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_po_ds(text)', 'kt_po_luu(text, jsonb)', 'kt_po_xoa(text, bigint)', 'kt_po_gia_nhap(text, date, date)', 'kt_gia_ds(text)',
                           'kt_gia_quy_tac_luu(text, jsonb, jsonb)', 'kt_gia_sp_luu(text, jsonb)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;
