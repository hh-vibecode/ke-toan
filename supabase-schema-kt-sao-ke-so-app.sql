-- 19/11/2026 kế toán: "đối chiếu sao kê kiểu gì, tk đang bị âm tiền mà tải sao kê lên vẫn báo khớp — nó không soi bị double khoản chi trên app"
-- "Khớp số dư sao kê" cũ chỉ kiểm sao kê tự cân (đầu kỳ + có − nợ = cuối kỳ), không so sổ app. Nay kèm số dư sổ app từng ngày + thanh toán trung gian vào danh sách phiếu app. — Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_sao_ke_du_lieu(p_ky bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k kt_sao_ke_ky; a date; b date;
begin
  select * into k from kt_sao_ke_ky where id = p_ky;
  if k.id is null then raise exception 'Không có kỳ sao kê này'; end if;
  a := k.tu - 5; b := k.den + 5;
  return jsonb_build_object(
    'ky', jsonb_build_object('id', k.id, 'tk_id', k.tk_id, 'tk', (select ten from kt_tai_khoan where id = k.tk_id), 'tu', k.tu, 'den', k.den, 'dau_ky', k.dau_ky,
          'cuoi_ky', k.cuoi_ky, 'thong_tin', k.thong_tin, 'ten_file', k.ten_file, 'nap_boi', k.nap_boi, 'nap_luc', k.nap_luc,
          'token', k.token, 'token_boi', k.token_boi, 'token_luc', k.token_luc, 'ket_qua_luc', k.ket_qua_luc),
    -- 19/11 kế toán: "tk đang bị âm tiền mà tải sao kê lên vẫn báo khớp, không soi bị double khoản chi trên app" → kèm số dư SỔ APP cuối từng ngày trong kỳ (cùng công thức Sổ quỹ)
    'app_ngay', (select coalesce(jsonb_agg(jsonb_build_object('ngay', g.d::date, 'so_du', tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b
          where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau and b.ngay <= g.d::date), 0)) order by g.d), '[]')
        from kt_tai_khoan tk, generate_series(greatest(k.tu - 1, (select ngay_ton_dau from kt_tai_khoan where id = k.tk_id) - 1), k.den, interval '1 day') g(d) where tk.id = k.tk_id),
    'dong', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'stt', s.stt, 'ngay', s.ngay, 'so_ct', s.so_ct, 'ngay_hl', s.ngay_hl, 'no', s.no, 'co', s.co,
          'so_du', s.so_du, 'nd', s.noi_dung, 'tay', s.tay, 'sua_boi', s.sua_boi, 'sua_luc', s.sua_luc) order by s.stt, s.id) from kt_sao_ke s where s.ky_id = k.id), '[]'),
    'app', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('k', 'thu', 'id', t.id, 'ngay', t.ngay, 'vao', t.so_tien, 'ra', 0, 'nd', t.noi_dung, 'loai', (select ten from kt_loai where id = t.loai_id),
               'hd', (select jsonb_agg(jsonb_build_object('so', h.so_hd, 'kh', h.ky_hieu, 'ngay', h.ngay_hd, 'ten', h.nguoi_mua, 'mst', h.mst, 'cb', h.canh_bao) order by h.ngay_hd, h.so_hd)
                        from kt_thu_hd h where h.thu_id = t.id)) x
        from kt_thu t where not t.da_xoa and t.trang_thai = 'da_duyet' and t.tai_khoan_id = k.tk_id and t.ngay between a and b
      union all
      select jsonb_build_object('k', 'chi', 'id', c.id, 'ngay', c.ngay_tt, 'vao', 0, 'ra', c.so_tien, 'nd', c.noi_dung, 'doi', c.thu_huong_ten,
               'loai', (select ten from kt_loai where id = c.loai_id), 'co_hd', c.co_hd_do, 'so_tay', c.so_hd_do,
               'hd', (select jsonb_agg(jsonb_build_object('so', h.so_hd, 'kh', h.ky_hieu, 'ngay', h.ngay_hd, 'ten', h.ncc, 'mst', h.mst) order by h.ngay_hd, h.so_hd)
                        from kt_chi_hd h where h.chi_id = c.id))
        from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.tai_khoan_id = k.tk_id and c.ngay_tt between a and b
      union all
      select jsonb_build_object('k', 'dc', 'id', d.id, 'ngay', d.ngay, 'vao', case when d.tk_nhan_id = k.tk_id then d.so_tien else 0 end,
               'ra', case when d.tk_di_id = k.tk_id then d.so_tien else 0 end, 'nd', d.noi_dung,
               'doi', (select ten from kt_tai_khoan where id = case when d.tk_nhan_id = k.tk_id then d.tk_di_id else d.tk_nhan_id end))
        from kt_dieu_chuyen d where not d.da_xoa and k.tk_id in (d.tk_di_id, d.tk_nhan_id) and d.ngay between a and b
      union all
      select jsonb_build_object('k', 'vay', 'id', n.id, 'ngay', n.ngay, 'vao', n.so_tien, 'ra', 0, 'nd', 'Nhận tiền vay · ' || v.ten, 'doi', v.ben_cho_vay)
        from kt_vay_nhan n join kt_vay v on v.id = n.vay_id where not n.da_xoa and n.tai_khoan_id = k.tk_id and n.ngay between a and b
      union all
      select jsonb_build_object('k', 'vay', 'id', -r.id, 'ngay', r.ngay, 'vao', 0, 'ra', r.goc + r.lai, 'nd', 'Trả nợ vay · ' || v.ten, 'doi', v.ben_cho_vay, 'goc', r.goc, 'lai', r.lai)
        from kt_vay_tra r join kt_vay v on v.id = r.vay_id where not r.da_xoa and r.da_tra and r.tai_khoan_id = k.tk_id and r.ngay between a and b
      union all   -- 19/11: thanh toán trung gian trừ thẳng tài khoản (VIEC 391) — trước đây thiếu khi ghép sao kê
      select jsonb_build_object('k', 'tt', 'id', tt.id, 'ngay', tt.ngay, 'vao', 0, 'ra', kt_tt_nn_ra(tt), 'nd', 'Thanh toán trung gian' || coalesce(' · ' || tt.ben_nhan, '') || ' · ' || tt.so_tien_nt || ' ' || tt.tien_te, 'doi', tt.ben_nhan)
        from kt_tt_nn tt where not tt.da_xoa and tt.tk_id = k.tk_id and tt.ngay between a and b and kt_tt_nn_ra(tt) > 0
         and not exists (select 1 from kt_chi c where c.id = tt.chi_id and not c.da_xoa and c.trang_thai = 'da_tt')) z), '[]'));
end $function$
;
