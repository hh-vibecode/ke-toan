-- 05/11/2026 anh (ảnh danh sách phiếu thu: kế toán ghi "HD 315 22/10/2026" mà không gắn): "phiếu thu phải check và nối lại đủ hoá đơn,
-- không đủ thì tách ra hoặc nêu lý do" + "cho nút gắn giống bên phiếu chi". Luật cũ (supabase-schema-kt-ghep-hd-thu.sql) bắt số tiền phiếu = HĐ ±1.000
-- và 1 phiếu ↔ 1 HĐ → trượt khi khách cọc trước + trả nốt (2 phiếu / 1 HĐ) hoặc 1 phiếu trả cho 2 HĐ. Luật mới (tự gắn, ghi lý do):
--  R1 nội dung phiếu ghi số HĐ ("HD 315", "hđ số 3 ngày 8/1") → gắn dù số tiền khác; số đi kèm ngày thì ngày phải = ngày HĐ; số trùng ở nhiều ký hiệu
--     mà không có ngày phân biệt → chỉ gợi ý. Bỏ "Tổng HD …", "VAT= ..." trước khi đọc số; mã Kiot HD0xxxxx (≥ 6 chữ số) không tính.
--  R2 HĐ đỏ = đúng 1 hoá đơn Kiot cùng số tiền (±1.000, HĐ đỏ từ 5 ngày trước → 45 ngày sau HĐ Kiot, người mua chung chung hoặc tên khớp ≥ 50%),
--     2 chiều duy nhất → gắn MỌI phiếu thu (tên khác khách Kiot: chỉ gợi ý) trả hoá đơn Kiot đó (bảng chia phiếu Kiot kt_kiot_hd_thu).
--  R3 luật cũ (số tiền ±1.000 + tên ≥ 80%, 1 ↔ 1) cho HĐ chưa gắn.
-- 1 HĐ được gắn nhiều phiếu (cọc + trả nốt), 1 phiếu nhiều HĐ. kt_hd_ra_doi_chieu: từng HĐ bán ra → Đủ / Thu thiếu / Thu thừa / Chưa nối + lý do. — Monsieur Claude
drop index if exists kt_thu_hd_hd;
create index if not exists kt_thu_hd_hd2 on kt_thu_hd (hd_ma);

-- tốc độ: dò ứng viên ~1,7 s → không chạy mỗi lần mở trang. kt_ghep_hd_thu (job sau kéo MISA 00:35 / 12:35) tự gắn rồi lưu GỢI Ý vào kt_thu_hd_goi_y;
-- trang phiếu thu / đối chiếu chỉ đọc bảng này (bỏ cặp đã gắn lúc đọc). HĐ khó (không chắc) để kế toán nối tay (anh 05/11).
create table if not exists kt_thu_hd_goi_y (thu_id bigint not null, hd_ma text not null, so_hd text, ky_hieu text, ngay_hd date, nguoi_mua text, mst text, tong numeric,
  diem numeric, ly_do text, luc timestamptz not null default now(), primary key (thu_id, hd_ma));
alter table kt_thu_hd_goi_y enable row level security;
revoke all on kt_thu_hd_goi_y from anon, authenticated;

