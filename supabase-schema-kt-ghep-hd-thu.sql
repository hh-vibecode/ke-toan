-- 23/10/2026 (anh): "cứ cái nào liên quan MISA mà có tồn tại trong app giao dịch thì gắn về cho chuẩn bất kể chi thu".
-- PHIẾU THU ↔ HOÁ ĐƠN BÁN RA công ty (meInvoice, kt_thue_hd nguon 'meinvoice:%', mỗi HĐ 1 dòng, khoá = ký hiệu-số HĐ):
--  · số tiền lệch ≤ 1.000 đ · ngày HĐ từ 15 ngày trước → 30 ngày sau ngày thu
--  · nội dung phiếu thu (tên khách Kiot + ghi chú) ghi SỐ HĐ ("HD 75", "hđ số 114") = số HĐ → chắc chắn; hoặc tên người mua (≥ 2 chữ sau khi bỏ anh / chị / cô…) khớp nội dung ≥ 80%
--  Tự gắn khi 1 phiếu ↔ 1 HĐ duy nhất VÀ (khớp số HĐ hoặc tên ≥ 80%); còn lại là gợi ý trong popup phiếu thu.
-- Kèm: gợi ý phiếu chi dùng luật mới (kt_ung_vien_hd_vao2) + lý do; kt_hd_can_pdf cho Edge kt-meinvoice-bot tải PDF HĐ đầu vào về chứng từ. — Monsieur Claude
create table if not exists kt_thu_hd (
  thu_id bigint not null references kt_thu(id), hd_ma text not null, so_hd text, ky_hieu text, ngay_hd date, nguoi_mua text, mst text, tong numeric,
  cach text not null default 'tu_dong', diem numeric, boi text, luc timestamptz not null default now(), ly_do text,
  primary key (thu_id, hd_ma));
create unique index if not exists kt_thu_hd_hd on kt_thu_hd (hd_ma);
alter table kt_thu_hd enable row level security;
revoke all on kt_thu_hd from anon, authenticated;

create or replace function public.kt_ung_vien_hd_thu() returns table(thu_id bigint, hd_ma text, so_hd text, ky_hieu text, ngay_hd date, nguoi_mua text, mst text, tong numeric,
    diem numeric, ly_do text, n_hd int, n_thu int) language sql stable security definer set search_path = public as $f$
  with h as (select ky_hieu || '-' || so_hd ma, so_hd, ky_hieu, ngay, nguoi_mua, mst, tong, ltrim(so_hd, '0') so,
                    -- tên ngắn kiểu "Anh Hải", "Cô Liên": bỏ xưng hô còn 1 chữ → chỉ gợi ý
                    cardinality(regexp_split_to_array(regexp_replace(trim(lower(kt_bo_dau(coalesce(nguoi_mua, '')))), '^(anh|chi|co|chu|thay|ba|ong|em|c|a)[ .]+', ''), '\s+')) < 2 ngan from kt_thue_hd
              where nguon like 'meinvoice:%' and so_hd is not null and not exists (select 1 from kt_thu_hd g where g.hd_ma = kt_thue_hd.ky_hieu || '-' || kt_thue_hd.so_hd)),
       t as (select id, ngay, so_tien, coalesce(noi_dung, '') || ' ' || coalesce(ghi_chu, '') nd from kt_thu x
              where not da_xoa and ngay >= '2026-01-01' and not exists (select 1 from kt_thu_hd g where g.thu_id = x.id)),
       p as (select t.id, h.*, kt_diem_ten(t.nd, h.nguoi_mua) d, h.ngay - t.ngay lech,
                    lower(kt_bo_dau(t.nd)) ~ ('(hd|hoa don)\s*(so)?\s*:?\s*0*' || h.so || '([^0-9]|$)') kso
               from t join h on abs(t.so_tien - h.tong) <= 1000 and h.ngay between t.ngay - 15 and t.ngay + 30)
  select id, ma, so_hd, ky_hieu, ngay, nguoi_mua, mst, tong,
         round(d + case when kso then 1 else 0 end + 0.2 * (1 - least(abs(lech), 30) / 30.0), 2),
         concat_ws(' · ', case when kso then 'nội dung ghi số HĐ ' || so end, case when d >= 0.5 and ngan then 'gần giống tên khách (' || round(d * 100) || '%, tên ngắn)' when d >= 0.5 then 'khớp tên khách (' || round(d * 100) || '%)' end,
                   'khớp số tiền', case when lech = 0 then 'cùng ngày' when lech < 0 then 'HĐ trước ' || -lech || ' ngày' else 'HĐ sau ' || lech || ' ngày' end),
         (count(*) over (partition by id))::int, (count(*) over (partition by ma))::int
    from p where kso or d >= 0.5;
$f$;

