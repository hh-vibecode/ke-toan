-- HỒ SƠ NHẬP KHẨU (30/10/2026, anh gửi sơ đồ "Luồng xử lý tổng quát": đơn đặt hàng NCC nước ngoài → thanh toán → hồ sơ nhập khẩu (lô / container) → hàng về kho, phân bổ giá vốn → đồng bộ Kiot).
-- "t cần thêm 1 mục là hồ sơ nhập khẩu trong nhà cung cấp và khách hàng". Monsieur Claude
-- kt_lo_nk      = 1 hồ sơ nhập khẩu (1 lô / container): thông tin chung, trạng thái thông quan, tiền tệ + tỷ giá, cách phân bổ chi phí
-- kt_lo_nk_don  = đơn hàng (PO) trong lô — nhiều NCC cùng container; hàng hoá (mã Kiot, tên, SL, đơn giá nguyên tệ) nhập tay / dán / đọc Excel; nối phiếu nhập Kiot khi hàng về
-- kt_lo_nk_cp   = chi phí liên quan (vận chuyển, thuế, hải quan…) — nối phiếu chi nếu có; tinh_gv = có cộng vào giá vốn (VAT nhập khẩu mặc định không)
-- Phân bổ giá vốn tính trên trình duyệt từ 3 bảng này (không lưu số). Chứng từ lô: kt_chung_tu bang 'lo_nk'. Quyền theo trang Nhà cung cấp (ncc).

create table if not exists public.kt_lo_nk (
  id bigserial primary key, ma text unique not null, ten text not null,
  trang_thai text not null default 'dat_hang' check (trang_thai in ('dat_hang','san_xuat','van_chuyen','thong_quan','ve_kho','hoan_tat')),
  so_cont text, forwarder text, ngay_kh date, ngay_du_kien date, ngay_ve date,
  tien_te text not null default 'CNY', ty_gia numeric, cach_pb text not null default 'gia_tri' check (cach_pb in ('gia_tri','so_luong')),
  ghi_chu text, tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, da_xoa boolean not null default false);

create table if not exists public.kt_lo_nk_don (
  id bigserial primary key, lo_id bigint not null references kt_lo_nk(id), ncc_id bigint not null references kt_ncc(id),
  ma_po text, ngay date, tien_te text, ty_gia numeric, gia_tri numeric,
  trang_thai text not null default 'san_xuat' check (trang_thai in ('san_xuat','xong','xep_hang','ve_kho')),
  nhap_id bigint, ho_so_id bigint references kt_ho_so(id), hang jsonb not null default '[]', ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, da_xoa boolean not null default false);
create index if not exists kt_lo_nk_don_lo on public.kt_lo_nk_don (lo_id) where not da_xoa;
create index if not exists kt_lo_nk_don_ncc on public.kt_lo_nk_don (ncc_id) where not da_xoa;

create table if not exists public.kt_lo_nk_cp (
  id bigserial primary key, lo_id bigint not null references kt_lo_nk(id),
  loai text not null default 'khac' check (loai in ('van_chuyen_qt','van_chuyen_nd','thue_nk','vat_nk','hai_quan','boc_xep','bao_hiem','khac')),
  noi_dung text, so_tien numeric not null check (so_tien >= 0), tinh_gv boolean not null default true, chi_id bigint references kt_chi(id), ngay date, ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, da_xoa boolean not null default false);
create index if not exists kt_lo_nk_cp_lo on public.kt_lo_nk_cp (lo_id) where not da_xoa;

