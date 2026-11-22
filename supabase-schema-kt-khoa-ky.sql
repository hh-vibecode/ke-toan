-- KHOÁ KỲ / CHỐT THÁNG + KHO SỔ THUẾ BƯỚC 3–4 (14/10/2026, Monsieur Claude)
-- A. Khoá sổ tháng: tháng đã khoá thì NGƯỜI DÙNG không thêm / sửa / xoá được phiếu có ngày tiền trong tháng đó
--    (Thu: ngay · Chi: ngay_tt · Điều chuyển: ngay · Kiểm két, tồn thực tế: ngay · Trả vay: ngay).
--    Sửa thông tin không đổi số (ghi chú, chứng từ, nhận hoá đơn đỏ, Kiot 4A/4B…) VẪN được.
--    Job tự động (Kiot, meInvoice…) KHÔNG bị chặn — không làm hỏng lần kéo; lúc khoá app chụp số liệu tháng, trang Khoá kỳ báo nếu số đổi sau khoá.
--    Cách nhận biết người dùng: kt_chan ghi tên người vào biến giao dịch kt.nguoi (job không qua kt_chan → không có).
-- B. Kho sổ thuế: kỳ theo QUÝ (sửa kt_nap_ton_thue — bản trước lưu theo tháng, lệch với dữ liệu có sẵn 2026-Q1..Q3),
--    đối chiếu tồn file 3TShop với tồn dự kiến (đầu kỳ + nhập HĐ − xuất HĐ ± điều chỉnh), ghi điều chỉnh, khoá quý.

-- ── A. KHOÁ SỔ THÁNG ─────────────────────────────────────────────────────
-- kt_chan (bản đang chạy 14/10) + ghi tên người dùng vào biến giao dịch
CREATE OR REPLACE FUNCTION public.kt_chan(p_phien text, p_trang text DEFAULT NULL::text, p_ghi boolean DEFAULT false)
 RETURNS kt_nguoi_dung
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare u kt_nguoi_dung;
begin
  select n.* into u from kt_phien p join kt_nguoi_dung n on n.id = p.nguoi_dung_id
   where p.token_hash = encode(digest(coalesce(p_phien, ''), 'sha256'), 'hex') and p.het_han > now() and n.hoat_dong;
  if u.id is null then raise exception 'Phiên đăng nhập hết hạn — đăng nhập lại' using errcode = '28P01'; end if;
  if not kt_co_quyen(u, p_trang, p_ghi) then
    raise exception 'Tài khoản chưa được cấp quyền % trang này', case when p_ghi then 'sửa' else 'xem' end using errcode = '42501';
  end if;
  perform set_config('kt.nguoi', coalesce(u.ho_ten, u.ten_dang_nhap), true);   -- 14/10/2026: cho trigger khoá sổ biết đây là người dùng (không phải job)
  return u;
end $function$;

create table if not exists public.kt_khoa_ky (
  thang text primary key check (thang ~ '^\d{4}-\d{2}$'), khoa_boi text, khoa_luc timestamptz not null default now(), ghi_chu text, so_lieu jsonb);
alter table public.kt_khoa_ky enable row level security;
revoke all on public.kt_khoa_ky from anon, authenticated;

-- trigger chung: TG_ARGV[0] = cột ngày tiền, TG_ARGV[1..] = các cột làm đổi số liệu
create or replace function public.kt_tg_khoa_ky() returns trigger language plpgsql security definer set search_path = public as $$
declare o jsonb; n jsonb; c text; doi boolean := false; d1 date; d2 date; t text;
begin
  if nullif(current_setting('kt.nguoi', true), '') is null then return coalesce(NEW, OLD); end if;   -- job tự động: cho qua
  if TG_OP <> 'INSERT' then o := to_jsonb(OLD); end if;
  if TG_OP <> 'DELETE' then n := to_jsonb(NEW); end if;
  if TG_OP = 'UPDATE' then
    for i in 1 .. TG_NARGS - 1 loop c := TG_ARGV[i]; if o->c is distinct from n->c then doi := true; end if; end loop;
    if not doi then return NEW; end if;
  end if;
  d1 := (o->>TG_ARGV[0])::date; d2 := (n->>TG_ARGV[0])::date;
  select k.thang into t from kt_khoa_ky k where k.thang in (to_char(d1, 'YYYY-MM'), to_char(d2, 'YYYY-MM')) order by k.thang limit 1;
  if t is not null then
    raise exception 'Tháng %/% đã khoá sổ — không thêm / sửa / xoá số tiền, ngày, tài khoản của phiếu trong tháng này. Nhờ quản trị mở khoá ở trang Khoá kỳ nếu cần.',
      right(t, 2), left(t, 4) using errcode = 'P0001';
  end if;
  return coalesce(NEW, OLD);
