-- 23/10/2026 (anh): "khoản thanh toán gắn với số hoá đơn nào — khớp số tài khoản người nhận với tên người nhận và số tiền, ngày nữa để thu hẹp phạm vi; gắn tự động
-- với các giao dịch có hoá đơn". Nâng luật ghép hoá đơn đầu vào (MISA) ↔ phiếu chi đã thanh toán:
--  · xét MỌI phiếu đã chi từ 01/01/2026 chưa gắn HĐ (trừ chi cá nhân), không chỉ phiếu người đề nghị tick "có HĐ đỏ"
--  · số tiền lệch ≤ 1.000 đ · ngày HĐ từ 30 ngày trước → 15 ngày sau ngày thanh toán (gần hơn điểm cao hơn)
--  · tên người nhận / nội dung ↔ tên người bán (kt_diem_ten) · SỐ TÀI KHOẢN người nhận: học từ các lần đã gắn mà tên người nhận cũng khớp người bán
--    (phiếu sheet cũ hay ghi STK cá nhân người đề nghị → không học từ những phiếu đó)
--  · 1 lần trả cho NHIỀU HĐ cùng người bán (so "tên lõi" bỏ công ty / TNHH / cổ phần…, hoặc STK đã học): tổng HĐ trong khoảng ngày = số tiền → gắn cả nhóm
--  Tự gắn khi chắc chắn (1 phiếu ↔ 1 HĐ duy nhất VÀ khớp STK / tên người nhận ≥ 50% / tên trong nội dung ≥ 80%); còn lại để "Có HĐ gợi ý". Ghi lý do gắn (cột ly_do). — Monsieur Claude
alter table kt_chi_hd add column if not exists ly_do text;

-- tên lõi: bỏ dấu, bỏ loại hình doanh nghiệp, chỉ giữ chữ số
create or replace function public.kt_ten_loi(p text) returns text language sql immutable as $f$
  select regexp_replace(regexp_replace(lower(kt_bo_dau(coalesce(p, ''))),
    '(cong ty|\ycty\y|tnhh|co phan|\yctcp\y|ho kinh doanh|\yhkd\y|thuong mai|dich vu|\ytm\y|\ydv\y|\ymtv\y|mot thanh vien|san xuat|xuat nhap khau|\yxnk\y|tap doan|chi nhanh)', '', 'g'),
    '[^a-z0-9]', '', 'g') $f$;

create or replace function public.kt_stk_mst() returns table(stk text, mst text) language sql stable security definer set search_path = public as $f$
  select distinct regexp_replace(c.thu_huong_stk, '\D', '', 'g'), g.mst from kt_chi_hd g join kt_chi c on c.id = g.chi_id
   where coalesce(c.thu_huong_stk, '') <> '' and coalesce(g.mst, '') <> '' and kt_diem_ten(c.thu_huong_ten, g.ncc) >= 0.5 $f$;

create or replace function public.kt_ung_vien_hd_vao2() returns table(chi_id bigint, hd_ma text, so_hd text, ky_hieu text, ngay_hd date, ncc text, mst text, tong numeric,
    diem numeric, ly_do text, n_hd int, n_chi int) language sql stable security definer set search_path = public as $f$
  with stkmst as materialized (select * from kt_stk_mst()),
       c as (select id, so_tien, ngay_tt, coalesce(thu_huong_ten, '') ten, coalesce(noi_dung, '') || ' ' || coalesce(ghi_chu, '') nd,
                    regexp_replace(coalesce(thu_huong_stk, ''), '\D', '', 'g') stk from kt_chi
              where not da_xoa and trang_thai = 'da_tt' and not coalesce(ca_nhan, false) and ngay_tt >= '2026-01-01'
                and not exists (select 1 from kt_chi_hd g where g.chi_id = kt_chi.id)),
       h as (select ma_ngoai, so_hd, ky_hieu, ngay, nguoi_mua ncc, mst, tong from kt_thue_hd
              where nguon like 'misabot:%' and ma_ngoai is not null and not exists (select 1 from kt_chi_hd g where g.hd_ma = kt_thue_hd.ma_ngoai)),
       p as (select c.id chi_id, h.*, kt_diem_ten(c.ten, h.ncc) dt1, kt_diem_ten(c.nd, h.ncc) dnd,
                    exists (select 1 from stkmst s where s.stk = c.stk and s.stk <> '' and s.mst = h.mst) kstk, (h.ngay - c.ngay_tt) lech
               from c join h on abs(h.tong - c.so_tien) <= 1000 and h.ngay between c.ngay_tt - 30 and c.ngay_tt + 15)
  select chi_id, ma_ngoai, so_hd, ky_hieu, ngay, ncc, mst, tong,
         round(greatest(dt1, dnd) + case when kstk then 0.5 else 0 end + 0.2 * (1 - least(abs(lech), 30) / 30.0), 2) diem,
         concat_ws(' · ', case when kstk then 'khớp STK người nhận' end, case when dt1 >= 0.5 then 'khớp tên người nhận (' || round(dt1 * 100) || '%)' when dnd >= 0.5 then 'khớp tên trong nội dung (' || round(dnd * 100) || '%)' end,
                   'khớp số tiền', case when lech = 0 then 'cùng ngày' when lech < 0 then 'HĐ trước ' || -lech || ' ngày' else 'HĐ sau ' || lech || ' ngày' end) ly_do,
         (count(*) over (partition by chi_id))::int, (count(*) over (partition by ma_ngoai))::int
    from p where greatest(dt1, dnd) >= 0.3 or kstk;
