-- DOANH THU THEO ĐÚNG KIOT (16/10/2026, anh: "phải đúng theo Kiot" + "chia làm doanh thu và doanh thu thuần"). Monsieur Claude
-- Kiot tính doanh thu gồm hoá đơn Hoàn thành (1) VÀ Đang xử lý (3 — đang giao hàng). App trước chỉ lấy Hoàn thành → T9 thiếu (số ở file local) (HD059764 Shidai).
-- Mọi hàm đọc hoá đơn Kiot: trang_thai = 1 → trang_thai in (1, 3). (Bản đang chạy 16/10 của từng hàm, chỉ đổi điều kiện này.)

-- kt_bc_ban_hang (1 chỗ)
CREATE OR REPLACE FUNCTION public.kt_bc_ban_hang(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'ban_hang');
  with hd as (select * from kt_kiot_hoa_don where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
  ct as (select hd.chi_nhanh, hd.nv_ban, d from hd cross join lateral jsonb_array_elements(hd.chi_tiet) d),
  th as (select * from kt_kiot_tra_hang where coalesce(trang_thai,1) = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
  -- 13/10/2026: giá vốn hàng trả = tiền trả × (giá vốn / tổng) của hoá đơn gốc (không tìm thấy → tỷ lệ chung của kỳ) — để lãi gộp không bị âm giả
  -- khi khách trả hàng của đơn tháng trước (vd NPP trả Shidai tháng 10 hàng bán tháng 4–6)
  tg as (select th.chi_nhanh, th.tong_tra * coalesce(h.gia_von / nullif(h.tong, 0), (select sum(gia_von) / nullif(sum(tong), 0) from hd), 0) gvt
           from th left join kt_kiot_hoa_don h on h.id = th.hoa_don_id)
  select jsonb_build_object(
    'doanh_thu', (select coalesce(sum(tong),0) from hd), 'so_hd', (select count(*) from hd), 'gia_von', (select coalesce(sum(gia_von),0) from hd),
    'tra_hang', (select coalesce(sum(tong_tra),0) from th), 'so_tra', (select count(*) from th), 'gv_tra', (select coalesce(round(sum(gvt)),0) from tg),
    'da_thu_hd', (select coalesce(sum(da_tra),0) from hd),
    'theo_cn', (select coalesce(jsonb_agg(jsonb_build_object('cn', chi_nhanh, 'dt', dt, 'gv', gv, 'so', n, 'tra', coalesce((select sum(tong_tra) from th where th.chi_nhanh = x.chi_nhanh),0), 'gv_tra', coalesce((select round(sum(gvt)) from tg where tg.chi_nhanh = x.chi_nhanh),0)) order by dt desc), '[]')
       from (select chi_nhanh, sum(tong) dt, sum(gia_von) gv, count(*) n from hd group by 1) x),
    'theo_ngay', (select coalesce(jsonb_agg(jsonb_build_object('ngay', ng, 'cn', chi_nhanh, 'dt', dt) order by ng), '[]')
       from (select (ngay at time zone 'Asia/Ho_Chi_Minh')::date ng, chi_nhanh, sum(tong) dt from hd group by 1, 2) x),
    'top_sp', (select coalesce(jsonb_agg(x order by x->>'dt' desc), '[]') from (select jsonb_build_object('ma', d->>'ma', 'ten', max(d->>'ten'), 'nhom', max(d->>'nhom'),
         'sl', sum((d->>'sl')::numeric), 'dt', sum((d->>'tien')::numeric)) x from ct group by d->>'ma' order by sum((d->>'tien')::numeric) desc limit 30) y),
    'theo_nhom', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'dt', dt, 'sl', sl) order by dt desc), '[]')
       from (select coalesce(d->>'nhom','(không nhóm)') nhom, sum((d->>'tien')::numeric) dt, sum((d->>'sl')::numeric) sl from ct group by 1) x),
    'theo_nv', (select coalesce(jsonb_agg(jsonb_build_object('nv', nv_ban, 'dt', dt, 'so', n) order by dt desc), '[]')
       from (select coalesce(nv_ban,'(không rõ)') nv_ban, sum(tong) dt, count(*) n from hd group by 1) x),
    -- Phương thức thanh toán: phiếu thu khách trên sổ quỹ Kiot (tiền khách trả + cọc) trong kỳ
    'thanh_toan', (select coalesce(jsonb_agg(jsonb_build_object('pt', pt, 'tien', s, 'so', n) order by s desc), '[]')
       from (select coalesce(phuong_thuc,'Khác') pt, sum(so_tien) s, count(*) n from kt_kiot_so_quy
              where la_thu and trang_thai = '0' and nhom in ('Tiền khách trả','Thu tiền đặt cọc')
                and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1) x),
    'hoa_don', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', ngay, 'cn', chi_nhanh, 'khach', khach_ten, 'nv', nv_ban, 'tong', tong, 'da_tra', da_tra, 'gv', gia_von,
         'so_mat_hang', jsonb_array_length(chi_tiet)) order by ngay desc), '[]') from (select * from hd order by ngay desc limit 300) z)
  ) into r;
  return r;
end $function$
;

