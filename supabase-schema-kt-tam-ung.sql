-- TẠM ỨNG & HOÀN ỨNG (14/10/2026, Monsieur Claude). Sổ theo dõi: ai đang cầm tiền ứng, đã quyết toán bao nhiêu, còn phải hoàn bao nhiêu.
-- KHÔNG làm đổi số dư tài khoản: tiền ứng ra vẫn đi bằng Phiếu chi (như hiện nay), nhân viên trả lại tiền thì ghi Phiếu thu.
-- Ở đây chỉ gắn khoản ứng với phiếu chi đã chi + ghi các lần hoàn (bằng chứng từ chi phí / trả lại tiền / trừ lương).
create table if not exists public.kt_tam_ung (
  id bigserial primary key, ngay date not null, nguoi_nhan text not null, bo_phan_id int references kt_don_vi(id),
  so_tien numeric not null check (so_tien > 0), ly_do text, han_hoan date, chi_id bigint references kt_chi(id), ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, da_xoa boolean not null default false);
create unique index if not exists kt_tam_ung_chi_uq on public.kt_tam_ung (chi_id) where chi_id is not null and not da_xoa;
create table if not exists public.kt_tam_ung_hoan (
  id bigserial primary key, tam_ung_id bigint not null references kt_tam_ung(id), ngay date not null,
  hinh_thuc text not null check (hinh_thuc in ('chung_tu','tien','tru_luong')), so_tien numeric not null check (so_tien > 0),
  thu_id bigint references kt_thu(id), ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, da_xoa boolean not null default false);
alter table public.kt_tam_ung enable row level security;
alter table public.kt_tam_ung_hoan enable row level security;
revoke all on public.kt_tam_ung, public.kt_tam_ung_hoan from anon, authenticated;

create or replace function public.kt_ds_tam_ung(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'tam_ung');
  return coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object(
      'hoan', coalesce((select jsonb_agg(to_jsonb(h) order by h.ngay, h.id) from kt_tam_ung_hoan h where h.tam_ung_id = t.id and not h.da_xoa), '[]'),
      'da_hoan', coalesce((select sum(h.so_tien) from kt_tam_ung_hoan h where h.tam_ung_id = t.id and not h.da_xoa), 0),
      'chi', (select jsonb_build_object('id', c.id, 'noi_dung', c.noi_dung, 'ngay_tt', c.ngay_tt, 'so_tien', c.so_tien, 'trang_thai', c.trang_thai) from kt_chi c where c.id = t.chi_id))
    order by t.ngay desc, t.id desc) from kt_tam_ung t where not t.da_xoa), '[]');
end $$;

-- phiếu chi có chữ "ứng" (tạm ứng, ứng lương…) chưa gắn khoản tạm ứng → gợi ý tạo nhanh
create or replace function public.kt_goi_y_tam_ung(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'tam_ung');
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'noi_dung', c.noi_dung, 'so_tien', c.so_tien,
      'nguoi', coalesce(nullif(c.thu_huong_ten, ''), c.nguoi_de_nghi), 'bo_phan_id', c.bo_phan_id, 'trang_thai', c.trang_thai) order by coalesce(c.ngay_tt, c.ngay_de_nghi) desc)
    from kt_chi c where not c.da_xoa and c.trang_thai <> 'tu_choi'
      and (c.noi_dung ilike '%tạm ứng%' or c.noi_dung ilike '%tam ung%' or c.noi_dung ilike '%ứng lương%' or c.noi_dung ilike '%ứng trước%')
      and not exists (select 1 from kt_tam_ung t where t.chi_id = c.id and not t.da_xoa)), '[]');
end $$;

