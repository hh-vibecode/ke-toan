-- ĐỐI CHIẾU SAO KÊ NGÂN HÀNG ↔ HOÁ ĐƠN MISA (Hoá đơn & Thuế) — 10/11/2026. Monsieur Claude
-- Anh: "dựa vào tab 599, tạo báo cáo so sánh sao kê định kỳ trong phần hoá đơn và thuế, nội dung y như bảng tab 599 — kết nối giữa sao kê với mã
-- hoá đơn MISA; hoàn thiện các phần hoá đơn / nội dung còn trống; xuất được file Excel + link online để đưa cho dịch vụ" + "từ tháng sau t gửi sao kê, m cứ nối định kỳ".
-- Cách làm: nạp file sao kê (trình duyệt đọc, gửi các dòng lên kt_sao_ke_nap) → trang tự ghép từng dòng sao kê với phiếu thu / chi / điều chuyển / vay
-- của đúng tài khoản trên app (cùng tiền, cùng ngày ±3, hoặc gộp nhiều phiếu cùng ngày = 1 dòng sao kê) → lấy HĐ đã gắn của phiếu (thu → HĐ bán ra,
-- chi → HĐ mua vào). Kế toán sửa tay được từng dòng (cột tay). Kết quả đã tính lưu lại (ket_qua) để link xem online (token) hiện đúng như trên app.
create table if not exists public.kt_sao_ke_ky (
  id bigserial primary key, tk_id int not null references kt_tai_khoan(id), tu date not null, den date not null,
  dau_ky numeric, cuoi_ky numeric, thong_tin jsonb not null default '{}', ten_file text,
  nap_boi text, nap_luc timestamptz not null default now(),
  token text unique, token_boi text, token_luc timestamptz,
  ket_qua jsonb, ket_qua_luc timestamptz,
  unique (tk_id, tu, den));
create table if not exists public.kt_sao_ke (
  id bigserial primary key, ky_id bigint not null references kt_sao_ke_ky(id) on delete cascade,
  stt int, ngay date not null, so_ct text, ngay_hl date, no numeric not null default 0, co numeric not null default 0, so_du numeric, noi_dung text,
  tay jsonb, sua_boi text, sua_luc timestamptz);
create index if not exists kt_sao_ke_ky_idx on public.kt_sao_ke (ky_id, stt);
alter table public.kt_sao_ke_ky enable row level security;
alter table public.kt_sao_ke enable row level security;
revoke all on public.kt_sao_ke_ky, public.kt_sao_ke from anon, authenticated;
drop trigger if exists kt_chi_xem on public.kt_sao_ke_ky;
create trigger kt_chi_xem before insert or delete or update on public.kt_sao_ke_ky for each row execute function kt_tg_chi_xem();
drop trigger if exists kt_chi_xem on public.kt_sao_ke;
create trigger kt_chi_xem before insert or delete or update on public.kt_sao_ke for each row execute function kt_tg_chi_xem();

-- danh sách các kỳ sao kê đã nạp
create or replace function public.kt_sao_ke_ds(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  return coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'tk_id', k.tk_id, 'tk', t.ten, 'tu', k.tu, 'den', k.den, 'dau_ky', k.dau_ky, 'cuoi_ky', k.cuoi_ky,
      'ten_file', k.ten_file, 'nap_boi', k.nap_boi, 'nap_luc', k.nap_luc, 'co_link', k.token is not null,
      'so_dong', (select count(*) from kt_sao_ke s where s.ky_id = k.id), 'tom_tat', k.ket_qua->'tom_tat') order by k.den desc, t.thu_tu, k.tk_id)
    from kt_sao_ke_ky k join kt_tai_khoan t on t.id = k.tk_id), '[]');
end $$;

