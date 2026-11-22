-- 24/10/2026 anh: "thêm nút báo lỗi ở mỗi phiếu, tất cả các phiếu" · "để icon là được, báo lỗi thì lưu lại vào 1 dashboard log" · "để cùng chỗ với in phiếu".
-- Bảng kt_bao_loi + gửi (ai đăng nhập cũng gửi được) · danh sách / xử lý (quyền nhat_ky — trang Log hệ thống → tab Báo lỗi). Monsieur Claude
create table if not exists public.kt_bao_loi (
  id bigserial primary key, bang text not null, dong_id bigint not null, so_phieu text, noi_dung text not null,
  nguoi text, luc timestamptz not null default now(),
  da_xu_ly boolean not null default false, xu_ly_boi text, xu_ly_luc timestamptz, xu_ly_ghi text);
alter table public.kt_bao_loi enable row level security;
revoke all on public.kt_bao_loi from anon, authenticated;
create index if not exists kt_bao_loi_mo on public.kt_bao_loi (da_xu_ly, luc desc);

create or replace function public.kt_bao_loi_gui(p_phien text, p_bang text, p_id bigint, p_so text, p_noi_dung text) returns bigint
 language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung; v_id bigint;
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  if p_bang not in ('chi','thu','dieu_chuyen','tam_ung') then raise exception 'Loại phiếu không hợp lệ'; end if;
  if coalesce(trim(p_noi_dung), '') = '' then raise exception 'Ghi lỗi gặp phải'; end if;
  insert into kt_bao_loi (bang, dong_id, so_phieu, noi_dung, nguoi) values (p_bang, p_id, left(p_so, 30), left(trim(p_noi_dung), 2000), u.ho_ten)
    returning id into v_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, 'bao_loi', jsonb_build_object('bao_loi_id', v_id, 'noi_dung', left(trim(p_noi_dung), 300)));
  return v_id;
end $f$;

create or replace function public.kt_ds_bao_loi(p_phien text) returns jsonb
 language plpgsql security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'nhat_ky');
  return (select coalesce(jsonb_agg(to_jsonb(b) order by b.da_xu_ly, b.luc desc), '[]') from (select * from kt_bao_loi order by da_xu_ly, luc desc limit 500) b);
end $f$;

create or replace function public.kt_bao_loi_xu_ly(p_phien text, p_id bigint, p_xong boolean, p_ghi text) returns void
 language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'nhat_ky');
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  update kt_bao_loi set da_xu_ly = p_xong, xu_ly_boi = case when p_xong then u.ho_ten end, xu_ly_luc = case when p_xong then now() end,
    xu_ly_ghi = nullif(trim(coalesce(p_ghi, '')), '') where id = p_id;
end $f$;

revoke all on function public.kt_bao_loi_gui(text,text,bigint,text,text) from public; grant execute on function public.kt_bao_loi_gui(text,text,bigint,text,text) to anon;
revoke all on function public.kt_ds_bao_loi(text) from public; grant execute on function public.kt_ds_bao_loi(text) to anon;
revoke all on function public.kt_bao_loi_xu_ly(text,bigint,boolean,text) from public; grant execute on function public.kt_bao_loi_xu_ly(text,bigint,boolean,text) to anon;

-- 24/10 bổ sung (anh: "nút báo lỗi trong profile để mọi người report lỗi khác · cho vào chuông thông báo của anh · báo lỗi là text kèm ô ảnh"):
-- (a) báo lỗi chung (không gắn phiếu): bang 'chung', dong_id null
alter table public.kt_bao_loi alter column dong_id drop not null;
create or replace function public.kt_bao_loi_gui(p_phien text, p_bang text, p_id bigint, p_so text, p_noi_dung text) returns bigint
 language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung; v_id bigint;
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  if p_bang not in ('chi','thu','dieu_chuyen','tam_ung','chung') then raise exception 'Loại phiếu không hợp lệ'; end if;
  if coalesce(trim(p_noi_dung), '') = '' then raise exception 'Ghi lỗi gặp phải'; end if;
  insert into kt_bao_loi (bang, dong_id, so_phieu, noi_dung, nguoi) values (p_bang, case when p_bang = 'chung' then null else p_id end, left(p_so, 30), left(trim(p_noi_dung), 2000), u.ho_ten)
    returning id into v_id;
  -- (b) chuông thông báo của Supreme (anh)
  insert into kt_thong_bao (nguoi_dung_id, tu, loai, tieu_de, noi_dung, bang, dong_id)
  select n.id, u.ho_ten, 'bao_loi', 'Báo lỗi' || coalesce(' · ' || nullif(p_so, ''), case when p_bang = 'chung' then ' chung' else '' end),
         left(trim(p_noi_dung), 300), 'bao_loi', v_id
    from kt_nguoi_dung n where n.vi_tri = 'supreme' and n.hoat_dong;
  if p_bang <> 'chung' then
    perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, 'bao_loi', jsonb_build_object('bao_loi_id', v_id, 'noi_dung', left(trim(p_noi_dung), 300)));
  end if;
  return v_id;
