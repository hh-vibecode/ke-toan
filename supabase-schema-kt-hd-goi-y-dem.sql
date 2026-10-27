-- 27/10/2026 (anh: "auke" — tăng tốc để Tổng quan / Phiếu chi không chạm ngưỡng 3 giây của anon).
-- kt_hd_vao_goi_y chạy MỖI LẦN trang Phiếu chi vẽ lại (~2.100 lần / kỳ thống kê, ~1,1 s / lần: so mọi phiếu chi đã chi với mọi HĐ MISA)
-- → góp phần làm CSDL dùng chung bận, các hàm khác (Tổng quan) bị "canceling statement due to statement timeout".
-- Cách làm: lưu đệm phần GỢI Ý (kt_hd_goi_y_dem). Trigger mức câu lệnh trên kt_chi (đúng các cột dùng để so), kt_chi_hd, kt_thue_hd
-- tăng số phiên bản; hàm chỉ tính lại khi phiên bản đổi. Phần "đã ghép" + giờ kéo vẫn đọc trực tiếp (nhẹ). — Monsieur Claude
create table if not exists public.kt_hd_goi_y_dem (
  id int primary key default 1 check (id = 1),
  ban bigint not null default 1,          -- tăng khi dữ liệu nguồn đổi
  ban_tinh bigint,                        -- phiên bản lúc tính du_lieu
  du_lieu jsonb, tinh_luc timestamptz);
alter table public.kt_hd_goi_y_dem enable row level security;
revoke all on public.kt_hd_goi_y_dem from anon, authenticated;
insert into kt_hd_goi_y_dem (id) values (1) on conflict do nothing;

create or replace function public.kt_tg_hd_goi_y_doi() returns trigger
 language plpgsql security definer set search_path = public as $$
begin
  update kt_hd_goi_y_dem set ban = ban + 1 where id = 1;
  return null;
end $$;
revoke all on function public.kt_tg_hd_goi_y_doi() from public, anon, authenticated;

drop trigger if exists kt_hd_goi_y_doi on public.kt_chi;
create trigger kt_hd_goi_y_doi after insert or delete or update of da_xoa, trang_thai, ca_nhan, ngay_tt, so_tien, thu_huong_ten, thu_huong_stk, noi_dung, ghi_chu
  on public.kt_chi for each statement execute function kt_tg_hd_goi_y_doi();
drop trigger if exists kt_hd_goi_y_doi on public.kt_chi_hd;
create trigger kt_hd_goi_y_doi after insert or delete or update on public.kt_chi_hd for each statement execute function kt_tg_hd_goi_y_doi();
drop trigger if exists kt_hd_goi_y_doi on public.kt_thue_hd;
create trigger kt_hd_goi_y_doi after insert or delete or update on public.kt_thue_hd for each statement execute function kt_tg_hd_goi_y_doi();

-- VOLATILE (có ghi bảng đệm). Giữ nguyên đầu ra như bản cũ.
create or replace function public.kt_hd_vao_goi_y(p_phien text)
 returns jsonb language plpgsql volatile security definer set search_path to 'public' as $function$
declare d kt_hd_goi_y_dem; v jsonb;
begin
  perform kt_chan(p_phien, 'chi');
  select * into d from kt_hd_goi_y_dem where id = 1;
  if d.ban_tinh is not null and d.ban_tinh = d.ban then
    v := d.du_lieu;
  else
    v := (select coalesce(jsonb_agg(to_jsonb(z) order by z.chi_id, z.diem desc), '[]') from (
            select chi_id, hd_ma, so_hd, ky_hieu, ngay_hd ngay, ncc, mst, tong, diem, ly_do from kt_ung_vien_hd_vao2()) z);
    -- chỉ ghi khi chưa ai đổi dữ liệu trong lúc tính (so phiên bản đã đọc lúc đầu)
    update kt_hd_goi_y_dem set du_lieu = v, ban_tinh = d.ban, tinh_luc = now() where id = 1 and ban = d.ban;
  end if;
  return jsonb_build_object(
    'goi_y', v,
    'da_ghep', (select coalesce(jsonb_agg(jsonb_build_object('chi_id', chi_id, 'hd_ma', hd_ma, 'so_hd', so_hd, 'ky_hieu', ky_hieu, 'ngay', ngay_hd,
        'ncc', ncc, 'mst', mst, 'tong', tong, 'cach', cach, 'boi', boi, 'luc', luc, 'ly_do', ly_do)), '[]') from kt_chi_hd),
    'keo_luc', (select max(keo_luc) from kt_thue_hd where nguon like 'misabot:%'));
