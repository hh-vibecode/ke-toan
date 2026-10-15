-- TÁCH RIÊNG KHOẢN VAY (15/10/2026, anh: "tách riêng khoản vay, chỉ tính chi phí nếu là lãi vay"). Monsieur Claude
-- • Trang Vay & lãi vay = sổ khoản vay: các lần NHẬN TIỀN (giải ngân, kt_vay_nhan) + các lần TRẢ (kt_vay_tra: gốc, lãi) — mỗi lần gắn tài khoản
--   ngân hàng → tính vào số dư tài khoản (kt_v_bien_dong thêm kiểu 'vay'). Dư nợ = tổng nhận − gốc đã trả.
-- • 98 phiếu chi "FINANCE - Trả gốc vay" chuyển khỏi Phiếu chi sang 6 khoản vay (phiếu cũ ẩn, ghi chú + nhật ký) — số dư tài khoản không đổi.
-- • P&L: lãi vay = lãi ở trang Vay + phiếu chi loại "Lãi vay & phí tài chính". Dòng tiền: hoạt động tài chính có nhận tiền vay / trả nợ vay.
-- • Lãi vay ghi 1 nơi: đã có phiếu chi lãi thì lần trả ở trang Vay để lãi = 0.

alter table public.kt_vay_tra add column if not exists tai_khoan_id int references kt_tai_khoan(id);
alter table public.kt_vay_tra add column if not exists chi_id bigint references kt_chi(id);
alter table public.kt_vay add column if not exists ma_vay text;
-- số tiền vay theo hợp đồng / hạn mức: được để 0 (khoản tạo tự động chưa biết số) — dư nợ tính theo các lần nhận tiền
alter table public.kt_vay drop constraint if exists kt_vay_so_tien_check;
alter table public.kt_vay add constraint kt_vay_so_tien_check check (so_tien >= 0);
create table if not exists public.kt_vay_nhan (
  id bigserial primary key, vay_id bigint not null references kt_vay(id), ngay date not null, so_tien numeric not null check (so_tien > 0),
  tai_khoan_id int references kt_tai_khoan(id), ghi_chu text, tao_boi text, tao_luc timestamptz not null default now(), da_xoa boolean not null default false);
alter table public.kt_vay_nhan enable row level security;
revoke all on public.kt_vay_nhan from anon, authenticated;

-- số dư tài khoản: thêm tiền vay nhận vào / trả nợ vay (gốc + lãi ghi ở trang Vay)
create or replace view public.kt_v_bien_dong as
 SELECT t.tai_khoan_id, t.ngay, 'thu'::text AS kieu, t.so_tien AS vao, 0::numeric AS ra FROM kt_thu t WHERE NOT t.da_xoa AND t.trang_thai = 'da_duyet'::text
UNION ALL
 SELECT c.tai_khoan_id, c.ngay_tt AS ngay, 'chi'::text AS kieu, 0 AS vao, c.so_tien AS ra FROM kt_chi c WHERE NOT c.da_xoa AND c.trang_thai = 'da_tt'::text
UNION ALL
 SELECT d.tk_di_id AS tai_khoan_id, d.ngay, 'dc'::text AS kieu, 0 AS vao, d.so_tien AS ra FROM kt_dieu_chuyen d WHERE NOT d.da_xoa
UNION ALL
 SELECT d.tk_nhan_id AS tai_khoan_id, d.ngay, 'dc'::text AS kieu, d.so_tien AS vao, 0 AS ra FROM kt_dieu_chuyen d WHERE NOT d.da_xoa
UNION ALL
 SELECT n.tai_khoan_id, n.ngay, 'vay'::text AS kieu, n.so_tien AS vao, 0 AS ra FROM kt_vay_nhan n WHERE NOT n.da_xoa AND n.tai_khoan_id IS NOT NULL
