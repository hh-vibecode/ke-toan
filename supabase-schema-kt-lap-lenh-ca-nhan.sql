-- 20/10/2026 chiều (anh + kế toán) — Monsieur Claude
-- 1) Nội dung chuyển khoản do người làm phiếu điền (kt_chi.noi_dung_ck) — gài vào mã QR
-- 2) Thủ quỹ "Đã lập lệnh" (tài khoản ngân hàng) → người duyệt lệnh "Đã duyệt lệnh" mới tính là đã chi (ngày tiền đi = ngày duyệt lệnh)
-- 3) Thủ quỹ xác nhận đã nhận tiền với thu / điều chuyển vào két (tq_nhan_luc)
-- 4) Quyền chi_thang: kế toán tự chi không cần duyệt (báo giám đốc) — cấp trên trang Phân quyền
-- 5) Giao dịch cá nhân: phiếu thu không bắt buộc loại thu
-- 6) Sổ quỹ theo ngày: xem chi tiết từng khoản trong ngày (kt_so_quy_ngay)
alter table kt_chi add column if not exists noi_dung_ck text, add column if not exists lap_lenh_luc timestamptz, add column if not exists lap_lenh_boi text;
alter table kt_thu add column if not exists tq_nhan_luc timestamptz, add column if not exists tq_nhan_boi text;
alter table kt_dieu_chuyen add column if not exists tq_nhan_luc timestamptz, add column if not exists tq_nhan_boi text;
alter table kt_thu alter column loai_id drop not null;

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
  if jsonb_typeof(v_pb) <> 'array' or (jsonb_array_length(v_pb) = 0 and v_loai = 'thanh_toan') then raise exception 'Chọn đơn vị chịu chi phí'; end if;
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

