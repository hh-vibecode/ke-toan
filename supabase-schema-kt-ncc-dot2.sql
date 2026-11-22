-- 16/11/2026 kế toán (đợt 2–3): báo giá theo từng NCC (danh mục SP, nhóm hàng, ảnh, tải file báo giá, lịch sử giá) ·
-- giá kê khai + thuế từng mã hàng trong hồ sơ nhập khẩu (tra lại giá đã khai cont trước) · thanh toán trung gian NCC nước ngoài
-- (mỗi lần chuyển tiền: nguồn tiền, tỷ giá → phân bổ cho NCC / PO). — Monsieur Claude

-- ── 1. BÁO GIÁ THEO NCC ──
alter table public.kt_bao_gia add column if not exists nhom text, add column if not exists ma_ncc text, add column if not exists quy_cach text,
  add column if not exists dvt text, add column if not exists anh_ct bigint, add column if not exists lich_su jsonb not null default '[]';

alter table public.kt_chung_tu drop constraint if exists kt_chung_tu_bang_check;
alter table public.kt_chung_tu add constraint kt_chung_tu_bang_check check (bang = any (array['thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung','bao_loi','ho_so','ncc','lo_nk','po','de_xuat','bao_gia']));

create or replace function public.kt_bg_luu(p_phien text, p_dong jsonb) returns bigint language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v bigint := nullif(p_dong->>'id', '')::bigint; v_ten text; c kt_bao_gia;
begin
  u := kt_chan(p_phien, 'ncc', true); v_ten := coalesce(u.ho_ten, u.ten_dang_nhap);
  if coalesce(btrim(p_dong->>'ten'), '') = '' then raise exception 'Nhập tên sản phẩm'; end if;
  if coalesce(nullif(p_dong->>'gia', '')::numeric, 0) <= 0 then raise exception 'Nhập giá báo'; end if;
  if nullif(p_dong->>'ncc_id', '') is null then raise exception 'Chọn nhà cung cấp'; end if;
  if v is null then
    insert into kt_bao_gia (ma_tht, ma_ncc, ten, nhom, quy_cach, dvt, ncc_id, ncc_ten, gia, tien_te, moq, tg_sx, ngay, anh, anh_ct, ghi_chu, tao_boi)
    values (nullif(btrim(p_dong->>'ma_tht'), ''), nullif(btrim(p_dong->>'ma_ncc'), ''), btrim(p_dong->>'ten'), nullif(btrim(p_dong->>'nhom'), ''), nullif(btrim(p_dong->>'quy_cach'), ''),
      nullif(btrim(p_dong->>'dvt'), ''), (p_dong->>'ncc_id')::bigint, p_dong->>'ncc_ten', (p_dong->>'gia')::numeric, coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'),
      nullif(p_dong->>'moq', '')::numeric, nullif(p_dong->>'tg_sx', '')::int, coalesce(nullif(p_dong->>'ngay', '')::date, current_date), nullif(p_dong->>'anh', ''),
      nullif(p_dong->>'anh_ct', '')::bigint, nullif(btrim(p_dong->>'ghi_chu'), ''), v_ten) returning id into v;
  else
    select * into c from kt_bao_gia where id = v and not da_xoa;
    if not found then raise exception 'Không tìm thấy sản phẩm báo giá'; end if;
    update kt_bao_gia set ma_tht = nullif(btrim(p_dong->>'ma_tht'), ''), ma_ncc = nullif(btrim(p_dong->>'ma_ncc'), ''), ten = btrim(p_dong->>'ten'), nhom = nullif(btrim(p_dong->>'nhom'), ''),
      quy_cach = nullif(btrim(p_dong->>'quy_cach'), ''), dvt = nullif(btrim(p_dong->>'dvt'), ''), ncc_id = (p_dong->>'ncc_id')::bigint, ncc_ten = p_dong->>'ncc_ten',
      gia = (p_dong->>'gia')::numeric, tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te), moq = nullif(p_dong->>'moq', '')::numeric, tg_sx = nullif(p_dong->>'tg_sx', '')::int,
      ngay = coalesce(nullif(p_dong->>'ngay', '')::date, ngay), anh = nullif(p_dong->>'anh', ''), anh_ct = coalesce(nullif(p_dong->>'anh_ct', '')::bigint, anh_ct),
      ghi_chu = nullif(btrim(p_dong->>'ghi_chu'), ''), la_mau = false, sua_boi = v_ten, sua_luc = now(),
      lich_su = case when c.gia is distinct from (p_dong->>'gia')::numeric or c.tien_te is distinct from coalesce(nullif(p_dong->>'tien_te', ''), c.tien_te)
                     then c.lich_su || jsonb_build_array(jsonb_build_object('gia', c.gia, 'tien_te', c.tien_te, 'ngay', c.ngay)) else c.lich_su end
    where id = v;
  end if;
  perform kt_ghi_nhat_ky(v_ten, 'kt_bao_gia', v, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v;
end $$;

-- nhập nhiều dòng từ file báo giá của 1 NCC: trùng (mã NCC / mã THT / tên) → cập nhật giá + giữ lịch sử; chưa có → thêm. Trả id theo thứ tự dòng.
create or replace function public.kt_bg_nhap(p_phien text, p_ncc bigint, p_ncc_ten text, p_ds jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_ten text; r jsonb; c kt_bao_gia; v bigint; ids bigint[] := '{}'; moi int := 0; cn int := 0;
begin
  u := kt_chan(p_phien, 'ncc', true); v_ten := coalesce(u.ho_ten, u.ten_dang_nhap);
  if p_ncc is null then raise exception 'Chọn nhà cung cấp'; end if;
  if jsonb_typeof(p_ds) <> 'array' or jsonb_array_length(p_ds) = 0 then raise exception 'File không có dòng nào'; end if;
  if jsonb_array_length(p_ds) > 2000 then raise exception 'Tối đa 2000 dòng / lần'; end if;
  for r in select * from jsonb_array_elements(p_ds) loop
    if coalesce(btrim(r->>'ten'), '') = '' and coalesce(btrim(r->>'ma_ncc'), '') = '' then ids := ids || null::bigint; continue; end if;
    c := null;
    select * into c from kt_bao_gia b where not b.da_xoa and b.ncc_id = p_ncc and (
        (nullif(btrim(r->>'ma_ncc'), '') is not null and lower(b.ma_ncc) = lower(btrim(r->>'ma_ncc')))
     or (nullif(btrim(r->>'ma_ncc'), '') is null and nullif(btrim(r->>'ma_tht'), '') is not null and b.ma_tht = btrim(r->>'ma_tht'))
     or (nullif(btrim(r->>'ma_ncc'), '') is null and nullif(btrim(r->>'ma_tht'), '') is null and lower(b.ten) = lower(btrim(r->>'ten'))))
     order by b.id limit 1;
    if c.id is null then
      insert into kt_bao_gia (ma_tht, ma_ncc, ten, nhom, quy_cach, dvt, ncc_id, ncc_ten, gia, tien_te, moq, ngay, ghi_chu, tao_boi)
      values (nullif(btrim(r->>'ma_tht'), ''), nullif(btrim(r->>'ma_ncc'), ''), coalesce(nullif(btrim(r->>'ten'), ''), btrim(r->>'ma_ncc')), nullif(btrim(r->>'nhom'), ''),
        nullif(btrim(r->>'quy_cach'), ''), nullif(btrim(r->>'dvt'), ''), p_ncc, p_ncc_ten, nullif(r->>'gia', '')::numeric, coalesce(nullif(r->>'tien_te', ''), 'CNY'),
        nullif(r->>'moq', '')::numeric, coalesce(nullif(r->>'ngay', '')::date, current_date), nullif(btrim(r->>'ghi_chu'), ''), v_ten) returning id into v;
      moi := moi + 1;
    else
      v := c.id;
      update kt_bao_gia set ma_tht = coalesce(nullif(btrim(r->>'ma_tht'), ''), ma_tht), ten = coalesce(nullif(btrim(r->>'ten'), ''), ten), nhom = coalesce(nullif(btrim(r->>'nhom'), ''), nhom),
        quy_cach = coalesce(nullif(btrim(r->>'quy_cach'), ''), quy_cach), dvt = coalesce(nullif(btrim(r->>'dvt'), ''), dvt),
        gia = coalesce(nullif(r->>'gia', '')::numeric, gia), tien_te = coalesce(nullif(r->>'tien_te', ''), tien_te), moq = coalesce(nullif(r->>'moq', '')::numeric, moq),
        ngay = coalesce(nullif(r->>'ngay', '')::date, current_date), ghi_chu = coalesce(nullif(btrim(r->>'ghi_chu'), ''), ghi_chu), la_mau = false, sua_boi = v_ten, sua_luc = now(),
        lich_su = case when nullif(r->>'gia', '') is not null and (c.gia is distinct from (r->>'gia')::numeric or c.tien_te is distinct from coalesce(nullif(r->>'tien_te', ''), c.tien_te))
                       then c.lich_su || jsonb_build_array(jsonb_build_object('gia', c.gia, 'tien_te', c.tien_te, 'ngay', c.ngay)) else c.lich_su end
      where id = v;
      cn := cn + 1;
    end if;
    ids := ids || v;
  end loop;
  perform kt_ghi_nhat_ky(v_ten, 'kt_bao_gia', null, 'nhap_file', jsonb_build_object('ncc', p_ncc, 'moi', moi, 'cap_nhat', cn));
  return jsonb_build_object('ids', to_jsonb(ids), 'moi', moi, 'cap_nhat', cn);
end $$;

create or replace function public.kt_bg_anh(p_phien text, p_id bigint, p_ct bigint) returns void language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'ncc', true);
  if not exists (select 1 from kt_chung_tu where id = p_ct and bang = 'bao_gia' and dong_id = p_id and not da_xoa) then raise exception 'Ảnh không thuộc sản phẩm này'; end if;
  update kt_bao_gia set anh_ct = p_ct where id = p_id and not da_xoa;
end $$;

-- ảnh sản phẩm báo giá (bang bao_gia) theo quyền trang Nhà cung cấp
CREATE OR REPLACE FUNCTION public.kt_quyen_chung_tu(p_phien text, p_bang text, p_ghi boolean, p_ids bigint[])
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  if p_bang not in ('bao_loi','thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung','ho_so','ncc','lo_nk','po','de_xuat','bao_gia') then raise exception 'Bảng chứng từ không hợp lệ'; end if;
  u := kt_chan_dong(p_phien, p_bang, p_ids, p_ghi);
  return u.ho_ten;
end $function$;

CREATE OR REPLACE FUNCTION public.kt_chan_dong(p_phien text, p_bang text, p_ids bigint[], p_ghi boolean)
 RETURNS kt_nguoi_dung
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  -- 24/10: ảnh báo lỗi — người báo (báo lỗi của chính mình) hoặc quyền trang Log
  if p_bang = 'bao_loi' then
    if kt_co_quyen(u, 'nhat_ky', false) then return u; end if;
    if cardinality(p_ids) > 0 and not exists (select 1 from unnest(p_ids) i where not exists (select 1 from kt_bao_loi b where b.id = i and b.nguoi = u.ho_ten)) then return u; end if;
    raise exception 'Tài khoản chưa được cấp quyền xem báo lỗi' using errcode = '42501';
  end if;
  -- 29/10: chứng từ hồ sơ NCC theo quyền trang Nhà cung cấp (người xác nhận phiếu chi cũng tải được ở bước 4)
  if p_bang = 'ho_so' then
    if kt_co_quyen(u, 'ncc', p_ghi) or kt_co_quyen(u, 'chi_duyet') then return u; end if;
    raise exception 'Tài khoản chưa được cấp quyền % hồ sơ NCC', case when p_ghi then 'sửa' else 'xem' end using errcode = '42501';
  end if;
  -- 14/10/2026: ảnh kiểm két theo quyền trang Sổ quỹ (dong_tien); 30/10: chứng từ hồ sơ nhập khẩu theo quyền trang Nhà cung cấp
  if kt_co_quyen(u, case p_bang when 'kiem_quy' then 'kiem_ket' when 'lo_nk' then 'ncc' when 'po' then 'ncc' when 'de_xuat' then 'ncc' when 'bao_gia' then 'ncc' else p_bang end, p_ghi) then return u; end if;
  -- 16/10: thủ quỹ (chi_tt) — phiếu chờ chi tiền / đã thanh toán
  if p_bang = 'chi' and kt_co_quyen(u, 'chi_tt') and cardinality(p_ids) > 0
     and not exists (select 1 from unnest(p_ids) i where not exists (
       select 1 from kt_chi c join kt_tai_khoan t on t.id = c.tai_khoan_id where c.id = i and c.trang_thai in ('cho_tt','da_tt') and t.thu_quy_chi and not c.da_xoa)) then
    return u;
  end if;
  if p_bang = 'chi' and kt_co_quyen(u, 'chi_de_nghi') and cardinality(p_ids) > 0
     and not exists (select 1 from unnest(p_ids) i where not exists (
       select 1 from kt_chi c where c.id = i and c.tao_boi = u.ho_ten and not c.da_xoa)) then
    return u;
  end if;
  raise exception 'Tài khoản chưa được cấp quyền % trang này', case when p_ghi then 'sửa' else 'xem' end using errcode = '42501';
end $function$;

-- ── 2. KÊ KHAI HẢI QUAN TỪNG MÃ HÀNG (hồ sơ nhập khẩu) ──
create table if not exists public.kt_lo_nk_kk (
  id bigserial primary key, lo_id bigint not null references public.kt_lo_nk(id), stt int, ma text, ten text, hs text, sl numeric, dvt text,
  don_gia numeric, tien_te text, tri_gia numeric, thue_nk_ts numeric, thue_nk numeric, thue_vat numeric, ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now());
create index if not exists kt_lo_nk_kk_lo on public.kt_lo_nk_kk(lo_id);
create index if not exists kt_lo_nk_kk_ma on public.kt_lo_nk_kk(lower(ma));
alter table public.kt_lo_nk_kk enable row level security;
revoke all on public.kt_lo_nk_kk from anon, authenticated;

-- dòng kê khai của 1 lô + lần khai gần nhất của cùng mã ở lô khác (để so)
create or replace function public.kt_lo_nk_kk_ds(p_phien text, p_lo bigint) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(to_jsonb(k) || jsonb_build_object('truoc', (
      select jsonb_build_object('lo', l.ma, 'lo_id', l.id, 'ngay', coalesce(l.ngay_ve, l.ngay_kh), 'don_gia', k2.don_gia, 'tien_te', k2.tien_te, 'thue_nk_ts', k2.thue_nk_ts)
        from kt_lo_nk_kk k2 join kt_lo_nk l on l.id = k2.lo_id where not l.da_xoa and k2.lo_id <> p_lo and coalesce(k.ma, '') <> '' and lower(k2.ma) = lower(k.ma)
       order by coalesce(l.ngay_ve, l.ngay_kh) desc nulls last, k2.id desc limit 1)) order by k.stt, k.id)
    from kt_lo_nk_kk k where k.lo_id = p_lo), '[]');