drop function if exists public.kt_ung_vien_hd_thu();
create function public.kt_ung_vien_hd_thu() returns table(thu_id bigint, hd_ma text, so_hd text, ky_hieu text, ngay_hd date, nguoi_mua text, mst text, tong numeric,
    diem numeric, ly_do text, chac boolean) language sql stable security definer set search_path = public as $f$
  with h as (select ky_hieu || '-' || so_hd ma, so_hd, ky_hieu, ngay, nguoi_mua, mst, tong, ltrim(so_hd, '0') so,
                    lower(kt_bo_dau(coalesce(nguoi_mua, ''))) ~ '(nguoi tieu dung|khach le|khong lay hoa don|nguoi mua khong)' chung,
                    cardinality(regexp_split_to_array(regexp_replace(trim(lower(kt_bo_dau(coalesce(nguoi_mua, '')))), '^(anh|chi|co|chu|thay|ba|ong|em|c|a)[ .]+', ''), '\s+')) < 2 ngan
               from kt_thue_hd where nguon like 'meinvoice:%' and so_hd is not null),
       g as (select thu_id, hd_ma from kt_thu_hd),
       t as (select id, ngay, so_tien, ma_nguon, coalesce(noi_dung, '') || ' ' || coalesce(ghi_chu, '') nd0,
                    regexp_replace(regexp_replace(lower(kt_bo_dau(coalesce(noi_dung, '') || ' ' || coalesce(ghi_chu, ''))),
                      'tong\s*(\d+\s*)?(hd|hoa don)\s*:?\s*[0-9.,]+', ' ', 'g'), 'vat\s*[=:]?\s*[0-9.,]+', ' ', 'g') nd
               from kt_thu where not da_xoa and ngay >= '2026-01-01'),
       ref as (select t.id, t.ngay, m[1] so, m[2] dd, m[3] mm
                 from t, regexp_matches(t.nd, '(?:hd|hoa don)\s*(?:so)?\s*:?\s*0*([0-9]{1,5})(?![0-9])(?:\s*(?:ngay)?\s*([0-9]{1,2})/([0-9]{1,2}))?', 'g') m),
       r1 as (select ref.id, h.ma, ref.so, count(*) over (partition by ref.id, ref.so) n
                from ref join h on h.so = ref.so and h.ngay between ref.ngay - 45 and ref.ngay + 45
                       and (ref.dd is null or (extract(day from h.ngay) = ref.dd::int and extract(month from h.ngay) = ref.mm::int))),
       kv as (select k.ma kma, k.tong, (k.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, k.khach_ten from kt_kiot_hoa_don k
               where k.trang_thai in (1, 3) and k.tong > 0 and k.ngay >= '2025-12-01'),
       r2c as (select h.ma, kv.kma, h.chung or kt_diem_ten(kv.khach_ten, h.nguoi_mua) >= 0.5 ten_ok, count(*) over (partition by h.ma) nh, count(*) over (partition by kv.kma) nk
                 from h join kv on abs(kv.tong - h.tong) <= 1000 and h.ngay between kv.ngay - 5 and kv.ngay + 45),
       r2 as (select distinct x.id, c.ma, c.kma, c.ten_ok from r2c c join kt_kiot_hd_thu p on p.ma = c.kma, jsonb_array_elements(p.ds) e
                join kt_kiot_so_quy q on q.ma = e->>'ma' join kt_thu x on x.ma_nguon = 'kiot:' || q.id and not x.da_xoa
               where c.nh = 1 and c.nk = 1 and x.id not in (select id from r1)),   -- phiếu đã ghi số HĐ: theo ghi chú kế toán, không gắn thêm theo bảng chia Kiot
       r3 as (select t.id, h.ma, kt_diem_ten(t.nd0, h.nguoi_mua) d, h.ngay - t.ngay lech, h.ngan
                from t join h on abs(t.so_tien - h.tong) <= 1000 and h.ngay between t.ngay - 15 and t.ngay + 30
               where not exists (select 1 from g where g.hd_ma = h.ma) and not exists (select 1 from g where g.thu_id = t.id)),
       r3n as (select r3.*, count(*) over (partition by id) n_hd, count(*) over (partition by ma) n_thu from r3 where d >= 0.5),
       u as (select id, ma, 3.0 diem, 'nội dung ghi số HĐ ' || so ly, n = 1 chac from r1
             union all select id, ma, 2.5, 'khớp hoá đơn Kiot ' || kma || ' (cùng số tiền' || case when ten_ok then '' else ', tên người mua khác khách Kiot' end || ') — phiếu trả hoá đơn Kiot đó', ten_ok from r2
             union all select id, ma, round(d + 0.2 * (1 - least(abs(lech), 30) / 30.0), 2),
                              concat_ws(' · ', case when ngan then 'gần giống tên khách (' || round(d * 100) || '%, tên ngắn)' else 'khớp tên khách (' || round(d * 100) || '%)' end, 'khớp số tiền',
                                        case when lech = 0 then 'cùng ngày' when lech < 0 then 'HĐ trước ' || -lech || ' ngày' else 'HĐ sau ' || lech || ' ngày' end),
                              n_hd = 1 and n_thu = 1 and d >= 0.8 and not ngan from r3n),
       uu as (select distinct on (id, ma) * from u order by id, ma, chac desc, diem desc)
  select uu.id, h.ma, h.so_hd, h.ky_hieu, h.ngay, h.nguoi_mua, h.mst, h.tong, uu.diem, uu.ly, uu.chac
    from uu join h on h.ma = uu.ma where not exists (select 1 from g where g.thu_id = uu.id and g.hd_ma = uu.ma);
$f$;
revoke all on function public.kt_ung_vien_hd_thu() from anon, authenticated, public;

-- gắn tay: 1 HĐ được gắn nhiều phiếu (cọc + trả nốt) — bỏ chặn "đã gắn với phiếu thu khác"
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
    insert into kt_thu_hd (thu_id, hd_ma, so_hd, ky_hieu, ngay_hd, nguoi_mua, mst, tong, cach, boi, ly_do)
      values (p_thu, h.ma, h.so_hd, h.ky_hieu, h.ngay, h.nguoi_mua, h.mst, h.tong, 'tay', u.ho_ten, 'kế toán xác nhận') on conflict do nothing;
  end if;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu)
    values (u.ho_ten, 'kt_thu', case when p_bo then 'bo_ghep_hd_ra' else 'ghep_hd_ra_tay' end, jsonb_build_object('thu_id', p_thu, 'hd', p_hd));
