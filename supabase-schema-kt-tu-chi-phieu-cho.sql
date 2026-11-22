-- 21/10/2026 (kế toán): quyền tự chi (chi_thang) bấm "Đã thanh toán luôn" cả với phiếu mình tạo còn chờ duyệt. Monsieur Claude
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
    -- 21/10 kế toán: phiếu tự tạo còn chờ duyệt cũng bấm được "Đã thanh toán luôn"
    v_thang := kt_co_quyen(u, 'chi_thang') and v_cu.tao_boi = u.ho_ten and v_cu.trang_thai in ('cho_duyet','cho_gd');
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
    or (v_tu in ('cho_duyet','cho_gd') and v_tt = 'da_tt' and v_thang)
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
    nguoi_duyet  = case when v_doi and (v_tt in ('cho_tt','tu_choi') or (v_tt = 'da_tt' and (v_tu = 'moi' or v_thang))) then u.ho_ten
                        when v_doi and (v_tt = 'cho_duyet' or (v_tt = 'cho_gd' and v_tu = 'cho_tt')) then null else nguoi_duyet end,
    duyet_luc    = case when v_doi and (v_tt in ('cho_tt','tu_choi') or (v_tt = 'da_tt' and (v_tu = 'moi' or v_thang))) then now()
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
    elsif v_moi.trang_thai = 'da_tt' and v_thang and not v_duyet then
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