end $$;

create or replace function public.kt_lo_nk_kk_luu(p_phien text, p_lo bigint, p_ds jsonb) returns int language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; n int;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if not exists (select 1 from kt_lo_nk where id = p_lo and not da_xoa) then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  if jsonb_typeof(p_ds) <> 'array' then raise exception 'Dữ liệu không hợp lệ'; end if;
  if jsonb_array_length(p_ds) > 3000 then raise exception 'Tối đa 3000 dòng'; end if;
  delete from kt_lo_nk_kk where lo_id = p_lo;
  insert into kt_lo_nk_kk (lo_id, stt, ma, ten, hs, sl, dvt, don_gia, tien_te, tri_gia, thue_nk_ts, thue_nk, thue_vat, ghi_chu, tao_boi)
  select p_lo, o.n, nullif(btrim(e->>'ma'), ''), nullif(btrim(e->>'ten'), ''), nullif(btrim(e->>'hs'), ''), nullif(e->>'sl', '')::numeric, nullif(btrim(e->>'dvt'), ''),
         nullif(e->>'don_gia', '')::numeric, nullif(e->>'tien_te', ''), nullif(e->>'tri_gia', '')::numeric, nullif(e->>'thue_nk_ts', '')::numeric,
         nullif(e->>'thue_nk', '')::numeric, nullif(e->>'thue_vat', '')::numeric, nullif(btrim(e->>'ghi_chu'), ''), u.ho_ten
    from jsonb_array_elements(p_ds) with ordinality o(e, n)
   where coalesce(btrim(e->>'ma'), '') <> '' or coalesce(btrim(e->>'ten'), '') <> '';
  get diagnostics n = row_count;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk', p_lo, 'ke_khai', jsonb_build_object('so_dong', n));
  return n;
