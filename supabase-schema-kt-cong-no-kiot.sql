-- CÔNG NỢ KHÁCH / NHÀ CUNG CẤP THEO SỐ KIOT + TUỔI NỢ (13/10/2026) — Monsieur Claude
-- Trang "Công nợ & Thanh toán" theo giao diện mẫu kế toán: bảng khách / NCC còn nợ + khung chi tiết.
-- SỐ NỢ = kt_kiot_khach.cong_no / kt_kiot_ncc.cong_no (số Kiot — anh chốt 08/10). KHÔNG cộng "tong − da_tra" từng hoá đơn:
-- khách trả nợ bằng phiếu thu riêng nên Kiot không trừ vào hoá đơn (13/10: nợ khách 640 tr nhưng hoá đơn "chưa trả" 5,24 tỷ).
-- TUỔI NỢ: gán số nợ vào các hoá đơn / phiếu nhập GẦN NHẤT của khách / NCC cho tới khi đủ (nợ cũ coi như đã trả trước — FIFO);
-- hoá đơn cũ nhất trong phần được gán = nợ lâu nhất. Phần không gán được (dữ liệu Kiot từ 01/01/2026) = "nợ từ trước 2026".
-- Kiot không có hạn thanh toán → app chỉ tính SỐ NGÀY NỢ (kế toán sẽ cho biết số ngày được nợ để tính quá hạn — câu hỏi trên app).

create or replace function public.kt_cong_no_dt(p_phien text, p_loai text default 'kh') returns jsonb
language plpgsql security definer set search_path = public as $$
declare hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; r jsonb;
begin
  perform kt_chan(p_phien, case when p_loai = 'ncc' then 'ncc' else 'khach_hang' end);
  with dt as (
    select id, ma, ten, sdt, cong_no no, tong_mua tong from kt_kiot_khach where p_loai = 'kh' and cong_no <> 0
    union all select id, ma, ten, sdt, cong_no, tong_nhap from kt_kiot_ncc where p_loai = 'ncc' and cong_no <> 0),
  ct as (   -- hoá đơn bán (khách) / phiếu nhập (NCC) đã hoàn thành
    select khach_id dt_id, id, ngay, chi_nhanh, tong from kt_kiot_hoa_don where p_loai = 'kh' and trang_thai = 1 and tong > 0
    union all select ncc_id, id, ngay, chi_nhanh, tong from kt_kiot_nhap_hang where p_loai = 'ncc' and trang_thai = 3 and tong > 0),
  lk as (select ct.*, d.no, sum(ct.tong) over (partition by ct.dt_id order by ct.ngay desc, ct.id desc) cum
           from ct join dt d on d.id = ct.dt_id where d.no > 0),
  pb as (select dt_id, chi_nhanh, (ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, least(tong, no - (cum - tong)) phan from lk where cum - tong < no),
  g as (select dt_id, sum(phan) da_gan, min(ngay) cu_nhat, count(*) so_ct, (array_agg(chi_nhanh order by ngay desc))[1] cn,
          sum(phan) filter (where hom - ngay <= 30) b1, sum(phan) filter (where hom - ngay between 31 and 60) b2,
          sum(phan) filter (where hom - ngay between 61 and 90) b3, sum(phan) filter (where hom - ngay > 90) b4
          from pb group by 1),
  cn_cuoi as (select distinct on (dt_id) dt_id, chi_nhanh from ct order by dt_id, ngay desc)
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'ma', d.ma, 'ten', d.ten, 'sdt', d.sdt, 'no', d.no, 'tong', d.tong,
      'cn', coalesce(g.cn, c.chi_nhanh), 'so_ct', coalesce(g.so_ct, 0), 'cu_nhat', g.cu_nhat, 'tuoi', hom - g.cu_nhat,
      'b1', coalesce(g.b1, 0), 'b2', coalesce(g.b2, 0), 'b3', coalesce(g.b3, 0), 'b4', coalesce(g.b4, 0),
      'truoc_2026', greatest(d.no - coalesce(g.da_gan, 0), 0)) order by d.no desc), '[]') into r
    from dt d left join g on g.dt_id = d.id left join cn_cuoi c on c.dt_id = d.id;
  return r;
end $$;
revoke execute on function public.kt_cong_no_dt(text, text) from public;
grant execute on function public.kt_cong_no_dt(text, text) to anon, authenticated;

-- Chi tiết 1 khách / NCC: thông tin · hoá đơn / phiếu nhập đang tính nợ (đã gán FIFO) · 15 chứng từ gần nhất · lịch sử trả tiền (sổ quỹ Kiot theo tên đối tác)
create or replace function public.kt_cong_no_dt_ct(p_phien text, p_loai text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; d record; r jsonb;
begin
  perform kt_chan(p_phien, case when p_loai = 'ncc' then 'ncc' else 'khach_hang' end);
  if p_loai = 'ncc' then select id, ma, ten, sdt, cong_no no, tong_nhap tong, null::text loai into d from kt_kiot_ncc where id = p_id;
  else select id, ma, ten, sdt, cong_no no, tong_mua tong, loai::text loai into d from kt_kiot_khach where id = p_id; end if;
  if d.id is null then return null; end if;
  with ct as (
    select id, ma, ngay, chi_nhanh, tong, da_tra from kt_kiot_hoa_don where p_loai <> 'ncc' and khach_id = p_id and trang_thai = 1
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
end $$;
revoke execute on function public.kt_cong_no_dt_ct(text, text, bigint) from public;
grant execute on function public.kt_cong_no_dt_ct(text, text, bigint) to anon, authenticated;
