-- TỔNG QUAN theo giao diện mẫu kế toán (13/10/2026) — số liệu bổ sung mà các hàm báo cáo cũ chưa có. Monsieur Claude
--   top_kh : 5 khách doanh thu cao nhất trong kỳ + cơ sở bán nhiều nhất cho khách + doanh thu kỳ trước (so sánh)
--   top_sp : 5 mặt hàng bán chạy (theo doanh thu) + cơ sở bán nhiều nhất
--   ton_cs : tồn kho theo cơ sở — giá trị (giá vốn), số mặt hàng còn tồn, hàng tồn > 6 tháng
--            (còn tồn ở cơ sở đó mà 180 ngày tới ngày cuối kỳ KHÔNG bán được ở chính cơ sở đó; dữ liệu Kiot từ 01/01/2026)
create or replace function public.kt_tq_bo_sung(p_phien text, p_tu date, p_den date, p_tu0 date, p_den0 date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'tong_quan');
  with hd as (select * from kt_kiot_hoa_don where trang_thai = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
  hd0 as (select khach_id, sum(tong) dt from kt_kiot_hoa_don where trang_thai = 1 and khach_id is not null
            and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu0 and p_den0 group by 1),
  kh as (select khach_id, max(khach_ma) ma, max(khach_ten) ten, sum(tong) dt, count(*) so, mode() within group (order by chi_nhanh) cn
           from hd where khach_id is not null group by 1 order by sum(tong) desc limit 5),
  ct as (select hd.chi_nhanh, d from hd cross join lateral jsonb_array_elements(hd.chi_tiet) d),
  sp as (select d->>'ma' ma, max(d->>'ten') ten, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt, mode() within group (order by chi_nhanh) cn
           from ct group by 1 order by sum((d->>'tien')::numeric) desc limit 5),
  ban180 as (select distinct h.chi_nhanh cn, d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
               where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_den - 180 and p_den),
  ton as (select t->>'cn' cn, p.ma, coalesce(p.nhom, '(không nhóm)') nhom, (t->>'ton')::numeric sl, (t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0) gt
            from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where (t->>'ton')::numeric > 0)
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
end $$;
revoke execute on function public.kt_tq_bo_sung(text, date, date, date, date) from public;
grant execute on function public.kt_tq_bo_sung(text, date, date, date, date) to anon, authenticated;