end $$;

-- tra giá đã khai theo mã / tên hàng (mọi lô)
create or replace function public.kt_lo_nk_kk_tra(p_phien text, p_q text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q text := lower(btrim(coalesce(p_q, '')));
begin
  perform kt_chan(p_phien, 'ncc');
  if length(q) < 2 then return '[]'; end if;
  return coalesce((select jsonb_agg(x order by x->>'ngay' desc nulls last) from (
    select jsonb_build_object('lo', l.ma, 'lo_id', l.id, 'lo_ten', l.ten, 'cont', l.so_cont, 'ngay', coalesce(l.ngay_ve, l.ngay_kh), 'ma', k.ma, 'ten', k.ten, 'hs', k.hs, 'sl', k.sl, 'dvt', k.dvt,
             'don_gia', k.don_gia, 'tien_te', k.tien_te, 'tri_gia', k.tri_gia, 'thue_nk_ts', k.thue_nk_ts, 'thue_nk', k.thue_nk, 'thue_vat', k.thue_vat) x
      from kt_lo_nk_kk k join kt_lo_nk l on l.id = k.lo_id
     where not l.da_xoa and (lower(k.ma) like '%' || q || '%' or lower(k.ten) like '%' || q || '%' or lower(k.hs) like q || '%')
     limit 300) t), '[]');
end $$;

-- ── 3. THANH TOÁN TRUNG GIAN NCC NƯỚC NGOÀI ──
create table if not exists public.kt_tt_nn (
  id bigserial primary key, ngay date not null default current_date, tk_id bigint, chi_id bigint, ben_nhan text, tien_te text not null default 'CNY',
  so_tien_nt numeric not null, ty_gia numeric, phi numeric, phan_bo jsonb not null default '[]', ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, da_xoa boolean not null default false);
alter table public.kt_tt_nn enable row level security;
revoke all on public.kt_tt_nn from anon, authenticated;

create or replace function public.kt_tt_nn_ds(p_phien text) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(to_jsonb(t) - 'da_xoa' || jsonb_build_object('tk', (select ten from kt_tai_khoan where id = t.tk_id), 'tk_loai', (select loai from kt_tai_khoan where id = t.tk_id),
      'chi', (select jsonb_build_object('id', c.id, 'so_tien', c.so_tien, 'tt', c.trang_thai, 'ngay', c.ngay_tt) from kt_chi c where c.id = t.chi_id and not c.da_xoa)) order by t.ngay desc, t.id desc)
    from kt_tt_nn t where not t.da_xoa), '[]');