-- kt_bc_hang (1 chỗ)
CREATE OR REPLACE FUNCTION public.kt_bc_hang(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'hang_hoa');
  with ban as (select d->>'ma' ma, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1),
  nhap as (select d->>'ma' ma, sum((d->>'sl')::numeric) sl, sum((d->>'sl')::numeric * (d->>'gia')::numeric) gt from kt_kiot_nhap_hang h cross join lateral jsonb_array_elements(h.chi_tiet) d
                where coalesce(h.trang_thai,3) <> 4 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1),
  ton_cn as (select t->>'cn' cn, sum((t->>'ton')::numeric) sl, sum((t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric,0)) gt
               from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and (t->>'ton')::numeric > 0 group by 1)
  select jsonb_build_object(
    'so_mat_hang', (select count(*) from kt_kiot_hang where hoat_dong and dv_goc_id is null),
    'mat_hang_con', (select count(*) from kt_kiot_hang where tong_ton > 0 and dv_goc_id is null),
    'gia_tri_ton', (select coalesce(sum(gt),0) from ton_cn), 'sl_ton', (select coalesce(sum(sl),0) from ton_cn),
    'ton_am', (select count(*) from kt_kiot_hang where tong_ton < 0 and dv_goc_id is null),
    'ton_cn', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'sl', sl, 'gt', gt) order by gt desc), '[]') from ton_cn),
    'ton_nhom', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'sl', sl, 'gt', gt) order by gt desc), '[]')
       from (select coalesce(nhom,'(không nhóm)') nhom, sum(greatest(tong_ton,0)) sl, sum(greatest(gia_tri_ton,0)) gt from kt_kiot_hang where dv_goc_id is null group by 1 having sum(greatest(gia_tri_ton,0)) > 0) x),
    'nhap_ky', (select coalesce(sum(gt),0) from nhap), 'ban_ky', (select coalesce(sum(dt),0) from ban),
    'ban_chay', (select coalesce(jsonb_agg(x order by (x->>'sl')::numeric desc), '[]') from (select jsonb_build_object('ma', b.ma, 'ten', p.ten, 'nhom', p.nhom, 'sl', b.sl, 'dt', b.dt,
         'ton', p.tong_ton, 'nhap', coalesce(n.sl,0)) x from ban b left join kt_kiot_hang p on p.ma = b.ma left join nhap n on n.ma = b.ma order by b.sl desc limit 40) y),
    -- Bán chậm: còn tồn, giá trị tồn lớn, KHÔNG bán được cái nào trong kỳ
    'ban_cham', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'ton', tong_ton, 'gt', gia_tri_ton) order by gia_tri_ton desc), '[]')
       from (select * from kt_kiot_hang p where tong_ton > 0 and hoat_dong and p.dv_goc_id is null and not exists (select 1 from ban b where b.ma = p.ma) order by gia_tri_ton desc limit 40) x)
  ) into r;
  return r;
end $function$
;

-- kt_bc_khach (1 chỗ)
CREATE OR REPLACE FUNCTION public.kt_bc_khach(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'khach_hang');
  with hd as (select * from kt_kiot_hoa_don where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
  mua as (select khach_id, max(khach_ten) ten, max(khach_ma) ma, sum(tong) dt, count(*) n from hd where khach_id is not null group by 1)
  select jsonb_build_object(
    'tong_khach', (select count(*) from kt_kiot_khach),
    'khach_mua', (select count(*) from mua),
    'khach_moi', (select count(*) from kt_kiot_khach where (tao_kiot at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
    'khach_moi_mua', (select count(*) from mua join kt_kiot_khach k on k.id = mua.khach_id where (k.tao_kiot at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
    'khach_le_dt', (select coalesce(sum(tong),0) from hd where khach_id is null),
    'no_phai_thu', (select coalesce(sum(cong_no),0) from kt_kiot_khach where cong_no > 0),
    'so_khach_no', (select count(*) from kt_kiot_khach where cong_no > 0),
    'tra_truoc', (select coalesce(-sum(cong_no),0) from kt_kiot_khach where cong_no < 0),
    'so_tra_truoc', (select count(*) from kt_kiot_khach where cong_no < 0),
    'top_mua', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'dt', dt, 'so', n,
        'no', (select cong_no from kt_kiot_khach k where k.id = mua.khach_id)) order by dt desc), '[]') from (select * from mua order by dt desc limit 50) mua),
    'top_no', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'sdt', sdt, 'no', cong_no, 'tong_mua', tong_mua) order by cong_no desc), '[]')
        from (select * from kt_kiot_khach where cong_no > 0 order by cong_no desc limit 100) x)
  ) into r;
  return r;
end $function$
;

-- kt_bc_pl (1 chỗ)
CREATE OR REPLACE FUNCTION public.kt_bc_pl(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'pl');
  select jsonb_build_object(
    'thu', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai, 'tien', s)), '[]') from (
        select to_char(t.ngay, 'YYYY-MM') th, l.ten loai, sum(t.so_tien) s from kt_thu t join kt_loai l on l.id = t.loai_id
         where not t.da_xoa and t.trang_thai = 'da_duyet' and t.ngay between p_tu and p_den group by 1, 2) x),
    'chi', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai, 'nhom_bc', nhom_bc, 'tien', s)), '[]') from (
        -- 14/10/2026: phiếu có phân bổ nhiều tháng (kt_chi.phan_bo_thang) → ghi nhận chi phí theo từng tháng phân bổ; còn lại theo ngày thanh toán
        select coalesce(pt->>'thang', to_char(c.ngay_tt, 'YYYY-MM')) th, l.ten loai, l.nhom_bc, sum(coalesce((pt->>'so_tien')::numeric, c.so_tien)) s
          from kt_chi c join kt_loai l on l.id = c.loai_id
          left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' then c.phan_bo_thang end) pt on true
         where not c.da_xoa and c.trang_thai = 'da_tt'
           and (case when pt is null then c.ngay_tt between p_tu and p_den else pt->>'thang' between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM') end)
         group by 1, 2, 3) x),
    'lai_vay', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'lai', s)), '[]') from (
        select to_char(ngay, 'YYYY-MM') th, sum(lai) s from kt_vay_tra where not da_xoa and da_tra and ngay between p_tu and p_den group by 1) x),
    'kiot', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'dt', dt, 'gv', gv)), '[]') from (
        select to_char((ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, sum(tong) dt, sum(gia_von) gv from kt_kiot_hoa_don
         where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1) x),
    'kiot_tra', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'tra', s)), '[]') from (
        select to_char((ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, sum(tong_tra) s from kt_kiot_tra_hang
         where coalesce(trang_thai,1) = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1) x)
  ) into r;
  return r;
end $function$
;

-- kt_bc_pl2 (1 chỗ)
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
          from kt_kiot_hoa_don where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
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

