-- 04/11/2026 anh: "mỗi nhân sự trong bảng hoa hồng 1 mã, chỗ truy cập trong trang kế toán luôn, 1 ô riêng để check hoa hồng
-- bên dưới chỗ đăng nhập app, mỗi mã gắn với dữ liệu 1 người" (kế toán đề xuất: sales tự xem hoa hồng, không điền file tay).
-- Mã do quản trị (quyền sửa trang P&L / Hoa hồng) tạo ở trang Hoa hồng; tra cứu qua Edge kt-hoa-hong-ma: Edge chạy ĐÚNG hàm hhTinh của
-- index.html trên dữ liệu kt_bc_hoa_hong_dl rồi chỉ trả phần của người có mã. Chặn dò mã: 1 máy sai 10 lần / 15 phút, toàn hệ thống 200. — Monsieur Claude

-- 1. tách phần dữ liệu của kt_bc_hoa_hong (không kiểm phiên) để Edge dùng chung; kt_bc_hoa_hong = kiểm phiên + gọi phần dữ liệu
do $$ declare d text := pg_get_functiondef('public.kt_bc_hoa_hong(text, date, date)'::regprocedure); begin
  if position('perform kt_chan(p_phien, ''pl'');' in d) = 0 then raise exception 'kt_bc_hoa_hong đổi cấu trúc — soát tay'; end if;
  d := replace(d, 'perform kt_chan(p_phien, ''pl'');', '');
  d := replace(d, 'public.kt_bc_hoa_hong(p_phien text, p_tu date, p_den date)', 'public.kt_bc_hoa_hong_dl(p_tu date, p_den date)');
  if position('p_phien' in d) > 0 then raise exception 'thân hàm còn dùng p_phien'; end if;
  execute d;
end $$;
revoke execute on function public.kt_bc_hoa_hong_dl(date, date) from public, anon, authenticated;

create or replace function public.kt_bc_hoa_hong(p_phien text, p_tu date, p_den date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'pl');
  return kt_bc_hoa_hong_dl(p_tu, p_den);
end $$;

-- 2. mã tra cứu
create table if not exists public.kt_hh_ma (
  ten text primary key,            -- đúng tên nhân sự trên bảng hoa hồng
  ma text not null unique,
  tao_boi text, tao_luc timestamptz not null default now(),
  dung_luc timestamptz, so_lan int not null default 0
);
create table if not exists public.kt_hh_ma_thu (id bigserial primary key, ip text, ok boolean not null, luc timestamptz not null default now());
create index if not exists kt_hh_ma_thu_luc on public.kt_hh_ma_thu (luc);
alter table public.kt_hh_ma enable row level security;
alter table public.kt_hh_ma_thu enable row level security;
revoke all on public.kt_hh_ma, public.kt_hh_ma_thu from anon, authenticated;

create or replace function public.kt_hh_ma_ds(p_phien text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'pl', true);
  return coalesce((select jsonb_agg(jsonb_build_object('ten', ten, 'ma', ma, 'tao_boi', tao_boi, 'tao_luc', tao_luc, 'dung_luc', dung_luc, 'so_lan', so_lan) order by ten) from kt_hh_ma), '[]');
end $$;

create or replace function public.kt_hh_ma_luu(p_phien text, p_ten text, p_xoa boolean default false)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare u kt_nguoi_dung; v_ma text; v_bc text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; b bytea; i int;
begin
  u := kt_chan(p_phien, 'pl', true);
  if coalesce(trim(p_ten), '') = '' then raise exception 'Thiếu tên nhân sự'; end if;
  if p_xoa then
    delete from kt_hh_ma where ten = trim(p_ten);
  else
    loop
      b := gen_random_bytes(8); v_ma := '';
      for i in 0..7 loop v_ma := v_ma || substr(v_bc, (get_byte(b, i) % length(v_bc)) + 1, 1); end loop;
      exit when not exists (select 1 from kt_hh_ma where ma = v_ma);
    end loop;
    insert into kt_hh_ma (ten, ma, tao_boi) values (trim(p_ten), v_ma, u.ho_ten)
      on conflict (ten) do update set ma = excluded.ma, tao_boi = excluded.tao_boi, tao_luc = now(), dung_luc = null, so_lan = 0;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_hh_ma', null, case when p_xoa then 'xoa_ma_hh' else 'tao_ma_hh' end, jsonb_build_object('ten', trim(p_ten)));   -- không ghi mã vào nhật ký
  return case when p_xoa then null else v_ma end;
end $$;

-- Edge (service role) gọi: kiểm mã + chặn dò → tên nhân sự
create or replace function public.kt_hh_ma_tra(p_ma text, p_ip text)
returns text language plpgsql security definer set search_path = public as $$
declare v_ten text; v_ma text := upper(regexp_replace(coalesce(p_ma, ''), '\s', '', 'g'));
begin
  delete from kt_hh_ma_thu where luc < now() - interval '2 days';
  if (select count(*) from kt_hh_ma_thu where not ok and ip = p_ip and luc > now() - interval '15 minutes') >= 10
     or (select count(*) from kt_hh_ma_thu where not ok and luc > now() - interval '15 minutes') >= 200 then
    raise exception 'Nhập sai mã nhiều lần — đợi 15 phút rồi thử lại';
  end if;
  select ten into v_ten from kt_hh_ma where ma = v_ma;
  insert into kt_hh_ma_thu (ip, ok) values (p_ip, v_ten is not null);
  if v_ten is null then raise exception 'Mã không đúng'; end if;
  update kt_hh_ma set dung_luc = now(), so_lan = so_lan + 1 where ma = v_ma;
  return v_ten;
end $$;
revoke execute on function public.kt_hh_ma_tra(text, text) from public, anon, authenticated;

revoke execute on function public.kt_hh_ma_ds(text) from public;
grant execute on function public.kt_hh_ma_ds(text) to anon, authenticated;
revoke execute on function public.kt_hh_ma_luu(text, text, boolean) from public;
grant execute on function public.kt_hh_ma_luu(text, text, boolean) to anon, authenticated;