create or replace function public.kt_luu_tam_ung(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_tien numeric := (p_dong->>'so_tien')::numeric;
begin
  u := kt_chan(p_phien, 'tam_ung', true);
  if nullif(trim(p_dong->>'nguoi_nhan'), '') is null or v_tien is null or v_tien <= 0 or (p_dong->>'ngay') is null then
    raise exception 'Cần người nhận, số tiền, ngày ứng'; end if;
  if v_id is not null and v_tien < coalesce((select sum(so_tien) from kt_tam_ung_hoan where tam_ung_id = v_id and not da_xoa), 0) then
    raise exception 'Số tiền ứng nhỏ hơn số đã hoàn'; end if;
  if v_id is null then
    insert into kt_tam_ung (ngay, nguoi_nhan, bo_phan_id, so_tien, ly_do, han_hoan, chi_id, ghi_chu, tao_boi)
    values ((p_dong->>'ngay')::date, trim(p_dong->>'nguoi_nhan'), (p_dong->>'bo_phan_id')::int, v_tien, nullif(trim(p_dong->>'ly_do'), ''),
      (p_dong->>'han_hoan')::date, (p_dong->>'chi_id')::bigint, nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten) returning id into v_id;
  else
    update kt_tam_ung set ngay = (p_dong->>'ngay')::date, nguoi_nhan = trim(p_dong->>'nguoi_nhan'), bo_phan_id = (p_dong->>'bo_phan_id')::int, so_tien = v_tien,
      ly_do = nullif(trim(p_dong->>'ly_do'), ''), han_hoan = (p_dong->>'han_hoan')::date, chi_id = (p_dong->>'chi_id')::bigint,
      ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_tam_ung', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

create or replace function public.kt_luu_tam_ung_hoan(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_tu bigint := (p_dong->>'tam_ung_id')::bigint; v_tien numeric := (p_dong->>'so_tien')::numeric; v_con numeric;
begin
  u := kt_chan(p_phien, 'tam_ung', true);
  if v_tu is null or v_tien is null or v_tien <= 0 or (p_dong->>'ngay') is null then raise exception 'Cần ngày và số tiền hoàn'; end if;
  select t.so_tien - coalesce((select sum(h.so_tien) from kt_tam_ung_hoan h where h.tam_ung_id = t.id and not h.da_xoa and h.id is distinct from v_id), 0)
    into v_con from kt_tam_ung t where t.id = v_tu and not t.da_xoa;
  if v_con is null then raise exception 'Không thấy khoản tạm ứng'; end if;
  if v_tien > v_con then raise exception 'Hoàn vượt số còn phải hoàn (còn %)', replace(to_char(v_con, 'FM999G999G999G999'), ',', '.'); end if;
  if v_id is null then
    insert into kt_tam_ung_hoan (tam_ung_id, ngay, hinh_thuc, so_tien, thu_id, ghi_chu, tao_boi)
    values (v_tu, (p_dong->>'ngay')::date, coalesce(p_dong->>'hinh_thuc', 'chung_tu'), v_tien, (p_dong->>'thu_id')::bigint, nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten)
    returning id into v_id;
  else
    update kt_tam_ung_hoan set ngay = (p_dong->>'ngay')::date, hinh_thuc = coalesce(p_dong->>'hinh_thuc', hinh_thuc), so_tien = v_tien,
      thu_id = (p_dong->>'thu_id')::bigint, ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and tam_ung_id = v_tu and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_tam_ung_hoan', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_ds_tam_ung(text)','kt_goi_y_tam_ung(text)','kt_luu_tam_ung(text, jsonb)','kt_luu_tam_ung_hoan(text, jsonb)'] loop
    execute format('revoke execute on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop; end $$;

-- kt_xoa (bản đang chạy 14/10) + thêm tam_ung / tam_ung_hoan (quyền theo trang tam_ung)
CREATE OR REPLACE FUNCTION public.kt_xoa(p_phien text, p_bang text, p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, case when p_bang = 'cong_no_thu' then 'cong_no' when p_bang = 'vay_tra' then 'vay' when p_bang = 'tam_ung_hoan' then 'tam_ung' else p_bang end, true);
  if p_bang not in ('thu','chi','dieu_chuyen','cong_no','cong_no_thu','sap_tra','vay','vay_tra','tai_san','tam_ung','tam_ung_hoan') then raise exception 'Bảng không hợp lệ'; end if;
  execute format('update public.%I set da_xoa = true where id = $1', 'kt_' || p_bang) using p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, 'xoa', null);
end $function$;