UNION ALL
 SELECT r.tai_khoan_id, r.ngay, 'vay'::text AS kieu, 0 AS vao, r.goc + r.lai AS ra FROM kt_vay_tra r WHERE NOT r.da_xoa AND r.da_tra AND r.tai_khoan_id IS NOT NULL;

-- khoá sổ tháng: trả vay thêm cột tài khoản; nhận tiền vay cũng bị khoá
drop trigger if exists kt_khoa_ky_tg on public.kt_vay_tra;
create trigger kt_khoa_ky_tg before insert or update or delete on public.kt_vay_tra for each row
  execute function kt_tg_khoa_ky('ngay', 'ngay', 'goc', 'lai', 'da_tra', 'tai_khoan_id', 'da_xoa');
drop trigger if exists kt_khoa_ky_tg on public.kt_vay_nhan;
create trigger kt_khoa_ky_tg before insert or update or delete on public.kt_vay_nhan for each row
  execute function kt_tg_khoa_ky('ngay', 'ngay', 'so_tien', 'tai_khoan_id', 'da_xoa');

create or replace function public.kt_luu_vay_nhan(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint;
begin
  u := kt_chan(p_phien, 'vay', true);
  if (p_dong->>'ngay') is null or coalesce((p_dong->>'so_tien')::numeric, 0) <= 0 or (p_dong->>'tai_khoan_id') is null then
    raise exception 'Cần ngày, số tiền nhận, tài khoản nhận'; end if;
  if v_id is null then
    insert into kt_vay_nhan (vay_id, ngay, so_tien, tai_khoan_id, ghi_chu, tao_boi)
    values ((p_dong->>'vay_id')::bigint, (p_dong->>'ngay')::date, (p_dong->>'so_tien')::numeric, (p_dong->>'tai_khoan_id')::int, nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten)
    returning id into v_id;
  else
    update kt_vay_nhan set ngay = (p_dong->>'ngay')::date, so_tien = (p_dong->>'so_tien')::numeric, tai_khoan_id = (p_dong->>'tai_khoan_id')::int,
      ghi_chu = nullif(trim(p_dong->>'ghi_chu'), '') where id = v_id and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vay_nhan', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;
revoke execute on function public.kt_luu_vay_nhan(text, jsonb) from public;
grant execute on function public.kt_luu_vay_nhan(text, jsonb) to anon, authenticated;

-- trả vay: thêm tài khoản trả (bản đang chạy + tai_khoan_id)
CREATE OR REPLACE FUNCTION public.kt_luu_vay_tra(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint;
begin
  u := kt_chan(p_phien, 'vay', true);
  if v_id is null then
    insert into kt_vay_tra (vay_id, ngay, goc, lai, da_tra, ghi_chu, tao_boi, tai_khoan_id)
    values ((p_dong->>'vay_id')::bigint, (p_dong->>'ngay')::date, coalesce((p_dong->>'goc')::numeric,0), coalesce((p_dong->>'lai')::numeric,0),
      coalesce((p_dong->>'da_tra')::boolean,false), nullif(trim(p_dong->>'ghi_chu'),''), u.ho_ten, (p_dong->>'tai_khoan_id')::int) returning id into v_id;
  else
    update kt_vay_tra set ngay = (p_dong->>'ngay')::date, goc = coalesce((p_dong->>'goc')::numeric,0), lai = coalesce((p_dong->>'lai')::numeric,0),
      da_tra = coalesce((p_dong->>'da_tra')::boolean,false), ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''), tai_khoan_id = (p_dong->>'tai_khoan_id')::int where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vay_tra', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $function$
;

-- danh sách vay (bản đang chạy + giải ngân)
CREATE OR REPLACE FUNCTION public.kt_ds_vay(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'vay');
  return coalesce((select jsonb_agg(to_jsonb(v) || jsonb_build_object(
      'nhan', coalesce((select jsonb_agg(to_jsonb(n) order by n.ngay) from kt_vay_nhan n where n.vay_id = v.id and not n.da_xoa), '[]'),
      'tong_nhan', coalesce((select sum(so_tien) from kt_vay_nhan n where n.vay_id = v.id and not n.da_xoa), 0),
      'lan_tra', coalesce((select jsonb_agg(to_jsonb(t) order by t.ngay) from kt_vay_tra t where t.vay_id = v.id and not t.da_xoa), '[]'),
      'goc_da_tra', coalesce((select sum(goc) from kt_vay_tra t where t.vay_id = v.id and not t.da_xoa and t.da_tra), 0),
      'lai_da_tra', coalesce((select sum(lai) from kt_vay_tra t where t.vay_id = v.id and not t.da_xoa and t.da_tra), 0))
    order by v.da_tat_toan, v.ngay_vay desc) from kt_vay v where not v.da_xoa), '[]');
end $function$
;

-- kt_xoa (bản đang chạy + vay_nhan)
CREATE OR REPLACE FUNCTION public.kt_xoa(p_phien text, p_bang text, p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, case when p_bang = 'cong_no_thu' then 'cong_no' when p_bang in ('vay_tra', 'vay_nhan') then 'vay' when p_bang = 'tam_ung_hoan' then 'tam_ung' else p_bang end, true);
  if p_bang not in ('thu','chi','dieu_chuyen','cong_no','cong_no_thu','sap_tra','vay','vay_tra','vay_nhan','tai_san','tam_ung','tam_ung_hoan') then raise exception 'Bảng không hợp lệ'; end if;
  execute format('update public.%I set da_xoa = true where id = $1', 'kt_' || p_bang) using p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, 'xoa', null);
