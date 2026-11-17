-- SO DOANH THU 2 APP (kế toán ↔ MKT/Sale) MỖI ĐÊM — 17/11/2026. Monsieur Claude
-- Anh (qua phiên MKT/SALE): "làm cái so định kỳ hàng ngày đi, không cần đổi làm gì mất công, bọn m so qua lại và trao đổi với nhau trên cloud về doanh thu tổng,
-- doanh thu onl off, doanh thu nhân sự định kỳ đêm hàng ngày". Bảng chung so_dt_2app / so_dt_2app_tin do app MKT tạo (repo mkt-sale-app, chỉ service_role).
-- App kế toán CHỈ ghi dòng ben = 'kt' (xoá + ghi lại từ T6/2026), không đụng dòng ben = 'mkt', không đổi luật tính bên nào.
-- Nguồn: kt_bc_hoa_hong_dl → dt_sale (đúng số "doanh thu xét mốc" trang Hoa hồng): phiếu đặt đã cọc (tháng tạo đơn, cả giá trị) + hoá đơn không qua
-- phiếu đặt cọc + trả hàng (âm). Tiền gửi = GIÁ TRỊ PHIẾU, CHƯA trừ VAT TK 599 (để cùng gốc với MKT). Kênh theo kt_hd_online (luật app kế toán).
-- Lịch kt-so-dt-2app 21:30 giờ VN (MKT so lúc ~22:20).

create or replace function public.kt_so_dt_2app_gui() returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := date '2026-06-01'; den date := date_trunc('month', (now() at time zone 'Asia/Ho_Chi_Minh')::date)::date; d jsonb; n int := 0; t0 timestamptz := clock_timestamp();
        cfg jsonb := coalesce((select gia_tri::jsonb from kt_cai_dat where khoa = 'hh_cau_hinh'), '{}');
begin
  create temp table if not exists _kt_so (thang text, ma text, tien numeric, kenh text, nhan_su text, doi text, ma_kh text, ly_do text) on commit drop;
  truncate _kt_so;
  while m <= den loop
    d := kt_bc_hoa_hong_dl(m, (m + interval '1 month - 1 day')::date);
    insert into _kt_so
    select x->>'thang', x->>'ma', (x->>'dt')::numeric,
           case when coalesce(case when x->>'loai' = 'dat' then kt_hd_online(null, o.id)
                                   when x->>'loai' = 'hd' then kt_hd_online(h.id, h.dat_hang_id)
                                   else kt_hd_online(h2.id, h2.dat_hang_id) end, false) then 'Online' else 'Offline' end,
           x->>'nv',
           (select case n2->>'cs' when 'si' then 'Sỉ' when 'le' then 'Lẻ' when 'online' then 'Online' end from jsonb_array_elements(coalesce(cfg->'nguoi', '[]')) n2
             where n2->'kiot' ? (x->>'nv') or n2->>'ten' = x->>'nv' limit 1),
           coalesce(o.khach_ma, h.khach_ma, h2.khach_ma),
           case x->>'loai'
             when 'dat' then case when exists (select 1 from kt_kiot_so_quy q where q.ma like 'TTDH' || (x->>'ma') || '%' and q.la_thu and q.trang_thai = '0') then 'phiếu đặt đã cọc (phiếu TTDH)'
                                  when exists (select 1 from kt_coc_tt() c where c.dh = x->>'ma') then 'phiếu đặt đã cọc (phiếu thu ' || (select string_agg(c.ma, ', ') from kt_coc_tt() c where c.dh = x->>'ma') || ' không gắn đơn)'
                                  else 'phiếu đặt đã trả tiền trên Kiot' end || ' — tính cả giá trị đơn, tháng tạo đơn'
             when 'hd' then 'hoá đơn hoàn thành không qua phiếu đặt đã cọc'
             else 'trả hàng (trừ) của ' || coalesce(x->>'dh', '?') end
      from jsonb_array_elements(d->'dt_sale') x
      left join kt_kiot_dat_hang o on x->>'loai' = 'dat' and o.ma = x->>'ma'
      left join kt_kiot_hoa_don h on x->>'loai' = 'hd' and h.ma = x->>'ma'
      left join kt_kiot_hoa_don h2 on x->>'loai' = 'tra' and h2.ma = x->>'dh'
     where x->>'thang' = to_char(m, 'YYYY-MM') and x->>'loai' in ('dat', 'hd', 'tra') and coalesce((x->>'dt')::numeric, 0) <> 0;
    m := (m + interval '1 month')::date;
  end loop;
  delete from so_dt_2app where ben = 'kt' and thang >= '2026-06';
  insert into so_dt_2app (thang, ben, ma, tien, kenh, nhan_su, doi, ma_kh, ly_do, luc)
  select thang, 'kt', ma, sum(tien), max(kenh), max(nhan_su), max(doi), max(ma_kh), string_agg(distinct ly_do, ' · '), now()
    from _kt_so group by thang, ma;
  get diagnostics n = row_count;
  perform kt_ghi_nhat_ky('Hệ thống', 'so_dt_2app', null, 'gui_so_dt_2app',
    jsonb_build_object('so_dong', n, 'giay', round(extract(epoch from clock_timestamp() - t0)::numeric, 1)));
  return jsonb_build_object('so_dong', n, 'giay', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $$;
revoke all on function public.kt_so_dt_2app_gui() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('kt-so-dt-2app') where exists (select 1 from cron.job where jobname = 'kt-so-dt-2app');
  perform cron.schedule('kt-so-dt-2app', '30 14 * * *', 'select public.kt_so_dt_2app_gui()');   -- 14:30 UTC = 21:30 giờ VN
end $$;
