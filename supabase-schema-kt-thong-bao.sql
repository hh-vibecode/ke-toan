-- =========================================================================
-- APP KẾ TOÁN — QUYỀN ĐỀ NGHỊ / DUYỆT CHI + CHUÔNG THÔNG BÁO + ĐẾM CHỨNG TỪ (anh chốt 08/10/2026) — Monsieur Claude
-- * Quyền chi_de_nghi (nhân viên chỉ tạo đề nghị, thấy phiếu mình). CẬP NHẬT 08/10/2026: luồng duyệt chi 2 lượt + quyền chi_duyet / chi_gd
--   + thông báo về phiếu chi nằm ở supabase-schema-kt-duyet-2-cap.sql.
-- * Chuông thông báo trong app (thay báo Zalo, không đẩy về điện thoại): bảng kt_thong_bao, mỗi người 1 dòng.
--     Điều chuyển mới (tạo trên app)   → người sửa được trang Điều chuyển (kế toán xác nhận)
--     Điều chuyển đã xác nhận          → người tạo
--   Không báo cho chính người vừa thao tác. Dữ liệu kéo Kiot / sheet cũ không sinh thông báo (không đi qua hàm lưu).
-- * kt_ds trả thêm so_ct (số chứng từ) cho Thu / Chi / Điều chuyển để danh sách hiện ghim giấy.
-- File này ĐỊNH NGHĨA LẠI kt_ds, kt_luu_dieu_chuyen (bản trong supabase-schema-kt.sql là bản cũ). kt_luu_chi: xem supabase-schema-kt-duyet-2-cap.sql.
-- =========================================================================

create table if not exists public.kt_thong_bao (
  id            bigserial primary key,
  nguoi_dung_id int not null references public.kt_nguoi_dung(id) on delete cascade,
  tu            text,
  loai          text not null,
  tieu_de       text not null,
  noi_dung      text,
  bang          text,
  dong_id       bigint,
  tao_luc       timestamptz not null default now(),
  da_doc        boolean not null default false
);
create index if not exists kt_thong_bao_nd_idx on kt_thong_bao(nguoi_dung_id, id desc);
alter table public.kt_thong_bao enable row level security;
revoke all on public.kt_thong_bao from anon, authenticated;

-- Danh sách id người dùng đang hoạt động có quyền (trang, ghi), trừ 1 người
create or replace function public.kt_ai_co_quyen(p_trang text, p_ghi boolean, p_tru int) returns int[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(id), '{}') from kt_nguoi_dung n where hoat_dong and kt_co_quyen(n, p_trang, p_ghi) and id <> coalesce(p_tru, 0);
$$;
-- Id người dùng theo họ tên (người tạo phiếu), trừ 1 người
create or replace function public.kt_ai_ten(p_ten text[], p_tru int) returns int[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(id), '{}') from kt_nguoi_dung where hoat_dong and ho_ten = any(p_ten) and id <> coalesce(p_tru, 0);
$$;
create or replace function public.kt_bao(p_nguoi int[], p_tu text, p_loai text, p_tieu_de text, p_noi_dung text, p_bang text, p_dong_id bigint) returns void
language sql security definer set search_path = public as $$
  insert into kt_thong_bao (nguoi_dung_id, tu, loai, tieu_de, noi_dung, bang, dong_id)
  select distinct x, p_tu, p_loai, p_tieu_de, p_noi_dung, p_bang, p_dong_id from unnest(p_nguoi) x where x is not null;
$$;
revoke execute on function public.kt_ai_co_quyen(text, boolean, int) from public, anon, authenticated;
revoke execute on function public.kt_ai_ten(text[], int) from public, anon, authenticated;
revoke execute on function public.kt_bao(int[], text, text, text, text, text, bigint) from public, anon, authenticated;

