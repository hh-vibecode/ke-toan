-- KHO SAO KÊ + LUỒNG XỬ LÝ SAO KÊ MỚI — 16/11/2026. Monsieur Claude
-- Anh: "phần nạp sao kê sửa thành 1 popup, chọn TKNH đang có sẵn rồi up sao kê, các sao kê lưu luôn trong đấy, xem kho sao kê trong đó luôn
--       … set luồng xử lý khi có người up sao kê mới. Mỗi 2h check 1 lần, có thì xử lý, không có thì thôi".
-- (1) File gốc lưu vào kho chứng từ (bucket kt-chung-tu, bang = 'sao_ke', dong_id = id kỳ) — quyền theo trang Hoá đơn & Thuế.
-- (2) kt_sao_ke_ky.xu_ly_luc: null = mới nạp / nạp lại, chưa xử lý. Lịch kt-sao-ke-moi 2 tiếng / lần: chỉ gọi Edge khi CÓ kỳ chờ
--     (kt_sao_ke_cho_xu_ly), Edge tính đối chiếu → kt_sao_ke_xu_ly_xong lưu kết quả + báo chuông người có quyền sửa Hoá đơn & Thuế.

alter table public.kt_sao_ke_ky add column if not exists xu_ly_luc timestamptz;
update public.kt_sao_ke_ky set xu_ly_luc = coalesce(ket_qua_luc, now()) where xu_ly_luc is null;   -- 5 kỳ T10 đã xử lý từ trước, không báo lại

alter table public.kt_chung_tu drop constraint if exists kt_chung_tu_bang_check;
alter table public.kt_chung_tu add constraint kt_chung_tu_bang_check check (bang = any (array['thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung','bao_loi',
  'ho_so','ncc','lo_nk','po','de_xuat','bao_gia','sao_ke']));
-- quyền chứng từ: thêm bảng 'sao_ke' (theo quyền trang hoa_don_thue)
do $$ declare d text; begin
  d := pg_get_functiondef('public.kt_quyen_chung_tu(text,text,boolean,bigint[])'::regprocedure);
  if d not like '%''sao_ke''%' then
    if d not like '%''bao_gia'')%' then raise exception 'kt_quyen_chung_tu đổi khác — sửa tay'; end if;
    execute replace(d, '''bao_gia'')', '''bao_gia'',''sao_ke'')');
  end if;
  d := pg_get_functiondef('public.kt_chan_dong(text,text,bigint[],boolean)'::regprocedure);
  if d not like '%''sao_ke'' then ''hoa_don_thue''%' then
    if d not like '%when ''bao_gia'' then ''ncc''%' then raise exception 'kt_chan_dong đổi khác — sửa tay'; end if;
    execute replace(d, 'when ''bao_gia'' then ''ncc''', 'when ''bao_gia'' then ''ncc'' when ''sao_ke'' then ''hoa_don_thue''');
  end if;
end $$;

-- danh sách kỳ: thêm trạng thái xử lý + file gốc mới nhất trong kho
create or replace function public.kt_sao_ke_ds(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  return coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'tk_id', k.tk_id, 'tk', t.ten, 'tu', k.tu, 'den', k.den, 'dau_ky', k.dau_ky, 'cuoi_ky', k.cuoi_ky,
      'ten_file', k.ten_file, 'nap_boi', k.nap_boi, 'nap_luc', k.nap_luc, 'co_link', k.token is not null, 'xu_ly_luc', k.xu_ly_luc,
      'file', (select jsonb_build_object('id', c.id, 'ten', c.ten_file, 'kb', c.kich_thuoc) from kt_chung_tu c
                where c.bang = 'sao_ke' and c.dong_id = k.id and not c.da_xoa order by c.id desc limit 1),
      'so_dong', (select count(*) from kt_sao_ke s where s.ky_id = k.id), 'tom_tat', k.ket_qua->'tom_tat') order by k.den desc, t.thu_tu, k.tk_id)
    from kt_sao_ke_ky k join kt_tai_khoan t on t.id = k.tk_id), '[]');