CREATE OR REPLACE FUNCTION public.kt_luu_chi(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_cu kt_chi; v_moi kt_chi; v_tt text := p_dong->>'trang_thai';
  v_pb jsonb := coalesce(p_dong->'phan_bo', '[]'::jsonb); v_tong numeric;
  v_ghi boolean; v_duyet boolean; v_gd boolean; v_tu text; v_doi boolean; v_tom text; v_tq boolean; v_tqc boolean; v_thang boolean; v_tk int;
begin
  u := kt_chan(p_phien);
  v_ghi := kt_co_quyen(u, 'chi', true); v_duyet := kt_co_quyen(u, 'chi_duyet'); v_gd := kt_co_quyen(u, 'chi_gd'); v_tq := kt_co_quyen(u, 'chi_tt');
  v_thang := v_id is null and kt_co_quyen(u, 'chi_thang');   -- 20/10: kế toán tự chi (không cần duyệt) — phiếu cân tài khoản cuối ngày
  if not v_ghi and not v_tq and not kt_co_quyen(u, 'chi_de_nghi') then
    raise exception 'Tài khoản chưa được cấp quyền tạo đề nghị chi' using errcode = '42501';
  end if;
  if jsonb_array_length(v_pb) > 0 then
    select sum((x->>'so_tien')::numeric) into v_tong from jsonb_array_elements(v_pb) x;
    if v_tong <> (p_dong->>'so_tien')::numeric then
      raise exception 'Tổng phân bổ (%) khác số tiền chi (%)', v_tong, p_dong->>'so_tien';
    end if;
  end if;
  if v_id is not null then
    select * into v_cu from kt_chi where id = v_id and not da_xoa;
    if v_cu.id is null then raise exception 'Không tìm thấy phiếu chi %', v_id; end if;
    if not v_ghi and not (v_tq and v_cu.trang_thai in ('cho_tt','da_tt')) and (v_cu.tao_boi is distinct from u.ho_ten or v_cu.trang_thai <> 'cho_duyet') then
      raise exception 'Chỉ sửa được đề nghị của chính mình khi còn chờ duyệt' using errcode = '42501';
    end if;
    if v_cu.trang_thai in ('cho_tt','da_tt') and (p_dong->>'so_tien')::numeric <> v_cu.so_tien and not v_gd then
      raise exception 'Phiếu đã được giám đốc xác nhận — muốn đổi số tiền thì giám đốc trả lại để kiểm / xác nhận lại' using errcode = '42501';
    end if;
  end if;
  -- Chuyển trạng thái hợp lệ (kế toán kiểm lượt 1 → giám đốc xác nhận lượt 2 → kế toán thanh toán)
  v_tu := coalesce(v_cu.trang_thai, 'moi');
  v_doi := v_tt is not null and v_tt is distinct from v_cu.trang_thai;
  if v_doi and not (
       (v_tu = 'moi' and v_tt = 'cho_duyet')
    or (v_tu = 'moi' and v_tt = 'da_tt' and (v_duyet or v_thang))
    or (v_tu = 'cho_tt' and v_tt = 'da_tt' and (v_duyet or v_gd) and v_cu.lap_lenh_luc is not null)   -- 20/10: thủ quỹ lập lệnh → người duyệt lệnh bấm Đã duyệt lệnh
    or (v_tu = 'cho_duyet' and v_tt in ('cho_gd','tu_choi') and v_duyet)
    or (v_tu = 'cho_duyet' and v_tt = 'tu_choi' and v_gd)
    or (v_tu = 'cho_gd' and v_tt in ('cho_tt','tu_choi') and v_gd)
    or (v_tu = 'cho_duyet' and v_tt = 'cho_tt' and (v_gd or v_duyet))   -- 16/10: GĐ / kế toán xác nhận 1 bước + chọn TK đi tiền
    or (v_tu = 'cho_gd' and v_tt = 'cho_tt' and v_duyet)
    or (v_tu = 'cho_gd' and v_tt = 'cho_duyet' and (v_gd or v_duyet))
    or (v_tu = 'cho_tt' and v_tt = 'tu_choi_tt' and (v_duyet or v_gd))
    or (v_tu = 'cho_tt' and v_tt = 'da_tt' and (v_tq or v_gd))
    or (v_tu = 'da_tt' and v_tt = 'cho_tt' and (v_duyet or v_gd))
    or (v_tu = 'cho_tt' and v_tt = 'cho_duyet' and v_gd)                          -- 20/10: GĐ lùi về chờ xác nhận
    or (v_tu in ('tu_choi','tu_choi_tt') and v_tt = 'cho_duyet' and v_gd)         -- 20/10: GĐ mở lại phiếu bị từ chối   -- 20/10: huỷ "Đã chi tiền" (chi nhầm / chưa duyệt lệnh)
    or (v_tu in ('tu_choi','tu_choi_tt') and v_tt = 'cho_duyet' and v_duyet)) then
    raise exception 'Không chuyển được phiếu từ "%" sang "%" (luồng: kế toán kiểm → giám đốc xác nhận → kế toán thanh toán)',
      kt_ten_tt_chi(v_tu), kt_ten_tt_chi(v_tt) using errcode = '42501';
  end if;
  -- 20/10 (anh): đã được GĐ xác nhận mà đổi người nhận / ngân hàng / STK → phiếu về chờ GĐ xác nhận lại (GĐ tự đổi thì thôi)
  if v_cu.trang_thai = 'cho_tt' and v_ghi and not v_gd and (
       (p_dong ? 'thu_huong_stk' and nullif(trim(p_dong->>'thu_huong_stk'),'') is distinct from v_cu.thu_huong_stk)
    or (p_dong ? 'thu_huong_ten' and nullif(trim(p_dong->>'thu_huong_ten'),'') is distinct from v_cu.thu_huong_ten)
    or (p_dong ? 'thu_huong_nh' and nullif(trim(p_dong->>'thu_huong_nh'),'') is distinct from v_cu.thu_huong_nh)) then
    v_tt := 'cho_gd'; v_doi := true;
  end if;
  v_tk := case when v_duyet or v_gd or v_thang then coalesce((p_dong->>'tai_khoan_id')::int, v_cu.tai_khoan_id) else v_cu.tai_khoan_id end;
  if v_doi and v_tt = 'cho_tt' and v_tk is null then
    raise exception 'Chọn tài khoản đi tiền trước khi xác nhận' using errcode = '42501';
  end if;
  if v_doi and v_tu = 'cho_tt' and v_tt = 'da_tt' then
    select coalesce(thu_quy_chi, false) into v_tqc from kt_tai_khoan where id = v_tk;
    if v_tq and not v_duyet and not v_gd and (select loai from kt_tai_khoan where id = v_tk) = 'ngan_hang' then
      raise exception 'Tài khoản ngân hàng: lập lệnh xong bấm "Đã lập lệnh" — tiền tính là đã chi khi người duyệt lệnh bấm "Đã duyệt lệnh"' using errcode = '42501'; end if;
    if coalesce(v_tqc, false) and not v_tq and v_cu.lap_lenh_luc is null then raise exception 'Tài khoản công ty / két tiền mặt: thủ quỹ chi tiền và up ảnh giao dịch' using errcode = '42501'; end if;
    if not coalesce(v_tqc, false) and not v_gd then raise exception 'Tài khoản cá nhân: giám đốc chi tiền và up ảnh giao dịch' using errcode = '42501'; end if;
    if not exists (select 1 from kt_chung_tu k where k.bang = 'chi' and k.dong_id = v_id and not k.da_xoa and k.ten_file ilike 'UNC%')
       and coalesce(nullif(trim(p_dong->>'unc'), ''), v_cu.unc, '') = '' then
      raise exception 'Up ảnh giao dịch (uỷ nhiệm chi / phiếu chi tiền mặt) trước khi bấm Đã chi tiền';
    end if;
    if (select loai from kt_tai_khoan where id = v_tk) = 'tien_mat'
       and coalesce(nullif(trim(p_dong->>'nguoi_nhan_tien'), ''), v_cu.nguoi_nhan_tien) is null then
      raise exception 'Chi tiền mặt: ghi tên người đến nhận tiền';
    end if;
  end if;
  if v_duyet and p_dong->>'kiot' = 'khong_tao' and coalesce(trim(p_dong->>'kiot_ly_do'), '') = '' then
    raise exception 'Không tạo phiếu Kiot thì phải ghi lý do';
  end if;
  if v_id is null then
    insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, thu_huong_nh,
      thu_huong_stk, phan_bo, han_tt, co_hd_do, ghi_chu, chung_tu, tao_boi, khong_hach_toan, noi_dung_ck)
    values (coalesce((p_dong->>'ngay_de_nghi')::date, (now() at time zone 'Asia/Ho_Chi_Minh')::date),
      coalesce(nullif(trim(p_dong->>'nguoi_de_nghi'),''), u.ho_ten), (p_dong->>'bo_phan_id')::int, trim(p_dong->>'noi_dung'),
      (p_dong->>'ngay_su_dung')::date, (p_dong->>'so_tien')::numeric, nullif(trim(p_dong->>'thu_huong_ten'),''),
      nullif(trim(p_dong->>'thu_huong_nh'),''), nullif(trim(p_dong->>'thu_huong_stk'),''), v_pb, (p_dong->>'han_tt')::date,
      coalesce((p_dong->>'co_hd_do')::boolean,false), nullif(trim(p_dong->>'ghi_chu'),''),
      coalesce(array(select jsonb_array_elements_text(p_dong->'chung_tu')), '{}'), u.ho_ten, coalesce((p_dong->>'khong_hach_toan')::boolean, false), nullif(left(trim(p_dong->>'noi_dung_ck'), 50), ''))
    returning id into v_id;
    v_tt := coalesce(v_tt, 'cho_duyet'); v_doi := true;
  elsif v_ghi or (v_cu.tao_boi = u.ho_ten and v_cu.trang_thai = 'cho_duyet') then   -- 20/10: người tạo (vd thủ quỹ tự đề nghị) không sửa được nội dung / STK sau khi đã duyệt
    update kt_chi set ngay_de_nghi = coalesce((p_dong->>'ngay_de_nghi')::date, ngay_de_nghi),
      nguoi_de_nghi = coalesce(nullif(trim(p_dong->>'nguoi_de_nghi'),''), nguoi_de_nghi), bo_phan_id = (p_dong->>'bo_phan_id')::int,
      noi_dung = trim(p_dong->>'noi_dung'), ngay_su_dung = (p_dong->>'ngay_su_dung')::date, so_tien = (p_dong->>'so_tien')::numeric,
      thu_huong_ten = nullif(trim(p_dong->>'thu_huong_ten'),''), thu_huong_nh = nullif(trim(p_dong->>'thu_huong_nh'),''),
      thu_huong_stk = nullif(trim(p_dong->>'thu_huong_stk'),''), phan_bo = v_pb, han_tt = (p_dong->>'han_tt')::date,
      co_hd_do = coalesce((p_dong->>'co_hd_do')::boolean,false), ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''),
      chung_tu = coalesce(array(select jsonb_array_elements_text(p_dong->'chung_tu')), '{}'),
      noi_dung_ck = case when p_dong ? 'noi_dung_ck' then nullif(left(trim(p_dong->>'noi_dung_ck'), 50), '') else noi_dung_ck end,
      sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id;
  end if;
  if coalesce((p_dong->>'khong_hach_toan')::boolean, v_cu.khong_hach_toan, false) = false and coalesce(v_tt, v_cu.trang_thai) = 'da_tt'
     and coalesce((p_dong->>'loai_id')::int, v_cu.loai_id) is null then
    raise exception 'Phiếu đã chi tiền: bỏ "Không hạch toán chi phí" thì chọn loại chi';
  end if;
  update kt_chi set
    trang_thai   = case when v_doi then v_tt else trang_thai end,
    khong_hach_toan = case when v_ghi or (v_cu.tao_boi = u.ho_ten and coalesce(v_cu.trang_thai, 'cho_duyet') = 'cho_duyet') then coalesce((p_dong->>'khong_hach_toan')::boolean, khong_hach_toan) else khong_hach_toan end,
    lap_lenh_luc = case when v_doi and v_tt <> 'da_tt' then null else lap_lenh_luc end,
    lap_lenh_boi = case when v_doi and v_tt <> 'da_tt' then null else lap_lenh_boi end,
    kiem_boi     = case when v_doi and (v_tt = 'cho_gd' or (v_tt = 'cho_tt' and v_tu = 'cho_duyet')) then u.ho_ten when v_doi and v_tt = 'cho_duyet' then null else kiem_boi end,
    kiem_luc     = case when v_doi and (v_tt = 'cho_gd' or (v_tt = 'cho_tt' and v_tu = 'cho_duyet')) then now() when v_doi and v_tt = 'cho_duyet' then null else kiem_luc end,
    nguoi_duyet  = case when v_doi and (v_tt in ('cho_tt','tu_choi') or (v_tt = 'da_tt' and v_tu = 'moi')) then u.ho_ten
                        when v_doi and (v_tt = 'cho_duyet' or (v_tt = 'cho_gd' and v_tu = 'cho_tt')) then null else nguoi_duyet end,
    duyet_luc    = case when v_doi and (v_tt in ('cho_tt','tu_choi') or (v_tt = 'da_tt' and v_tu = 'moi')) then now()
                        when v_doi and (v_tt = 'cho_duyet' or (v_tt = 'cho_gd' and v_tu = 'cho_tt')) then null else duyet_luc end,
    ngay_tt      = case when v_duyet or v_gd or v_tq or v_thang then coalesce((p_dong->>'ngay_tt')::date, case when v_tt = 'da_tt' then ngay_tt end) else ngay_tt end,
    tai_khoan_id = case when v_duyet or v_gd or v_thang then coalesce((p_dong->>'tai_khoan_id')::int, tai_khoan_id) else tai_khoan_id end,
    loai_id      = case when v_duyet or v_gd or v_tq or v_thang then coalesce((p_dong->>'loai_id')::int, loai_id) else loai_id end,
    nguoi_nhan_tien = case when v_duyet or v_gd or v_tq or v_thang then coalesce(nullif(trim(p_dong->>'nguoi_nhan_tien'), ''), nguoi_nhan_tien) else nguoi_nhan_tien end,
    unc          = case when v_duyet or v_gd or v_tq or v_thang then coalesce(nullif(trim(p_dong->>'unc'),''), unc) else unc end,
    kiot         = case when v_duyet then coalesce(p_dong->>'kiot', kiot) else kiot end,
    kiot_ly_do   = case when v_duyet then coalesce(nullif(trim(p_dong->>'kiot_ly_do'),''), kiot_ly_do) else kiot_ly_do end,
    hd_do_nhan   = case when v_ghi then coalesce((p_dong->>'hd_do_nhan')::boolean, hd_do_nhan) else hd_do_nhan end,
    ngay_nhan_hd = case when v_ghi then coalesce((p_dong->>'ngay_nhan_hd')::date, ngay_nhan_hd) else ngay_nhan_hd end
   where id = v_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', v_id, case when (p_dong->>'id') is null then 'them' else coalesce('trang_thai:' || v_tt, 'sua') end, p_dong);
  -- Thông báo theo bước
  select * into v_moi from kt_chi where id = v_id;
  if v_doi then
    v_tom := left(v_moi.noi_dung, 120) || ' · ' || replace(to_char(v_moi.so_tien, 'FM999G999G999G999'), ',', '.') || ' đ';
    if v_moi.trang_thai = 'cho_duyet' then
      perform kt_bao(kt_ai_ke_toan(u.id), u.ho_ten, 'chi_moi',
        case v_tu when 'moi' then 'Đề nghị chi mới — chờ kế toán kiểm' when 'cho_gd' then 'Giám đốc trả lại phiếu chi — kiểm lại'
          else 'Phiếu chi mở lại — chờ kế toán kiểm' end, v_tom, 'chi', v_id);
    elsif v_moi.trang_thai = 'cho_gd' then
      perform kt_bao(kt_ai_giam_doc(u.id), u.ho_ten, 'chi_cho_gd', case when v_tu = 'cho_tt' then 'Đổi người nhận / STK sau khi đã xác nhận — giám đốc xác nhận lại' else 'Kế toán đã kiểm — chờ giám đốc xác nhận' end, v_tom, 'chi', v_id);
    elsif v_moi.trang_thai = 'cho_tt' then
      if coalesce((select thu_quy_chi from kt_tai_khoan where id = v_moi.tai_khoan_id), false) then
        perform kt_bao(array(select id from kt_nguoi_dung where hoat_dong and 'chi_tt' = any(quyen) and id <> u.id), u.ho_ten, 'chi_cho_tt', 'Đã xác nhận — thủ quỹ chi tiền', v_tom, 'chi', v_id);
      else
        perform kt_bao(kt_ai_giam_doc(u.id), u.ho_ten, 'chi_cho_tt', 'Đã xác nhận — giám đốc chi từ tài khoản cá nhân', v_tom, 'chi', v_id);
      end if;
      perform kt_bao(array(select unnest(kt_ai_ten(array[v_moi.tao_boi], u.id)) except select unnest(kt_ai_ke_toan(u.id))), u.ho_ten, 'chi_duyet', 'Đề nghị chi của anh/chị đã được duyệt', v_tom, 'chi', v_id);
    elsif v_moi.trang_thai = 'da_tt' and v_tu = 'moi' and v_thang and not v_duyet then
      perform kt_bao(kt_ai_giam_doc(u.id), u.ho_ten, 'chi_tu_chi', 'Kế toán tự chi (không qua duyệt) — giám đốc xem lại', v_tom, 'chi', v_id);
    elsif v_moi.trang_thai = 'da_tt' and v_tu <> 'moi' then
      perform kt_bao(kt_ai_ten(array[v_moi.tao_boi], u.id), u.ho_ten, 'chi_da_tt', 'Phiếu chi đã thanh toán', v_tom, 'chi', v_id);
    elsif v_moi.trang_thai in ('tu_choi','tu_choi_tt') then
      perform kt_bao(kt_ai_ten(array[v_moi.tao_boi, v_cu.kiem_boi], u.id), u.ho_ten, 'chi_tu_choi',
        case when v_moi.trang_thai = 'tu_choi' then 'Đề nghị chi bị từ chối' else 'Phiếu chi bị từ chối thanh toán' end, v_tom, 'chi', v_id);
    end if;
  end if;
  return v_id;