-- 1 kỳ: dòng sao kê + phiếu trên app của tài khoản đó (kỳ ±5 ngày) kèm HĐ đã gắn — trang tự ghép
create or replace function public.kt_sao_ke_lay(p_phien text, p_ky bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u kt_nguoi_dung; k kt_sao_ke_ky; a date; b date;
begin
  u := kt_chan(p_phien, 'hoa_don_thue');
  select * into k from kt_sao_ke_ky where id = p_ky;
  if k.id is null then raise exception 'Không có kỳ sao kê này'; end if;
  a := k.tu - 5; b := k.den + 5;
  return jsonb_build_object(
    'ky', jsonb_build_object('id', k.id, 'tk_id', k.tk_id, 'tk', (select ten from kt_tai_khoan where id = k.tk_id), 'tu', k.tu, 'den', k.den, 'dau_ky', k.dau_ky,
          'cuoi_ky', k.cuoi_ky, 'thong_tin', k.thong_tin, 'ten_file', k.ten_file, 'nap_boi', k.nap_boi, 'nap_luc', k.nap_luc,
          'token', k.token, 'token_boi', k.token_boi, 'token_luc', k.token_luc, 'ket_qua_luc', k.ket_qua_luc),
    'dong', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'stt', s.stt, 'ngay', s.ngay, 'so_ct', s.so_ct, 'ngay_hl', s.ngay_hl, 'no', s.no, 'co', s.co,
          'so_du', s.so_du, 'nd', s.noi_dung, 'tay', s.tay, 'sua_boi', s.sua_boi, 'sua_luc', s.sua_luc) order by s.stt, s.id) from kt_sao_ke s where s.ky_id = k.id), '[]'),
    'app', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('k', 'thu', 'id', t.id, 'ngay', t.ngay, 'vao', t.so_tien, 'ra', 0, 'nd', t.noi_dung, 'loai', (select ten from kt_loai where id = t.loai_id),
               'hd', (select jsonb_agg(jsonb_build_object('so', h.so_hd, 'kh', h.ky_hieu, 'ngay', h.ngay_hd, 'ten', h.nguoi_mua, 'mst', h.mst, 'cb', h.canh_bao) order by h.ngay_hd, h.so_hd)
                        from kt_thu_hd h where h.thu_id = t.id)) x
        from kt_thu t where not t.da_xoa and t.trang_thai = 'da_duyet' and t.tai_khoan_id = k.tk_id and t.ngay between a and b
      union all
      select jsonb_build_object('k', 'chi', 'id', c.id, 'ngay', c.ngay_tt, 'vao', 0, 'ra', c.so_tien, 'nd', c.noi_dung, 'doi', c.thu_huong_ten,
               'loai', (select ten from kt_loai where id = c.loai_id), 'co_hd', c.co_hd_do, 'so_tay', c.so_hd_do,
               'hd', (select jsonb_agg(jsonb_build_object('so', h.so_hd, 'kh', h.ky_hieu, 'ngay', h.ngay_hd, 'ten', h.ncc, 'mst', h.mst) order by h.ngay_hd, h.so_hd)
                        from kt_chi_hd h where h.chi_id = c.id))
        from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.tai_khoan_id = k.tk_id and c.ngay_tt between a and b
      union all
      select jsonb_build_object('k', 'dc', 'id', d.id, 'ngay', d.ngay, 'vao', case when d.tk_nhan_id = k.tk_id then d.so_tien else 0 end,
               'ra', case when d.tk_di_id = k.tk_id then d.so_tien else 0 end, 'nd', d.noi_dung,
               'doi', (select ten from kt_tai_khoan where id = case when d.tk_nhan_id = k.tk_id then d.tk_di_id else d.tk_nhan_id end))
        from kt_dieu_chuyen d where not d.da_xoa and k.tk_id in (d.tk_di_id, d.tk_nhan_id) and d.ngay between a and b
      union all
      select jsonb_build_object('k', 'vay', 'id', n.id, 'ngay', n.ngay, 'vao', n.so_tien, 'ra', 0, 'nd', 'Nhận tiền vay · ' || v.ten, 'doi', v.ben_cho_vay)
        from kt_vay_nhan n join kt_vay v on v.id = n.vay_id where not n.da_xoa and n.tai_khoan_id = k.tk_id and n.ngay between a and b
      union all
      select jsonb_build_object('k', 'vay', 'id', -r.id, 'ngay', r.ngay, 'vao', 0, 'ra', r.goc + r.lai, 'nd', 'Trả nợ vay · ' || v.ten, 'doi', v.ben_cho_vay, 'goc', r.goc, 'lai', r.lai)
        from kt_vay_tra r join kt_vay v on v.id = r.vay_id where not r.da_xoa and r.da_tra and r.tai_khoan_id = k.tk_id and r.ngay between a and b) z), '[]'));
end $$;