end $$;

-- nạp / nạp lại: như bản 10/11, thêm xu_ly_luc = null (vào hàng chờ xử lý)
create or replace function public.kt_sao_ke_nap(p_phien text, p_ky jsonb, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint; v_tk int := (p_ky->>'tk_id')::int; v_tu date := (p_ky->>'tu')::date; v_den date := (p_ky->>'den')::date; cu jsonb;
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  if v_tk is null or v_tu is null or v_den is null or v_den < v_tu then raise exception 'Thiếu tài khoản hoặc kỳ sao kê'; end if;
  if jsonb_typeof(p_dong) <> 'array' or jsonb_array_length(p_dong) = 0 then raise exception 'File không có dòng giao dịch nào'; end if;
  if jsonb_array_length(p_dong) > 5000 then raise exception 'Tối đa 5000 dòng / lần nạp'; end if;
  if not exists (select 1 from kt_tai_khoan where id = v_tk) then raise exception 'Tài khoản không tồn tại'; end if;
  insert into kt_sao_ke_ky (tk_id, tu, den, dau_ky, cuoi_ky, thong_tin, ten_file, nap_boi, nap_luc, xu_ly_luc)
  values (v_tk, v_tu, v_den, (p_ky->>'dau_ky')::numeric, (p_ky->>'cuoi_ky')::numeric, coalesce(p_ky->'thong_tin', '{}'), p_ky->>'ten_file', coalesce(u.ho_ten, u.ten_dang_nhap), now(), null)
  on conflict (tk_id, tu, den) do update set dau_ky = excluded.dau_ky, cuoi_ky = excluded.cuoi_ky, thong_tin = excluded.thong_tin, ten_file = excluded.ten_file,
    nap_boi = excluded.nap_boi, nap_luc = now(), ket_qua = null, ket_qua_luc = null, xu_ly_luc = null
  returning id into v_id;
  select coalesce(jsonb_agg(jsonb_build_object('k', s.ngay || '|' || coalesce(s.so_ct, '') || '|' || s.no || '|' || s.co, 'tay', s.tay, 'boi', s.sua_boi, 'luc', s.sua_luc)), '[]')
    into cu from kt_sao_ke s where s.ky_id = v_id and s.tay is not null;
  delete from kt_sao_ke where ky_id = v_id;
  insert into kt_sao_ke (ky_id, stt, ngay, so_ct, ngay_hl, no, co, so_du, noi_dung, tay, sua_boi, sua_luc)
  select v_id, (d->>'stt')::int, (d->>'ngay')::date, nullif(d->>'so_ct', ''), (d->>'ngay_hl')::date, coalesce((d->>'no')::numeric, 0), coalesce((d->>'co')::numeric, 0),
         (d->>'so_du')::numeric, d->>'nd', c->'tay', c->>'boi', (c->>'luc')::timestamptz
    from jsonb_array_elements(p_dong) d
    left join lateral (select x c from jsonb_array_elements(cu) x
       where x->>'k' = (d->>'ngay') || '|' || coalesce(nullif(d->>'so_ct', ''), '') || '|' || coalesce((d->>'no')::numeric, 0) || '|' || coalesce((d->>'co')::numeric, 0) limit 1) l on true;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_sao_ke_ky', v_id, 'nap_sao_ke',
    jsonb_build_object('tk_id', v_tk, 'tu', v_tu, 'den', v_den, 'so_dong', jsonb_array_length(p_dong), 'ten_file', p_ky->>'ten_file'));
  return v_id;
end $$;