end $function$;

-- (2) Lần tính lại (khi dữ liệu đổi) cũng nhanh hơn: trước chấm tên từng cặp phiếu–HĐ → kt_diem_ten tách từ lại 2 chuỗi mỗi cặp (~1,2 s / 339 cặp).
-- Nay: lọc cặp theo số tiền + ngày trước, tách từ MỖI CHUỖI 1 LẦN rồi chấm bằng mảng từ (kt_diem_tu — đúng công thức kt_diem_ten). Kết quả y hệt bản cũ.
create or replace function public.kt_diem_tu(x text[], y text[]) returns numeric language sql immutable as $$
  select case when cardinality(x) = 0 or cardinality(y) = 0 then 0
              else round((select count(*) from unnest(x) w where w = any(y))::numeric / least(cardinality(x), cardinality(y)), 2) end;
$$;

create or replace function public.kt_ung_vien_hd_vao2()
 returns table(chi_id bigint, hd_ma text, so_hd text, ky_hieu text, ngay_hd date, ncc text, mst text, tong numeric, diem numeric, ly_do text, n_hd integer, n_chi integer)
 language sql stable security definer set search_path to 'public' as $function$
  with stkmst as materialized (select * from kt_stk_mst()),
       c as (select id, so_tien, ngay_tt, coalesce(thu_huong_ten, '') ten, coalesce(noi_dung, '') || ' ' || coalesce(ghi_chu, '') nd,
                    regexp_replace(coalesce(thu_huong_stk, ''), '\D', '', 'g') stk from kt_chi
              where not da_xoa and trang_thai = 'da_tt' and not coalesce(ca_nhan, false) and ngay_tt >= '2026-01-01'
                and not exists (select 1 from kt_chi_hd g where g.chi_id = kt_chi.id)),
       h as (select ma_ngoai, so_hd, ky_hieu, ngay, nguoi_mua ncc, mst, tong from kt_thue_hd
              where nguon like 'misabot:%' and ma_ngoai is not null and not exists (select 1 from kt_chi_hd g where g.hd_ma = kt_thue_hd.ma_ngoai)),
       p0 as materialized (select c.id chi_id, c.ten, c.nd, c.stk, c.ngay_tt, h.*
               from c join h on abs(h.tong - c.so_tien) <= 1000 and h.ngay between c.ngay_tt - 30 and c.ngay_tt + 15),
       tu as materialized (select s, kt_tu_ten(s) w from (select ten s from p0 union select nd from p0 union select coalesce(ncc, '') from p0) z),
       p as (select p0.chi_id, p0.ma_ngoai, p0.so_hd, p0.ky_hieu, p0.ngay, p0.ncc, p0.mst, p0.tong,
                    kt_diem_tu(a.w, b.w) dt1, kt_diem_tu(n.w, b.w) dnd,
                    exists (select 1 from stkmst s where s.stk = p0.stk and s.stk <> '' and s.mst = p0.mst) kstk, (p0.ngay - p0.ngay_tt) lech
               from p0 join tu a on a.s = p0.ten join tu n on n.s = p0.nd join tu b on b.s = coalesce(p0.ncc, ''))
  select chi_id, ma_ngoai, so_hd, ky_hieu, ngay, ncc, mst, tong,
         round(greatest(dt1, dnd) + case when kstk then 0.5 else 0 end + 0.2 * (1 - least(abs(lech), 30) / 30.0), 2) diem,
         concat_ws(' · ', case when kstk then 'khớp STK người nhận' end, case when dt1 >= 0.5 then 'khớp tên người nhận (' || round(dt1 * 100) || '%)' when dnd >= 0.5 then 'khớp tên trong nội dung (' || round(dnd * 100) || '%)' end,
                   'khớp số tiền', case when lech = 0 then 'cùng ngày' when lech < 0 then 'HĐ trước ' || -lech || ' ngày' else 'HĐ sau ' || lech || ' ngày' end) ly_do,
         (count(*) over (partition by chi_id))::int, (count(*) over (partition by ma_ngoai))::int
    from p where greatest(dt1, dnd) >= 0.3 or kstk;
$function$;
revoke all on function public.kt_ung_vien_hd_vao2() from public, anon, authenticated;
revoke all on function public.kt_diem_tu(text[], text[]) from public, anon, authenticated;