end $function$;

create or replace function kt_lap_lenh(p_phien text, p_id bigint, p_huy boolean default false) returns void
 language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; v_tom text;
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi'; end if;
  if c.trang_thai <> 'cho_tt' then raise exception 'Phiếu không ở bước Chờ chi tiền'; end if;
  if p_huy then
    if not (kt_co_quyen(u, 'chi_tt') or kt_co_quyen(u, 'chi_duyet') or kt_co_quyen(u, 'chi_gd')) then raise exception 'Tài khoản không có quyền' using errcode = '42501'; end if;
    update kt_chi set lap_lenh_luc = null, lap_lenh_boi = null where id = p_id;
    perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'huy_lap_lenh', null);
    return;
  end if;
  if not kt_co_quyen(u, 'chi_tt') then raise exception 'Thủ quỹ bấm "Đã lập lệnh"' using errcode = '42501'; end if;
  if not exists (select 1 from kt_tai_khoan t where t.id = c.tai_khoan_id and t.loai = 'ngan_hang') then raise exception 'Chỉ dùng cho tài khoản ngân hàng — két tiền mặt bấm Đã chi tiền'; end if;
  if not exists (select 1 from kt_chung_tu k where k.bang = 'chi' and k.dong_id = p_id and not k.da_xoa and k.ten_file ilike 'UNC%') and coalesce(c.unc, '') = '' then
    raise exception 'Up ảnh lệnh chuyển tiền (uỷ nhiệm chi) trước khi bấm Đã lập lệnh'; end if;
  update kt_chi set lap_lenh_luc = now(), lap_lenh_boi = u.ho_ten where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'lap_lenh', null);
  v_tom := left(c.noi_dung, 120) || ' · ' || replace(to_char(c.so_tien, 'FM999G999G999G999'), ',', '.') || ' đ';
  perform kt_bao(kt_ai_ke_toan(u.id), u.ho_ten, 'chi_lap_lenh', 'Thủ quỹ đã lập lệnh — duyệt lệnh trên ngân hàng rồi bấm Đã duyệt lệnh', v_tom, 'chi', p_id);
