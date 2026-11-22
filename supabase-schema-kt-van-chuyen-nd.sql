-- 16/11/2026 — VẬN CHUYỂN NỘI ĐỊA (kế toán trả lời: "chỉ cần theo dõi danh mục các đơn vị vận chuyển và tiền thanh toán cho họ khi có phát sinh từng chuyến;
-- vd Nhất Tín trừ luôn vào tiền hàng COD, 1 số nhà xe thì cửa hàng xuất két trả tiền sau đó cộng luôn vào giá vốn trên Kiot").
--   kt_vc_dv     = danh mục đơn vị vận chuyển (chuyển phát / nhà xe / khác) + cách trả thường dùng
--   kt_vc_chuyen = từng chuyến: ngày, đơn vị, cơ sở, nội dung, số tiền, cách trả (tru_cod / cua_hang_tra / cong_ty_tra), mã Kiot, PO, phiếu chi
-- Chỉ THEO DÕI — không ghi vào P&L (trừ COD / cửa hàng trả đã nằm trong giá vốn Kiot; công ty trả có phiếu chi riêng) → tránh tính 2 lần. — Monsieur Claude
create table if not exists public.kt_vc_dv (
  id bigserial primary key, ten text not null, loai text not null default 'nha_xe' check (loai in ('chuyen_phat', 'nha_xe', 'khac')),
  cach_tt text not null default 'cua_hang_tra' check (cach_tt in ('tru_cod', 'cua_hang_tra', 'cong_ty_tra')), sdt text, ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, da_xoa boolean not null default false);
create table if not exists public.kt_vc_chuyen (
  id bigserial primary key, ngay date not null default current_date, dv_id bigint not null references kt_vc_dv(id), co_so int references kt_don_vi(id),
  noi_dung text, so_tien numeric not null check (so_tien >= 0), cach_tt text not null check (cach_tt in ('tru_cod', 'cua_hang_tra', 'cong_ty_tra')),
  ma_kiot text, po_id bigint, chi_id bigint, ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, da_xoa boolean not null default false);
create index if not exists kt_vc_chuyen_ngay on public.kt_vc_chuyen (ngay) where not da_xoa;
do $$ declare t text; begin
  foreach t in array array['kt_vc_dv', 'kt_vc_chuyen'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop; end $$;

create or replace function public.kt_vc_ds(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'ncc');
  return jsonb_build_object(
    'dv', coalesce((select jsonb_agg(to_jsonb(d) - 'da_xoa' order by d.ten) from kt_vc_dv d where not d.da_xoa), '[]'),
    'chuyen', coalesce((select jsonb_agg(to_jsonb(c) - 'da_xoa' || jsonb_build_object(
        'po', (select so from kt_po where id = c.po_id),
        'chi', (select jsonb_build_object('id', k.id, 'tt', k.trang_thai) from kt_chi k where k.id = c.chi_id and not k.da_xoa)) order by c.ngay desc, c.id desc)
      from kt_vc_chuyen c where not c.da_xoa and c.ngay between p_tu and p_den), '[]'));
end $$;

create or replace function public.kt_vc_dv_luu(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v bigint := nullif(p_dong->>'id', '')::bigint; v_ten text := btrim(p_dong->>'ten');
begin
  u := kt_chan(p_phien, 'ncc', true);
  if coalesce(v_ten, '') = '' then raise exception 'Nhập tên đơn vị vận chuyển'; end if;
  if exists (select 1 from kt_vc_dv where not da_xoa and lower(btrim(kt_vc_dv.ten)) = lower(v_ten) and kt_vc_dv.id is distinct from v) then raise exception 'Đã có đơn vị "%"', v_ten; end if;
  if v is null then
    insert into kt_vc_dv (ten, loai, cach_tt, sdt, ghi_chu, tao_boi)
    values (v_ten, coalesce(nullif(p_dong->>'loai', ''), 'nha_xe'), coalesce(nullif(p_dong->>'cach_tt', ''), 'cua_hang_tra'), nullif(btrim(p_dong->>'sdt'), ''), nullif(btrim(p_dong->>'ghi_chu'), ''), u.ho_ten)
    returning id into v;
  else
    update kt_vc_dv set ten = v_ten, loai = coalesce(nullif(p_dong->>'loai', ''), loai), cach_tt = coalesce(nullif(p_dong->>'cach_tt', ''), cach_tt),
           sdt = nullif(btrim(p_dong->>'sdt'), ''), ghi_chu = nullif(btrim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vc_dv', v, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v;
end $$;

create or replace function public.kt_vc_dv_xoa(p_phien text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if exists (select 1 from kt_vc_chuyen where dv_id = p_id and not da_xoa) then raise exception 'Đơn vị đã có chuyến — xoá / chuyển các chuyến trước'; end if;
  update kt_vc_dv set da_xoa = true, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vc_dv', p_id, 'xoa', null);
end $$;

create or replace function public.kt_vc_luu(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v bigint := nullif(p_dong->>'id', '')::bigint; tien numeric := nullif(p_dong->>'so_tien', '')::numeric; dv bigint := nullif(p_dong->>'dv_id', '')::bigint;
  ct text := p_dong->>'cach_tt'; chi bigint := nullif(p_dong->>'chi_id', '')::bigint;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if not exists (select 1 from kt_vc_dv where id = dv and not da_xoa) then raise exception 'Chọn đơn vị vận chuyển'; end if;
  if tien is null or tien < 0 then raise exception 'Nhập số tiền'; end if;
  if ct not in ('tru_cod', 'cua_hang_tra', 'cong_ty_tra') then raise exception 'Chọn cách thanh toán'; end if;
  if chi is not null and not exists (select 1 from kt_chi where id = chi and not da_xoa) then raise exception 'Không thấy phiếu chi PC%', lpad(chi::text, 6, '0'); end if;
  if v is null then
    insert into kt_vc_chuyen (ngay, dv_id, co_so, noi_dung, so_tien, cach_tt, ma_kiot, po_id, chi_id, ghi_chu, tao_boi)
    values (coalesce(nullif(p_dong->>'ngay', '')::date, current_date), dv, nullif(p_dong->>'co_so', '')::int, nullif(btrim(p_dong->>'noi_dung'), ''), tien, ct,
            nullif(btrim(p_dong->>'ma_kiot'), ''), nullif(p_dong->>'po_id', '')::bigint, chi, nullif(btrim(p_dong->>'ghi_chu'), ''), u.ho_ten)
    returning id into v;
  else
    update kt_vc_chuyen set ngay = coalesce(nullif(p_dong->>'ngay', '')::date, ngay), dv_id = dv, co_so = nullif(p_dong->>'co_so', '')::int,
           noi_dung = nullif(btrim(p_dong->>'noi_dung'), ''), so_tien = tien, cach_tt = ct, ma_kiot = nullif(btrim(p_dong->>'ma_kiot'), ''),
           po_id = nullif(p_dong->>'po_id', '')::bigint, chi_id = chi, ghi_chu = nullif(btrim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vc_chuyen', v, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v;
end $$;

create or replace function public.kt_vc_xoa(p_phien text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc', true);
  update kt_vc_chuyen set da_xoa = true, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vc_chuyen', p_id, 'xoa', null);
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_vc_ds(text, date, date)', 'kt_vc_dv_luu(text, jsonb)', 'kt_vc_dv_xoa(text, bigint)', 'kt_vc_luu(text, jsonb)', 'kt_vc_xoa(text, bigint)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop; end $$;