create or replace function public.kt_ghep_hd_thu(p_ghi boolean default true) returns int language plpgsql security definer set search_path = public as $f$
declare n int := 0; r record;
begin
  for r in select * from kt_ung_vien_hd_thu() u where u.n_hd = 1 and u.n_thu = 1 and (u.ly_do like 'nội dung ghi số HĐ%' or u.ly_do ~ 'khớp tên khách \((8|9)[0-9]%|khớp tên khách \(100%') loop
    n := n + 1;
    if p_ghi then
      insert into kt_thu_hd (thu_id, hd_ma, so_hd, ky_hieu, ngay_hd, nguoi_mua, mst, tong, cach, diem, boi, ly_do)
        values (r.thu_id, r.hd_ma, r.so_hd, r.ky_hieu, r.ngay_hd, r.nguoi_mua, r.mst, r.tong, 'tu_dong', r.diem, 'Hệ thống', r.ly_do) on conflict do nothing;
    end if;
  end loop;
  if p_ghi and n > 0 then insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_thu', 'ghep_hd_ra', jsonb_build_object('so_phieu', n)); end if;
  return n;
end $f$;

-- phiếu thu: HĐ đã gắn + gợi ý (popup phiếu thu)
create or replace function public.kt_hd_thu_ds(p_phien text) returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'thu');
  return jsonb_build_object(
    'da_ghep', (select coalesce(jsonb_agg(to_jsonb(g)), '[]') from kt_thu_hd g),
    'goi_y', (select coalesce(jsonb_agg(to_jsonb(u) order by u.thu_id, u.diem desc), '[]') from kt_ung_vien_hd_thu() u
               where not (u.n_hd = 1 and u.n_thu = 1 and (u.ly_do like 'nội dung ghi số HĐ%' or u.ly_do ~ 'khớp tên khách \((8|9)[0-9]%|khớp tên khách \(100%'))));
end $f$;

create or replace function public.kt_ghep_hd_thu_tay(p_phien text, p_thu bigint, p_hd text, p_bo boolean default false) returns void
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung; h record;
begin
  u := kt_chan(p_phien, 'thu', true);
  if p_bo then delete from kt_thu_hd where thu_id = p_thu and hd_ma = p_hd;
  else
    select ky_hieu || '-' || so_hd ma, so_hd, ky_hieu, ngay, nguoi_mua, mst, tong into h from kt_thue_hd
     where nguon like 'meinvoice:%' and ky_hieu || '-' || so_hd = p_hd limit 1;
    if h.ma is null then raise exception 'Không thấy hoá đơn này'; end if;
    if exists (select 1 from kt_thu_hd where hd_ma = p_hd and thu_id <> p_thu) then raise exception 'Hoá đơn này đã gắn với phiếu thu khác'; end if;
    insert into kt_thu_hd (thu_id, hd_ma, so_hd, ky_hieu, ngay_hd, nguoi_mua, mst, tong, cach, boi, ly_do)
      values (p_thu, h.ma, h.so_hd, h.ky_hieu, h.ngay, h.nguoi_mua, h.mst, h.tong, 'tay', u.ho_ten, 'kế toán xác nhận') on conflict do nothing;
  end if;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu)
    values (u.ho_ten, 'kt_thu', case when p_bo then 'bo_ghep_hd_ra' else 'ghep_hd_ra_tay' end, jsonb_build_object('thu_id', p_thu, 'hd', p_hd));
end $f$;

-- phiếu chi: gợi ý = luật cũ (phiếu tick có HĐ đỏ, khoảng ngày rộng) ∪ luật mới (mọi phiếu đã chi) chưa đủ chắc để tự gắn; kèm lý do + MST
create or replace function public.kt_hd_vao_goi_y(p_phien text) returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'chi');
  return jsonb_build_object(
    'goi_y', (select coalesce(jsonb_agg(to_jsonb(z) order by z.chi_id, z.diem desc), '[]') from (
        select distinct on (chi_id, hd_ma) * from (
          select chi_id, hd_ma, so_hd, ky_hieu, ngay_hd ngay, ncc, mst, tong, diem, ly_do from kt_ung_vien_hd_vao2()
          union all
          select chi_id, hd_ma, so_hd, ky_hieu, ngay_hd, ncc, mst, tong, diem, 'khớp số tiền · ngày gần' from kt_ung_vien_hd_vao()) a
        order by chi_id, hd_ma, ly_do desc) z),
    'da_ghep', (select coalesce(jsonb_agg(jsonb_build_object('chi_id', chi_id, 'hd_ma', hd_ma, 'so_hd', so_hd, 'ky_hieu', ky_hieu, 'ngay', ngay_hd,
        'ncc', ncc, 'mst', mst, 'tong', tong, 'cach', cach, 'boi', boi, 'luc', luc, 'ly_do', ly_do)), '[]') from kt_chi_hd),
    'keo_luc', (select max(keo_luc) from kt_thue_hd where nguon like 'misabot:%'));
end $f$;