end $$;
drop trigger if exists kt_khoa_ky_tg on public.kt_thu;
create trigger kt_khoa_ky_tg before insert or update or delete on public.kt_thu for each row
  execute function kt_tg_khoa_ky('ngay', 'ngay', 'so_tien', 'don_vi_id', 'tai_khoan_id', 'loai_id', 'trang_thai', 'da_xoa');
drop trigger if exists kt_khoa_ky_tg on public.kt_chi;
create trigger kt_khoa_ky_tg before insert or update or delete on public.kt_chi for each row
  execute function kt_tg_khoa_ky('ngay_tt', 'ngay_tt', 'so_tien', 'tai_khoan_id', 'loai_id', 'bo_phan_id', 'phan_bo', 'phan_bo_thang', 'ngay_su_dung', 'trang_thai', 'da_xoa');
drop trigger if exists kt_khoa_ky_tg on public.kt_dieu_chuyen;
create trigger kt_khoa_ky_tg before insert or update or delete on public.kt_dieu_chuyen for each row
  execute function kt_tg_khoa_ky('ngay', 'ngay', 'so_tien', 'tk_di_id', 'tk_nhan_id', 'da_xoa');
drop trigger if exists kt_khoa_ky_tg on public.kt_kiem_quy;
create trigger kt_khoa_ky_tg before insert or update or delete on public.kt_kiem_quy for each row
  execute function kt_tg_khoa_ky('ngay', 'ngay', 'tai_khoan_id', 'so_dem');
drop trigger if exists kt_khoa_ky_tg on public.kt_ton_thuc_te;
create trigger kt_khoa_ky_tg before insert or update or delete on public.kt_ton_thuc_te for each row
  execute function kt_tg_khoa_ky('ngay', 'ngay', 'tai_khoan_id', 'so_tien');
drop trigger if exists kt_khoa_ky_tg on public.kt_vay_tra;
create trigger kt_khoa_ky_tg before insert or update or delete on public.kt_vay_tra for each row
  execute function kt_tg_khoa_ky('ngay', 'ngay', 'goc', 'lai', 'da_tra', 'da_xoa');

-- số liệu 1 tháng (chụp lúc khoá, so lại sau): tổng thu, tổng chi đã trả, số dư cuối tháng từng tài khoản
create or replace function public.kt_so_lieu_thang(p_thang text) returns jsonb language sql stable set search_path = public as $$
  with k as (select to_date(p_thang || '-01', 'YYYY-MM-DD') tu, (to_date(p_thang || '-01', 'YYYY-MM-DD') + interval '1 month - 1 day')::date den)
  select jsonb_build_object(
    'thu', (select coalesce(sum(t.so_tien), 0) from kt_thu t, k where not t.da_xoa and t.ngay between k.tu and k.den),
    'chi', (select coalesce(sum(c.so_tien), 0) from kt_chi c, k where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between k.tu and k.den),
    'dc', (select coalesce(sum(d.so_tien), 0) from kt_dieu_chuyen d, k where not d.da_xoa and d.ngay between k.tu and k.den),
    'so_du', (select coalesce(jsonb_object_agg(tk.id::text, kt_so_du_ngay(tk.id, k.den)), '{}') from kt_tai_khoan tk, k where tk.ngay_ton_dau <= k.den))
$$;
revoke execute on function public.kt_so_lieu_thang(text) from public, anon, authenticated;

-- danh sách tháng: trạng thái khoá + việc còn tồn đọng + số hiện tại so với lúc khoá
create or replace function public.kt_ds_khoa_ky(p_phien text, p_tu text, p_den text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'khoa_ky');
  return coalesce((select jsonb_agg(jsonb_build_object('thang', m.thang, 'khoa', k.thang is not null, 'khoa_boi', k.khoa_boi, 'khoa_luc', k.khoa_luc, 'ghi_chu', k.ghi_chu,
      'luc_khoa', k.so_lieu, 'hien_tai', kt_so_lieu_thang(m.thang),
      'chi_cho', (select count(*) from kt_chi c where not c.da_xoa and c.trang_thai in ('cho_duyet', 'cho_tt') and c.ngay_de_nghi between m.tu and m.den),
      'chi_chua_hd', (select count(*) from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.co_hd_do and not coalesce(c.hd_do_nhan, false) and c.ngay_tt between m.tu and m.den),
      'dc_chua_xn', (select count(*) from kt_dieu_chuyen d where not d.da_xoa and not d.da_xac_nhan and d.ngay between m.tu and m.den),
      'ket_so', (select count(*) from kt_kiem_quy q where q.ngay between m.tu and m.den),
      'ket_lech', (select count(*) from kt_kiem_quy q where q.ngay between m.tu and m.den and abs(q.so_dem - kt_so_du_ngay(q.tai_khoan_id, q.ngay)) > 0.5),
      'tu_con', (select count(*) from kt_tam_ung t where not t.da_xoa and t.ngay <= m.den
                  and t.so_tien > coalesce((select sum(h.so_tien) from kt_tam_ung_hoan h where h.tam_ung_id = t.id and not h.da_xoa and h.ngay <= m.den), 0)))
    order by m.thang desc)
    from (select to_char(g, 'YYYY-MM') thang, g::date tu, (g + interval '1 month - 1 day')::date den
            from generate_series(to_date(p_tu || '-01', 'YYYY-MM-DD'), to_date(p_den || '-01', 'YYYY-MM-DD'), interval '1 month') g) m
    left join kt_khoa_ky k on k.thang = m.thang), '[]');