do $$ declare t text; begin
  foreach t in array array['kt_lo_nk','kt_lo_nk_don','kt_lo_nk_cp'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('drop trigger if exists kt_chi_xem on public.%I', t);
    execute format('create trigger kt_chi_xem before insert or update or delete on public.%I for each row execute function public.kt_tg_chi_xem()', t);
  end loop; end $$;

-- chứng từ lô nhập khẩu: bang 'lo_nk', quyền theo trang Nhà cung cấp
alter table public.kt_chung_tu drop constraint if exists kt_chung_tu_bang_check;
alter table public.kt_chung_tu add constraint kt_chung_tu_bang_check check (bang = any (array['thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung','bao_loi','ho_so','ncc','lo_nk']));

CREATE OR REPLACE FUNCTION public.kt_quyen_chung_tu(p_phien text, p_bang text, p_ghi boolean, p_ids bigint[])
 RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  if p_bang not in ('bao_loi','thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung','ho_so','ncc','lo_nk') then raise exception 'Bảng chứng từ không hợp lệ'; end if;
  u := kt_chan_dong(p_phien, p_bang, p_ids, p_ghi);
  return u.ho_ten;
end $function$;

CREATE OR REPLACE FUNCTION public.kt_chan_dong(p_phien text, p_bang text, p_ids bigint[], p_ghi boolean)
 RETURNS kt_nguoi_dung LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
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
  if kt_co_quyen(u, case p_bang when 'kiem_quy' then 'kiem_ket' when 'lo_nk' then 'ncc' else p_bang end, p_ghi) then return u; end if;
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

-- giá trị VND 1 đơn: giá trị nguyên tệ × tỷ giá (đơn → lô; VND = 1); chưa có giá trị thì lấy tổng phiếu nhập Kiot đã nối
create or replace function public.kt_lo_nk_don_vnd(d kt_lo_nk_don, l kt_lo_nk) returns numeric language sql stable set search_path = public as $$
  select case when d.gia_tri is not null then round(d.gia_tri * case when coalesce(d.tien_te, l.tien_te) = 'VND' then 1 else coalesce(d.ty_gia, l.ty_gia, 0) end)
              else (select h.tong from kt_kiot_nhap_hang h where h.id = d.nhap_id) end $$;

-- danh sách hồ sơ nhập khẩu (trang + thẻ): mỗi lô kèm số đơn, NCC, giá trị hàng VND, chi phí, số chứng từ
create or replace function public.kt_ds_lo_nk(p_phien text) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(to_jsonb(l) || jsonb_build_object(
      'so_don', (select count(*) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa),
      'ncc', (select coalesce(jsonb_agg(distinct n.ten), '[]') from kt_lo_nk_don d join kt_ncc n on n.id = d.ncc_id where d.lo_id = l.id and not d.da_xoa),
      'gia_tri', (select coalesce(sum(kt_lo_nk_don_vnd(d, l)), 0) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa),
      'gia_tri_te', (select sum(d.gia_tri) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa and coalesce(d.tien_te, l.tien_te) = l.tien_te),
      'chi_phi', (select coalesce(sum(c.so_tien), 0) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and c.tinh_gv),
      'chi_phi_khac', (select coalesce(sum(c.so_tien), 0) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and not c.tinh_gv),
      'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'lo_nk' and ct.dong_id = l.id and not ct.da_xoa))
    order by coalesce(l.ngay_kh, l.tao_luc::date) desc, l.id desc) from kt_lo_nk l where not l.da_xoa), '[]');
end $$;