end $f$;

-- tìm HĐ: bán ra hiện cả HĐ đã gắn phiếu khác (trả nhiều lần) — kèm số phiếu đã gắn + tiền đã nối
create or replace function public.kt_tim_hd(p_phien text, p_chieu text, p_q text, p_tien numeric default null) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
declare q text := lower(kt_bo_dau(trim(coalesce(p_q, '')))); qs text := ltrim(regexp_replace(coalesce(p_q, ''), '\D', '', 'g'), '0');
begin
  perform kt_chan(p_phien, case when p_chieu = 'ra' then 'thu' else 'chi' end);
  if length(q) < 2 and qs = '' then return '[]'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(z)), '[]') from (
    select case when p_chieu = 'ra' then t.ky_hieu || '-' || t.so_hd else t.ma_ngoai end hd_ma, t.so_hd, t.ky_hieu, t.ngay, t.nguoi_mua ncc, t.nguoi_mua, t.mst, t.tong,
           case when p_chieu = 'ra' then (select count(*) from kt_thu_hd g where g.hd_ma = t.ky_hieu || '-' || t.so_hd) end so_phieu,
           case when p_chieu = 'ra' then (select sum(x.so_tien) from kt_thu_hd g join kt_thu x on x.id = g.thu_id where g.hd_ma = t.ky_hieu || '-' || t.so_hd) end da_noi
      from kt_thue_hd t
     where (case when p_chieu = 'ra' then t.nguon like 'meinvoice:%'
                 else t.nguon like 'misabot:%' and t.ma_ngoai is not null and not exists (select 1 from kt_chi_hd g where g.hd_ma = t.ma_ngoai) end)
       and ((qs <> '' and (ltrim(t.so_hd, '0') = qs or t.mst like qs || '%')) or (length(q) >= 2 and lower(kt_bo_dau(coalesce(t.nguoi_mua, ''))) like '%' || q || '%'))
     order by abs(t.tong - coalesce(p_tien, t.tong)), t.ngay desc limit 15) z);
end $f$;

-- đối chiếu từng HĐ bán ra công ty ↔ phiếu thu đã gắn: nhóm = HĐ + mọi HĐ chung phiếu với nó (1 phiếu trả nhiều HĐ) → so tổng HĐ nhóm với tổng phiếu nhóm
create or replace function public.kt_hd_ra_doi_chieu(p_phien text, p_tu date, p_den date) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  return (with h as (select ky_hieu || '-' || so_hd ma, so_hd, ky_hieu, ngay, nguoi_mua, tong from kt_thue_hd
                      where nguon like 'meinvoice:%' and so_hd is not null),
               hk as (select * from h where ngay between p_tu and p_den),
               g as (select g.hd_ma, g.thu_id, g.cach, g.ly_do, g.canh_bao, x.ngay, x.so_tien, x.noi_dung, x.ma_nguon from kt_thu_hd g join kt_thu x on x.id = g.thu_id and not x.da_xoa),
               -- nhóm: các HĐ cùng phiếu với HĐ này
               nh as (select hk.ma, (select array_agg(distinct g2.hd_ma) from g g1 join g g2 on g2.thu_id = g1.thu_id where g1.hd_ma = hk.ma) hds from hk),
               gy as (select u.hd_ma, jsonb_agg(jsonb_build_object('thu_id', u.thu_id, 'ly_do', u.ly_do, 'so_tien', x.so_tien, 'ngay', x.ngay, 'nd', left(x.noi_dung, 120)) order by u.diem desc) ds
                        from kt_thu_hd_goi_y u join kt_thu x on x.id = u.thu_id and not x.da_xoa
                       where not exists (select 1 from kt_thu_hd g2 where g2.thu_id = u.thu_id and g2.hd_ma = u.hd_ma) group by 1),
               kv as (select h.ma, string_agg(k.ma, ', ') kma, count(*) n from h join kt_kiot_hoa_don k on abs(k.tong - h.tong) <= 1000 and k.trang_thai in (1, 3)
                         and h.ngay between (k.ngay at time zone 'Asia/Ho_Chi_Minh')::date - 5 and (k.ngay at time zone 'Asia/Ho_Chi_Minh')::date + 45
                       where h.ngay between p_tu and p_den group by 1)
          select coalesce(jsonb_agg(jsonb_build_object('ma', hk.ma, 'so_hd', hk.so_hd, 'ky_hieu', hk.ky_hieu, 'ngay', hk.ngay, 'nguoi_mua', hk.nguoi_mua, 'tong', hk.tong,
                   'phieu', (select coalesce(jsonb_agg(jsonb_build_object('thu_id', g.thu_id, 'ngay', g.ngay, 'so_tien', g.so_tien, 'nd', left(g.noi_dung, 120), 'cach', g.cach, 'ly_do', g.ly_do, 'canh_bao', g.canh_bao,
                               'chung', (select count(*) from g g3 where g3.thu_id = g.thu_id)) order by g.ngay), '[]') from g where g.hd_ma = hk.ma),
                   'nhom_hd', coalesce(array_length(nh.hds, 1), 0),
                   'tong_hd_nhom', (select sum(h2.tong) from h h2 where h2.ma = any(nh.hds)),
                   'tong_thu_nhom', (select sum(s.so_tien) from (select distinct g.thu_id, g.so_tien from g where g.hd_ma = any(nh.hds)) s),
                   'goi_y', coalesce(gy.ds, '[]'), 'kiot', kv.kma, 'kiot_n', coalesce(kv.n, 0)) order by hk.ngay desc, hk.so_hd desc), '[]')
            from hk join nh on nh.ma = hk.ma left join gy on gy.hd_ma = hk.ma left join kv on kv.ma = hk.ma);
