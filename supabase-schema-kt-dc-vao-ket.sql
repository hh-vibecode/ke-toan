-- 20/10/2026 (anh): điều chuyển vào két (quỹ cửa hàng → két) chỉ thủ quỹ xác nhận; thủ quỹ bấm Đã nhận tiền = xác nhận. Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_luu_dieu_chuyen(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_xn boolean := (p_dong->>'da_xac_nhan')::boolean;
  v_cu kt_dieu_chuyen; v_moi kt_dieu_chuyen; v_tom text;
begin
  u := kt_chan(p_phien, 'dieu_chuyen', true);
  if p_dong->>'kiot' = 'khong_tao' and coalesce(trim(p_dong->>'kiot_ly_do'), '') = '' then
    raise exception 'Không tạo phiếu Kiot thì phải ghi lý do';
  end if;
  if v_id is null then
    insert into kt_dieu_chuyen (ngay, noi_dung, so_tien, tk_di_id, tk_nhan_id, ghi_chu, kiot, kiot_ly_do, tao_boi, khong_hach_toan)
    values ((p_dong->>'ngay')::date, coalesce(nullif(trim(p_dong->>'noi_dung'),''), 'Điều chuyển giữa các tài khoản'),
      (p_dong->>'so_tien')::numeric, (p_dong->>'tk_di_id')::int, (p_dong->>'tk_nhan_id')::int, nullif(trim(p_dong->>'ghi_chu'),''),
      coalesce(p_dong->>'kiot','khong'), nullif(trim(p_dong->>'kiot_ly_do'),''), u.ho_ten, coalesce((p_dong->>'khong_hach_toan')::boolean, false)) returning id into v_id;
  else
    select * into v_cu from kt_dieu_chuyen where id = v_id and not da_xoa;
    update kt_dieu_chuyen set ngay = (p_dong->>'ngay')::date, noi_dung = coalesce(nullif(trim(p_dong->>'noi_dung'),''), noi_dung),
      so_tien = (p_dong->>'so_tien')::numeric, tk_di_id = (p_dong->>'tk_di_id')::int, tk_nhan_id = (p_dong->>'tk_nhan_id')::int,
      ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''), kiot = coalesce(p_dong->>'kiot', kiot),
      kiot_ly_do = nullif(trim(p_dong->>'kiot_ly_do'),''), khong_hach_toan = coalesce((p_dong->>'khong_hach_toan')::boolean, khong_hach_toan), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
  end if;
  -- 20/10 (anh): tiền vào KÉT (vd quỹ cửa hàng → két) chỉ thủ quỹ xác nhận (đã nhận tiền) — tài khoản admin kế toán không bấm được
  if v_xn is not null and v_xn is distinct from coalesce(v_cu.da_xac_nhan, false) and not kt_co_quyen(u, 'chi_tt')
     and exists (select 1 from kt_dieu_chuyen d join kt_tai_khoan t on t.id = d.tk_nhan_id where d.id = v_id and t.loai = 'tien_mat' and t.thu_quy_chi) then
    raise exception 'Tiền vào két: thủ quỹ bấm "Đã nhận tiền" để xác nhận' using errcode = '42501';
  end if;
  if v_xn is not null then
    update kt_dieu_chuyen set da_xac_nhan = v_xn, xac_nhan_boi = case when v_xn then u.ho_ten end,
      xac_nhan_luc = case when v_xn then now() end where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_dieu_chuyen', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  select * into v_moi from kt_dieu_chuyen where id = v_id;
  v_tom := replace(to_char(v_moi.so_tien, 'FM999G999G999G999'), ',', '.') || ' đ · ' || coalesce((select ten from kt_tai_khoan where id = v_moi.tk_di_id), '?')
    || ' → ' || coalesce((select ten from kt_tai_khoan where id = v_moi.tk_nhan_id), '?');
  if v_cu.id is null then
    perform kt_bao(kt_ai_co_quyen('dieu_chuyen', true, u.id), u.ho_ten, 'dc_moi', 'Điều chuyển mới cần xác nhận', v_tom, 'dieu_chuyen', v_id);
  elsif v_moi.da_xac_nhan and not v_cu.da_xac_nhan then
    perform kt_bao(kt_ai_ten(array[v_moi.tao_boi], u.id), u.ho_ten, 'dc_xac_nhan', 'Điều chuyển đã được kế toán xác nhận', v_tom, 'dieu_chuyen', v_id);
  end if;
  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.kt_tq_nhan(p_phien text, p_bang text, p_id bigint, p_huy boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_tk int;
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  if not kt_co_quyen(u, 'chi_tt') then raise exception 'Thủ quỹ xác nhận đã nhận tiền' using errcode = '42501'; end if;
  if p_bang = 'thu' then select tai_khoan_id into v_tk from kt_thu where id = p_id and not da_xoa;
  elsif p_bang = 'dieu_chuyen' then select tk_nhan_id into v_tk from kt_dieu_chuyen where id = p_id and not da_xoa;
  else raise exception 'Bảng không hợp lệ'; end if;
  if v_tk is null or not exists (select 1 from kt_tai_khoan where id = v_tk and loai = 'tien_mat' and thu_quy_chi) then raise exception 'Chỉ xác nhận tiền vào két'; end if;
  if p_bang = 'thu' then update kt_thu set tq_nhan_luc = case when p_huy then null else now() end, tq_nhan_boi = case when p_huy then null else u.ho_ten end where id = p_id;
  else update kt_dieu_chuyen set tq_nhan_luc = case when p_huy then null else now() end, tq_nhan_boi = case when p_huy then null else u.ho_ten end,
      da_xac_nhan = not p_huy, xac_nhan_boi = case when p_huy then null else u.ho_ten end, xac_nhan_luc = case when p_huy then null else now() end where id = p_id; end if;   -- 20/10: thủ quỹ nhận = xác nhận điều chuyển vào két
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, case when p_huy then 'huy_tq_nhan' else 'tq_nhan' end, null);
end $function$;