-- Chuông: đếm chưa đọc (gọi mỗi phút) · danh sách 40 thông báo gần nhất · đánh dấu đã đọc (1 cái hoặc tất cả)
create or replace function public.kt_dem_thong_bao(p_phien text) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  return (select count(*) from kt_thong_bao where nguoi_dung_id = u.id and not da_doc);
end $$;
create or replace function public.kt_ds_thong_bao(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  return coalesce((select jsonb_agg(to_jsonb(t) - 'nguoi_dung_id' order by t.id desc) from (
    select * from kt_thong_bao where nguoi_dung_id = u.id order by id desc limit 40) t), '[]');
end $$;
create or replace function public.kt_doc_thong_bao(p_phien text, p_id bigint default null) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  update kt_thong_bao set da_doc = true where nguoi_dung_id = u.id and not da_doc and (p_id is null or id = p_id);
  -- dọn thông báo đã đọc quá 90 ngày
  delete from kt_thong_bao where nguoi_dung_id = u.id and da_doc and tao_luc < now() - interval '90 days';
end $$;

-- Kiểm quyền theo DÒNG: có quyền trang thì qua; riêng Chi, người chỉ có 'chi_de_nghi' qua được nếu MỌI dòng là phiếu mình tạo.
create or replace function public.kt_chan_dong(p_phien text, p_bang text, p_ids bigint[], p_ghi boolean) returns kt_nguoi_dung
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if kt_co_quyen(u, p_bang, p_ghi) then return u; end if;
  if p_bang = 'chi' and kt_co_quyen(u, 'chi_de_nghi') and cardinality(p_ids) > 0
     and not exists (select 1 from unnest(p_ids) i where not exists (
       select 1 from kt_chi c where c.id = i and c.tao_boi = u.ho_ten and not c.da_xoa)) then
    return u;
  end if;
  raise exception 'Tài khoản chưa được cấp quyền % trang này', case when p_ghi then 'sửa' else 'xem' end using errcode = '42501';
end $$;
revoke execute on function public.kt_chan_dong(text, text, bigint[], boolean) from public, anon, authenticated;

-- Danh sách: Chi lọc theo quyền (chi_de_nghi chỉ thấy phiếu mình) · Thu / Chi / Điều chuyển kèm số chứng từ
create or replace function public.kt_ds(p_phien text, p_bang text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_tat boolean;
begin
  if p_bang = 'chi' then
    u := kt_chan(p_phien);
    v_tat := kt_co_quyen(u, 'chi');
    if not v_tat and not kt_co_quyen(u, 'chi_de_nghi') then
      raise exception 'Tài khoản chưa được cấp quyền xem trang này' using errcode = '42501';
    end if;
    return coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object('so_ct', (select count(*) from kt_chung_tu k
        where k.bang = 'chi' and k.dong_id = c.id and not k.da_xoa)) order by coalesce(c.ngay_tt, c.ngay_de_nghi) desc, c.id desc) from kt_chi c
      where not da_xoa and (v_tat or c.tao_boi = u.ho_ten) and (ngay_de_nghi between p_tu and p_den or ngay_tt between p_tu and p_den
        or trang_thai in ('cho_duyet','cho_gd','cho_tt'))), '[]');
  end if;
  perform kt_chan(p_phien, p_bang);
  if p_bang = 'thu' then
    return coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('so_ct', (select count(*) from kt_chung_tu k
        where k.bang = 'thu' and k.dong_id = t.id and not k.da_xoa)) order by t.ngay desc, t.id desc) from kt_thu t
      where not da_xoa and ngay between p_tu and p_den), '[]');
  elsif p_bang = 'dieu_chuyen' then
    return coalesce((select jsonb_agg(to_jsonb(d) || jsonb_build_object('so_ct', (select count(*) from kt_chung_tu k
        where k.bang = 'dieu_chuyen' and k.dong_id = d.id and not k.da_xoa)) order by d.ngay desc, d.id desc) from kt_dieu_chuyen d
      where not da_xoa and ngay between p_tu and p_den), '[]');
  elsif p_bang = 'cong_no' then
    return coalesce((select jsonb_agg(x order by x->>'ngay' desc) from (
      select to_jsonb(n) || jsonb_build_object('da_thu', coalesce(t.da_thu, 0), 'lan_thu', coalesce(t.lan, '[]'::jsonb),
        'con_no', n.so_tien - n.tra_hang - coalesce(t.da_thu, 0)) x
      from kt_cong_no n
      left join lateral (select sum(so_tien) da_thu, jsonb_agg(jsonb_build_object('id', id, 'ngay', ngay, 'so_tien', so_tien,
          'ghi_chu', ghi_chu) order by ngay) lan from kt_cong_no_thu where cong_no_id = n.id and not da_xoa) t on true
      where not n.da_xoa and (n.ngay between p_tu and p_den or n.so_tien - n.tra_hang - coalesce(t.da_thu, 0) <> 0)) s), '[]');
  elsif p_bang = 'sap_tra' then
    return coalesce((select jsonb_agg(to_jsonb(s) order by s.da_tra, s.han nulls last) from kt_sap_tra s where not da_xoa), '[]');
  end if;
  raise exception 'Bảng không hợp lệ';
end $$;

-- kt_luu_chi: CHUYỂN sang supabase-schema-kt-duyet-2-cap.sql (08/10/2026 — duyệt 2 lượt: kế toán kiểm → giám đốc xác nhận).