end $$;

-- khoá (quyền sửa trang Khoá kỳ) / mở khoá (chỉ Supreme / Admin)
create or replace function public.kt_khoa_thang(p_phien text, p_thang text, p_khoa boolean, p_ghi_chu text default null) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'khoa_ky', true);
  if p_thang !~ '^\d{4}-\d{2}$' then raise exception 'Tháng không hợp lệ'; end if;
  if p_khoa then
    if to_date(p_thang || '-01', 'YYYY-MM-DD') + interval '1 month' > (now() at time zone 'Asia/Ho_Chi_Minh')::date + interval '1 day' then
      raise exception 'Chỉ khoá được tháng đã kết thúc'; end if;
    insert into kt_khoa_ky (thang, khoa_boi, ghi_chu, so_lieu) values (p_thang, u.ho_ten, nullif(trim(p_ghi_chu), ''), kt_so_lieu_thang(p_thang))
    on conflict (thang) do nothing;
  else
    if u.vi_tri not in ('supreme', 'admin') then raise exception 'Chỉ Supreme / Admin được mở khoá sổ' using errcode = '42501'; end if;
    delete from kt_khoa_ky where thang = p_thang;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_khoa_ky', null, case when p_khoa then 'khoa_so' else 'mo_khoa_so' end,
    jsonb_build_object('thang', p_thang, 'ghi_chu', p_ghi_chu));
end $$;

-- ── B. KHO SỔ THUẾ BƯỚC 3–4 ──────────────────────────────────────────────
create table if not exists public.kt_thue_dieu_chinh (
  id bigserial primary key, hkd text not null, ky text not null, ma text not null, sl numeric not null, ly_do text not null, ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now(), da_xoa boolean not null default false);
create table if not exists public.kt_thue_khoa (
  hkd text not null, ky text not null, khoa_boi text, khoa_luc timestamptz not null default now(), con_lech int, ghi_chu text, primary key (hkd, ky));
alter table public.kt_thue_dieu_chinh enable row level security;
alter table public.kt_thue_khoa enable row level security;
revoke all on public.kt_thue_dieu_chinh, public.kt_thue_khoa from anon, authenticated;

