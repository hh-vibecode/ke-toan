-- XEM NHANH (drill-down) — bấm vào dòng trên Tổng quan / Công nợ / Hoá đơn & Thuế mở khung chi tiết ngay tại chỗ, không chuyển trang
-- (anh 13/10/2026: "nối luôn, giống app MKT/Sale, nhiều dashboard tương tác để check nhanh"). Monsieur Claude
-- kt_drill(phiên, loại, khoá, từ, đến, chi nhánh Kiot | null):
--   nhom    : mặt hàng của 1 nhóm bán trong kỳ (SL, DT, tồn hiện tại)
--   sp      : 1 mặt hàng — bán theo cơ sở trong kỳ, tồn từng cơ sở, 15 hoá đơn gần nhất
--   kh      : 1 khách (khoá = id Kiot) — hoá đơn trong kỳ + tổng mua / công nợ
--   hd      : 1 hoá đơn bán Kiot (khoá = mã HĐ) — từng dòng hàng
--   ton_lau : hàng còn tồn ở 1 cơ sở mà 180 ngày tới ngày cuối kỳ không bán (giá trị lớn nhất trước)
--   cp      : phiếu chi phí hoạt động đã trả trong kỳ (khoá = tên loại chi | '' = tất cả; chi nhánh = cơ sở chịu chi phí | '_chung' = bộ phận chung)
create or replace function public.kt_drill(p_phien text, p_loai text, p_khoa text, p_tu date, p_den date, p_cn text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  -- quyền theo trang tương ứng: chi phí → Chi · khách / hoá đơn → Khách hàng · tồn → Hàng hoá · nhóm / mặt hàng → Bán hàng
  perform kt_chan(p_phien, case p_loai when 'cp' then 'chi' when 'kh' then 'khach_hang' when 'hd' then 'khach_hang' when 'ton_lau' then 'hang_hoa' else 'ban_hang' end);
  if p_loai = 'nhom' then
    with ct as (select h.chi_nhanh, d from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                 where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
                   and coalesce(d->>'nhom', '(không nhóm)') = p_khoa and (p_cn is null or h.chi_nhanh = p_cn))
    select coalesce(jsonb_agg(jsonb_build_object('ma', g.ma, 'ten', g.ten, 'sl', g.sl, 'dt', g.dt, 'ton', (select tong_ton from kt_kiot_hang p where p.ma = g.ma limit 1)) order by g.dt desc), '[]') into r
      from (select ct.d->>'ma' ma, max(ct.d->>'ten') ten, sum((ct.d->>'sl')::numeric) sl, sum((ct.d->>'tien')::numeric) dt from ct group by 1 order by 4 desc limit 200) g;
  elsif p_loai = 'sp' then
    select jsonb_build_object(
      'sp', (select jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'dvt', don_vi, 'gia_ban', gia_ban, 'tong_ton', tong_ton, 'gia_tri_ton', gia_tri_ton, 'ton', ton) from kt_kiot_hang where ma = p_khoa limit 1),
      'ban_cs', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'sl', sl, 'dt', dt) order by dt desc), '[]') from (
          select h.chi_nhanh cn, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
           where h.trang_thai = 1 and d->>'ma' = p_khoa and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1) x),
      'hd', (select coalesce(jsonb_agg(x order by x->>'ngay' desc), '[]') from (
          select jsonb_build_object('ma', h.ma, 'ngay', (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', h.chi_nhanh, 'khach', h.khach_ten, 'sl', (d->>'sl')::numeric, 'tien', (d->>'tien')::numeric) x
            from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d where h.trang_thai = 1 and d->>'ma' = p_khoa order by h.ngay desc limit 15) t)) into r;
  elsif p_loai = 'kh' then
    select jsonb_build_object(
      'kh', (select jsonb_build_object('id', id, 'ma', ma, 'ten', ten, 'sdt', sdt, 'cong_no', cong_no, 'tong_mua', tong_mua) from kt_kiot_khach where id = p_khoa::bigint),
      'hd', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'tong', tong, 'da_tra', da_tra, 'nv', nv_ban,
          'so_mh', jsonb_array_length(chi_tiet)) order by ngay desc), '[]') from kt_kiot_hoa_don
         where khach_id = p_khoa::bigint and trang_thai = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den)) into r;
  elsif p_loai = 'hd' then
    select jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'khach', khach_ten, 'khach_id', khach_id, 'nv', nv_ban,
      'tong', tong, 'da_tra', da_tra, 'gia_von', gia_von, 'trang_thai', trang_thai_ten, 'dong', chi_tiet) into r from kt_kiot_hoa_don where ma = p_khoa limit 1;
  elsif p_loai = 'ton_lau' then
    with ban as (select distinct d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai = 1 and h.chi_nhanh = p_cn and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_den - 180 and p_den),
    ton as (select p.ma, p.ten, p.nhom, (t->>'ton')::numeric sl, (t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0) gt
              from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where t->>'cn' = p_cn and (t->>'ton')::numeric > 0)
    select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'nhom', nhom, 'sl', sl, 'gt', gt,
        'ban_cuoi', (select max((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date) from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                      where h.trang_thai = 1 and h.chi_nhanh = p_cn and d->>'ma' = ton.ma)) order by gt desc), '[]') into r
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
end $$;
revoke execute on function public.kt_drill(text, text, text, date, date, text) from public;
grant execute on function public.kt_drill(text, text, text, date, date, text) to anon, authenticated;

-- kt_tq_bo_sung: thêm id khách (để bấm mở chi tiết khách)
