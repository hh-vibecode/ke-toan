-- 22/10/2026 (kế toán, anh chuyển): "phiếu đề nghị thanh toán bỏ phần hạch toán, bỏ đơn vị chịu CP, bỏ tháng hạch toán — chỉ khai có hoá đơn đỏ hay không và xuất về đâu;
-- kế toán chọn hạch toán / không hạch toán ở bước xác nhận; loại chi xuống dưới phân bổ chi phí đơn vị; nút Hạch toán vào chi phí P&L / Không hạch toán / Khoản chi cá nhân;
-- hạch toán → 9 loại chi phí; không hạch toán → 1. Chi thanh toán tiền hàng 2. Chi đặt cọc". — Monsieur Claude
-- loại chi KHÔNG hạch toán: dùng lại loại cũ id 5 (COGS - nhập hàng, 316 phiếu cũ) đổi tên + thêm Chi đặt cọc (nhóm báo cáo dòng tiền: Chi nhập hàng)
update kt_loai set ten = 'Chi thanh toán tiền hàng', hoat_dong = true, thu_tu = 1 where id = 5;
insert into kt_loai (nhom, ten, nhom_bc, thu_tu, hoat_dong) select 'chi', 'Chi đặt cọc', 'Chi nhập hàng', 2, true
  where not exists (select 1 from kt_loai where nhom = 'chi' and ten = 'Chi đặt cọc');