-- nạp / nạp lại 1 kỳ (cùng tài khoản + từ + đến → thay dòng cũ, GIỮ phần kế toán sửa tay của dòng trùng ngày + số CT + tiền)
create or replace function public.kt_sao_ke_nap(p_phien text, p_ky jsonb, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint; v_tk int := (p_ky->>'tk_id')::int; v_tu date := (p_ky->>'tu')::date; v_den date := (p_ky->>'den')::date; cu jsonb;
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  if v_tk is null or v_tu is null or v_den is null or v_den < v_tu then raise exception 'Thiếu tài khoản hoặc kỳ sao kê'; end if;
  if jsonb_typeof(p_dong) <> 'array' or jsonb_array_length(p_dong) = 0 then raise exception 'File không có dòng giao dịch nào'; end if;
  if jsonb_array_length(p_dong) > 5000 then raise exception 'Tối đa 5000 dòng / lần nạp'; end if;
  if not exists (select 1 from kt_tai_khoan where id = v_tk) then raise exception 'Tài khoản không tồn tại'; end if;
  insert into kt_sao_ke_ky (tk_id, tu, den, dau_ky, cuoi_ky, thong_tin, ten_file, nap_boi, nap_luc)
  values (v_tk, v_tu, v_den, (p_ky->>'dau_ky')::numeric, (p_ky->>'cuoi_ky')::numeric, coalesce(p_ky->'thong_tin', '{}'), p_ky->>'ten_file', coalesce(u.ho_ten, u.ten_dang_nhap), now())
  on conflict (tk_id, tu, den) do update set dau_ky = excluded.dau_ky, cuoi_ky = excluded.cuoi_ky, thong_tin = excluded.thong_tin, ten_file = excluded.ten_file,
    nap_boi = excluded.nap_boi, nap_luc = now(), ket_qua = null, ket_qua_luc = null
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

-- kế toán sửa tay 1 dòng: {vao:[{so,kh,ngay,ten}], ra:[...], gc:'...'} — null = bỏ sửa tay, quay về tự ghép
create or replace function public.kt_sao_ke_sua(p_phien text, p_id bigint, p_tay jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  update kt_sao_ke set tay = case when p_tay is null or p_tay = '{}'::jsonb then null else p_tay end,
    sua_boi = coalesce(u.ho_ten, u.ten_dang_nhap), sua_luc = now() where id = p_id;
  if not found then raise exception 'Không có dòng sao kê này'; end if;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_sao_ke', p_id, 'sua_sao_ke', p_tay);
end $$;

-- lưu bảng kết quả đã ghép (để link online hiện đúng như app) — người xem trang cũng lưu được (chỉ là kết quả tính lại từ dữ liệu có sẵn)
create or replace function public.kt_sao_ke_luu_kq(p_phien text, p_ky bigint, p_kq jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  if exists (select 1 from kt_phien p where p.token_hash = encode(extensions.digest(coalesce(p_phien, ''), 'sha256'), 'hex') and p.chi_xem) then return; end if;
  update kt_sao_ke_ky set ket_qua = p_kq, ket_qua_luc = now() where id = p_ky and ket_qua is distinct from p_kq;
end $$;

-- bật / tắt link xem online (không cần đăng nhập, chỉ xem + tải Excel)
create or replace function public.kt_sao_ke_link(p_phien text, p_ky bigint, p_bat boolean) returns text
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v text;
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  v := case when p_bat then encode(extensions.gen_random_bytes(18), 'hex') end;
  update kt_sao_ke_ky set token = v, token_boi = case when p_bat then coalesce(u.ho_ten, u.ten_dang_nhap) end, token_luc = case when p_bat then now() end where id = p_ky;
  if not found then raise exception 'Không có kỳ sao kê này'; end if;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_sao_ke_ky', p_ky, case when p_bat then 'mo_link_sao_ke' else 'tat_link_sao_ke' end, null);
  return v;
end $$;

-- trang xem online (không đăng nhập): chỉ trả bảng kết quả đã lưu của đúng kỳ có token
create or replace function public.kt_sao_ke_xem(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k kt_sao_ke_ky;
begin
  if coalesce(length(p_token), 0) < 30 then raise exception 'Link không hợp lệ'; end if;
  select * into k from kt_sao_ke_ky where token = p_token;
  if k.id is null then raise exception 'Link đã bị tắt hoặc không đúng'; end if;
  if k.ket_qua is null then raise exception 'Báo cáo chưa sẵn sàng — nhờ kế toán mở lại trang Đối chiếu sao kê'; end if;
  return k.ket_qua || jsonb_build_object('luc', k.ket_qua_luc);
end $$;

create or replace function public.kt_sao_ke_xoa(p_phien text, p_ky bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  delete from kt_sao_ke_ky where id = p_ky;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_sao_ke_ky', p_ky, 'xoa_sao_ke', null);
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_sao_ke_ds(text)', 'kt_sao_ke_lay(text,bigint)', 'kt_sao_ke_nap(text,jsonb,jsonb)', 'kt_sao_ke_sua(text,bigint,jsonb)',
    'kt_sao_ke_luu_kq(text,bigint,jsonb)', 'kt_sao_ke_link(text,bigint,boolean)', 'kt_sao_ke_xem(text)', 'kt_sao_ke_xoa(text,bigint)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop; end $$;
