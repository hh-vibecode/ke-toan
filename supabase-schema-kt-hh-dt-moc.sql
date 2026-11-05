-- 04/11/2026 anh: "mốc theo doanh thu, còn pay hoa hồng theo thực thu" + "tự tính doanh thu theo phiếu tạo đã cọc trong tháng" (không lấy app MKT).
-- kt_bc_hoa_hong_dl thêm 'dt_sale' = doanh thu xét mốc của người bán theo tháng — mỗi đơn tính 1 lần:
--   (a) phiếu đặt hàng TẠO trong tháng, chưa huỷ, ĐÃ CỌC (có phiếu thu TTDH hoặc đã trả trên phiếu) → cả giá trị phiếu, tháng tạo phiếu;
--   (b) hoá đơn (hoàn thành + đang xử lý) không thuộc phiếu đặt đã cọc → tháng hoá đơn;
--   (c) trừ trả hàng trong tháng (người bán theo hoá đơn gốc). Trả từng phiếu (loai dat / hd / tra) để sales soát được. — Monsieur Claude
-- 05/11/2026 anh: "phải đối chiếu trên Kiot khi làm hoa hồng" → thêm dòng loai 'hd_coc' (dt 0): hoá đơn trong tháng thuộc phiếu đặt đã cọc
--   (doanh thu đã tính ở phiếu đặt) kèm kiot = tổng HĐ, dh = mã phiếu đặt, th_dat = tháng tạo phiếu → app dựng bảng
--   "HĐ trên Kiot → doanh thu xét mốc" ra đúng số tổng danh sách Hoá đơn Kiot (lọc người bán + tháng). Dòng hd cũng có kiot.
do $$ declare d text := pg_get_functiondef('public.kt_bc_hoa_hong_dl(date, date)'::regprocedure); m text := '    ''cau_hinh'', (select gia_tri::jsonb from kt_cai_dat where khoa = ''hh_cau_hinh''),'; begin
  -- chạy lại được: bỏ khối dt_sale cũ (nếu có) rồi chèn bản mới
  if position('    ''dt_sale'',' in d) > 0 then d := left(d, position('    ''dt_sale'',' in d) - 1) || substr(d, position(m in d)); end if;
  if position('''dt_sale''' in d) > 0 then raise exception 'không gỡ được dt_sale cũ'; end if;
  if position(m in d) = 0 then raise exception 'kt_bc_hoa_hong_dl đổi cấu trúc — soát tay'; end if;
  d := replace(d, m, $x$    'dt_sale', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('thang', th, 'nv', nv, 'dt', round(dt), 'ma', ma, 'ngay', ngay, 'loai', loai, 'khach', khach,
          'kiot', kiot, 'dh', dh, 'th_dat', th_dat)) order by ngay, ma), '[]') from (
        with coc as materialized (select distinct regexp_replace(substr(q.ma, 3), '-[0-9]+$', '') dh from kt_kiot_so_quy q where q.ma like 'TTDH%' and q.la_thu and q.trang_thai = '0'),
             dc as materialized (select o.id, o.ma, o.ngay, o.nv_ban, o.tong from kt_kiot_dat_hang o
                                  where o.trang_thai is distinct from 4 and (coalesce(o.da_tra, 0) > 0 or o.ma in (select dh from coc))),
             hh as (select h.*, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date d,
                           (select dc.ma || '|' || to_char((dc.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') from dc
                             where dc.id = h.dat_hang_id or (h.dat_hang_id is null and dc.ma = nullif(h.ma_dat_hang, '')) order by dc.ngay limit 1) dcm
                      from kt_kiot_hoa_don h where h.trang_thai in (1, 3) and h.tong > 0 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
             x as (select to_char((o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, coalesce(nullif(trim(o.nv_ban), ''), '(không ghi)') nv, o.tong dt,
                          o.ma, (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, 'dat' loai, o.khach_ten khach, null::numeric kiot, null::text dh, null::text th_dat
                     from kt_kiot_dat_hang o join dc on dc.id = o.id where (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
                   union all
                   select to_char(h.d, 'YYYY-MM'), coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)'), case when h.dcm is null then h.tong else 0 end, h.ma, h.d,
                          case when h.dcm is null then 'hd' else 'hd_coc' end, h.khach_ten, h.tong, split_part(h.dcm, '|', 1), nullif(split_part(h.dcm, '|', 2), '')
                     from hh h
                   union all
                   select to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM'), coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)'), -t.tong_tra, t.ma, (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'tra', h.khach_ten,
                          null, h.ma, null
                     from kt_kiot_tra_hang t join kt_kiot_hoa_don h on h.id = t.hoa_don_id
                    where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den)
        select * from x) z),
$x$ || m);
  execute d;
end $$;
revoke execute on function public.kt_bc_hoa_hong_dl(date, date) from public, anon, authenticated;
