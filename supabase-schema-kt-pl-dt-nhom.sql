-- 23/10/2026 (anh): P&L chính dựng theo form sheet BÁO CÁO P&L — doanh thu tách bán buôn / bán lẻ offline / bán lẻ online / nến bơ TTV (từ T9, hoá đơn Kiot).
-- Bán buôn = khách tên bắt đầu KB / NPP / ĐL / DL / CTV; nến bơ = kênh "… Nến Bơ"; online = kênh Facebook / Tiktok / Website / Shopee…; còn lại = bán lẻ offline. — Monsieur Claude
create or replace function public.kt_pl_dt_nhom(p_phien text, p_tu date, p_den date) returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'pl');
  return coalesce((select jsonb_agg(jsonb_build_object('thang', thang, 'cn', chi_nhanh, 'nhom', nhom, 'dt', dt)) from (
    select to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, h.chi_nhanh,
           case when h.khach_ten ~* '^(KB|NPP|ĐL|DL|CTV)[ .-]' then 'buon' when kt_bo_dau(coalesce(k.ten, '')) ~ 'nen bo' then 'ttv'
                when kt_kenh_ten(k.ten, h.chi_nhanh) in ('Bán trực tiếp tại cửa hàng', 'Khác') then 'off' else 'on' end nhom, sum(h.tong) dt
      from kt_kiot_hoa_don h left join kt_kiot_kenh k on k.id = h.kenh_id
     where h.trang_thai in (1, 3) and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between greatest(p_tu, '2026-09-01') and p_den
     group by 1, 2, 3) x), '[]');
end $f$;
revoke all on function public.kt_pl_dt_nhom(text, date, date) from public; grant execute on function public.kt_pl_dt_nhom(text, date, date) to anon;
