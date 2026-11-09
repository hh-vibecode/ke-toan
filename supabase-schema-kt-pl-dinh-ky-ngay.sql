-- 09/11/2026 kế toán (anh chuyển, mục 2.1): "các phần chi phí định kỳ nếu chưa phát sinh chi sẽ cần phân bổ đến thời điểm nào trong tháng đó chứ không phải
-- phân bổ cả 1 cục (vd mới hết tuần 1 tháng 11 thì chỉ phân bổ đến tuần 1)" + mục 8 (P&L cả năm lỗ hơn Tổng quan): P&L năm cộng trọn định kỳ tháng đang chạy
-- và cả các tháng CHƯA TỚI. Sửa: hệ số tháng hs = 1 (tháng đã qua) · số ngày đã qua / số ngày của tháng (tháng đang chạy, giờ VN) · 0 (tháng chưa tới).
-- Luôn tính: so_tien × hs · Ước tính: max(so_tien × hs − phiếu thật, 0). Trả thêm he_so, so_tien_ky (= so_tien × hs). — Monsieur Claude
create or replace function public.kt_pl_dinh_ky_thang(p_phien text, p_tu text, p_den text) returns jsonb
  language plpgsql stable security definer set search_path = public as $function$
declare v_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  perform kt_chan(p_phien, 'pl');
  return (select coalesce(jsonb_agg(z), '[]') from (
    with th as (select to_char(g, 'YYYY-MM') thang,
                       case when g::date + interval '1 month' <= date_trunc('month', v_nay) then 1.0
                            when g::date = date_trunc('month', v_nay)::date then extract(day from v_nay) / extract(day from (g + interval '1 month - 1 day'))
                            else 0 end hs
                  from generate_series((greatest(p_tu, '2026-09') || '-01')::date, (p_den || '-01')::date, interval '1 month') g),
    k as (select d.*, th.thang, th.hs, coalesce(d.loai_con_id, d.loai_id) muc,
                 exists (select 1 from kt_pl_dinh_ky_chot c where c.dinh_ky_id = d.id and c.thang = th.thang) chot
            from kt_pl_dinh_ky d join th on th.thang >= d.tu_thang and (d.den_thang is null or th.thang <= d.den_thang) where not d.da_xoa),
    t as (select k.*, k.so_tien * k.hs so_tien_ky, case when k.kieu = 'uoc_tinh' then coalesce((select sum(h.tien) from kt_v_chi_ht h
                   where h.thang = k.thang and h.loai_id in (select kt_loai_cay(k.muc))), 0) end thuc from k),
    s as (select t.*, case when kieu = 'luon' then so_tien_ky when chot then 0 else greatest(so_tien_ky - thuc, 0) end them from t)
    select s.id, s.ten, s.kieu, s.thang, s.muc loai, s.so_tien, round(s.so_tien_ky) so_tien_ky, round(s.hs, 4) he_so, round(s.thuc) thuc, s.chot, round(s.them) them,
           (pb->>'don_vi_id')::int dv, round(case when pb is null then s.them else s.them * (pb->>'so_tien')::numeric / s.so_tien end) tien
      from s left join lateral jsonb_array_elements(case when jsonb_array_length(s.phan_bo) > 0 then s.phan_bo end) pb on true) z);
end $function$;