-- Lưu điều chuyển + báo kế toán xác nhận (thay báo Zalo)
create or replace function public.kt_luu_dieu_chuyen(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_xn boolean := (p_dong->>'da_xac_nhan')::boolean;
  v_cu kt_dieu_chuyen; v_moi kt_dieu_chuyen; v_tom text;
begin
  u := kt_chan(p_phien, 'dieu_chuyen', true);
  if p_dong->>'kiot' = 'khong_tao' and coalesce(trim(p_dong->>'kiot_ly_do'), '') = '' then
    raise exception 'Không tạo phiếu Kiot thì phải ghi lý do';
  end if;
  if v_id is null then
    insert into kt_dieu_chuyen (ngay, noi_dung, so_tien, tk_di_id, tk_nhan_id, ghi_chu, kiot, kiot_ly_do, tao_boi)
    values ((p_dong->>'ngay')::date, coalesce(nullif(trim(p_dong->>'noi_dung'),''), 'Điều chuyển giữa các tài khoản'),
      (p_dong->>'so_tien')::numeric, (p_dong->>'tk_di_id')::int, (p_dong->>'tk_nhan_id')::int, nullif(trim(p_dong->>'ghi_chu'),''),
      coalesce(p_dong->>'kiot','khong'), nullif(trim(p_dong->>'kiot_ly_do'),''), u.ho_ten) returning id into v_id;
  else
    select * into v_cu from kt_dieu_chuyen where id = v_id and not da_xoa;
    update kt_dieu_chuyen set ngay = (p_dong->>'ngay')::date, noi_dung = coalesce(nullif(trim(p_dong->>'noi_dung'),''), noi_dung),
      so_tien = (p_dong->>'so_tien')::numeric, tk_di_id = (p_dong->>'tk_di_id')::int, tk_nhan_id = (p_dong->>'tk_nhan_id')::int,
      ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''), kiot = coalesce(p_dong->>'kiot', kiot),
      kiot_ly_do = nullif(trim(p_dong->>'kiot_ly_do'),''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
  end if;
  if v_xn is not null then
    update kt_dieu_chuyen set da_xac_nhan = v_xn, xac_nhan_boi = case when v_xn then u.ho_ten end,
      xac_nhan_luc = case when v_xn then now() end where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_dieu_chuyen', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  select * into v_moi from kt_dieu_chuyen where id = v_id;
  v_tom := replace(to_char(v_moi.so_tien, 'FM999G999G999G999'), ',', '.') || ' đ · ' || coalesce((select ten from kt_tai_khoan where id = v_moi.tk_di_id), '?')
    || ' → ' || coalesce((select ten from kt_tai_khoan where id = v_moi.tk_nhan_id), '?');
  if v_cu.id is null then
    perform kt_bao(kt_ai_co_quyen('dieu_chuyen', true, u.id), u.ho_ten, 'dc_moi', 'Điều chuyển mới cần xác nhận', v_tom, 'dieu_chuyen', v_id);
  elsif v_moi.da_xac_nhan and not v_cu.da_xac_nhan then
    perform kt_bao(kt_ai_ten(array[v_moi.tao_boi], u.id), u.ho_ten, 'dc_xac_nhan', 'Điều chuyển đã được kế toán xác nhận', v_tom, 'dieu_chuyen', v_id);
  end if;
  return v_id;
end $$;

-- Chứng từ: kiểm quyền theo dòng (người chỉ có quyền đề nghị chi vẫn thêm / xem chứng từ phiếu mình)
drop function if exists public.kt_quyen_chung_tu(text, text, boolean);
create or replace function public.kt_quyen_chung_tu(p_phien text, p_bang text, p_ghi boolean, p_ids bigint[]) returns text
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  if p_bang not in ('thu','chi','dieu_chuyen','vay','tai_san') then raise exception 'Bảng chứng từ không hợp lệ'; end if;
  u := kt_chan_dong(p_phien, p_bang, p_ids, p_ghi);
  return u.ho_ten;
end $$;
revoke execute on function public.kt_quyen_chung_tu(text, text, boolean, bigint[]) from public, anon, authenticated;
grant execute on function public.kt_quyen_chung_tu(text, text, boolean, bigint[]) to service_role;

create or replace function public.kt_them_chung_tu(p_phien text, p_bang text, p_dong_id bigint, p_duong_dan text,
  p_ten text, p_mime text, p_kich_thuoc bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint;
begin
  u := kt_chan_dong(p_phien, p_bang, array[p_dong_id], true);
  if p_duong_dan not like p_bang || '/' || p_dong_id || '/%' then raise exception 'Đường dẫn chứng từ không hợp lệ'; end if;
  insert into kt_chung_tu (bang, dong_id, duong_dan, ten_file, mime, kich_thuoc, tao_boi)
  values (p_bang, p_dong_id, p_duong_dan, left(p_ten, 200), p_mime, p_kich_thuoc, u.ho_ten) returning id into v_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chung_tu', v_id, 'them', jsonb_build_object('bang', p_bang, 'dong_id', p_dong_id, 'ten', p_ten));
  return v_id;
end $$;

create or replace function public.kt_ds_chung_tu(p_phien text, p_bang text, p_dong_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan_dong(p_phien, p_bang, array[p_dong_id], false);
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'ten', ten_file, 'mime', mime, 'kich_thuoc', kich_thuoc,
    'tao_boi', tao_boi, 'tao_luc', tao_luc) order by id) from kt_chung_tu where bang = p_bang and dong_id = p_dong_id and not da_xoa), '[]');
end $$;

create or replace function public.kt_xoa_chung_tu(p_phien text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_bang text; v_dong bigint;
begin
  select bang, dong_id into v_bang, v_dong from kt_chung_tu where id = p_id;
  if v_bang is null then raise exception 'Không tìm thấy chứng từ'; end if;
  u := kt_chan_dong(p_phien, v_bang, array[v_dong], true);
  update kt_chung_tu set da_xoa = true where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chung_tu', p_id, 'xoa', null);
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_dem_thong_bao(text)','kt_ds_thong_bao(text)','kt_doc_thong_bao(text,bigint)'] loop
    execute 'revoke execute on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;
