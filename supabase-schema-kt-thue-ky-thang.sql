-- 03/11/2026 kế toán: kho THT cập nhật file NXT hằng tháng → kỳ sổ thuế Công ty THT theo tháng (YYYY-MM); 2 hộ giữ theo quý. — Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_nap_ton_thue(p_phien text, p_hkd text, p_ngay_chot date, p_ten_file text, p_ds jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_ky text := case when p_hkd = 'CTY' then to_char(p_ngay_chot, 'YYYY-MM') else to_char(p_ngay_chot, 'YYYY-"Q"Q') end; r jsonb;
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  if p_hkd not in ('CTY', 'CT', 'HT') then raise exception 'Đơn vị không hợp lệ'; end if;
  if p_ngay_chot is null or jsonb_typeof(p_ds) <> 'array' or jsonb_array_length(p_ds) = 0 then raise exception 'Thiếu ngày chốt hoặc file không có dòng nào'; end if;
  if exists (select 1 from kt_thue_khoa where hkd = p_hkd and ky = v_ky) then raise exception 'Kỳ % đã khoá — nhờ quản trị mở khoá trước khi nạp lại', v_ky; end if;
  delete from kt_thue_xnt where hkd = p_hkd and ky = v_ky;
  insert into kt_thue_xnt (hkd, ky, ma, ten, chung_loai, dvt, gia_nhap, dau_sl, dau_tien, nhap_sl, nhap_tien, xuat_sl, xuat_tien, cuoi_sl, cuoi_tien, nguon)
  select p_hkd, v_ky, ma, max(ten), max(nhom), max(dvt), max(gia), sum(dau_sl), sum(dau_tien), sum(nhap_sl), sum(nhap_tien), sum(xuat_sl), sum(xuat_tien), sum(sl), sum(gt),
         left('app:' || coalesce(p_ten_file, 'file'), 200)
    from (select trim(x->>'ma') ma, nullif(trim(x->>'ten'), '') ten, nullif(trim(x->>'nhom'), '') nhom, nullif(trim(x->>'dvt'), '') dvt,
                 (x->>'gia')::numeric gia, coalesce((x->>'sl')::numeric, 0) sl, coalesce((x->>'gt')::numeric, 0) gt,
                 coalesce((x->>'dau_sl')::numeric, 0) dau_sl, coalesce((x->>'dau_tien')::numeric, 0) dau_tien, coalesce((x->>'nhap_sl')::numeric, 0) nhap_sl,
                 coalesce((x->>'nhap_tien')::numeric, 0) nhap_tien, coalesce((x->>'xuat_sl')::numeric, 0) xuat_sl, coalesce((x->>'xuat_tien')::numeric, 0) xuat_tien
            from jsonb_array_elements(p_ds) x where coalesce(trim(x->>'ma'), '') <> '') t
   group by ma;
  select jsonb_build_object('ky', v_ky, 'so_ma', count(*), 'tong_sl', coalesce(sum(cuoi_sl), 0), 'tong_gt', coalesce(sum(cuoi_tien), 0)) into r
    from kt_thue_xnt where hkd = p_hkd and ky = v_ky;
  insert into kt_thue_nap (hkd, ky, ngay_chot, ten_file, so_ma, tong_sl, tong_gt, nap_boi)
  values (p_hkd, v_ky, p_ngay_chot, p_ten_file, (r->>'so_ma')::int, (r->>'tong_sl')::numeric, (r->>'tong_gt')::numeric, u.ho_ten);
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_thue_xnt', 'nap_ton_thue', r || jsonb_build_object('hkd', p_hkd, 'file', p_ten_file, 'ngay_chot', p_ngay_chot));
  return r;
end $function$;