-- 1 hồ sơ: lô · đơn hàng (NCC, phiếu nhập Kiot đã nối kèm chi tiết hàng) · chi phí (phiếu chi đã nối) · chứng từ
create or replace function public.kt_lo_nk_ct(p_phien text, p_id bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; l kt_lo_nk;
begin
  u := kt_chan(p_phien, 'ncc');
  select * into l from kt_lo_nk where id = p_id and not da_xoa;
  if l.id is null then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  return jsonb_build_object('lo', to_jsonb(l),
    'don', coalesce((select jsonb_agg(to_jsonb(d) || jsonb_build_object('gia_tri_vnd', kt_lo_nk_don_vnd(d, l),
        'ncc', jsonb_build_object('id', n.id, 'ma', n.ma, 'ten', n.ten, 'loai', n.loai, 'tien_te', n.them->>'tien_te', 'ty_gia', n.them->>'ty_gia'),
        'nhap', (select jsonb_build_object('id', h.id, 'ma', h.ma, 'ngay', h.ngay, 'tong', h.tong, 'chi_tiet', h.chi_tiet) from kt_kiot_nhap_hang h where h.id = d.nhap_id),
        'hs', (select jsonb_build_object('id', s.id, 'ten', s.ten, 'so_hd', s.so_hd) from kt_ho_so s where s.id = d.ho_so_id))
      order by d.ngay nulls last, d.id) from kt_lo_nk_don d join kt_ncc n on n.id = d.ncc_id where d.lo_id = p_id and not d.da_xoa), '[]'),
    'cp', coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object('chi', (select jsonb_build_object('id', k.id, 'ngay', coalesce(k.ngay_tt, k.ngay_de_nghi), 'noi_dung', k.noi_dung,
          'so_tien', k.so_tien, 'trang_thai', k.trang_thai, 'nguoi_nhan', coalesce(k.nguoi_nhan_tien, k.thu_huong_ten)) from kt_chi k where k.id = c.chi_id))
      order by c.ngay nulls last, c.id) from kt_lo_nk_cp c where c.lo_id = p_id and not c.da_xoa), '[]'),
    'ct', coalesce((select jsonb_agg(jsonb_build_object('id', ct.id, 'ten', ct.ten_file, 'mime', ct.mime, 'tao_boi', ct.tao_boi, 'tao_luc', ct.tao_luc) order by ct.id)
      from kt_chung_tu ct where ct.bang = 'lo_nk' and ct.dong_id = p_id and not ct.da_xoa), '[]'));
end $$;

-- lưu lô (thêm / sửa); mã tự đặt NK-<năm>-<số thứ tự> khi thêm
create or replace function public.kt_luu_lo_nk(p_phien text, p_dong jsonb) returns bigint language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_nam text; v_ma text; v_n int;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if nullif(trim(p_dong->>'ten'), '') is null then raise exception 'Nhập tên lô hàng'; end if;
  if nullif(p_dong->>'ty_gia', '') is not null and (p_dong->>'ty_gia')::numeric <= 0 then raise exception 'Tỷ giá phải lớn hơn 0'; end if;
  if v_id is null then
    v_nam := to_char(coalesce(nullif(p_dong->>'ngay_kh', '')::date, current_date), 'YYYY');
    select coalesce(max(nullif(regexp_replace(ma, '^NK-' || v_nam || '-', ''), ma)::int), 0) + 1 into v_n from kt_lo_nk where ma ~ ('^NK-' || v_nam || '-[0-9]+$');
    v_ma := coalesce(nullif(trim(p_dong->>'ma'), ''), 'NK-' || v_nam || '-' || lpad(v_n::text, 2, '0'));
    if exists (select 1 from kt_lo_nk where ma = v_ma) then raise exception 'Mã hồ sơ % đã có', v_ma; end if;
    insert into kt_lo_nk (ma, ten, trang_thai, so_cont, forwarder, ngay_kh, ngay_du_kien, ngay_ve, tien_te, ty_gia, cach_pb, ghi_chu, tao_boi)
    values (v_ma, trim(p_dong->>'ten'), coalesce(nullif(p_dong->>'trang_thai', ''), 'dat_hang'), nullif(trim(p_dong->>'so_cont'), ''), nullif(trim(p_dong->>'forwarder'), ''),
      nullif(p_dong->>'ngay_kh', '')::date, nullif(p_dong->>'ngay_du_kien', '')::date, nullif(p_dong->>'ngay_ve', '')::date,
      coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'), nullif(p_dong->>'ty_gia', '')::numeric, coalesce(nullif(p_dong->>'cach_pb', ''), 'gia_tri'), nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten)
    returning id into v_id;
  else
    if nullif(trim(p_dong->>'ma'), '') is not null and exists (select 1 from kt_lo_nk where ma = trim(p_dong->>'ma') and id <> v_id) then raise exception 'Mã hồ sơ % đã có', trim(p_dong->>'ma'); end if;
    update kt_lo_nk set ma = coalesce(nullif(trim(p_dong->>'ma'), ''), ma), ten = trim(p_dong->>'ten'), trang_thai = coalesce(nullif(p_dong->>'trang_thai', ''), trang_thai),
      so_cont = nullif(trim(p_dong->>'so_cont'), ''), forwarder = nullif(trim(p_dong->>'forwarder'), ''),
      ngay_kh = nullif(p_dong->>'ngay_kh', '')::date, ngay_du_kien = nullif(p_dong->>'ngay_du_kien', '')::date, ngay_ve = nullif(p_dong->>'ngay_ve', '')::date,
      tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te), ty_gia = nullif(p_dong->>'ty_gia', '')::numeric, cach_pb = coalesce(nullif(p_dong->>'cach_pb', ''), cach_pb),
      ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
    if not found then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