-- nạp file tồn 3TShop (bản đang chạy 14/10) — SỬA: kỳ theo quý (YYYY-Qn) như dữ liệu có sẵn + chặn quý đã khoá
CREATE OR REPLACE FUNCTION public.kt_nap_ton_thue(p_phien text, p_hkd text, p_ngay_chot date, p_ten_file text, p_ds jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_ky text := to_char(p_ngay_chot, 'YYYY-"Q"Q'); r jsonb;
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  if p_hkd not in ('CTY', 'CT', 'HT') then raise exception 'Đơn vị không hợp lệ'; end if;
  if p_ngay_chot is null or jsonb_typeof(p_ds) <> 'array' or jsonb_array_length(p_ds) = 0 then raise exception 'Thiếu ngày chốt hoặc file không có dòng nào'; end if;
  if exists (select 1 from kt_thue_khoa where hkd = p_hkd and ky = v_ky) then raise exception 'Kỳ % đã khoá — nhờ quản trị mở khoá trước khi nạp lại', v_ky; end if;
  delete from kt_thue_xnt where hkd = p_hkd and ky = v_ky;
  insert into kt_thue_xnt (hkd, ky, ma, ten, chung_loai, dvt, gia_nhap, dau_sl, dau_tien, nhap_sl, nhap_tien, xuat_sl, xuat_tien, cuoi_sl, cuoi_tien, nguon)
  select p_hkd, v_ky, ma, max(ten), max(nhom), max(dvt), max(gia), sum(dau_sl), sum(dau_tien), sum(nhap_sl), sum(nhap_tien), sum(xuat_sl), sum(xuat_tien), sum(sl), sum(gt),
         left('app:' || coalesce(p_ten_file, 'file'), 200)
    from (select trim(x->>'ma') ma, nullif(trim(x->>'ten'), '') ten, nullif(trim(x->>'nhom'), '') nhom, nullif(trim(x->>'dvt'), '') dvt,
                 (x->>'gia')::numeric gia, coalesce((x->>'sl')::numeric, 0) sl, coalesce((x->>'gt')::numeric, 0) gt,
                 coalesce((x->>'dau_sl')::numeric, 0) dau_sl, coalesce((x->>'dau_tien')::numeric, 0) dau_tien, coalesce((x->>'nhap_sl')::numeric, 0) nhap_sl,
                 coalesce((x->>'nhap_tien')::numeric, 0) nhap_tien, coalesce((x->>'xuat_sl')::numeric, 0) xuat_sl, coalesce((x->>'xuat_tien')::numeric, 0) xuat_tien
            from jsonb_array_elements(p_ds) x where coalesce(trim(x->>'ma'), '') <> '') t
   group by ma;
  select jsonb_build_object('ky', v_ky, 'so_ma', count(*), 'tong_sl', coalesce(sum(cuoi_sl), 0), 'tong_gt', coalesce(sum(cuoi_tien), 0)) into r
    from kt_thue_xnt where hkd = p_hkd and ky = v_ky;
  insert into kt_thue_nap (hkd, ky, ngay_chot, ten_file, so_ma, tong_sl, tong_gt, nap_boi)
  values (p_hkd, v_ky, p_ngay_chot, p_ten_file, (r->>'so_ma')::int, (r->>'tong_sl')::numeric, (r->>'tong_gt')::numeric, u.ho_ten);
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_thue_xnt', 'nap_ton_thue', r || jsonb_build_object('hkd', p_hkd, 'file', p_ten_file, 'ngay_chot', p_ngay_chot));
  return r;
end $function$;

-- đối chiếu 1 quý: tồn file 3TShop vs tồn dự kiến = tồn đầu (cuối quý trước; chưa có quý trước thì tồn đầu trong file) + nhập HĐ − xuất HĐ + điều chỉnh
create or replace function public.kt_thue_doi_chieu(p_phien text, p_hkd text, p_ky text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tu date; v_den date; v_truoc text; v_co_truoc boolean; r jsonb;
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  if p_ky !~ '^\d{4}-Q[1-4]$' then raise exception 'Kỳ không hợp lệ'; end if;
  v_tu := make_date(left(p_ky, 4)::int, (right(p_ky, 1)::int - 1) * 3 + 1, 1); v_den := (v_tu + interval '3 month - 1 day')::date;
  v_truoc := to_char(v_tu - 1, 'YYYY-"Q"Q'); v_co_truoc := exists (select 1 from kt_thue_xnt where hkd = p_hkd and ky = v_truoc);
  with f as (select ma, ten, dau_sl, cuoi_sl from kt_thue_xnt where hkd = p_hkd and ky = p_ky),
       t as (select ma, ten, cuoi_sl from kt_thue_xnt where hkd = p_hkd and ky = v_truoc),
       h as (select ma, max(ten) ten, sum(case when chieu = 'vao' then sl else 0 end) nhap, sum(case when chieu = 'ra' then sl else 0 end) xuat
               from kt_thue_hd where hkd = p_hkd and ngay between v_tu and v_den and ma is not null group by ma),
       d as (select ma, sum(sl) sl from kt_thue_dieu_chinh where hkd = p_hkd and ky = p_ky and not da_xoa group by ma),
       m as (select ma from f union select ma from t where coalesce(cuoi_sl, 0) <> 0 union select ma from h union select ma from d),
       x as (select m.ma, coalesce(f.ten, h.ten, t.ten) ten,
                    case when v_co_truoc then coalesce(t.cuoi_sl, 0) else coalesce(f.dau_sl, 0) end dau,
                    coalesce(h.nhap, 0) nhap, coalesce(h.xuat, 0) xuat, coalesce(d.sl, 0) dc, f.cuoi_sl file_sl
               from m left join f on f.ma = m.ma left join t on t.ma = m.ma left join h on h.ma = m.ma left join d on d.ma = m.ma),
       y as (select *, dau + nhap - xuat + dc du_kien, coalesce(file_sl, 0) - (dau + nhap - xuat + dc) lech from x)
  select jsonb_build_object('ky', p_ky, 'ky_truoc', v_truoc, 'co_ky_truoc', v_co_truoc, 'tu', v_tu, 'den', v_den,
      'co_file', exists (select 1 from f),
      'khoa', (select to_jsonb(k) from kt_thue_khoa k where k.hkd = p_hkd and k.ky = p_ky),
      'so_ma', (select count(*) from y), 'so_lech', (select count(*) from y where abs(lech) > 0.0001),
      'ds', coalesce((select jsonb_agg(to_jsonb(y) order by abs(y.lech) desc, y.ma) from (select * from y where abs(lech) > 0.0001 or dc <> 0 limit 2000) y), '[]'),
      'dieu_chinh', coalesce((select jsonb_agg(to_jsonb(c) order by c.tao_luc desc) from kt_thue_dieu_chinh c where c.hkd = p_hkd and c.ky = p_ky and not c.da_xoa), '[]'))
    into r;
  return r;
end $$;

-- ghi / xoá điều chỉnh (p_dong.xoa = true để xoá)
create or replace function public.kt_thue_luu_dc(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_hkd text := p_dong->>'hkd'; v_ky text := p_dong->>'ky';
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  if v_id is not null then select hkd, ky into v_hkd, v_ky from kt_thue_dieu_chinh where id = v_id; end if;
  if exists (select 1 from kt_thue_khoa where hkd = v_hkd and ky = v_ky) then raise exception 'Kỳ % đã khoá', v_ky; end if;
  if coalesce((p_dong->>'xoa')::boolean, false) then
    update kt_thue_dieu_chinh set da_xoa = true where id = v_id;
  else
    if v_hkd not in ('CTY', 'CT', 'HT') or v_ky !~ '^\d{4}-Q[1-4]$' or nullif(trim(p_dong->>'ma'), '') is null
       or coalesce((p_dong->>'sl')::numeric, 0) = 0 or nullif(trim(p_dong->>'ly_do'), '') is null then
      raise exception 'Cần mã hàng, số lượng điều chỉnh (khác 0), lý do'; end if;
    if v_id is null then
      insert into kt_thue_dieu_chinh (hkd, ky, ma, sl, ly_do, ghi_chu, tao_boi)
      values (v_hkd, v_ky, trim(p_dong->>'ma'), (p_dong->>'sl')::numeric, trim(p_dong->>'ly_do'), nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten) returning id into v_id;
    else
      update kt_thue_dieu_chinh set ma = trim(p_dong->>'ma'), sl = (p_dong->>'sl')::numeric, ly_do = trim(p_dong->>'ly_do'), ghi_chu = nullif(trim(p_dong->>'ghi_chu'), '')
       where id = v_id and not da_xoa;
    end if;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_thue_dieu_chinh', v_id, case when coalesce((p_dong->>'xoa')::boolean, false) then 'xoa' when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

-- khoá quý sổ thuế (quyền sửa Hoá đơn & thuế) / mở khoá (chỉ Supreme / Admin)
create or replace function public.kt_thue_khoa_ky(p_phien text, p_hkd text, p_ky text, p_khoa boolean, p_ghi_chu text default null) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_lech int;
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  if p_khoa then
    if not exists (select 1 from kt_thue_xnt where hkd = p_hkd and ky = p_ky) then raise exception 'Chưa có file tồn cuối kỳ % — nạp file trước khi khoá', p_ky; end if;
    v_lech := (kt_thue_doi_chieu(p_phien, p_hkd, p_ky)->>'so_lech')::int;
    insert into kt_thue_khoa (hkd, ky, khoa_boi, con_lech, ghi_chu) values (p_hkd, p_ky, u.ho_ten, v_lech, nullif(trim(p_ghi_chu), '')) on conflict do nothing;
  else
    if u.vi_tri not in ('supreme', 'admin') then raise exception 'Chỉ Supreme / Admin được mở khoá kỳ' using errcode = '42501'; end if;
    delete from kt_thue_khoa where hkd = p_hkd and ky = p_ky;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_thue_khoa', null, case when p_khoa then 'khoa_ky_thue' else 'mo_khoa_ky_thue' end,
    jsonb_build_object('hkd', p_hkd, 'ky', p_ky, 'con_lech', v_lech, 'ghi_chu', p_ghi_chu));
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_ds_khoa_ky(text, text, text)','kt_khoa_thang(text, text, boolean, text)','kt_thue_doi_chieu(text, text, text)',
                           'kt_thue_luu_dc(text, jsonb)','kt_thue_khoa_ky(text, text, text, boolean, text)'] loop
    execute format('revoke execute on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop; end $$;