-- kt_bc_qt (6 chỗ)
CREATE OR REPLACE FUNCTION public.kt_bc_qt(p_phien text, p_loai text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; r jsonb;
begin
  perform kt_chan(p_phien, 'pl');
  if p_loai = 'don' then
    -- đơn đặt tạo trong kỳ: chia nhóm như Tổng quan (kt_tq_don) · hoá đơn hoàn thành trong kỳ (có / không qua đơn đặt)
    return jsonb_build_object(
      'don', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select to_char((o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, o.chi_nhanh cn, coalesce(kn.ten, 'Không ghi kênh') kenh,
               case when o.trang_thai = 4 then 'huy' when o.trang_thai = 3 then 'di_hang' when o.da_tra > 0 or coalesce(k.cong_no, 0) < 0 then 'coc' else 'bao_gia' end nhom,
               count(*) so, sum(o.tong) tong,
               sum(case when o.trang_thai not in (3, 4) then least(o.tong, greatest(o.da_tra, case when coalesce(k.cong_no, 0) < 0 then -k.cong_no else 0 end)) else 0 end) coc
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id left join kt_kiot_kenh kn on kn.id = o.kenh_id
         where (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2, 3, 4) x),
      'hd', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, h.chi_nhanh cn, h.dat_hang_id is not null qua_don, count(*) so, sum(h.tong) tong
          from kt_kiot_hoa_don h where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2, 3) x),
      -- đơn đã cọc chưa đi hàng (mọi thời điểm) — doanh số chờ ghi nhận
      'cho', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select o.chi_nhanh cn, to_char((o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, count(*) so, sum(o.tong) tong, sum(o.da_tra) da_tra
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id
         where o.trang_thai not in (3, 4) and (o.da_tra > 0 or coalesce(k.cong_no, 0) < 0) group by 1, 2) x));
  elsif p_loai = 'du_kien' then
    return jsonb_build_object('nay', v_nay,
      'so_du', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'ten', t.ten, 'loai', t.loai, 'so_du', kt_so_du_ngay(t.id, v_nay))), '[]')
                  from kt_tai_khoan t where t.hoat_dong and t.loai <> 'vay' and t.ngay_ton_dau <= v_nay),
      'chi_cho', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'noi_dung', c.noi_dung, 'so_tien', c.so_tien, 'han', c.han_tt, 'trang_thai', c.trang_thai,
                    'ngay', c.ngay_de_nghi) order by coalesce(c.han_tt, c.ngay_de_nghi)), '[]')
                  from kt_chi c where not c.da_xoa and c.trang_thai in ('cho_duyet', 'cho_gd', 'cho_tt')),
      'vay_tra', (select coalesce(jsonb_agg(jsonb_build_object('ngay', t.ngay, 'goc', t.goc, 'lai', t.lai, 'ten', v.ten) order by t.ngay), '[]')
                  from kt_vay_tra t join kt_vay v on v.id = t.vay_id where not t.da_xoa and not v.da_xoa and not t.da_tra),
      'no_kh', (select coalesce(sum(cong_no), 0) from kt_kiot_khach where cong_no > 0),
      'no_ncc', (select coalesce(sum(cong_no), 0) from kt_kiot_ncc where cong_no <> 0),
      'don_coc', (select coalesce(sum(o.tong - least(o.tong, o.da_tra)), 0) from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id
                   where o.trang_thai not in (3, 4) and (o.da_tra > 0 or coalesce(k.cong_no, 0) < 0)),
      -- bình quân 8 tuần gần nhất (để ước tính tuần tới)
      'thu_tuan', (select coalesce(sum(so_tien), 0) / 8 from kt_thu where not da_xoa and trang_thai = 'da_duyet' and ngay > v_nay - 56 and ngay <= v_nay),
      'chi_tuan', (select coalesce(sum(so_tien), 0) / 8 from kt_chi where not da_xoa and trang_thai = 'da_tt' and ngay_tt > v_nay - 56 and ngay_tt <= v_nay));
  elsif p_loai = 'ngan_sach' then
    return jsonb_build_object(
      'loai', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'nhom_bc', nhom_bc) order by ten), '[]') from kt_loai where nhom = 'chi' and hoat_dong),
      'ns', (select coalesce(jsonb_agg(jsonb_build_object('thang', thang, 'loai_id', loai_id, 'so_tien', so_tien)), '[]') from kt_ngan_sach
               where thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM')),
      'thuc', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai_id', lid, 'tien', s)), '[]') from (
          select coalesce(pt->>'thang', to_char(c.ngay_tt, 'YYYY-MM')) th, c.loai_id lid, sum(coalesce((pt->>'so_tien')::numeric, c.so_tien)) s
            from kt_chi c left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' then c.phan_bo_thang end) pt on true
           where not c.da_xoa and c.trang_thai = 'da_tt'
             and (case when pt is null then c.ngay_tt between p_tu and p_den else pt->>'thang' between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM') end)
           group by 1, 2) x));
  elsif p_loai = 'ton' then
    with ban as (select d->>'ma' ma, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1),
         ban90 as (select distinct d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date > v_nay - 90),
         hg as (select p.ma, p.ten, kt_nhom_cha(coalesce(p.nhom, '(không nhóm)')) nhom, greatest(p.tong_ton, 0) ton, greatest(p.gia_tri_ton, 0) gt,
                       (select max((t->>'gia_von')::numeric) from jsonb_array_elements(p.ton) t where (t->>'gia_von')::numeric > 0) gv from kt_kiot_hang p where p.dv_goc_id is null)
    select jsonb_build_object('so_ngay', least(p_den, v_nay) - p_tu + 1,
      'gv_ky', (select coalesce(sum(gia_von), 0) from kt_kiot_hoa_don where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
      'ton_cn', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'sl', sl, 'gt', gt, 'so_ma', n) order by gt desc), '[]') from (
          select t->>'cn' cn, sum((t->>'ton')::numeric) sl, sum((t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0)) gt, count(*) n
            from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and (t->>'ton')::numeric > 0 group by 1) x),
      'nhom', (select coalesce(jsonb_agg(to_jsonb(x) order by x.gt desc), '[]') from (
          select hg.nhom, sum(hg.gt) gt, sum(hg.ton) ton, count(*) filter (where hg.ton > 0) so_ma, coalesce(sum(b.dt), 0) dt, coalesce(sum(b.sl * coalesce(hg.gv, 0)), 0) gv_ban,
                 sum(hg.gt) filter (where hg.ton > 0 and not exists (select 1 from ban90 z where z.ma = hg.ma)) gt_cham
            from hg left join ban b on b.ma = hg.ma group by 1 having sum(hg.gt) > 0 or coalesce(sum(b.dt), 0) > 0) x),
      'cham', (select coalesce(jsonb_agg(to_jsonb(x) order by x.gt desc), '[]') from (
          select hg.ma, hg.ten, hg.nhom, hg.ton, hg.gt from hg where hg.ton > 0 and not exists (select 1 from ban90 z where z.ma = hg.ma) order by hg.gt desc limit 50) x),
      'cham_tong', (select jsonb_build_object('so_ma', count(*), 'gt', coalesce(sum(gt), 0)) from hg where hg.ton > 0 and not exists (select 1 from ban90 z where z.ma = hg.ma)))
      into r;
    return r;
  elsif p_loai = 'vay' then
    return jsonb_build_object(
      'vay', (select coalesce(jsonb_agg(jsonb_build_object('ten', v.ten, 'ben', v.ben_cho_vay, 'so_tien', v.so_tien, 'lai_suat', v.lai_suat, 'dao_han', v.ngay_dao_han, 'xong', v.da_tat_toan, 'nhan', coalesce((select sum(n.so_tien) from kt_vay_nhan n where n.vay_id = v.id and not n.da_xoa), 0),
                'goc_tra', coalesce((select sum(goc) from kt_vay_tra t where t.vay_id = v.id and not t.da_xoa and t.da_tra), 0))), '[]') from kt_vay v where not v.da_xoa),
      'lai', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'goc', g, 'lai', l)), '[]') from (
          select to_char(ngay, 'YYYY-MM') th, sum(goc) g, sum(lai) l from kt_vay_tra where not da_xoa and da_tra and ngay between p_tu and p_den group by 1) x),
      'chi_tc', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', l, 'tien', s)), '[]') from (
          select to_char(c.ngay_tt, 'YYYY-MM') th, lo.ten l, sum(c.so_tien) s from kt_chi c join kt_loai lo on lo.id = c.loai_id
           where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between p_tu and p_den and (lo.nhom_bc = 'Chi tài chính' or lo.ten ~* '^FINANCE') group by 1, 2) x));
  elsif p_loai = 'cs' then
    return jsonb_build_object(
      'dt', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'dt', dt, 'gv', gv, 'so', so)), '[]') from (
          select to_char((ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, chi_nhanh cn, sum(tong) dt, sum(gia_von) gv, count(*) so from kt_kiot_hoa_don
           where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
      -- giá vốn hàng trả = tiền trả × (giá vốn / tổng) của hoá đơn gốc — như P&L (kt_bc_pl2)
      'tra', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'tra', s, 'gv', gv)), '[]') from (
          select to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, t.chi_nhanh cn, sum(t.tong_tra) s, round(sum(t.tong_tra * coalesce(h.gia_von / nullif(h.tong, 0), 0))) gv
            from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
           where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
      -- chi phí đã trả, chia theo đơn vị chịu chi phí (phan_bo) — tháng theo phân bổ tháng nếu có
      'cp', (select coalesce(jsonb_agg(jsonb_build_object('dv', dv, 'tien', s, 'nhom_bc', nb)), '[]') from (
          select (pb->>'don_vi_id')::int dv, lo.nhom_bc nb, sum((pb->>'so_tien')::numeric * coalesce((pt->>'so_tien')::numeric / nullif(c.so_tien, 0), 1)) s
            from kt_chi c join kt_loai lo on lo.id = c.loai_id cross join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' then c.phan_bo else '[]' end) pb
            left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' then c.phan_bo_thang end) pt on true
           where not c.da_xoa and c.trang_thai = 'da_tt'
             and (case when pt is null then c.ngay_tt between p_tu and p_den else pt->>'thang' between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM') end)
           group by 1, 2) x),
      'cp_khong_pb', (select coalesce(sum(c.so_tien), 0) from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between p_tu and p_den
                       and (jsonb_typeof(c.phan_bo) <> 'array' or jsonb_array_length(c.phan_bo) = 0)),
      'kenh', (select coalesce(jsonb_agg(jsonb_build_object('kenh', ten, 'cn', cn, 'dt', dt, 'so', so)), '[]') from (
          select coalesce(k.ten, 'Không ghi kênh (bán tại quầy)') ten, h.chi_nhanh cn, sum(h.tong) dt, count(*) so
            from kt_kiot_hoa_don h left join kt_kiot_kenh k on k.id = h.kenh_id
           where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x));
  end if;
  raise exception 'Loại báo cáo không hợp lệ';
end $function$
;

-- kt_bc_thue (1 chỗ)
CREATE OR REPLACE FUNCTION public.kt_bc_thue(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  return jsonb_build_object(
    -- tồn kho sổ thuế: mỗi hộ × kỳ → tổng
    'xnt', (select coalesce(jsonb_agg(x order by x->>'hkd', x->>'ky'), '[]') from (
       select jsonb_build_object('hkd', hkd, 'ky', ky, 'so_ma', count(*), 'dau_sl', sum(dau_sl), 'dau_tien', sum(dau_tien), 'nhap_sl', sum(nhap_sl), 'nhap_tien', sum(nhap_tien),
         'xuat_sl', sum(xuat_sl), 'xuat_tien', sum(xuat_tien), 'cuoi_sl', sum(cuoi_sl), 'cuoi_tien', sum(cuoi_tien), 'keo_luc', max(keo_luc)) x
       from kt_thue_xnt group by hkd, ky) t),
    -- hoá đơn theo tháng × hộ × chiều (bỏ dòng ngày gõ sai)
    'hd', (select coalesce(jsonb_agg(jsonb_build_object('hkd', hkd, 'chieu', chieu, 'thang', th, 'so_hd', so_hd, 'thanh_tien', tt, 'tien_thue', thue, 'tong', tong) order by th, hkd), '[]') from (
       select hkd, chieu, to_char(ngay, 'YYYY-MM') th, count(distinct coalesce(ky_hieu,'') || '|' || coalesce(so_hd,'')) so_hd,
              sum(thanh_tien) tt, sum(tien_thue) thue, sum(coalesce(tong, thanh_tien + coalesce(tien_thue,0))) tong
         from kt_thue_hd where ngay between p_tu and p_den and ngay between date '2025-01-01' and hom + 1 group by 1, 2, 3) t),
    -- doanh thu Kiot cùng cửa hàng (để so tỷ lệ xuất hoá đơn)
    'kiot', (select coalesce(jsonb_agg(jsonb_build_object('chi_nhanh', chi_nhanh, 'thang', th, 'doanh_thu', dt) order by th), '[]') from (
       select chi_nhanh, to_char((ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, sum(tong) dt from kt_kiot_hoa_don
        where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) t),
    'ngay_sai', (select count(*) from kt_thue_hd where ngay is null or ngay not between date '2025-01-01' and hom + 1),
    'keo_luc', (select max(keo_luc) from kt_thue_hd));
end $function$
;

-- kt_cong_no_dt (1 chỗ)
CREATE OR REPLACE FUNCTION public.kt_cong_no_dt(p_phien text, p_loai text DEFAULT 'kh'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; r jsonb; han int;
begin
  perform kt_chan(p_phien, case when p_loai = 'ncc' then 'ncc' else 'khach_hang' end);
  select coalesce(nullif(gia_tri, '')::int, 30) into han from kt_cai_dat where khoa = case when p_loai = 'ncc' then 'han_no_ncc_ngay' else 'han_no_kh_ngay' end;
  han := coalesce(han, 30);
  with dt as (
    select id, ma, ten, sdt, cong_no no, tong_mua tong from kt_kiot_khach where p_loai = 'kh' and cong_no <> 0
    union all select id, ma, ten, sdt, cong_no, tong_nhap from kt_kiot_ncc where p_loai = 'ncc' and cong_no <> 0),
  ct as (   -- hoá đơn bán (khách) / phiếu nhập (NCC) đã hoàn thành
    select khach_id dt_id, id, ngay, chi_nhanh, tong, nv_ban nv from kt_kiot_hoa_don where p_loai = 'kh' and trang_thai in (1, 3) and tong > 0
    union all select ncc_id, id, ngay, chi_nhanh, tong, null from kt_kiot_nhap_hang where p_loai = 'ncc' and trang_thai = 3 and tong > 0),
  lk as (select ct.*, d.no, sum(ct.tong) over (partition by ct.dt_id order by ct.ngay desc, ct.id desc) cum
           from ct join dt d on d.id = ct.dt_id where d.no > 0),
  pb as (select dt_id, chi_nhanh, (ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, tong, least(tong, no - (cum - tong)) phan from lk where cum - tong < no),
  g as (select dt_id, sum(phan) da_gan, sum(tong) tong_ct, min(ngay) cu_nhat, count(*) so_ct, (array_agg(chi_nhanh order by ngay desc))[1] cn,
          sum(phan) filter (where hom - ngay <= 30) b1, sum(phan) filter (where hom - ngay between 31 and 60) b2,
          sum(phan) filter (where hom - ngay between 61 and 90) b3, sum(phan) filter (where hom - ngay > 90) b4
          from pb group by 1),
  cn_cuoi as (select distinct on (dt_id) dt_id, chi_nhanh, nv from ct order by dt_id, ngay desc),
  -- người phụ trách (14/10/2026): gán tay (kt_cong_no_pt) > NV bán phiếu gần nhất quy về tên trong Nhân sự (tên hoặc tên trên Kiot) > tên Kiot thô
  ns as (select id, ten, bo_phan_id, array(select lower(btrim(x)) from unnest(ten_kiot || ten) x) ten_kt from kt_nhan_su)
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'ma', d.ma, 'ten', d.ten, 'sdt', d.sdt, 'no', d.no, 'tong', d.tong,
      'cn', coalesce(g.cn, c.chi_nhanh), 'so_ct', coalesce(g.so_ct, 0), 'cu_nhat', g.cu_nhat, 'tuoi', hom - g.cu_nhat,
      'b1', coalesce(g.b1, 0), 'b2', coalesce(g.b2, 0), 'b3', coalesce(g.b3, 0), 'b4', coalesce(g.b4, 0),
      'truoc_2026', greatest(d.no - coalesce(g.da_gan, 0), 0), 'nv', coalesce(ng.ten, nk.ten, c.nv), 'nv_id', coalesce(ng.id, nk.id), 'nv_gan', pt.nhan_su_id is not null, 'nv_kiot', c.nv, 'han', han,
      -- tổng các chứng từ đang tính nợ (+ phần nợ trước 2026) · đã thanh toán = tổng − còn nợ · đến hạn = chứng từ nợ cũ nhất + số ngày được nợ
      'tong_ct', coalesce(g.tong_ct, 0) + greatest(d.no - coalesce(g.da_gan, 0), 0), 'den_han', g.cu_nhat + han,
      'qua_han', case when d.no > 0 and g.cu_nhat is not null then greatest(hom - (g.cu_nhat + han), 0) end) order by d.no desc), '[]') into r
    from dt d left join g on g.dt_id = d.id left join cn_cuoi c on c.dt_id = d.id
    left join kt_cong_no_pt pt on pt.loai = p_loai and pt.dt_id = d.id left join ns ng on ng.id = pt.nhan_su_id
    left join lateral (select n.id, n.ten from ns n where c.nv is not null and lower(btrim(c.nv)) = any(n.ten_kt) limit 1) nk on true;
  return r;
end $function$
;

-- kt_cong_no_dt_ct (1 chỗ)
CREATE OR REPLACE FUNCTION public.kt_cong_no_dt_ct(p_phien text, p_loai text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; d record; r jsonb;
begin
  perform kt_chan(p_phien, case when p_loai = 'ncc' then 'ncc' else 'khach_hang' end);
  if p_loai = 'ncc' then select id, ma, ten, sdt, cong_no no, tong_nhap tong, null::text loai into d from kt_kiot_ncc where id = p_id;
  else select id, ma, ten, sdt, cong_no no, tong_mua tong, loai::text loai into d from kt_kiot_khach where id = p_id; end if;
  if d.id is null then return null; end if;
  with ct as (
    select id, ma, ngay, chi_nhanh, tong, da_tra from kt_kiot_hoa_don where p_loai <> 'ncc' and khach_id = p_id and trang_thai in (1, 3)
    union all select id, ma, ngay, chi_nhanh, tong, da_tra from kt_kiot_nhap_hang where p_loai = 'ncc' and ncc_id = p_id and trang_thai = 3),
  lk as (select ct.*, sum(tong) over (order by ngay desc, id desc) cum from ct where tong > 0)
  select jsonb_build_object(
    'dt', jsonb_build_object('id', d.id, 'ma', d.ma, 'ten', d.ten, 'sdt', d.sdt, 'no', d.no, 'tong', d.tong, 'loai', d.loai),
    'dang_no', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'tong', tong,
        'con_no', least(tong, d.no - (cum - tong)), 'tuoi', hom - (ngay at time zone 'Asia/Ho_Chi_Minh')::date) order by ngay desc), '[]')
        from lk where d.no > 0 and cum - tong < d.no),
    'gan_day', (select coalesce(jsonb_agg(x order by x->>'ngay' desc), '[]') from (select jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date,
        'cn', chi_nhanh, 'tong', tong, 'da_tra', da_tra) x from ct order by ngay desc limit 15) t),
    'tra_tien', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'so_tien', so_tien,
        'pt', phuong_thuc, 'nd', noi_dung) order by ngay desc), '[]') from (select * from kt_kiot_so_quy
        where la_thu = (p_loai <> 'ncc') and trang_thai = '0' and lower(trim(doi_tac)) = lower(trim(d.ten)) order by ngay desc limit 15) q)) into r;
  return r;
