-- KÉO THÊM TỪ KIOT (14/10/2026, góp ý kế toán chị Jaycie) — Monsieur Claude
--   · kt_kiot_dat_hang : ĐƠN ĐẶT HÀNG (orders) — "doanh thu đã đánh đơn" + "khách đã cọc nhưng chưa đi hàng" (Tổng quan)
--       Doanh thu ghi nhận khi đơn đi hàng = hoá đơn hoàn thành; đơn đặt còn "Phiếu tạm" có tiền khách trả trước = cọc chưa đi hàng (dự kiến, không cộng doanh thu tháng)
--   · kt_kiot_hoa_don thêm: kenh_id (kênh bán) · ghi_chu (ghi chú đơn — sales ghi đơn vị vận chuyển / thu COD) · cod (ô COD Kiot) · dat_hang_id
--   · kt_kiot_kenh : danh sách kênh bán (Bán trực tiếp, Facebook, Tiktok, Shopee, Website…)
--   · kt_kiot_nhom : nhóm hàng cha / con (Tổng quan doanh thu theo NHÓM CHA)
-- Kéo: Edge Function kt-kiot — đơn đặt hàng 15 phút / lần (phần sửa), danh mục nhóm + kênh mỗi lần kéo đầy đủ hàng ban đêm.
create table if not exists public.kt_kiot_dat_hang (
  id bigint primary key, ma text, ngay timestamptz, chi_nhanh text, nv_ban text, khach_id bigint, khach_ma text, khach_ten text,
  tong numeric, da_tra numeric, trang_thai int, trang_thai_ten text, kenh_id bigint, ghi_chu text, cod boolean, so_mh int,
  sua_kiot timestamptz, keo_luc timestamptz);
create index if not exists kt_kiot_dat_hang_ngay_idx on public.kt_kiot_dat_hang (ngay);
alter table public.kt_kiot_hoa_don add column if not exists kenh_id bigint, add column if not exists ghi_chu text,
  add column if not exists cod boolean, add column if not exists dat_hang_id bigint;
create table if not exists public.kt_kiot_kenh (id bigint primary key, ten text, keo_luc timestamptz);
create table if not exists public.kt_kiot_nhom (id bigint primary key, ten text, cha_id bigint, sua_kiot timestamptz, keo_luc timestamptz);
alter table public.kt_kiot_dat_hang enable row level security;
alter table public.kt_kiot_kenh enable row level security;
alter table public.kt_kiot_nhom enable row level security;
revoke all on public.kt_kiot_dat_hang, public.kt_kiot_kenh, public.kt_kiot_nhom from anon, authenticated;

-- nhóm CHA của 1 nhóm (đi ngược lên gốc; Kiot tối đa 3 cấp)
create or replace function public.kt_nhom_cha(p_ten text) returns text language sql stable set search_path = public as $$
  with recursive n as (select id, ten, cha_id, 0 cap from kt_kiot_nhom where ten = p_ten
                       union all select k.id, k.ten, k.cha_id, n.cap + 1 from kt_kiot_nhom k join n on k.id = n.cha_id where n.cap < 5)
  select coalesce((select ten from n where cha_id is null order by cap desc limit 1), p_ten);
$$;

-- ── TỔNG QUAN: doanh thu thực tế vs doanh thu trên đơn (đã cọc) · nguồn doanh thu theo kênh · nhóm hàng CHA + lợi nhuận (14/10/2026, phiên cloud)
-- Kế toán (chị Jaycie): "bổ sung phần doanh thu đã đánh đơn, và doanh thu khách đã cọc nhưng chưa đi hàng"; anh: "tách hẳn doanh thu thực tế,
-- doanh thu trên đơn (chỉ tính đơn đã có cọc — cọc như app MKT/Sale)".
-- ĐƠN CÓ CỌC (luật app MKT/Sale 22–23/9/2026): đơn đặt hàng chưa huỷ VÀ (đã trả tiền trên đơn > 0 HOẶC khách có "nợ cần thu" ÂM trên Kiot = tiền trả trước
--   nằm ở tài khoản khách). Phiếu tạm không có dấu vết tiền = BÁO GIÁ, không tính.
-- Doanh thu THỰC TẾ = hoá đơn hoàn thành (đã đi hàng) − trả hàng. Đơn đã cọc CHƯA ĐI HÀNG (còn Phiếu tạm) = doanh thu DỰ KIẾN, ghi nhận vào tháng xuất hoá đơn.
create or replace function public.kt_tq_don(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'tong_quan');
  return jsonb_build_object(
    'kenh', (select coalesce(jsonb_agg(jsonb_build_object('ten', ten, 'cn', cn, 'dt', dt, 'so', so) order by dt desc), '[]') from (
        select coalesce(k.ten, 'Không ghi kênh (bán tại quầy)') ten, h.chi_nhanh cn, sum(h.tong) dt, count(*) so
          from kt_kiot_hoa_don h left join kt_kiot_kenh k on k.id = h.kenh_id
         where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
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
         where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
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
end $$;
revoke execute on function public.kt_tq_don(text, date, date) from public;
grant execute on function public.kt_tq_don(text, date, date) to anon, authenticated;
