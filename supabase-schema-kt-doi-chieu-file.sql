-- ĐỐI CHIẾU SỔ QUỸ / SỐ DƯ VỚI FILE "THT BẢNG KIỂM SOÁT DÒNG TIỀN" (16/10/2026, anh Hải) — Monsieur Claude
-- Anh: "follow theo trang quỹ & số dư trong file (3.CASHFLOW TỔNG) để chỉnh số cho chuẩn … không khớp note ra, note vào app luôn"
--      + "duy trì kéo dữ liệu file gg sheet dòng tiền T10 vào để đối chiếu".
-- kt_dcf_ngay: số của FILE theo tài khoản × ngày (thu / chi / tồn sổ sách / tồn thực tế) — nạp bằng kt_nap_dcf (script kéo file định kỳ).
-- Số APP tính trực tiếp từ kt_v_bien_dong lúc xem → sửa dữ liệu xong lệch tự cập nhật. Ghi chú lệch: kt_dcf_ghi_chu (kế toán / hệ thống).
create table if not exists public.kt_dcf_ngay (
  tai_khoan_id int not null references kt_tai_khoan(id), ngay date not null,
  thu numeric not null default 0, chi numeric not null default 0, ton_ss numeric, ton_tt numeric,
  file_thang text not null, nap_luc timestamptz not null default now(),
  primary key (tai_khoan_id, ngay));
create table if not exists public.kt_dcf_dau (   -- tồn đầu kì từng tháng theo file
  tai_khoan_id int not null references kt_tai_khoan(id), thang text not null, ton_dau numeric not null,
  nap_luc timestamptz not null default now(), primary key (tai_khoan_id, thang));
create table if not exists public.kt_dcf_ghi_chu (
  tai_khoan_id int not null references kt_tai_khoan(id), ngay date not null, ghi_chu text not null,
  da_xu_ly boolean not null default false, sua_boi text, sua_luc timestamptz not null default now(),
  primary key (tai_khoan_id, ngay));
alter table public.kt_dcf_ngay enable row level security;
alter table public.kt_dcf_dau enable row level security;
alter table public.kt_dcf_ghi_chu enable row level security;
revoke all on public.kt_dcf_ngay, public.kt_dcf_dau, public.kt_dcf_ghi_chu from anon, authenticated;

