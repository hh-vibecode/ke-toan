-- SO DOANH THU 2 APP (kế toán ↔ MKT/Sale) MỖI ĐÊM — 17/11/2026. Monsieur Claude
-- Anh (qua phiên MKT/SALE): "làm cái so định kỳ hàng ngày đi, không cần đổi làm gì mất công, bọn m so qua lại và trao đổi với nhau trên cloud về doanh thu tổng,
-- doanh thu onl off, doanh thu nhân sự định kỳ đêm hàng ngày". Bảng chung so_dt_2app / so_dt_2app_tin do app MKT tạo (repo mkt-sale-app, chỉ service_role).
-- App kế toán CHỈ ghi dòng ben = 'kt' (xoá + ghi lại từ T6/2026), không đụng dòng ben = 'mkt', không đổi luật tính bên nào.
-- Nguồn: kt_bc_hoa_hong_dl → dt_sale (đúng số "doanh thu xét mốc" trang Hoa hồng): phiếu đặt đã cọc (tháng tạo đơn, cả giá trị) + hoá đơn không qua
-- phiếu đặt cọc + trả hàng (âm). Tiền gửi = GIÁ TRỊ PHIẾU, CHƯA trừ VAT TK 599 (để cùng gốc với MKT). Kênh: khách nguồn online = Online (cả mua lại / Shopee — anh 17/11).
-- Lịch kt-so-dt-2app 21:30 giờ VN (MKT so lúc ~22:20).

-- 17/11 (phiên MKT, anh muốn mỗi đơn lệch có ghi chú CẢ 2 bên, cập nhật hằng đêm): mã ben='mkt' mà kế toán KHÔNG tính cùng tháng → 1 dòng ben='kt' nêu lý do
-- vào so_dt_2app_ly_do (xoá + ghi lại dòng ben='kt' từ T6). Không đụng dòng ben='mkt'.
create or replace function public.kt_so_dt_2app_ly_do() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from so_dt_2app_ly_do where ben = 'kt' and thang >= '2026-06';
  insert into so_dt_2app_ly_do (thang, ben, ma, ly_do, luc)
  select m.thang, 'kt', m.ma,
    case
      when o.id is not null then case
        when o.trang_thai = 4 then 'Đơn đặt đã huỷ trên Kiot — không tính'
        when coalesce(o.tong, 0) = 0 then 'Đơn 0 đ — kế toán không ghi dòng 0 đ'
        when hx.n > 0 and hx.song = 0 then 'Hoá đơn của đơn (' || hx.ds || ') đã huỷ trên Kiot — không tính'
        when k1.thang is not null then 'Đã tính ' || m.ma || ' ở tháng ' || k1.thang || ' (kế toán xếp tháng theo ngày tạo đơn giờ VN)'
        when kh.ma is not null then 'Đơn chưa có cọc gắn đơn khi tạo → kế toán tính theo hoá đơn ' || kh.ma || ' tháng ' || kh.thang
        when o.trang_thai_ten = 'Phiếu tạm' then 'Phiếu tạm chưa có cọc gắn đơn (không TTDH, Kiot chưa ghi trả trên đơn, không có phiếu thu sổ quỹ gắn vào đơn mới nhất của khách) — kế toán coi là báo giá, chưa tính'
                                                   || case when o.ngay < timestamptz '2026-11-01 00:00+07' then '; luật phiếu thu sổ quỹ chỉ áp đơn từ 01/11' else '' end
        when coalesce(hx.n, 0) = 0 then 'Đơn ' || coalesce(o.trang_thai_ten, '?') || ' nhưng không có hoá đơn nào trên Kiot, không có cọc gắn đơn — chưa tính'
        else 'Đơn ' || coalesce(o.trang_thai_ten, '?') || ' chưa ra hoá đơn hoàn thành và không có cọc gắn đơn — chưa tính' end
      when h.id is not null then case
        when h.trang_thai not in (1, 3) then 'Hoá đơn ' || coalesce(h.trang_thai_ten, 'chưa hoàn thành') || ' — không tính'
        when coalesce(h.tong, 0) = 0 then 'Hoá đơn 0 đ — kế toán không ghi dòng 0 đ'
        when kd.ma is not null then 'Đã tính ở phiếu đặt ' || kd.ma || ' tháng ' || kd.thang || ' (phiếu đặt đã cọc tính cả giá trị ở tháng tạo đơn)'
        when k1.thang is not null then 'Đã tính ' || m.ma || ' ở tháng ' || k1.thang
        else 'Chưa xác định — kế toán cần soát' end
      else 'Không thấy mã này trong dữ liệu Kiot bên kế toán' end,
    now()
  from (select thang, ma from so_dt_2app x where ben = 'mkt' and thang >= '2026-11'
          and not exists (select 1 from so_dt_2app k where k.ben = 'kt' and k.thang = x.thang and k.ma = x.ma)) m
  left join kt_kiot_dat_hang o on o.ma = m.ma
  left join kt_kiot_hoa_don h on o.id is null and h.ma = m.ma
  left join lateral (select k.thang from so_dt_2app k where k.ben = 'kt' and k.ma = m.ma order by k.thang limit 1) k1 on true
  left join lateral (select count(*) n, count(*) filter (where h3.trang_thai in (1, 3)) song, string_agg(h3.ma, ', ') ds from kt_kiot_hoa_don h3
                      where o.id is not null and (h3.dat_hang_id = o.id or (h3.dat_hang_id is null and h3.ma_dat_hang = o.ma))) hx on true
  left join lateral (select k.ma, k.thang from kt_kiot_hoa_don h2 join so_dt_2app k on k.ben = 'kt' and k.ma = h2.ma
                      where o.id is not null and (h2.dat_hang_id = o.id or (h2.dat_hang_id is null and h2.ma_dat_hang = o.ma)) order by k.thang limit 1) kh on true
  left join lateral (select k.ma, k.thang from kt_kiot_dat_hang o2 join so_dt_2app k on k.ben = 'kt' and k.ma = o2.ma
                      where h.id is not null and (o2.id = h.dat_hang_id or (h.dat_hang_id is null and o2.ma = nullif(h.ma_dat_hang, ''))) order by k.thang limit 1) kd on true;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.kt_so_dt_2app_ly_do() from public, anon, authenticated;