-- chỉ đổi trạng thái (bấm nhanh trên bảng / popup)
create or replace function public.kt_lo_nk_trang_thai(p_phien text, p_id bigint, p_tt text) returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc', true);
  update kt_lo_nk set trang_thai = p_tt, ngay_ve = case when p_tt in ('ve_kho','hoan_tat') then coalesce(ngay_ve, current_date) else ngay_ve end, sua_boi = u.ho_ten, sua_luc = now()
   where id = p_id and not da_xoa;
  if not found then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk', p_id, 'trang_thai', jsonb_build_object('trang_thai', p_tt));
end $$;

create or replace function public.kt_xoa_lo_nk(p_phien text, p_id bigint) returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc', true);
  update kt_lo_nk set da_xoa = true, sua_boi = u.ho_ten, sua_luc = now() where id = p_id and not da_xoa;
  if not found then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk', p_id, 'xoa', null);
end $$;

-- đơn hàng (PO) trong lô; hàng = [{ma, ten, sl, gia}] (đơn giá nguyên tệ); giá trị để trống thì = tổng hàng
create or replace function public.kt_luu_lo_nk_don(p_phien text, p_dong jsonb) returns bigint language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; n kt_ncc; v_hang jsonb := coalesce(p_dong->'hang', '[]'); v_gt numeric; v_lo bigint := (p_dong->>'lo_id')::bigint;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if v_id is not null then select lo_id into v_lo from kt_lo_nk_don where id = v_id and not da_xoa; if v_lo is null then raise exception 'Không thấy đơn hàng'; end if; end if;
  if not exists (select 1 from kt_lo_nk where id = v_lo and not da_xoa) then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  select * into n from kt_ncc where id = (p_dong->>'ncc_id')::bigint and not da_xoa;
  if n.id is null then raise exception 'Chọn nhà cung cấp'; end if;
  if jsonb_typeof(v_hang) <> 'array' then raise exception 'Danh sách hàng không hợp lệ'; end if;
  if nullif(p_dong->>'nhap_id', '') is not null and (n.kiot_id is null or not exists (select 1 from kt_kiot_nhap_hang h where h.id = (p_dong->>'nhap_id')::bigint and h.ncc_id = n.kiot_id)) then
    raise exception 'Phiếu nhập Kiot không thuộc NCC này'; end if;
  if nullif(p_dong->>'ho_so_id', '') is not null and not exists (select 1 from kt_ho_so s where s.id = (p_dong->>'ho_so_id')::bigint and s.ncc_id = n.id and not s.da_xoa) then
    raise exception 'Hợp đồng không thuộc NCC này'; end if;
  v_gt := coalesce(nullif(p_dong->>'gia_tri', '')::numeric, (select nullif(sum(coalesce((h->>'sl')::numeric, 0) * coalesce((h->>'gia')::numeric, 0)), 0) from jsonb_array_elements(v_hang) h));
  if v_id is null then
    insert into kt_lo_nk_don (lo_id, ncc_id, ma_po, ngay, tien_te, ty_gia, gia_tri, trang_thai, nhap_id, ho_so_id, hang, ghi_chu, tao_boi)
    values (v_lo, n.id, nullif(trim(p_dong->>'ma_po'), ''), nullif(p_dong->>'ngay', '')::date, nullif(p_dong->>'tien_te', ''), nullif(p_dong->>'ty_gia', '')::numeric, v_gt,
      coalesce(nullif(p_dong->>'trang_thai', ''), 'san_xuat'), nullif(p_dong->>'nhap_id', '')::bigint, nullif(p_dong->>'ho_so_id', '')::bigint, v_hang, nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten)
    returning id into v_id;
  else
    update kt_lo_nk_don set ncc_id = n.id, ma_po = nullif(trim(p_dong->>'ma_po'), ''), ngay = nullif(p_dong->>'ngay', '')::date, tien_te = nullif(p_dong->>'tien_te', ''),
      ty_gia = nullif(p_dong->>'ty_gia', '')::numeric, gia_tri = v_gt, trang_thai = coalesce(nullif(p_dong->>'trang_thai', ''), trang_thai),
      nhap_id = nullif(p_dong->>'nhap_id', '')::bigint, ho_so_id = nullif(p_dong->>'ho_so_id', '')::bigint, hang = v_hang, ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''),
      sua_boi = u.ho_ten, sua_luc = now() where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk_don', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong - 'hang' || jsonb_build_object('so_hang', jsonb_array_length(v_hang)));
  return v_id;