-- Nạp 1 tháng của file (chỉ service_role — script kéo file). p_dl: {"thang":"2026-10","dau":[{"tk":"VCB CTY - …","ton":…}],
--   "ngay":[{"tk":"…","ngay":"2026-10-01","thu":…,"chi":…,"ton_ss":…,"ton_tt":…}]} — tài khoản khớp theo tên / tên cũ. Trả số dòng + tên TK lạ.
create or replace function public.kt_nap_dcf(p_dl jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_thang text := p_dl->>'thang'; v_n int := 0; v_la text[];
begin
  if v_thang !~ '^20[0-9]{2}-[01][0-9]$' then raise exception 'thang khong hop le'; end if;
  create temp table _tk on commit drop as
    select x->>'tk' ten, (select t.id from kt_tai_khoan t where lower(t.ten) = lower(btrim(x->>'tk')) or lower(btrim(x->>'tk')) = any(select lower(z) from unnest(t.ten_cu) z) limit 1) id
      from (select jsonb_array_elements(coalesce(p_dl->'dau', '[]')) x union all select jsonb_array_elements(coalesce(p_dl->'ngay', '[]'))) s group by 1, 2;
  select array_agg(distinct ten) into v_la from _tk where id is null;
  delete from kt_dcf_ngay where file_thang = v_thang;
  insert into kt_dcf_dau (tai_khoan_id, thang, ton_dau)
    select k.id, v_thang, (x->>'ton')::numeric from jsonb_array_elements(coalesce(p_dl->'dau', '[]')) x join _tk k on k.ten = x->>'tk' where k.id is not null
    on conflict (tai_khoan_id, thang) do update set ton_dau = excluded.ton_dau, nap_luc = now();
  insert into kt_dcf_ngay (tai_khoan_id, ngay, thu, chi, ton_ss, ton_tt, file_thang)
    select k.id, (x->>'ngay')::date, coalesce((x->>'thu')::numeric, 0), coalesce((x->>'chi')::numeric, 0), (x->>'ton_ss')::numeric, (x->>'ton_tt')::numeric, v_thang
      from jsonb_array_elements(coalesce(p_dl->'ngay', '[]')) x join _tk k on k.ten = x->>'tk' where k.id is not null
    on conflict (tai_khoan_id, ngay) do update set thu = excluded.thu, chi = excluded.chi, ton_ss = excluded.ton_ss, ton_tt = excluded.ton_tt,
      file_thang = excluded.file_thang, nap_luc = now();
  get diagnostics v_n = row_count;
  perform kt_ghi_nhat_ky('Hệ thống', 'kt_dcf_ngay', null, 'nap_file_dong_tien', jsonb_build_object('thang', v_thang, 'so_dong', v_n, 'tk_la', v_la));
  return jsonb_build_object('so_dong', v_n, 'tk_la', coalesce(to_jsonb(v_la), '[]'));
end $$;
revoke execute on function public.kt_nap_dcf(jsonb) from public, anon, authenticated;

-- Bảng đối chiếu: mỗi tài khoản có trong file × ngày: thu / chi / tồn file vs app, lệch, ghi chú
create or replace function public.kt_ds_dcf(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'dong_tien');
  return jsonb_build_object(
    'nap_luc', (select max(nap_luc) from kt_dcf_ngay),
    'dau', (select coalesce(jsonb_agg(jsonb_build_object('tk', tai_khoan_id, 'thang', thang, 'ton', ton_dau)), '[]') from kt_dcf_dau
             where thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM')),
    'ngay', (select coalesce(jsonb_agg(jsonb_build_object('tk', f.tai_khoan_id, 'ngay', f.ngay, 'f_thu', f.thu, 'f_chi', f.chi, 'f_ton', f.ton_ss, 'f_tt', f.ton_tt,
        'a_thu', coalesce(a.thu, 0), 'a_chi', coalesce(a.chi, 0), 'a_ton', kt_so_du_ngay(f.tai_khoan_id, f.ngay),
        'ghi_chu', g.ghi_chu, 'da_xu_ly', coalesce(g.da_xu_ly, false), 'gc_boi', g.sua_boi) order by f.tai_khoan_id, f.ngay), '[]')
        from kt_dcf_ngay f
        left join lateral (select sum(b.vao) thu, sum(b.ra) chi from kt_v_bien_dong b where b.tai_khoan_id = f.tai_khoan_id and b.ngay = f.ngay) a on true
        left join kt_dcf_ghi_chu g on g.tai_khoan_id = f.tai_khoan_id and g.ngay = f.ngay
       where f.ngay between p_tu and p_den));
end $$;
create or replace function public.kt_luu_dcf_ghi_chu(p_phien text, p_tk int, p_ngay date, p_ghi_chu text, p_da_xu_ly boolean) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'dong_tien', true);
  if nullif(btrim(p_ghi_chu), '') is null then delete from kt_dcf_ghi_chu where tai_khoan_id = p_tk and ngay = p_ngay; return; end if;
  insert into kt_dcf_ghi_chu (tai_khoan_id, ngay, ghi_chu, da_xu_ly, sua_boi) values (p_tk, p_ngay, left(btrim(p_ghi_chu), 1000), coalesce(p_da_xu_ly, false), u.ho_ten)
  on conflict (tai_khoan_id, ngay) do update set ghi_chu = excluded.ghi_chu, da_xu_ly = excluded.da_xu_ly, sua_boi = excluded.sua_boi, sua_luc = now();
end $$;
do $$ declare f text; begin
  foreach f in array array['kt_ds_dcf(text, date, date)','kt_luu_dcf_ghi_chu(text, integer, date, text, boolean)'] loop
    execute format('revoke execute on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop; end $$;

-- 16/10/2026 (anh: "không khớp note ra, note vào app luôn"): sau mỗi lần nạp file, ngày lệch chưa có ghi chú → hệ thống tự ghi
-- "lệch thu / chi bao nhiêu"; ngày đã khớp lại thì gỡ ghi chú TỰ ĐỘNG (ghi chú kế toán gõ tay giữ nguyên).
create or replace function public.kt_dcf_tu_ghi_chu() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with l as (select f.tai_khoan_id tk, f.ngay, round(coalesce(a.v, 0) - f.thu) lt, round(coalesce(a.r, 0) - f.chi) lc
               from kt_dcf_ngay f left join lateral (select sum(vao) v, sum(ra) r from kt_v_bien_dong b where b.tai_khoan_id = f.tai_khoan_id and b.ngay = f.ngay) a on true)
  delete from kt_dcf_ghi_chu g using l where g.tai_khoan_id = l.tk and g.ngay = l.ngay and g.sua_boi = 'Hệ thống (tự đối chiếu)' and abs(l.lt) <= 1 and abs(l.lc) <= 1;
  with l as (select f.tai_khoan_id tk, f.ngay, round(coalesce(a.v, 0) - f.thu) lt, round(coalesce(a.r, 0) - f.chi) lc
               from kt_dcf_ngay f left join lateral (select sum(vao) v, sum(ra) r from kt_v_bien_dong b where b.tai_khoan_id = f.tai_khoan_id and b.ngay = f.ngay) a on true)
  insert into kt_dcf_ghi_chu (tai_khoan_id, ngay, ghi_chu, sua_boi)
  select tk, ngay, concat_ws(' · ',
      case when lt > 1 then 'App thu nhiều hơn file ' || replace(to_char(lt, 'FM999G999G999G999'), ',', '.') when lt < -1 then 'App thiếu thu ' || replace(to_char(-lt, 'FM999G999G999G999'), ',', '.') end,
      case when lc > 1 then 'App chi nhiều hơn file ' || replace(to_char(lc, 'FM999G999G999G999'), ',', '.') when lc < -1 then 'App thiếu chi ' || replace(to_char(-lc, 'FM999G999G999G999'), ',', '.') end)
      || ' — chưa rõ nguyên nhân, kế toán kiểm', 'Hệ thống (tự đối chiếu)'
    from l where (abs(lt) > 1 or abs(lc) > 1) and ngay < (now() at time zone 'Asia/Ho_Chi_Minh')::date
  on conflict (tai_khoan_id, ngay) do update set ghi_chu = excluded.ghi_chu, sua_luc = now() where kt_dcf_ghi_chu.sua_boi = 'Hệ thống (tự đối chiếu)';
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.kt_dcf_tu_ghi_chu() from public, anon, authenticated;
-- nạp file xong tự ghi chú
do $x$ declare d text; begin
  d := pg_get_functiondef('public.kt_nap_dcf'::regproc);
  if position('kt_dcf_tu_ghi_chu' in d) = 0 then
    d := replace(d, $a$  return jsonb_build_object('so_dong', v_n, 'tk_la', coalesce(to_jsonb(v_la), '[]'));$a$,
                    $a$  return jsonb_build_object('so_dong', v_n, 'tk_la', coalesce(to_jsonb(v_la), '[]'), 'ghi_chu_tu_dong', kt_dcf_tu_ghi_chu());$a$);
    if position('kt_dcf_tu_ghi_chu' in d) = 0 then raise exception 'kt_nap_dcf: khong thay return'; end if;
    execute d;
  end if;
end $x$;