end $f$;
revoke all on function public.kt_hd_ra_doi_chieu(text, date, date) from public;
grant execute on function public.kt_hd_ra_doi_chieu(text, date, date) to anon, authenticated;

-- 05/11 anh: "gắn nhưng thấy sai vẫn phải note lại" — cặp TỰ GẮN có dấu hiệu sai thì vẫn gắn (theo ghi chú kế toán) nhưng ghi canh_bao:
--  (a) HĐ đang gắn bị THU THỪA (tổng phiếu > HĐ) và có HĐ khác CHƯA NỐI phiếu nào đúng bằng tiền phiếu ±1.000 trong ±45 ngày → "có thể ghi nhầm số HĐ, HĐ x cùng số tiền"
--  (c) HĐ chỉ gắn phiếu trả riêng nó mà tổng phiếu > HĐ → "HĐ đã thu thừa x qua n phiếu — kiểm lại số HĐ ghi trên phiếu"
--  (tên người mua khác khách trên phiếu KHÔNG báo: thử 05/11 ra 51 cặp đều đúng — thu riêng VAT, trả 1 phần, HKD đứng tên chủ)
-- Cặp kế toán gắn tay = đã xác nhận → không cảnh báo. Tính lại mỗi lượt job.
alter table kt_thu_hd add column if not exists canh_bao text;
create or replace function public.kt_thu_hd_canh_bao() returns int language plpgsql security definer set search_path = public as $f$
declare n int;
begin
  with x as (select g.thu_id, g.hd_ma, t.so_tien, t.ngay, coalesce(t.noi_dung, '') || ' ' || coalesce(t.ghi_chu, '') nd, h.nguoi_mua,
                    (select sum(g2.tong) from kt_thu_hd g2 where g2.thu_id = g.thu_id) tong_hd, h.tong hd_tong,
                    (select sum(t2.so_tien) from kt_thu_hd g2 join kt_thu t2 on t2.id = g2.thu_id and not t2.da_xoa where g2.hd_ma = g.hd_ma) thu_hd,
                    (select count(*) from kt_thu_hd g2 where g2.thu_id = g.thu_id) n_hd,
                    (select count(*) from kt_thu_hd g2 where g2.hd_ma = g.hd_ma) n_phieu,
                    (select bool_and((select count(*) from kt_thu_hd g4 where g4.thu_id = g2.thu_id) = 1) from kt_thu_hd g2 where g2.hd_ma = g.hd_ma) don
               from kt_thu_hd g join kt_thu t on t.id = g.thu_id join kt_thue_hd h on h.nguon like 'meinvoice:%' and h.ky_hieu || '-' || h.so_hd = g.hd_ma
              where g.cach = 'tu_dong'),
       c as (select x.thu_id, x.hd_ma, concat_ws(' · ',
               case when abs(x.so_tien - x.tong_hd) > 1000 and x.thu_hd > x.hd_tong + 1000 then (select 'có thể ghi nhầm số HĐ: HĐ ' || h2.ky_hieu || ' số ' || ltrim(h2.so_hd, '0') || ' ngày ' || to_char(h2.ngay, 'DD/MM') || ' đúng bằng tiền phiếu'
                    from kt_thue_hd h2 where h2.nguon like 'meinvoice:%' and h2.so_hd is not null and abs(h2.tong - x.so_tien) <= 1000 and h2.ngay between x.ngay - 45 and x.ngay + 45
                     and not exists (select 1 from kt_thu_hd g3 where g3.hd_ma = h2.ky_hieu || '-' || h2.so_hd)
                     order by abs(h2.ngay - x.ngay) limit 1) end,
               case when x.don and x.thu_hd > x.hd_tong + 1000 then 'HĐ đã thu thừa ' || replace(to_char(x.thu_hd - x.hd_tong, 'FM999G999G999G999'), ',', '.') || ' qua ' || x.n_phieu || ' phiếu — kiểm lại số HĐ ghi trên phiếu' end) cb from x)
  update kt_thu_hd g set canh_bao = nullif(c.cb, '') from c where c.thu_id = g.thu_id and c.hd_ma = g.hd_ma and g.canh_bao is distinct from nullif(c.cb, '');
  get diagnostics n = row_count;
  update kt_thu_hd set canh_bao = null where cach <> 'tu_dong' and canh_bao is not null;
  return n;