end $$;

create or replace function public.kt_xoa_lo_nk_don(p_phien text, p_id bigint) returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc', true);
  update kt_lo_nk_don set da_xoa = true, sua_boi = u.ho_ten, sua_luc = now() where id = p_id and not da_xoa;
  if not found then raise exception 'Không thấy đơn hàng'; end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk_don', p_id, 'xoa', null);
end $$;

-- chi phí lô (VND)
create or replace function public.kt_luu_lo_nk_cp(p_phien text, p_dong jsonb) returns bigint language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_lo bigint := (p_dong->>'lo_id')::bigint; v_chi bigint := nullif(p_dong->>'chi_id', '')::bigint;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if v_id is not null then select lo_id into v_lo from kt_lo_nk_cp where id = v_id and not da_xoa; if v_lo is null then raise exception 'Không thấy khoản chi phí'; end if; end if;
  if not exists (select 1 from kt_lo_nk where id = v_lo and not da_xoa) then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  if not (nullif(p_dong->>'so_tien', '')::numeric >= 0) then raise exception 'Nhập số tiền'; end if;
  if v_chi is not null and not exists (select 1 from kt_chi where id = v_chi and not da_xoa) then raise exception 'Không thấy phiếu chi PC%', lpad(v_chi::text, 6, '0'); end if;
  if v_id is null then
    insert into kt_lo_nk_cp (lo_id, loai, noi_dung, so_tien, tinh_gv, chi_id, ngay, ghi_chu, tao_boi)
    values (v_lo, coalesce(nullif(p_dong->>'loai', ''), 'khac'), nullif(trim(p_dong->>'noi_dung'), ''), (p_dong->>'so_tien')::numeric,
      coalesce((p_dong->>'tinh_gv')::boolean, true), v_chi, nullif(p_dong->>'ngay', '')::date, nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten) returning id into v_id;
  else
    update kt_lo_nk_cp set loai = coalesce(nullif(p_dong->>'loai', ''), loai), noi_dung = nullif(trim(p_dong->>'noi_dung'), ''), so_tien = (p_dong->>'so_tien')::numeric,
      tinh_gv = coalesce((p_dong->>'tinh_gv')::boolean, tinh_gv), chi_id = v_chi, ngay = nullif(p_dong->>'ngay', '')::date, ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''),
      sua_boi = u.ho_ten, sua_luc = now() where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk_cp', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