end $function$
;

-- P&L (bản đang chạy + lãi vay từ phiếu chi)
CREATE OR REPLACE FUNCTION public.kt_bc_pl2(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_t0 text := to_char(p_tu, 'YYYY-MM'); v_t1 text := to_char(p_den, 'YYYY-MM');
begin
  perform kt_chan(p_phien, 'pl');
  return jsonb_build_object(
    'dt', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'dt', dt, 'gv', gv)), '[]') from (
        select to_char((ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, chi_nhanh cn, sum(tong) dt, sum(coalesce(gia_von, 0)) gv
          from kt_kiot_hoa_don where trang_thai = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    -- trả hàng: trừ doanh thu theo ngày trả; giá vốn hàng trả = tiền trả × (giá vốn / tổng) của hoá đơn gốc (như trang Bán hàng)
    'tra', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'tra', tra, 'gv', gv)), '[]') from (
        select to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, t.chi_nhanh cn, sum(t.tong_tra) tra,
               round(sum(t.tong_tra * coalesce(h.gia_von / nullif(h.tong, 0), 0))) gv
          from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
         where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    'cp', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai_id, 'dv', dv, 'tien', tien)), '[]') from (
        select th, loai_id, dv, round(sum(tien)) tien from (
          select coalesce(pt->>'thang', to_char(c.ngay_tt, 'YYYY-MM')) th, c.loai_id, (pb->>'don_vi_id')::int dv,
                 coalesce((pt->>'so_tien')::numeric, c.so_tien) * coalesce((pb->>'so_tien')::numeric / nullif(c.so_tien, 0), 1) tien
            from kt_chi c join kt_loai l on l.id = c.loai_id
            left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' and jsonb_array_length(c.phan_bo_thang) > 0 then c.phan_bo_thang end) pt on true
            left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' and jsonb_array_length(c.phan_bo) > 0 then c.phan_bo end) pb on true
           where not c.da_xoa and c.trang_thai = 'da_tt' and l.nhom_bc = 'Chi vận hành & quản lí'
             and (case when pt is null then c.ngay_tt between p_tu and p_den else pt->>'thang' between v_t0 and v_t1 end)) z
         group by 1, 2, 3) x),
    'lai_vay', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'lai', s)), '[]') from (
        select th, sum(s) s from (
          select to_char(ngay, 'YYYY-MM') th, lai s from kt_vay_tra where not da_xoa and da_tra and lai <> 0 and ngay between p_tu and p_den
          union all   -- 15/10/2026: lãi vay & phí tài chính trả qua phiếu chi
          select to_char(c.ngay_tt, 'YYYY-MM'), c.so_tien from kt_chi c join kt_loai l on l.id = c.loai_id
           where not c.da_xoa and c.trang_thai = 'da_tt' and l.ten = 'FINANCE - Lãi vay & phí tài chính' and c.ngay_tt between p_tu and p_den) z group by 1) x),
    'loai', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'nhom_bc', nhom_bc, 'thu_tu', thu_tu, 'hoat_dong', hoat_dong) order by thu_tu, id), '[]') from kt_loai where nhom = 'chi'));