end $f$;
revoke all on function public.kt_thu_hd_canh_bao() from anon, authenticated, public;

create or replace function public.kt_ghep_hd_thu(p_ghi boolean default true) returns int language plpgsql security definer set search_path = public as $f$
declare n int := 0;
begin
  create temp table if not exists _kt_u on commit drop as select * from kt_ung_vien_hd_thu() limit 0;
  truncate _kt_u; insert into _kt_u select * from kt_ung_vien_hd_thu();
  if p_ghi then
    insert into kt_thu_hd (thu_id, hd_ma, so_hd, ky_hieu, ngay_hd, nguoi_mua, mst, tong, cach, diem, boi, ly_do)
      select u.thu_id, u.hd_ma, u.so_hd, u.ky_hieu, u.ngay_hd, u.nguoi_mua, u.mst, u.tong, 'tu_dong', u.diem, 'Hệ thống', u.ly_do from _kt_u u
       where u.chac and not exists (select 1 from kt_nhat_ky k where k.hanh_dong = 'bo_ghep_hd_ra' and (k.du_lieu->>'thu_id')::bigint = u.thu_id and k.du_lieu->>'hd' = u.hd_ma)
      on conflict do nothing;
    get diagnostics n = row_count;
    delete from kt_thu_hd_goi_y;
    insert into kt_thu_hd_goi_y (thu_id, hd_ma, so_hd, ky_hieu, ngay_hd, nguoi_mua, mst, tong, diem, ly_do)
      select distinct on (thu_id, hd_ma) thu_id, hd_ma, so_hd, ky_hieu, ngay_hd, nguoi_mua, mst, tong, diem, ly_do from _kt_u u
       where not u.chac
       order by thu_id, hd_ma, diem desc;
    perform kt_thu_hd_canh_bao();
    if n > 0 then insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_thu', 'ghep_hd_ra', jsonb_build_object('so_phieu', n)); end if;
  else select count(*) into n from _kt_u u where u.chac;
  end if;
  return n;
end $f$;
revoke all on function public.kt_ghep_hd_thu(boolean) from anon, authenticated, public;

create or replace function public.kt_hd_thu_ds(p_phien text) returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'thu');
  return jsonb_build_object(
    'da_ghep', (select coalesce(jsonb_agg(to_jsonb(g)), '[]') from kt_thu_hd g),
    'goi_y', (select coalesce(jsonb_agg(to_jsonb(u) order by u.thu_id, u.diem desc), '[]') from kt_thu_hd_goi_y u
               where not exists (select 1 from kt_thu_hd g where g.thu_id = u.thu_id and g.hd_ma = u.hd_ma)));
end $f$;

-- 05/11 dọn 1 lần: gỡ cặp tự gắn theo Kiot trên phiếu mà kế toán đã ghi số HĐ khác (vd TT011987 ghi HD 325, Kiot chia vào hoá đơn tháng 9)
-- delete from kt_thu_hd g where g.cach = 'tu_dong' and g.ly_do like 'khớp hoá đơn Kiot%' and exists (select 1 from kt_thu_hd r where r.thu_id = g.thu_id and r.ly_do like 'nội dung ghi số HĐ%');