create or replace function public.kt_xoa_lo_nk_cp(p_phien text, p_id bigint) returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc', true);
  update kt_lo_nk_cp set da_xoa = true, sua_boi = u.ho_ten, sua_luc = now() where id = p_id and not da_xoa;
  if not found then raise exception 'Không thấy khoản chi phí'; end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk_cp', p_id, 'xoa', null);
end $$;

-- tìm phiếu chi để nối vào chi phí lô (số phiếu / nội dung / người nhận / số tiền); trống = phiếu gần đây có chữ hải quan, thuế, vận chuyển, cont, logistics
create or replace function public.kt_lo_nk_tim_chi(p_phien text, p_q text) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; q text := nullif(trim(coalesce(p_q, '')), ''); v_so bigint; v_tien numeric;
begin
  u := kt_chan(p_phien, 'ncc');
  if q ~* '^(pc)?\s*0*[0-9]{1,6}$' then v_so := regexp_replace(q, '\D', '', 'g')::bigint; end if;
  if q ~ '^[0-9.,]{5,}$' then v_tien := regexp_replace(q, '\D', '', 'g')::numeric; end if;
  return coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'noi_dung', c.noi_dung, 'so_tien', c.so_tien, 'trang_thai', c.trang_thai,
      'nguoi_nhan', coalesce(c.nguoi_nhan_tien, c.thu_huong_ten), 'da_noi', exists (select 1 from kt_lo_nk_cp p join kt_lo_nk l on l.id = p.lo_id where p.chi_id = c.id and not p.da_xoa and not l.da_xoa)) x
      from kt_chi c where not c.da_xoa and c.trang_thai not in ('tu_choi','tu_choi_tt')
       and case when q is null then (c.noi_dung || ' ' || coalesce(c.thu_huong_ten, '')) ~* '(hải quan|hai quan|thuế nhập|thue nhap|nhập khẩu|nhap khau|vận chuyển|van chuyen|cont|logistic|forwarder|cước)'
                when v_so is not null then c.id = v_so or c.so_tien = v_so
                when v_tien is not null then c.so_tien = v_tien
                else (c.noi_dung || ' ' || coalesce(c.thu_huong_ten, '') || ' ' || coalesce(c.nguoi_nhan_tien, '')) ilike '%' || q || '%' end
     order by coalesce(c.ngay_tt, c.ngay_de_nghi) desc nulls last, c.id desc limit 30) t), '[]');
end $$;

-- phiếu nhập Kiot của 1 NCC (để nối đơn hàng khi hàng về); kèm đã nối vào đơn nào
create or replace function public.kt_lo_nk_nhap(p_phien text, p_ncc bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; n kt_ncc;
begin
  u := kt_chan(p_phien, 'ncc');
  select * into n from kt_ncc where id = p_ncc and not da_xoa;
  if n.kiot_id is null then return '[]'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'ngay', h.ngay, 'tong', h.tong, 'so_hang', jsonb_array_length(coalesce(h.chi_tiet, '[]')),
      'don', (select l.ma from kt_lo_nk_don d join kt_lo_nk l on l.id = d.lo_id where d.nhap_id = h.id and not d.da_xoa and not l.da_xoa limit 1)) order by h.ngay desc)
    from kt_kiot_nhap_hang h where h.ncc_id = n.kiot_id and h.trang_thai = 3 and h.ma !~ '\{DEL\}'), '[]');
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_ds_lo_nk(text)','kt_lo_nk_ct(text, bigint)','kt_luu_lo_nk(text, jsonb)','kt_lo_nk_trang_thai(text, bigint, text)','kt_xoa_lo_nk(text, bigint)',
    'kt_luu_lo_nk_don(text, jsonb)','kt_xoa_lo_nk_don(text, bigint)','kt_luu_lo_nk_cp(text, jsonb)','kt_xoa_lo_nk_cp(text, bigint)','kt_lo_nk_tim_chi(text, text)','kt_lo_nk_nhap(text, bigint)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
  revoke all on function public.kt_lo_nk_don_vnd(kt_lo_nk_don, kt_lo_nk) from public, anon, authenticated;