end $function$
;

-- kt_drill (6 chỗ)
CREATE OR REPLACE FUNCTION public.kt_drill(p_phien text, p_loai text, p_khoa text, p_tu date, p_den date, p_cn text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  -- quyền theo trang tương ứng: chi phí → Chi · khách / hoá đơn → Khách hàng · tồn → Hàng hoá · nhóm / mặt hàng → Bán hàng
  perform kt_chan(p_phien, case p_loai when 'cp' then 'chi' when 'kh' then 'khach_hang' when 'hd' then 'khach_hang' when 'ton_lau' then 'hang_hoa' else 'ban_hang' end);
  if p_loai = 'nhom' then
    with ct as (select h.chi_nhanh, d from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                 where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
                   and coalesce(d->>'nhom', '(không nhóm)') = p_khoa and (p_cn is null or h.chi_nhanh = p_cn))
    select coalesce(jsonb_agg(jsonb_build_object('ma', g.ma, 'ten', g.ten, 'sl', g.sl, 'dt', g.dt, 'ton', (select tong_ton from kt_kiot_hang p where p.ma = g.ma limit 1)) order by g.dt desc), '[]') into r
      from (select ct.d->>'ma' ma, max(ct.d->>'ten') ten, sum((ct.d->>'sl')::numeric) sl, sum((ct.d->>'tien')::numeric) dt from ct group by 1 order by 4 desc limit 200) g;
  elsif p_loai = 'sp' then
    select jsonb_build_object(
      'sp', (select jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'dvt', don_vi, 'gia_ban', gia_ban, 'tong_ton', tong_ton, 'gia_tri_ton', gia_tri_ton, 'ton', ton) from kt_kiot_hang where ma = p_khoa limit 1),
      'ban_cs', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'sl', sl, 'dt', dt) order by dt desc), '[]') from (
          select h.chi_nhanh cn, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
           where h.trang_thai in (1, 3) and d->>'ma' = p_khoa and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1) x),
      'hd', (select coalesce(jsonb_agg(x order by x->>'ngay' desc), '[]') from (
          select jsonb_build_object('ma', h.ma, 'ngay', (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', h.chi_nhanh, 'khach', h.khach_ten, 'sl', (d->>'sl')::numeric, 'tien', (d->>'tien')::numeric) x
            from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d where h.trang_thai in (1, 3) and d->>'ma' = p_khoa order by h.ngay desc limit 15) t)) into r;
  elsif p_loai = 'kh' then
    select jsonb_build_object(
      'kh', (select jsonb_build_object('id', id, 'ma', ma, 'ten', ten, 'sdt', sdt, 'cong_no', cong_no, 'tong_mua', tong_mua) from kt_kiot_khach where id = p_khoa::bigint),
      'hd', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'tong', tong, 'da_tra', da_tra, 'nv', nv_ban,
          'so_mh', jsonb_array_length(chi_tiet)) order by ngay desc), '[]') from kt_kiot_hoa_don
         where khach_id = p_khoa::bigint and trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den)) into r;
  elsif p_loai = 'hd' then
    select jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'khach', khach_ten, 'khach_id', khach_id, 'nv', nv_ban,
      'tong', tong, 'da_tra', da_tra, 'gia_von', gia_von, 'trang_thai', trang_thai_ten, 'dong', chi_tiet) into r from kt_kiot_hoa_don where ma = p_khoa limit 1;
  elsif p_loai = 'ton_lau' then
    with ban as (select distinct d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai in (1, 3) and h.chi_nhanh = p_cn and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_den - 180 and p_den),
    ton as (select p.ma, p.ten, p.nhom, (t->>'ton')::numeric sl, (t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0) gt
              from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and t->>'cn' = p_cn and (t->>'ton')::numeric > 0)
    select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'sl', sl, 'gt', gt,
        'ban_cuoi', (select max((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date) from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                      where h.trang_thai in (1, 3) and h.chi_nhanh = p_cn and d->>'ma' = ton.ma)) order by gt desc), '[]') into r
      from (select * from ton where ma not in (select ma from ban where ma is not null) order by gt desc limit 100) ton;
  elsif p_loai = 'cp' then
    select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ngay', c.ngay_tt, 'nd', c.noi_dung, 'th', c.thu_huong_ten, 'loai', l.ten, 'tien', coalesce(pb.tien, c.so_tien), 'dv', dv.ten)
        order by coalesce(pb.tien, c.so_tien) desc), '[]') into r
      from kt_chi c join kt_loai l on l.id = c.loai_id
      left join lateral (select (p->>'don_vi_id')::int dv_id, (p->>'so_tien')::numeric tien from jsonb_array_elements(coalesce(c.phan_bo, '[]'::jsonb)) p) pb on true
      left join kt_don_vi dv on dv.id = pb.dv_id
     where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between p_tu and p_den and l.nhom_bc = 'Chi vận hành & quản lí'
       and (coalesce(p_khoa, '') = '' or l.ten = p_khoa)
       and (p_cn is null or (p_cn = '_chung' and coalesce(array_length(dv.kiot_chi_nhanh, 1), 0) = 0) or p_cn = any(dv.kiot_chi_nhanh));
  end if;
  return coalesce(r, 'null'::jsonb);