-- HĐ đầu vào đã gắn phiếu chi mà chưa có file PDF trong chứng từ (Edge kt-meinvoice-bot tải về: chi/{chi}/misa_{ma}.pdf)
create or replace function public.kt_hd_can_pdf(p_n int default 8) returns table(chi_id bigint, hd_ma text, so_hd text, ky_hieu text)
  language sql stable security definer set search_path = public as $f$
  select g.chi_id, g.hd_ma, g.so_hd, g.ky_hieu from kt_chi_hd g
   where not exists (select 1 from kt_chung_tu k where k.duong_dan = 'chi/' || g.chi_id || '/misa_' || g.hd_ma || '.pdf')
   order by g.luc desc limit p_n $f$;
revoke all on function public.kt_hd_can_pdf(int), public.kt_ghep_hd_thu(boolean), public.kt_ung_vien_hd_thu() from anon, authenticated, public;

-- chạy kèm job ghép HĐ đầu vào (Edge kt-meinvoice-bot gọi sau khi kéo, 00:35 — sau kt-meinvoice HĐ bán ra 00:25)
create or replace function public.kt_ghep_hd_vao_va_thu(p_ghi boolean default true) returns jsonb language plpgsql security definer set search_path = public as $f$
begin
  return kt_ghep_hd_vao(p_ghi) || jsonb_build_object('thu', kt_ghep_hd_thu(p_ghi));
end $f$;
revoke all on function public.kt_ghep_hd_vao_va_thu(boolean) from anon, authenticated, public;
-- hàm nội bộ trả dữ liệu HĐ / STK: chỉ service role gọi (trình duyệt dùng kt_hd_vao_goi_y / kt_hd_thu_ds có kiểm phiên)
revoke all on function public.kt_ung_vien_hd_vao2(), public.kt_ung_vien_hd_vao(), public.kt_stk_mst(), public.kt_ghep_hd_vao(boolean) from anon, authenticated, public;

-- 23/10 (kế toán: PC Nhất Tín bị gợi ý HĐ Viettel — "chả liên quan"): luật gợi ý cũ chỉ cần số tiền ±1.000 → bỏ;
-- gợi ý phải khớp tên (≥ 30%) hoặc STK. Kế toán hỏi "HĐ đã xuất mà chưa nối được thì làm gì" → ô tìm HĐ MISA theo số HĐ / MST / tên rồi bấm gắn.
create or replace function public.kt_hd_vao_goi_y(p_phien text) returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'chi');
  return jsonb_build_object(
    'goi_y', (select coalesce(jsonb_agg(to_jsonb(z) order by z.chi_id, z.diem desc), '[]') from (
        select chi_id, hd_ma, so_hd, ky_hieu, ngay_hd ngay, ncc, mst, tong, diem, ly_do from kt_ung_vien_hd_vao2()) z),
    'da_ghep', (select coalesce(jsonb_agg(jsonb_build_object('chi_id', chi_id, 'hd_ma', hd_ma, 'so_hd', so_hd, 'ky_hieu', ky_hieu, 'ngay', ngay_hd,
        'ncc', ncc, 'mst', mst, 'tong', tong, 'cach', cach, 'boi', boi, 'luc', luc, 'ly_do', ly_do)), '[]') from kt_chi_hd),
    'keo_luc', (select max(keo_luc) from kt_thue_hd where nguon like 'misabot:%'));
end $f$;

-- tìm HĐ chưa gắn: p_chieu 'vao' (đầu vào, phiếu chi) / 'ra' (bán ra, phiếu thu); q = số HĐ, MST hoặc tên (không dấu cũng được); số tiền gần p_tien lên đầu
create or replace function public.kt_tim_hd(p_phien text, p_chieu text, p_q text, p_tien numeric default null) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
declare q text := lower(kt_bo_dau(trim(coalesce(p_q, '')))); qs text := ltrim(regexp_replace(coalesce(p_q, ''), '\D', '', 'g'), '0');
begin
  perform kt_chan(p_phien, case when p_chieu = 'ra' then 'thu' else 'chi' end);
  if length(q) < 2 then return '[]'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(z)), '[]') from (
    select case when p_chieu = 'ra' then t.ky_hieu || '-' || t.so_hd else t.ma_ngoai end hd_ma, t.so_hd, t.ky_hieu, t.ngay, t.nguoi_mua ncc, t.nguoi_mua, t.mst, t.tong
      from kt_thue_hd t
     where (case when p_chieu = 'ra' then t.nguon like 'meinvoice:%' and not exists (select 1 from kt_thu_hd g where g.hd_ma = t.ky_hieu || '-' || t.so_hd)
                 else t.nguon like 'misabot:%' and t.ma_ngoai is not null and not exists (select 1 from kt_chi_hd g where g.hd_ma = t.ma_ngoai) end)
       and ((qs <> '' and (ltrim(t.so_hd, '0') = qs or t.mst like qs || '%')) or lower(kt_bo_dau(coalesce(t.nguoi_mua, ''))) like '%' || q || '%')
     order by abs(t.tong - coalesce(p_tien, t.tong)), t.ngay desc limit 15) z);
end $f$;