create or replace function public.kt_so_dt_2app_gui() returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := date '2026-11-01';   -- 17/11 anh (qua phiên MKT): "bắt đầu so từ tháng 11, mấy tháng trước kệ đi"
        den date := date_trunc('month', (now() at time zone 'Asia/Ho_Chi_Minh')::date)::date; d jsonb; n int := 0; t0 timestamptz := clock_timestamp();
        cfg jsonb := coalesce((select gia_tri::jsonb from kt_cai_dat where khoa = 'hh_cau_hinh'), '{}');
begin
  create temp table if not exists _kt_so (thang text, ma text, tien numeric, kenh text, nhan_su text, doi text, ma_kh text, ly_do text, kenh_ly text, ns_ly text, nv_ban text) on commit drop;
  truncate _kt_so;
  while m <= den loop
    d := kt_bc_hoa_hong_dl(m, (m + interval '1 month - 1 day')::date);
    insert into _kt_so
    select x->>'thang', x->>'ma', (x->>'dt')::numeric,
           -- 17/11 anh: khách nguồn online LUÔN là Online (cả mua lại, Shopee); kt_hd_online chỉ quyết định hoa hồng online của anh Hải
           case when nn.ly_do in ('thang_dau', 'nhan_trang', 'mua_lai', 'shopee') then 'Online' else 'Offline' end,
           x->>'nv',
           (select case n2->>'cs' when 'si' then 'Sỉ' when 'le' then 'Lẻ' when 'online' then 'Online' end from jsonb_array_elements(coalesce(cfg->'nguoi', '[]')) n2
             where n2->'kiot' ? (x->>'nv') or n2->>'ten' = x->>'nv' limit 1),
           coalesce(o.khach_ma, h.khach_ma, h2.khach_ma),
           case x->>'loai'
             when 'dat' then case when exists (select 1 from kt_kiot_so_quy q where q.ma like 'TTDH' || (x->>'ma') || '%' and q.la_thu and q.trang_thai = '0') then 'phiếu đặt đã cọc (phiếu TTDH)'
                                  when exists (select 1 from kt_coc_tt() c where c.dh = x->>'ma') then 'phiếu đặt đã cọc (phiếu thu ' || (select string_agg(c.ma, ', ') from kt_coc_tt() c where c.dh = x->>'ma') || ' không gắn đơn)'
                                  else 'phiếu đặt đã trả tiền trên Kiot' end || ' — tính cả giá trị đơn, tháng tạo đơn'
             when 'hd' then 'hoá đơn hoàn thành không qua phiếu đặt đã cọc'
             else 'trả hàng (trừ) của ' || coalesce(x->>'dh', '?') end,
           -- 17/11: vì sao Online / Offline (bảng kt_don_nguon — luật MKT chép 30/10, dùng cho hoa hồng) + kênh ghi trên phiếu Kiot
           case nn.ly_do
             when 'thang_dau' then 'Online: khách nguồn online, đơn trong 1 tháng kể từ đơn có tiền đầu tiên (Lẻ / Sỉ tính riêng) — có tính hoa hồng online anh Hải'
             when 'nhan_trang' then 'Online: khách nguồn online, có nhắn trang trong 30 ngày trước đơn — có tính hoa hồng online anh Hải'
             when 'shopee' then 'Online: khách Shopee — không tính hoa hồng online anh Hải'
             when 'mua_lai' then 'Online mua lại: khách nguồn online, quá 1 tháng từ đơn đầu và không nhắn trang trong 30 ngày — không tính hoa hồng online anh Hải'
             when 'khach_offline' then 'Offline: khách chưa từng có phiếu kênh online, không có trong Pancake / lead Online'
             when 'vang_lai' then 'Offline: phiếu không gắn khách (vãng lai)'
             when 'truoc_t6' then 'Offline: phiếu trước 01/06/2026'
             else 'Offline: không có trong bảng nguồn đơn' end
           || coalesce(' · kênh trên phiếu Kiot: ' || kn.ten, ' · phiếu Kiot không ghi kênh'),
           'Người bán ghi trên phiếu Kiot' || case when x->>'loai' = 'hd' and h.dat_hang_id is not null then ' (hoá đơn của đơn đặt)' else '' end,
           x->>'nv'
      from jsonb_array_elements(d->'dt_sale') x
      left join kt_kiot_dat_hang o on x->>'loai' = 'dat' and o.ma = x->>'ma'
      left join kt_kiot_hoa_don h on x->>'loai' = 'hd' and h.ma = x->>'ma'
      left join kt_kiot_hoa_don h2 on x->>'loai' = 'tra' and h2.ma = x->>'dh'
      left join lateral (select coalesce(o.id, h.dat_hang_id, h2.dat_hang_id) dh_id, coalesce(h.id, h2.id) hd_id, coalesce(o.kenh_id, h.kenh_id, h2.kenh_id) kenh_id) id on true
      left join kt_don_nguon nn on (id.dh_id is not null and nn.loai = 'dh' and nn.id = id.dh_id) or (id.dh_id is null and nn.loai = 'hd' and nn.id = id.hd_id)
      left join kt_kiot_kenh kn on kn.id = id.kenh_id
     where x->>'thang' = to_char(m, 'YYYY-MM') and x->>'loai' in ('dat', 'hd', 'tra') and coalesce((x->>'dt')::numeric, 0) <> 0;
    m := (m + interval '1 month')::date;
  end loop;
  delete from so_dt_2app where ben = 'kt' and thang >= '2026-06';
  insert into so_dt_2app (thang, ben, ma, tien, kenh, nhan_su, doi, ma_kh, ly_do, luc, kenh_ly, ns_ly, nv_ban)
  select thang, 'kt', ma, sum(tien), max(kenh), max(nhan_su), max(doi), max(ma_kh), string_agg(distinct ly_do, ' · '), now(), max(kenh_ly), max(ns_ly), max(nv_ban)
    from _kt_so group by thang, ma;
  get diagnostics n = row_count;
  perform kt_so_dt_2app_ly_do();   -- 17/11: lý do bên kế toán không tính các mã chỉ MKT tính (bảng so_dt_2app_ly_do)
  perform kt_ghi_nhat_ky('Hệ thống', 'so_dt_2app', null, 'gui_so_dt_2app',
    jsonb_build_object('so_dong', n, 'giay', round(extract(epoch from clock_timestamp() - t0)::numeric, 1)));
  return jsonb_build_object('so_dong', n, 'giay', round(extract(epoch from clock_timestamp() - t0)::numeric, 1));
end $$;
revoke all on function public.kt_so_dt_2app_gui() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('kt-so-dt-2app') where exists (select 1 from cron.job where jobname = 'kt-so-dt-2app');
  perform cron.schedule('kt-so-dt-2app', '30 14 * * *', 'select public.kt_so_dt_2app_gui()');   -- 14:30 UTC = 21:30 giờ VN
end $$;