end $$;

-- popup NCC: thêm danh sách hồ sơ nhập khẩu có đơn của NCC (khoá 'lo_nk')
CREATE OR REPLACE FUNCTION public.kt_ncc_ct(p_phien text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; n kt_ncc; v_chi bigint[]; v_hs bigint[];
begin
  u := kt_chan(p_phien, 'ncc');
  select * into n from kt_ncc where id = p_id and not da_xoa;
  if n.id is null then raise exception 'Không thấy nhà cung cấp'; end if;
  select coalesce(array_agg(dong_id), '{}') into v_chi from kt_v_ncc_phieu where ncc_id = p_id and bang = 'chi';
  select coalesce(array_agg(id), '{}') into v_hs from kt_ho_so where ncc_id = p_id and not da_xoa;
  return jsonb_build_object(
    'ncc', to_jsonb(n) || jsonb_build_object('nguon', case when n.kiot_id is null then 'app' else 'kiot' end)
           || coalesce((select jsonb_build_object('cong_no', k.cong_no, 'tong_nhap', k.tong_nhap, 'tong_nhap_tru_tra', k.tong_nhap_tru_tra) from kt_kiot_ncc k where k.id = n.kiot_id), '{}'),
    'so', kt_ncc_so(p_id),
    'ho_so', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'ten', h.ten, 'loai', h.loai, 'so_hd', h.so_hd, 'ngay', h.ngay, 'gia_tri', h.gia_tri,
        'trang_thai', h.trang_thai, 'ghi_chu', h.ghi_chu, 'tao_boi', h.tao_boi,
        'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'ho_so' and ct.dong_id = h.id and not ct.da_xoa)) order by coalesce(h.ngay, h.tao_luc::date) desc, h.id desc)
      from kt_ho_so h where h.ncc_id = p_id and not h.da_xoa), '[]'),
    'phieu', coalesce((select jsonb_agg(x order by x->>'ngay' desc nulls last, (x->>'id')::bigint desc) from (
        select jsonb_build_object('bang', 'chi', 'id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'noi_dung', c.noi_dung, 'so_tien', c.so_tien,
          'trang_thai', c.trang_thai, 'nguoi_nhan', c.thu_huong_ten, 'stk', c.thu_huong_stk, 'tai_khoan_id', c.tai_khoan_id, 'loai_id', c.loai_id,
          'ho_so_id', p.ho_so_id, 'cach', p.cach, 'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'chi' and ct.dong_id = c.id and not ct.da_xoa)) x
          from kt_v_ncc_phieu p join kt_chi c on c.id = p.dong_id where p.bang = 'chi' and p.ncc_id = p_id
        union all
        select jsonb_build_object('bang', 'thu', 'id', t.id, 'ngay', t.ngay, 'noi_dung', t.noi_dung, 'so_tien', t.so_tien, 'trang_thai', t.trang_thai,
          'tai_khoan_id', t.tai_khoan_id, 'loai_id', t.loai_id, 'ho_so_id', p.ho_so_id, 'cach', p.cach,
          'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'thu' and ct.dong_id = t.id and not ct.da_xoa))
          from kt_v_ncc_phieu p join kt_thu t on t.id = p.dong_id where p.bang = 'thu' and p.ncc_id = p_id) z), '[]'),
    'tl', coalesce((select jsonb_object_agg(t.ct_id, jsonb_build_object('thu_muc', t.thu_muc, 'so_hieu', t.so_hieu, 'ngay_bh', t.ngay_bh, 'hl_tu', t.hl_tu, 'hl_den', t.hl_den, 'mo_ta', t.mo_ta, 'ho_so_id', t.ho_so_id, 'sua_boi', t.sua_boi, 'sua_luc', t.sua_luc))
        from kt_tai_lieu t where t.ncc_id = p_id), '{}'),
    'pb', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'chi_id', b.chi_id, 'nhap_id', b.nhap_id, 'so_tien', b.so_tien, 'tao_boi', b.tao_boi)) from kt_ncc_phan_bo b where b.ncc_id = p_id), '[]'),
    'dm', (select nullif(gia_tri, '')::jsonb from kt_cai_dat where khoa = 'tl_danh_muc'),
    'thu_muc', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'ten', m.ten, 'cha', m.cha) order by m.id) from kt_ncc_thu_muc m where m.ncc_id = p_id and not m.da_xoa), '[]'),
    'lo_nk', coalesce((select jsonb_agg(x order by x->>'ma') from (select distinct jsonb_build_object('id', l.id, 'ma', l.ma, 'ten', l.ten, 'trang_thai', l.trang_thai) x from kt_lo_nk_don d join kt_lo_nk l on l.id = d.lo_id where d.ncc_id = p_id and not d.da_xoa and not l.da_xoa) t), '[]'),   -- 30/10 hồ sơ nhập khẩu có đơn của NCC
    'han', coalesce((select nullif(gia_tri, '')::int from kt_cai_dat where khoa = 'han_no_ncc_ngay'), 30),
    'no', case when n.kiot_id is not null then kt_cong_no_dt_ct(p_phien, 'ncc', n.kiot_id) end,
    'nhap', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'ngay', h.ngay, 'chi_nhanh', h.chi_nhanh, 'tong', h.tong, 'da_tra', h.da_tra, 'trang_thai', h.trang_thai, 'mo_ta', h.mo_ta,
          'ho_so_id', (select g.ho_so_id from kt_ncc_gan g where g.bang = 'nhap' and g.dong_id = h.id), 'giam_gia', h.giam_gia, 'chi_tiet', h.chi_tiet)
        order by h.ngay desc) from kt_kiot_nhap_hang h where n.kiot_id is not null and h.ncc_id = n.kiot_id), '[]'),
    'ct', coalesce((select jsonb_agg(jsonb_build_object('id', ct.id, 'bang', ct.bang, 'dong_id', ct.dong_id, 'ten', ct.ten_file, 'mime', ct.mime, 'tao_boi', ct.tao_boi, 'tao_luc', ct.tao_luc) order by ct.tao_luc desc)
        from kt_chung_tu ct where not ct.da_xoa and ((ct.bang = 'chi' and ct.dong_id = any (v_chi)) or (ct.bang = 'ho_so' and ct.dong_id = any (v_hs)) or (ct.bang = 'ncc' and ct.dong_id = p_id)
          or (ct.bang = 'thu' and ct.dong_id in (select dong_id from kt_v_ncc_phieu where ncc_id = p_id and bang = 'thu')))), '[]'));
end $function$
;

-- giá trị đơn trống mà có danh sách hàng → tính từ hàng (SL × đơn giá)
create or replace function public.kt_lo_nk_don_vnd(d kt_lo_nk_don, l kt_lo_nk) returns numeric language sql stable set search_path = public as $$
  select case when coalesce(d.gia_tri, (select nullif(sum(coalesce((h->>'sl')::numeric, 0) * coalesce((h->>'gia')::numeric, 0)), 0) from jsonb_array_elements(d.hang) h)) is not null
              then round(coalesce(d.gia_tri, (select sum(coalesce((h->>'sl')::numeric, 0) * coalesce((h->>'gia')::numeric, 0)) from jsonb_array_elements(d.hang) h))
                         * case when coalesce(d.tien_te, l.tien_te) = 'VND' then 1 else coalesce(d.ty_gia, l.ty_gia, 0) end)
              else (select h.tong from kt_kiot_nhap_hang h where h.id = d.nhap_id) end $$;
revoke all on function public.kt_lo_nk_don_vnd(kt_lo_nk_don, kt_lo_nk) from public, anon, authenticated;