CREATE OR REPLACE FUNCTION public.kt_gui_de_nghi(p_dong jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_ip text := kt_ip_goi(); v_nguoi text := btrim(regexp_replace(coalesce(p_dong->>'nguoi_de_nghi', ''), '\s+', ' ', 'g'));
  v_nd text := btrim(coalesce(p_dong->>'noi_dung', '')); v_tien numeric; v_sd date; v_han date; v_bp int; v_ck boolean;
  v_th text := btrim(coalesce(p_dong->>'thu_huong_ten', '')); v_nh text := btrim(coalesce(p_dong->>'thu_huong_nh', ''));
  v_stk text := regexp_replace(coalesce(p_dong->>'thu_huong_stk', ''), '[\s.\-]', '', 'g'); v_gc text := nullif(btrim(coalesce(p_dong->>'ghi_chu', '')), '');
  v_pb jsonb := coalesce(p_dong->'phan_bo', '[]'::jsonb); v_tong numeric; v_hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_id bigint; v_ma text; v_cu bigint; v_tom text;
  v_loai text := case when p_dong->>'loai_dn' in ('tam_ung', 'hoan_ung') then p_dong->>'loai_dn' when coalesce(p_dong->>'la_tam_ung', '') = 'true' then 'tam_ung' else 'thanh_toan' end;
  v_tu boolean := v_loai = 'tam_ung'; v_du numeric; v_hdve text := nullif(p_dong->>'hd_ve', '');
begin
  if coalesce(p_dong->>'web', '') <> '' then raise exception 'Không gửi được phiếu'; end if;   -- ô bẫy máy tự điền
  -- chống gửi ồ ạt
  if (select count(*) from kt_chi_phieu where ip = v_ip and tao_luc > now() - interval '1 hour') >= 10 then
    raise exception 'Máy này đã gửi 10 phiếu trong 1 giờ — đợi một lúc rồi gửi tiếp, hoặc báo kế toán'; end if;
  if (select count(*) from kt_chi_phieu where tao_luc > now() - interval '1 hour') >= 60 then
    raise exception 'Hệ thống đang nhận quá nhiều phiếu — thử lại sau ít phút'; end if;
  -- kiểm từng ô
  if length(v_nguoi) < 2 or length(v_nguoi) > 80 then raise exception 'Nhập họ và tên người đề nghị'; end if;
  v_bp := nullif(p_dong->>'bo_phan_id', '')::int;
  if v_bp is null or not exists (select 1 from kt_don_vi where id = v_bp and hoat_dong and la_bo_phan) then raise exception 'Chọn bộ phận'; end if;
  if length(v_nd) < 5 then raise exception 'Nhập nội dung chi (hạng mục, lý do)'; end if;
  if length(v_nd) > 1000 then raise exception 'Nội dung chi tối đa 1.000 ký tự'; end if;
  begin v_tien := (p_dong->>'so_tien')::numeric; exception when others then v_tien := null; end;
  if v_tien is null or v_tien < 1000 or v_tien > 100000000000 or v_tien <> round(v_tien) then raise exception 'Số tiền không hợp lệ (từ 1.000 đ, số nguyên)'; end if;
  begin v_sd := (p_dong->>'ngay_su_dung')::date; exception when others then v_sd := null; end;
  if v_sd is null then raise exception 'Nhập ngày sử dụng dịch vụ / nhận hàng'; end if;
  if v_sd < v_hom - 400 or v_sd > v_hom + 365 then raise exception 'Ngày sử dụng dịch vụ không hợp lệ'; end if;
  begin v_han := nullif(p_dong->>'han_tt', '')::date; exception when others then raise exception 'Ngày mong muốn thanh toán không hợp lệ'; end;
  if v_han is not null and (v_han < v_hom - 1 or v_han > v_hom + 365) then raise exception 'Ngày mong muốn thanh toán phải từ hôm nay trở đi'; end if;
  if v_loai = 'hoan_ung' and length(v_th) < 2 then v_th := v_nguoi; end if;   -- hoàn ứng: không nhận tiền qua phiếu này
  if length(v_th) < 2 or length(v_th) > 150 then raise exception 'Nhập tên người / đơn vị thụ hưởng'; end if;
  v_ck := coalesce(p_dong->>'hinh_thuc', 'ck') <> 'tien_mat' and v_loai <> 'hoan_ung';
  if v_ck then
    if length(v_nh) < 2 or length(v_nh) > 100 then raise exception 'Nhập ngân hàng thụ hưởng'; end if;
    if v_stk !~ '^[0-9A-Za-z]{4,25}$' then raise exception 'Số tài khoản thụ hưởng không hợp lệ'; end if;
  else v_nh := 'Tiền mặt'; v_stk := null; end if;
  if v_tu or v_loai = 'hoan_ung' then p_dong := p_dong || jsonb_build_object('co_hd_do', coalesce(p_dong->>'co_hd_do', 'false')); end if;   -- tạm ứng: hoá đơn nộp khi hoàn ứng
  if p_dong->>'co_hd_do' is null or p_dong->>'co_hd_do' not in ('true', 'false') then raise exception 'Chọn có / không có hoá đơn đỏ'; end if;
  -- 16/10/2026 (kế toán): có hoá đơn thì chọn hoá đơn xuất về Công ty hay hộ kinh doanh nào
  -- anh 16/10: áp dụng mọi hoá đơn (đỏ hoặc trắng), không chỉ hoá đơn đỏ; tạm ứng chọn sau khi hoàn ứng
  if v_loai = 'thanh_toan' and coalesce(v_hdve, '') not in ('cong_ty', 'hkd_ht', 'hkd_ct') then
    raise exception 'Chọn hoá đơn xuất về: Công ty / HKD Hiền Thủy / HKD Chánh Tâm'; end if;
  if v_hdve is not null and v_hdve not in ('cong_ty', 'hkd_ht', 'hkd_ct') then v_hdve := null; end if;
  if v_loai = 'hoan_ung' then
    begin v_du := (p_dong->>'tu_da_ung')::numeric; exception when others then v_du := null; end;
    if v_du is not null and (v_du <= 0 or v_du <> round(v_du)) then v_du := null; end if;   -- hoàn ứng: số đã ứng chỉ để kế toán dò, không bắt buộc
  end if;
  if length(coalesce(v_gc, '')) > 500 then raise exception 'Ghi chú tối đa 500 ký tự'; end if;
  -- đơn vị chịu chi phí: 1–6 đơn vị đang dùng, không trùng, tổng = số tiền
  if jsonb_typeof(v_pb) <> 'array' then v_pb := '[]'::jsonb; end if;   -- 22/10 kế toán: người đề nghị không khai đơn vị chịu chi phí nữa (kế toán phân bổ khi xác nhận)
  if jsonb_array_length(v_pb) > 6 then raise exception 'Tối đa 6 đơn vị chịu chi phí'; end if;
  if exists (select 1 from jsonb_array_elements(v_pb) x where not exists (select 1 from kt_don_vi d where d.id = (x->>'don_vi_id')::int and d.hoat_dong and d.la_co_so)
             or (x->>'so_tien')::numeric <= 0 or (x->>'so_tien')::numeric <> round((x->>'so_tien')::numeric)) then
    raise exception 'Đơn vị chịu chi phí không hợp lệ'; end if;
  if (select count(distinct x->>'don_vi_id') from jsonb_array_elements(v_pb) x) <> jsonb_array_length(v_pb) then raise exception 'Đơn vị chịu chi phí bị chọn trùng'; end if;
  select sum((x->>'so_tien')::numeric) into v_tong from jsonb_array_elements(v_pb) x;
  if jsonb_array_length(v_pb) > 0 and v_tong <> v_tien then raise exception 'Tổng tiền chia cho các đơn vị (%) phải bằng số tiền đề nghị (%)', v_tong, v_tien; end if;
  v_pb := (select coalesce(jsonb_agg(jsonb_build_object('don_vi_id', (x->>'don_vi_id')::int, 'so_tien', (x->>'so_tien')::numeric)), '[]') from jsonb_array_elements(v_pb) x);
  -- bấm gửi 2 lần
  select c.id into v_cu from kt_chi c join kt_chi_phieu p on p.chi_id = c.id
   where not c.da_xoa and lower(c.nguoi_de_nghi) = lower(v_nguoi) and c.so_tien = v_tien and lower(c.noi_dung) = lower(v_nd) and p.tao_luc > now() - interval '30 minutes' limit 1;
  if v_cu is not null then raise exception 'Phiếu này vừa được gửi (mã #%) — không gửi lại', v_cu; end if;

  insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, thu_huong_nh, thu_huong_stk,
    phan_bo, han_tt, co_hd_do, ghi_chu, trang_thai, nguon, tao_boi, hd_ve, la_tam_ung, loai_dn, tu_da_ung, noi_dung_ck)
  values (v_hom, v_nguoi, v_bp, v_nd, v_sd, v_tien, v_th, v_nh, nullif(v_stk, ''), v_pb, v_han, (p_dong->>'co_hd_do')::boolean, v_gc,
    'cho_duyet', 'phieu', 'Phiếu đề nghị', v_hdve, v_tu, v_loai, v_du, case when v_ck then nullif(left(btrim(coalesce(p_dong->>'noi_dung_ck', '')), 50), '') end)
  returning id into v_id;
  v_ma := encode(gen_random_bytes(18), 'hex');
  insert into kt_chi_phieu (chi_id, ma_hash, ip) values (v_id, encode(digest(v_ma, 'sha256'), 'hex'), v_ip);
  perform kt_ghi_nhat_ky('Phiếu đề nghị: ' || v_nguoi, 'kt_chi', v_id, 'them', (p_dong - 'web') || jsonb_build_object('nguon', 'phieu'));
  v_tom := left(v_nd, 120) || ' · ' || replace(to_char(v_tien, 'FM999G999G999G999'), ',', '.') || ' đ';
  perform kt_bao(kt_ai_ke_toan(null), v_nguoi, 'chi_moi', case when v_tu then 'Phiếu đề nghị TẠM ỨNG mới — chờ kế toán kiểm' when v_loai = 'hoan_ung' then 'Phiếu HOÀN ỨNG (trả lại tiền tạm ứng) — chờ kế toán xác nhận tiền về' else 'Phiếu đề nghị thanh toán mới — chờ kế toán kiểm' end, v_tom, 'chi', v_id);
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $function$;