end $function$
;

-- Dòng tiền (bản đang chạy + vay)
CREATE OR REPLACE FUNCTION public.kt_bc_lctt(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_moc date;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'dong_tien') or kt_co_quyen(u, 'pl')) then raise exception 'Tài khoản chưa được cấp quyền xem dòng tiền' using errcode = '42501'; end if;
  select max(ngay_ton_dau) into v_moc from kt_tai_khoan where hoat_dong;
  return jsonb_build_object(
    'moc', v_moc,
    -- số dư (tổng các tài khoản — điều chuyển nội bộ tự triệt tiêu) tại ngày dau_ngay = max(p_tu, mốc tồn đầu); trước mốc không có số dư
    'dau_ngay', greatest(p_tu, v_moc),
    'dau', case when greatest(p_tu, v_moc) <= p_den then (select sum(tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b
                 where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau and b.ngay < greatest(p_tu, v_moc)), 0)) from kt_tai_khoan tk) end,
    'thu', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai_id, 'dv', don_vi_id, 'tien', s)), '[]') from (
        select to_char(ngay, 'YYYY-MM') th, loai_id, don_vi_id, sum(so_tien) s from kt_thu
         where not da_xoa and trang_thai = 'da_duyet' and ngay between p_tu and p_den group by 1, 2, 3) x),
    'chi', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai_id, 'dv', dv, 'tien', s)), '[]') from (
        select to_char(c.ngay_tt, 'YYYY-MM') th, c.loai_id, (pb->>'don_vi_id')::int dv,
               round(sum(c.so_tien * coalesce((pb->>'so_tien')::numeric / nullif(c.so_tien, 0), 1))) s
          from kt_chi c left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' and jsonb_array_length(c.phan_bo) > 0 then c.phan_bo end) pb on true
         where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between p_tu and p_den group by 1, 2, 3) x),
    -- biến động ròng theo tháng (để ra số dư cuối từng tháng, chỉ phần từ mốc)
    'rong', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'rong', s)), '[]') from (
        select to_char(b.ngay, 'YYYY-MM') th, sum(b.vao - b.ra) s from kt_v_bien_dong b join kt_tai_khoan tk on tk.id = b.tai_khoan_id
         where b.ngay between p_tu and p_den and b.ngay >= tk.ngay_ton_dau group by 1) x),
    -- 15/10/2026: nhận tiền vay / trả nợ vay (trang Vay) — hoạt động tài chính
    'vay', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'nhan', n, 'tra', t)), '[]') from (
        select th, sum(n) n, sum(t) t from (select to_char(ngay, 'YYYY-MM') th, so_tien n, 0 t from kt_vay_nhan where not da_xoa and tai_khoan_id is not null and ngay between p_tu and p_den
          union all select to_char(ngay, 'YYYY-MM'), 0, goc + lai from kt_vay_tra where not da_xoa and da_tra and tai_khoan_id is not null and ngay between p_tu and p_den) z group by 1) x),
    'loai', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'nhom', nhom, 'nhom_bc', nhom_bc)), '[]') from kt_loai));
end $function$
;