end $function$
;

-- kt_ds_nhan_su (1 chỗ)
CREATE OR REPLACE FUNCTION public.kt_ds_nhan_su(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien);
  return jsonb_build_object(
    'ns', (select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'ten', n.ten, 'bo_phan_id', n.bo_phan_id, 'ten_kiot', n.ten_kiot, 'dang_lam', n.dang_lam, 'ghi_chu', n.ghi_chu,
              'so_kh', (select count(*) from kt_cong_no_pt p where p.nhan_su_id = n.id and p.loai = 'kh'),
              'so_ncc', (select count(*) from kt_cong_no_pt p where p.nhan_su_id = n.id and p.loai = 'ncc')) order by n.ten), '[]') from kt_nhan_su n),
    'kiot', (select coalesce(jsonb_agg(jsonb_build_object('ten', nv, 'so_hd', so, 'cn', cn) order by so desc), '[]') from (
        select h.nv_ban nv, count(*) so, mode() within group (order by h.chi_nhanh) cn from kt_kiot_hoa_don h
         where h.ngay >= '2026-01-01' and h.trang_thai in (1, 3) and coalesce(btrim(h.nv_ban), '') <> ''
           and not exists (select 1 from kt_nhan_su n where lower(btrim(h.nv_ban)) = lower(n.ten) or lower(btrim(h.nv_ban)) = any(array(select lower(btrim(x)) from unnest(n.ten_kiot) x)))
         group by 1) x));