end $f$;
-- (c) ảnh báo lỗi dùng kho chứng từ (bang 'bao_loi'): kt_quyen_chung_tu phải nhận bang 'bao_loi' — xem phần vá sau khi đọc hàm hiện tại.
-- (c) vá tại chỗ các hàm kho chứng từ cho bang 'bao_loi': ghi (tải lên) = ai đăng nhập cũng được; xem = quyền trang Log (nhat_ky)
do $d$ declare r record; d text; n int;
begin
  for r in select p.oid, p.proname from pg_proc p where p.proname in ('kt_quyen_chung_tu','kt_them_chung_tu','kt_ds_chung_tu') loop
    d := pg_get_functiondef(r.oid); n := length(d);
    if position('bao_loi' in d) > 0 then continue; end if;
    d := replace(d, $s$('thu','chi','dieu_chuyen',$s$, $s$('bao_loi','thu','chi','dieu_chuyen',$s$);
    d := replace(d, $s$kt_chan(p_phien, p_bang, p_ghi)$s$, $s$kt_chan(p_phien, case when p_bang = 'bao_loi' then case when p_ghi then null else 'nhat_ky' end else p_bang end, case when p_bang = 'bao_loi' then false else p_ghi end)$s$);
    d := replace(d, $s$kt_chan(p_phien, p_bang, true)$s$, $s$kt_chan(p_phien, case when p_bang = 'bao_loi' then null else p_bang end, p_bang <> 'bao_loi')$s$);
    d := replace(d, $s$kt_chan(p_phien, p_bang)$s$, $s$kt_chan(p_phien, case when p_bang = 'bao_loi' then 'nhat_ky' else p_bang end)$s$);
    if length(d) = n then raise notice '% không vá được — xem tay', r.proname; continue; end if;
    execute d;
  end loop;
end $d$;
-- (d) kho chứng từ đi qua kt_chan_dong → nhánh riêng cho ảnh báo lỗi: người báo (báo lỗi của chính mình) hoặc quyền trang Log (nhat_ky)
do $d$ declare d text := pg_get_functiondef('kt_chan_dong(text,text,bigint[],boolean)'::regprocedure); n int := length(d);
begin
  if position('bao_loi' in d) > 0 then return; end if;
  d := replace(d, $s$  u := kt_chan(p_phien);
$s$, $s$  u := kt_chan(p_phien);
  -- 24/10: ảnh báo lỗi — người báo (báo lỗi của chính mình) hoặc quyền trang Log
  if p_bang = 'bao_loi' then
    if kt_co_quyen(u, 'nhat_ky', false) then return u; end if;
    if cardinality(p_ids) > 0 and not exists (select 1 from unnest(p_ids) i where not exists (select 1 from kt_bao_loi b where b.id = i and b.nguoi = u.ho_ten)) then return u; end if;
    raise exception 'Tài khoản chưa được cấp quyền xem báo lỗi' using errcode = '42501';
  end if;
$s$);
  if length(d) = n then raise exception 'Vá kt_chan_dong không khớp mẫu'; end if;
  execute d;
end $d$;
-- (e) kt_chung_tu.bang có ràng buộc danh sách → thêm 'bao_loi' (E2E 24/10 bắt lỗi: ảnh tải lên kho xong nhưng ghi chứng từ bị chặn)
alter table public.kt_chung_tu drop constraint if exists kt_chung_tu_bang_check;
alter table public.kt_chung_tu add constraint kt_chung_tu_bang_check check (bang = any (array['thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung','bao_loi']));