-- xoá kỳ: dòng sao kê xoá theo (cascade), file gốc trong kho ẩn theo
create or replace function public.kt_sao_ke_xoa(p_phien text, p_ky bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  delete from kt_sao_ke_ky where id = p_ky;
  if not found then raise exception 'Không có kỳ sao kê này'; end if;
  update kt_chung_tu set da_xoa = true where bang = 'sao_ke' and dong_id = p_ky and not da_xoa;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_sao_ke_ky', p_ky, 'xoa_sao_ke', null);
end $$;

-- lịch 2 tiếng: có kỳ nào chờ xử lý không (rẻ — chỉ 1 lệnh exists, không gọi Edge khi không có)
create or replace function public.kt_sao_ke_cho_xu_ly() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from kt_sao_ke_ky where xu_ly_luc is null);
$$;

-- Edge kt-sao-ke (?moi=1) xử lý xong 1 kỳ: lưu kết quả + báo chuông người sửa được Hoá đơn & Thuế (và người nạp) — CHỈ service_role
create or replace function public.kt_sao_ke_xu_ly_xong(p_ky bigint, p_kq jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare k kt_sao_ke_ky; v_tk text; t jsonb := p_kq->'tom_tat'; v_lech numeric; v_nd text;
begin
  select * into k from kt_sao_ke_ky where id = p_ky for update;
  if k.id is null or k.xu_ly_luc is not null then return; end if;
  update kt_sao_ke_ky set ket_qua = p_kq, ket_qua_luc = now(), xu_ly_luc = now() where id = p_ky;
  select ten into v_tk from kt_tai_khoan where id = k.tk_id;
  v_lech := case when k.dau_ky is not null and k.cuoi_ky is not null
                 then round(k.dau_ky + coalesce((t->>'tong_co')::numeric, 0) - coalesce((t->>'tong_no')::numeric, 0) - k.cuoi_ky) end;
  v_nd := jsonb_array_length(coalesce(p_kq->'rows', '[]')) || ' dòng · có HĐ ' || coalesce(t->>'co_hd', '0')
       || ' · chưa có HĐ ' || coalesce(t->>'chua_hd', '0') || ' · không cần HĐ ' || coalesce(t->>'khong_can', '0') || ' · chưa khớp app ' || coalesce(t->>'chua_khop', '0')
       || case when v_lech is null then '' when v_lech = 0 then ' · khớp số dư' else ' · số dư lệch ' || to_char(v_lech, 'FM999G999G999G999') end;
  perform kt_bao(kt_ai_co_quyen('hoa_don_thue', true, null) || kt_ai_ten(array[k.nap_boi], null), 'Hệ thống', 'sao_ke',
    'Sao kê ' || v_tk || ' · ' || to_char(k.tu, 'DD/MM') || '–' || to_char(k.den, 'DD/MM/YYYY') || ' đã đối chiếu', v_nd, 'sao_ke', p_ky);
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_sao_ke_ds(text)', 'kt_sao_ke_nap(text,jsonb,jsonb)', 'kt_sao_ke_xoa(text,bigint)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop; end $$;
revoke all on function public.kt_sao_ke_cho_xu_ly() from public, anon, authenticated;
revoke all on function public.kt_sao_ke_xu_ly_xong(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.kt_sao_ke_xu_ly_xong(bigint, jsonb) to service_role;

-- lịch kt-sao-ke-moi: 2 tiếng / lần, chỉ gọi Edge khi có kỳ chờ. Lệnh chép từ lịch kt-sao-ke (khoá không nằm trong file này).
do $$ declare c text; begin
  select replace(command, 'functions/v1/kt-sao-ke''', 'functions/v1/kt-sao-ke?moi=1''') || ' where public.kt_sao_ke_cho_xu_ly()' into c
    from cron.job where jobname = 'kt-sao-ke';
  if c is null or c not like '%kt-sao-ke?moi=1%' or c like '%;%' then raise exception 'Không chép được lệnh mẫu'; end if;
  perform cron.unschedule('kt-sao-ke-moi') where exists (select 1 from cron.job where jobname = 'kt-sao-ke-moi');
  perform cron.schedule('kt-sao-ke-moi', '0 */2 * * *', c);
end $$;