end $function$
;

-- kt_dt_thang_cs (1 chỗ)
CREATE OR REPLACE FUNCTION public.kt_dt_thang_cs(p_phien text, p_thang text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d1 date := (p_thang || '-01')::date; d2 date := ((p_thang || '-01')::date + interval '1 month')::date - 1;
begin
  perform kt_chan(p_phien, 'chi');
  return coalesce((select jsonb_object_agg(cn, dt) from (
    select h.chi_nhanh cn, sum(h.tong) - coalesce((select sum(t.tong_tra) from kt_kiot_tra_hang t where coalesce(t.trang_thai, 1) = 1 and t.chi_nhanh = h.chi_nhanh
             and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between d1 and d2), 0) dt
      from kt_kiot_hoa_don h where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between d1 and d2 group by 1) x), '{}');
end $function$
;

-- kt_pb_ds_tinh_lai (1 chỗ)
CREATE OR REPLACE FUNCTION public.kt_pb_ds_tinh_lai()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; v_pb jsonb; v_n int := 0; v_ids int[] := array[2, 3, 4];
  v_cn text[] := array['đồ thờ hiền thủy', 'đồ thờ chánh tâm', 'tổng kho sỉ shidai']; v_w numeric[]; v_tw numeric; v_con numeric; v_v numeric; v_cuoi int; i int;
begin
  for r in select c.id, c.so_tien, c.phan_bo->0->>'ds' thang from kt_chi c
            where not c.da_xoa and jsonb_typeof(c.phan_bo) = 'array' and c.phan_bo->0 ? 'ds'
              and c.phan_bo->0->>'ds' >= to_char((now() at time zone 'Asia/Ho_Chi_Minh')::date - interval '1 month', 'YYYY-MM')
              and not exists (select 1 from kt_khoa_ky k where k.thang = c.phan_bo->0->>'ds') loop
    v_w := array[0, 0, 0]::numeric[];
    for i in 1..3 loop
      select greatest(0, coalesce(sum(h.tong), 0) - coalesce((select sum(t.tong_tra) from kt_kiot_tra_hang t where coalesce(t.trang_thai, 1) = 1 and lower(t.chi_nhanh) = v_cn[i]
               and to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') = r.thang), 0))
        into v_v from kt_kiot_hoa_don h where h.trang_thai in (1, 3) and lower(h.chi_nhanh) = v_cn[i] and to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') = r.thang;
      v_w[i] := v_v;
    end loop;
    v_tw := v_w[1] + v_w[2] + v_w[3];
    if v_tw <= 0 then continue; end if;
    v_cuoi := case when v_w[3] > 0 then 3 when v_w[2] > 0 then 2 else 1 end;
    v_pb := '[]'; v_con := r.so_tien;
    for i in 1..3 loop
      if v_w[i] = 0 then continue; end if;
      v_v := case when i = v_cuoi then v_con else round(r.so_tien * v_w[i] / v_tw) end;
      v_con := v_con - v_v;
      v_pb := v_pb || jsonb_build_array(jsonb_build_object('don_vi_id', v_ids[i], 'so_tien', v_v, 'ds', r.thang));
    end loop;
    update kt_chi set phan_bo = v_pb where id = r.id and phan_bo is distinct from v_pb;
    if found then v_n := v_n + 1; end if;
  end loop;
  if v_n > 0 then insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_chi', 'pb_ds_tinh_lai', jsonb_build_object('so_phieu', v_n)); end if;
  return v_n;
end $function$
;

-- kt_tq_bo_sung (3 chỗ)
CREATE OR REPLACE FUNCTION public.kt_tq_bo_sung(p_phien text, p_tu date, p_den date, p_tu0 date, p_den0 date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'tong_quan');
  with hd as (select * from kt_kiot_hoa_don where trang_thai in (1, 3) and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
  hd0 as (select khach_id, sum(tong) dt from kt_kiot_hoa_don where trang_thai in (1, 3) and khach_id is not null
            and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu0 and p_den0 group by 1),
  kh as (select khach_id, max(khach_ma) ma, max(khach_ten) ten, sum(tong) dt, count(*) so, mode() within group (order by chi_nhanh) cn
           from hd where khach_id is not null group by 1 order by sum(tong) desc limit 5),
  ct as (select hd.chi_nhanh, d from hd cross join lateral jsonb_array_elements(hd.chi_tiet) d),
  sp as (select d->>'ma' ma, max(d->>'ten') ten, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt, mode() within group (order by chi_nhanh) cn
           from ct group by 1 order by sum((d->>'tien')::numeric) desc limit 5),
  ban180 as (select distinct h.chi_nhanh cn, d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
               where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_den - 180 and p_den),
  ton as (select t->>'cn' cn, p.ma, coalesce(p.nhom, '(không nhóm)') nhom, (t->>'ton')::numeric sl, (t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0) gt
            from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and (t->>'ton')::numeric > 0)
  select jsonb_build_object(
    'top_kh', (select coalesce(jsonb_agg(jsonb_build_object('id', kh.khach_id, 'ma', kh.ma, 'ten', kh.ten, 'dt', kh.dt, 'so', kh.so, 'cn', kh.cn, 'dt0', coalesce(hd0.dt, 0)) order by kh.dt desc), '[]')
                 from kh left join hd0 on hd0.khach_id = kh.khach_id),
    'top_sp', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'sl', sl, 'dt', dt, 'cn', cn) order by dt desc), '[]') from sp),
    -- 14/10 (kế toán): thêm 3 nhóm hàng tồn nhiều tiền nhất ở từng kho
    'ton_cs', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'gt', gt, 'so_ma', so_ma, 'lau_so', lau_so, 'lau_gt', lau_gt,
        'nhom_top', (select coalesce(jsonb_agg(jsonb_build_object('nhom', n.nhom, 'gt', n.gt) order by n.gt desc), '[]') from (select nhom, sum(gt) gt from ton t2 where t2.cn = x.cn group by 1 order by 2 desc limit 3) n)) order by gt desc), '[]') from (
                 select t.cn, sum(t.gt) gt, count(*) so_ma, count(*) filter (where b.ma is null) lau_so, coalesce(sum(t.gt) filter (where b.ma is null), 0) lau_gt
                   from ton t left join ban180 b on b.cn = t.cn and b.ma = t.ma group by 1) x)) into r;
  return r;