end $$;
revoke all on function kt_lap_lenh(text, bigint, boolean) from public; grant execute on function kt_lap_lenh(text, bigint, boolean) to anon;

create or replace function kt_tq_nhan(p_phien text, p_bang text, p_id bigint, p_huy boolean default false) returns void
 language plpgsql security definer set search_path = public as $$
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
  else update kt_dieu_chuyen set tq_nhan_luc = case when p_huy then null else now() end, tq_nhan_boi = case when p_huy then null else u.ho_ten end where id = p_id; end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, case when p_huy then 'huy_tq_nhan' else 'tq_nhan' end, null);
end $$;
revoke all on function kt_tq_nhan(text, text, bigint, boolean) from public; grant execute on function kt_tq_nhan(text, text, bigint, boolean) to anon;

create or replace function kt_so_quy_ngay(p_phien text, p_tk int, p_ngay date) returns jsonb
 language plpgsql stable security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'tong_quan') or kt_co_quyen(u, 'dong_tien')) then raise exception 'Tài khoản chưa được cấp quyền xem dòng tiền' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'kieu', (x->>'id')::bigint) from (
    select jsonb_build_object('kieu', 'thu', 'id', t.id, 'nd', t.noi_dung, 'vao', t.so_tien, 'ra', 0, 'ca_nhan', t.khong_hach_toan) x
      from kt_thu t where not t.da_xoa and t.trang_thai = 'da_duyet' and t.tai_khoan_id = p_tk and t.ngay = p_ngay and not kt_an_thu(u, t.noi_dung)
    union all select jsonb_build_object('kieu', 'chi', 'id', c.id, 'nd', c.noi_dung, 'vao', 0, 'ra', c.so_tien, 'ca_nhan', c.khong_hach_toan, 'doi', c.thu_huong_ten)
      from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.tai_khoan_id = p_tk and c.ngay_tt = p_ngay and not kt_an_thu(u, c.noi_dung)
    union all select jsonb_build_object('kieu', 'dc', 'id', d.id, 'nd', d.noi_dung, 'vao', 0, 'ra', d.so_tien, 'ca_nhan', d.khong_hach_toan, 'doi', 'sang ' || (select ten from kt_tai_khoan where id = d.tk_nhan_id))
      from kt_dieu_chuyen d where not d.da_xoa and d.tk_di_id = p_tk and d.ngay = p_ngay and not kt_an_thu(u, d.noi_dung)
    union all select jsonb_build_object('kieu', 'dc', 'id', d.id, 'nd', d.noi_dung, 'vao', d.so_tien, 'ra', 0, 'ca_nhan', d.khong_hach_toan, 'doi', 'từ ' || (select ten from kt_tai_khoan where id = d.tk_di_id))
      from kt_dieu_chuyen d where not d.da_xoa and d.tk_nhan_id = p_tk and d.ngay = p_ngay and not kt_an_thu(u, d.noi_dung)
    union all select jsonb_build_object('kieu', 'vay', 'id', n.id, 'nd', 'Nhận tiền vay · ' || v.ten, 'vao', n.so_tien, 'ra', 0)
      from kt_vay_nhan n join kt_vay v on v.id = n.vay_id where not n.da_xoa and n.tai_khoan_id = p_tk and n.ngay = p_ngay
    union all select jsonb_build_object('kieu', 'vay', 'id', r.id, 'nd', 'Trả nợ vay · ' || v.ten, 'vao', 0, 'ra', r.goc + r.lai)
      from kt_vay_tra r join kt_vay v on v.id = r.vay_id where not r.da_xoa and r.da_tra and r.tai_khoan_id = p_tk and r.ngay = p_ngay) s), '[]');
end $$;
revoke all on function kt_so_quy_ngay(text, int, date) from public; grant execute on function kt_so_quy_ngay(text, int, date) to anon;