$f$;

create or replace function public.kt_ghep_hd_vao(p_ghi boolean default true) returns jsonb language plpgsql security definer set search_path = public as $f$
declare n int := 0; ng int := 0; r record; g record;
begin
  -- 1 phiếu ↔ 1 HĐ chắc chắn
  for r in select * from kt_ung_vien_hd_vao2() u where u.n_hd = 1 and u.n_chi = 1 and (u.ly_do like 'khớp STK%' or u.ly_do like '%khớp tên người nhận%' or u.ly_do ~ 'nội dung \((8|9)[0-9]%|nội dung \(100%') loop
    n := n + 1;
    if p_ghi then
      insert into kt_chi_hd (chi_id, hd_ma, so_hd, ky_hieu, ngay_hd, ncc, mst, tong, cach, diem, boi, ly_do)
        values (r.chi_id, r.hd_ma, r.so_hd, r.ky_hieu, r.ngay_hd, r.ncc, r.mst, r.tong, 'tu_dong', r.diem, 'Hệ thống', r.ly_do) on conflict do nothing;
      update kt_chi set co_hd_do = true, hd_do_nhan = true, ngay_nhan_hd = coalesce(ngay_nhan_hd, r.ngay_hd), sua_boi = 'Hệ thống', sua_luc = now() where id = r.chi_id;
    end if;
  end loop;
  -- 1 lần trả cho nhiều HĐ cùng người bán: tên lõi trùng (hoặc STK đã học), tổng HĐ trong khoảng ngày = số tiền
  for g in
    with stkmst as materialized (select * from kt_stk_mst()),
         c as materialized (select x.id, x.so_tien, x.ngay_tt, kt_ten_loi(x.thu_huong_ten) loi, regexp_replace(coalesce(x.thu_huong_stk, ''), '\D', '', 'g') stk from kt_chi x
                where not x.da_xoa and x.trang_thai = 'da_tt' and not coalesce(x.ca_nhan, false) and x.ngay_tt >= '2026-01-01'
                  and not exists (select 1 from kt_chi_hd d where d.chi_id = x.id)),
         h as materialized (select t.ma_ngoai, t.ngay, t.mst, t.tong, kt_ten_loi(t.nguoi_mua) loi from kt_thue_hd t
                where t.nguon like 'misabot:%' and t.ma_ngoai is not null and coalesce(t.mst, '') <> '' and not exists (select 1 from kt_chi_hd d where d.hd_ma = t.ma_ngoai))
    select c.id chi_id, h.mst, sum(h.tong) tong, count(*) so, array_agg(h.ma_ngoai) ds
      from c join h on h.ngay between c.ngay_tt - 30 and c.ngay_tt + 15 and h.tong <= c.so_tien + 1000
       and ((length(c.loi) >= 4 and c.loi = h.loi) or exists (select 1 from stkmst s where s.stk = c.stk and c.stk <> '' and s.mst = h.mst))
     group by c.id, c.so_tien, h.mst having count(*) between 2 and 12 and abs(sum(h.tong) - c.so_tien) <= 1000
  loop
    ng := ng + 1;
    if p_ghi then
      insert into kt_chi_hd (chi_id, hd_ma, so_hd, ky_hieu, ngay_hd, ncc, mst, tong, cach, diem, boi, ly_do)
        select g.chi_id, t.ma_ngoai, t.so_hd, t.ky_hieu, t.ngay, t.nguoi_mua, t.mst, t.tong, 'tu_dong', 1, 'Hệ thống',
               'trả gộp ' || g.so || ' HĐ cùng người bán · tổng khớp số tiền'
          from kt_thue_hd t where t.ma_ngoai = any(g.ds) on conflict do nothing;
      update kt_chi set co_hd_do = true, hd_do_nhan = true, ngay_nhan_hd = coalesce(ngay_nhan_hd, (select max(ngay) from kt_thue_hd where ma_ngoai = any(g.ds))),
             sua_boi = 'Hệ thống', sua_luc = now() where id = g.chi_id;
    end if;
  end loop;
  if p_ghi and n + ng > 0 then
    insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_chi', 'ghep_hd_vao', jsonb_build_object('so_phieu', n, 'tra_gop', ng));
  end if;
  return jsonb_build_object('tu_ghep', n, 'tra_gop', ng);
end $f$;