end $function$
;

-- kt_tq_don (2 chỗ)
CREATE OR REPLACE FUNCTION public.kt_tq_don(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'tong_quan');
  return jsonb_build_object(
    'kenh', (select coalesce(jsonb_agg(jsonb_build_object('ten', ten, 'cn', cn, 'dt', dt, 'so', so) order by dt desc), '[]') from (
        select coalesce(k.ten, 'Không ghi kênh (bán tại quầy)') ten, h.chi_nhanh cn, sum(h.tong) dt, count(*) so
          from kt_kiot_hoa_don h left join kt_kiot_kenh k on k.id = h.kenh_id
         where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    -- nhóm CHA: doanh thu dòng hàng quy về tổng hoá đơn (đã trừ giảm giá HĐ); giá vốn HĐ chia cho các dòng theo tỷ lệ (SL × giá vốn hiện tại)
    'nhom', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'cn', cn, 'dt', round(dt), 'gv', round(gv)) order by dt desc), '[]') from (
        select kt_nhom_cha(coalesce(d->>'nhom', '(không nhóm)')) nhom, h.chi_nhanh cn,
               sum((d->>'tien')::numeric * h.tong / nullif(t.tien, 0)) dt,
               sum(coalesce(h.gia_von, 0) * coalesce(c.gv / nullif(t.gv, 0), (d->>'tien')::numeric / nullif(t.tien, 0))) gv
          from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
          left join lateral (select (d->>'sl')::numeric * coalesce((select (e->>'gia_von')::numeric from kt_kiot_hang p, jsonb_array_elements(p.ton) e
                               where p.id = (d->>'sp')::bigint and e->>'cn' = h.chi_nhanh limit 1), 0) gv) c on true
          cross join lateral (select sum((x->>'tien')::numeric) tien,
                 sum((x->>'sl')::numeric * coalesce((select (e->>'gia_von')::numeric from kt_kiot_hang p, jsonb_array_elements(p.ton) e
                               where p.id = (x->>'sp')::bigint and e->>'cn' = h.chi_nhanh limit 1), 0)) gv from jsonb_array_elements(h.chi_tiet) x) t
         where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    -- đơn đặt hàng tạo trong kỳ: đã đi hàng (Hoàn thành) / đã cọc chưa đi hàng / báo giá (không dấu vết tiền) / huỷ
    'don_ky', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'cn', cn, 'so', so, 'tong', tong, 'coc', coc)), '[]') from (
        select case when o.trang_thai = 4 then 'huy' when o.trang_thai = 3 then 'di_hang'
                    when o.da_tra > 0 or coalesce(k.cong_no, 0) < 0 then 'coc' else 'bao_gia' end nhom, o.chi_nhanh cn,
               count(*) so, sum(o.tong) tong, sum(case when o.trang_thai not in (3, 4) then least(o.tong, greatest(o.da_tra, case when coalesce(k.cong_no, 0) < 0 then -k.cong_no else 0 end)) else 0 end) coc
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id
         where (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    -- TẤT CẢ đơn đã cọc chưa đi hàng (không theo kỳ) — doanh thu dự kiến
    'coc_cho', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'ma', o.ma, 'ngay', (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', o.chi_nhanh,
                 'khach', o.khach_ten, 'nv', o.nv_ban, 'tong', o.tong, 'da_tra', o.da_tra, 'tra_truoc', case when coalesce(k.cong_no, 0) < 0 then -k.cong_no else 0 end,
                 'ghi_chu', o.ghi_chu) order by o.ngay desc), '[]')
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id
         where o.trang_thai not in (3, 4) and (o.da_tra > 0 or coalesce(k.cong_no, 0) < 0)));
end $function$
;