end $$;

create or replace function public.kt_tt_nn_luu(p_phien text, p_dong jsonb) returns bigint language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v bigint := nullif(p_dong->>'id', '')::bigint; pb jsonb; tong numeric := coalesce(nullif(p_dong->>'so_tien_nt', '')::numeric, 0);
begin
  u := kt_chan(p_phien, 'ncc', true);
  if tong <= 0 then raise exception 'Nhập số tiền nguyên tệ'; end if;
  if nullif(p_dong->>'ty_gia', '') is not null and (p_dong->>'ty_gia')::numeric <= 0 then raise exception 'Tỷ giá phải lớn hơn 0'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('ncc_id', nullif(e->>'ncc_id', '')::bigint, 'ncc_ten', e->>'ncc_ten', 'po_id', nullif(e->>'po_id', '')::bigint,
           'so_tien_nt', (e->>'so_tien_nt')::numeric, 'ghi_chu', nullif(btrim(e->>'ghi_chu'), ''))), '[]') into pb
    from jsonb_array_elements(coalesce(p_dong->'phan_bo', '[]')) e where coalesce(nullif(e->>'so_tien_nt', '')::numeric, 0) > 0;
  if exists (select 1 from jsonb_array_elements(pb) e where e->>'ncc_id' is null) then raise exception 'Mỗi dòng phân bổ chọn nhà cung cấp'; end if;
  if (select coalesce(sum((e->>'so_tien_nt')::numeric), 0) from jsonb_array_elements(pb) e) > tong + 0.005 then raise exception 'Tổng phân bổ lớn hơn số tiền chuyển'; end if;
  if v is null then
    insert into kt_tt_nn (ngay, tk_id, chi_id, ben_nhan, tien_te, so_tien_nt, ty_gia, phi, phan_bo, ghi_chu, tao_boi)
    values (coalesce(nullif(p_dong->>'ngay', '')::date, current_date), nullif(p_dong->>'tk_id', '')::bigint, nullif(p_dong->>'chi_id', '')::bigint, nullif(btrim(p_dong->>'ben_nhan'), ''),
      coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'), tong, nullif(p_dong->>'ty_gia', '')::numeric, nullif(p_dong->>'phi', '')::numeric, pb, nullif(btrim(p_dong->>'ghi_chu'), ''), u.ho_ten)
    returning id into v;
  else
    update kt_tt_nn set ngay = coalesce(nullif(p_dong->>'ngay', '')::date, ngay), tk_id = nullif(p_dong->>'tk_id', '')::bigint, chi_id = nullif(p_dong->>'chi_id', '')::bigint,
      ben_nhan = nullif(btrim(p_dong->>'ben_nhan'), ''), tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te), so_tien_nt = tong, ty_gia = nullif(p_dong->>'ty_gia', '')::numeric,
      phi = nullif(p_dong->>'phi', '')::numeric, phan_bo = pb, ghi_chu = nullif(btrim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v and not da_xoa;
    if not found then raise exception 'Không thấy lần thanh toán'; end if;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_tt_nn', v, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v;
end $$;

create or replace function public.kt_tt_nn_xoa(p_phien text, p_id bigint) returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc', true);
  update kt_tt_nn set da_xoa = true, sua_boi = u.ho_ten, sua_luc = now() where id = p_id and not da_xoa;
  if not found then raise exception 'Không thấy lần thanh toán'; end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_tt_nn', p_id, 'xoa', null);
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_bg_luu(text, jsonb)', 'kt_bg_nhap(text, bigint, text, jsonb)', 'kt_bg_anh(text, bigint, bigint)', 'kt_lo_nk_kk_ds(text, bigint)',
                           'kt_lo_nk_kk_luu(text, bigint, jsonb)', 'kt_lo_nk_kk_tra(text, text)', 'kt_tt_nn_ds(text)', 'kt_tt_nn_luu(text, jsonb)', 'kt_tt_nn_xoa(text, bigint)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;
