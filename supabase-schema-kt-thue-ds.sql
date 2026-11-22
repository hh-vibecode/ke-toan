-- HOÁ ĐƠN & THUẾ theo giao diện mẫu kế toán (13/10/2026) — danh sách cho các màn con. Monsieur Claude
-- kt_thue_hd_ds : danh sách HOÁ ĐƠN (gộp dòng hàng 3TShop theo hộ + ký hiệu + số + ngày; meInvoice mỗi hoá đơn đã là 1 dòng)
-- kt_thue_ps    : phát sinh nhập / xuất trong kỳ theo dòng hàng (kho sổ thuế) — từ hoá đơn 3TShop của hộ đó
create or replace function public.kt_thue_hd_ds(p_phien text, p_tu date, p_den date, p_chieu text, p_hkd text default null, p_tim text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  select coalesce(jsonb_agg(x order by x->>'ngay' desc, x->>'so_hd' desc), '[]') into r from (
    select jsonb_build_object('hkd', hkd, 'ky_hieu', ky_hieu, 'mau', max(mau), 'so_hd', so_hd, 'ngay', ngay, 'mst', max(mst), 'doi_tac', max(nguoi_mua),
      'thanh_tien', sum(thanh_tien), 'tien_thue', sum(coalesce(tien_thue, 0)), 'tong', sum(coalesce(tong, thanh_tien + coalesce(tien_thue, 0))),
      'so_dong', count(*), 'ten', max(ten), 'ghi_chu', max(ghi_chu), 'nguon', case when max(nguon) like 'meinvoice:%' then 'MISA meInvoice' else '3TShop' end) x
    from kt_thue_hd
    where chieu = p_chieu and ngay between p_tu and p_den and (p_hkd is null or hkd = p_hkd)
      and (p_tim is null or so_hd ilike '%' || p_tim || '%' or nguoi_mua ilike '%' || p_tim || '%' or mst ilike '%' || p_tim || '%' or ten ilike '%' || p_tim || '%')
    group by hkd, ky_hieu, so_hd, ngay limit 2000) t;
  return r;
end $$;
revoke execute on function public.kt_thue_hd_ds(text, date, date, text, text, text) from public;
grant execute on function public.kt_thue_hd_ds(text, date, date, text, text, text) to anon, authenticated;

create or replace function public.kt_thue_ps(p_phien text, p_hkd text, p_tu date, p_den date, p_tim text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  return coalesce((select jsonb_agg(jsonb_build_object('ngay', ngay, 'loai', case chieu when 'ra' then 'Xuất' else 'Nhập' end, 'so_hd', so_hd, 'ma', ma, 'ten', ten,
      'sl', case chieu when 'ra' then -sl else sl end, 'don_gia', don_gia, 'thanh_tien', thanh_tien, 'doi_tac', nguoi_mua) order by ngay desc, so_hd desc)
    from (select * from kt_thue_hd where hkd = p_hkd and ngay between p_tu and p_den and ma is not null
            and (p_tim is null or ma ilike '%' || p_tim || '%' or ten ilike '%' || p_tim || '%' or so_hd ilike '%' || p_tim || '%')
          order by ngay desc limit 1000) x), '[]');
end $$;
revoke execute on function public.kt_thue_ps(text, text, date, date, text) from public;
grant execute on function public.kt_thue_ps(text, text, date, date, text) to anon, authenticated;
