-- =========================================================================
-- APP KẾ TOÁN — HOÁ ĐƠN & THUẾ: TỒN KHO SỔ THUẾ + HOÁ ĐƠN (nguồn 3TShop, anh 09/10/2026) — Monsieur Claude
-- 3TShop KHÔNG có API: anh xuất ra Google Sheet → scripts/keo-3tshop.js đọc (Drive qua rclone, link xuất bản) → 2 bảng dưới.
-- 3 hộ kinh doanh: HT = Hiền Thủy (Kiot "Đồ thờ Hiền Thủy") · CT = Chánh Tâm ("Đồ Thờ Chánh Tâm") · SD = Shidai ("Tổng kho sỉ Shidai").
--   kt_thue_xnt: nhập – xuất – tồn theo hộ × kỳ (quý '2026-Q1' hoặc tháng '2026-09') × mã hàng (số lượng + tiền).
--   kt_thue_hd : từng dòng hàng trên hoá đơn bán ra (chieu 'ra') / mua vào (chieu 'vao'). Mỗi lần kéo thay nguyên phần của 1 file (nguon).
-- Ngày hoá đơn ngoài khoảng 01/01/2025 → hôm nay + 1 coi là GÕ SAI (vẫn lưu, báo ở trang Đối soát lỗi).
-- =========================================================================
create table if not exists public.kt_thue_xnt (
  hkd text not null, ky text not null, ma text not null, ten text, chung_loai text, dvt text, gia_nhap numeric,
  dau_sl numeric, dau_tien numeric, nhap_sl numeric, nhap_tien numeric, xuat_sl numeric, xuat_tien numeric, cuoi_sl numeric, cuoi_tien numeric,
  nguon text, keo_luc timestamptz not null default now(), primary key (hkd, ky, ma));
create table if not exists public.kt_thue_hd (
  id bigserial primary key, hkd text not null, chieu text not null check (chieu in ('ra','vao')),
  so_hd text, mau text, ky_hieu text, ngay date, mst text, nguoi_mua text, ma text, ten text, dvt text,
  sl numeric, don_gia numeric, thanh_tien numeric, thue_suat numeric, tien_thue numeric, tong numeric, ghi_chu text,
  nguon text not null, dong int, keo_luc timestamptz not null default now());
create index if not exists kt_thue_hd_ngay_idx on kt_thue_hd (hkd, chieu, ngay);
create index if not exists kt_thue_hd_nguon_idx on kt_thue_hd (nguon);
alter table public.kt_thue_xnt enable row level security; alter table public.kt_thue_hd enable row level security;
revoke all on public.kt_thue_xnt, public.kt_thue_hd from anon, authenticated;

create or replace function public.kt_hkd_chi_nhanh(p text) returns text language sql immutable as $$
  select case p when 'HT' then 'Đồ thờ Hiền Thủy' when 'CT' then 'Đồ Thờ Chánh Tâm' when 'SD' then 'Tổng kho sỉ Shidai' end;
$$;

-- Báo cáo trang "Hoá đơn & thuế"
create or replace function public.kt_bc_thue(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
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
        where trang_thai = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) t),
    'ngay_sai', (select count(*) from kt_thue_hd where ngay is null or ngay not between date '2025-01-01' and hom + 1),
    'keo_luc', (select max(keo_luc) from kt_thue_hd));
end $$;
revoke execute on function public.kt_bc_thue(text, date, date) from public;
grant execute on function public.kt_bc_thue(text, date, date) to anon, authenticated;

-- Chi tiết tồn kho sổ thuế 1 hộ × kỳ (top theo giá trị tồn cuối, có tìm)
create or replace function public.kt_thue_xnt_ct(p_phien text, p_hkd text, p_ky text, p_tim text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  return coalesce((select jsonb_agg(to_jsonb(x) - 'nguon' - 'keo_luc' order by x.cuoi_tien desc nulls last) from (
    select * from kt_thue_xnt where hkd = p_hkd and ky = p_ky and (p_tim is null or ten ilike '%' || p_tim || '%' or ma ilike '%' || p_tim || '%')
    order by cuoi_tien desc nulls last limit 500) x), '[]');
end $$;
revoke execute on function public.kt_thue_xnt_ct(text, text, text, text) from public;
grant execute on function public.kt_thue_xnt_ct(text, text, text, text) to anon, authenticated;