-- ── CHUYỂN 98 PHIẾU TRẢ GỐC VAY SANG TRANG VAY (chạy 1 lần; chạy lại không làm gì) ──────────────────
do $mig$ declare r record; v_vay bigint; v_truoc numeric; v_sau numeric; v_n int := 0;
begin
  if exists (select 1 from kt_vay where ghi_chu like '%[Tạo từ phiếu chi trả gốc 15/10/2026]%') then return; end if;
  select sum(tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau), 0)) into v_truoc from kt_tai_khoan tk;
  create temp table _sd on commit drop as select tk.id, tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau), 0) sd from kt_tai_khoan tk;
  create temp table _vg on commit drop as
  select c.id, c.ngay_tt, c.so_tien, c.tai_khoan_id, c.noi_dung,
    case when c.noi_dung ~ '406004307224' then 'BIDV — TK vay 406004307224'
         when c.noi_dung ~ '406004717371' then 'BIDV — TK vay 406004717371'
         when c.noi_dung ~ '401004519925' then 'BIDV — TK vay 401004519925'
         when c.noi_dung ~ '8837562543' then 'BIDV — thấu chi 8837562543'
         when c.noi_dung ~* 'dài hạn' then 'VCB — vay dài hạn (HN)'
         when c.noi_dung ~* 'cá nhân' then 'VCB — vay cá nhân'
         else 'VCB — vay ngắn hạn (hạn mức, nhiều khế ước TKV)' end ten
    from kt_chi c join kt_loai l on l.id = c.loai_id where not c.da_xoa and c.trang_thai = 'da_tt' and l.ten = 'FINANCE - Trả gốc vay';
  for r in select ten, min(ngay_tt) d, (array_agg(tai_khoan_id order by ngay_tt))[1] tk from _vg group by ten loop
    insert into kt_vay (ten, ben_cho_vay, so_tien, ngay_vay, hinh_thuc, tai_khoan_id, ghi_chu, chung_tu, tao_boi)
    values (r.ten, split_part(r.ten, ' — ', 1), 0, r.d, 'goc_cuoi_ky', r.tk,
      'Cần nhập các lần nhận tiền (giải ngân) để có dư nợ đúng. [Tạo từ phiếu chi trả gốc 15/10/2026]', '{}', 'Hệ thống') returning id into v_vay;
    insert into kt_vay_tra (vay_id, ngay, goc, lai, da_tra, ghi_chu, tao_boi, tai_khoan_id, chi_id)
    select v_vay, g.ngay_tt, g.so_tien, 0, true, left(g.noi_dung, 300), 'Hệ thống', g.tai_khoan_id, g.id from _vg g where g.ten = r.ten;
  end loop;
  update kt_chi c set da_xoa = true, ghi_chu = concat_ws(' ', c.ghi_chu, '[Trả gốc vay — chuyển sang trang Vay & lãi vay 15/10/2026]') from _vg g where g.id = c.id;
  get diagnostics v_n = row_count;
  insert into kt_nhat_ky (nguoi, bang, dong_id, hanh_dong, du_lieu)
  select 'Hệ thống', 'kt_chi', g.id, 'chuyen_sang_vay', jsonb_build_object('khoan_vay', g.ten, 'so_tien', g.so_tien) from _vg g;
  select sum(tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau), 0)) into v_sau from kt_tai_khoan tk;
  if v_truoc is distinct from v_sau then raise exception 'Số dư tài khoản đổi sau khi chuyển (% → %) — huỷ', v_truoc, v_sau; end if;
  -- từng tài khoản cũng phải giữ nguyên
  if exists (select 1 from _sd t join kt_tai_khoan tk on tk.id = t.id
              where t.sd is distinct from tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau), 0)) then
    raise exception 'Số dư 1 tài khoản đổi sau khi chuyển — huỷ'; end if;
  raise notice 'Đã chuyển % phiếu', v_n;
end $mig$;
