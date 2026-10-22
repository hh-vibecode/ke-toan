-- 22/10/2026 (anh, chọn đề xuất): "tiền nộp két ghi theo NGÀY THỦ QUỸ NHẬN, để các ngày sau không bị lệch kiểu này nữa".
-- Lý do: phiếu nộp két doanh thu ngày 21/10 thủ quỹ nhận 22/10 nhưng mang ngày 21 → sổ sách két 21/10 cao hơn tiền thật lúc kiểm két tối 21/10.
-- Làm: thủ quỹ bấm "Đã nhận" phiếu điều chuyển vào két → ngày phiếu = ngày nhận (giờ VN), ngày cũ giữ ở ngay_goc; huỷ nhận → trả lại ngày cũ.
-- Mọi báo cáo / số dư đọc cột ngay nên tự theo. Kỳ đã khoá sổ (trigger kt_tg_khoa_ky chặn) thì giữ nguyên ngày. — Monsieur Claude
alter table kt_dieu_chuyen add column if not exists ngay_goc date;

create or replace function public.kt_tq_nhan(p_phien text, p_bang text, p_id bigint, p_huy boolean DEFAULT false) returns void language plpgsql security definer set search_path to 'public' as $function$
declare u kt_nguoi_dung; v_tk int; v_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  if not kt_la_thu_quy(u) then raise exception 'Thủ quỹ xác nhận đã nhận tiền' using errcode = '42501'; end if;
  if p_bang = 'thu' then select tai_khoan_id into v_tk from kt_thu where id = p_id and not da_xoa;
  elsif p_bang = 'dieu_chuyen' then select tk_nhan_id into v_tk from kt_dieu_chuyen where id = p_id and not da_xoa;
  else raise exception 'Bảng không hợp lệ'; end if;
  if v_tk is null or not exists (select 1 from kt_tai_khoan where id = v_tk and loai = 'tien_mat' and thu_quy_chi) then raise exception 'Chỉ xác nhận tiền vào két'; end if;
  if p_bang = 'thu' then update kt_thu set tq_nhan_luc = case when p_huy then null else now() end, tq_nhan_boi = case when p_huy then null else u.ho_ten end where id = p_id;
  else update kt_dieu_chuyen set tq_nhan_luc = case when p_huy then null else now() end, tq_nhan_boi = case when p_huy then null else u.ho_ten end,
      da_xac_nhan = not p_huy, xac_nhan_boi = case when p_huy then null else u.ho_ten end, xac_nhan_luc = case when p_huy then null else now() end where id = p_id;   -- 20/10: thủ quỹ nhận = xác nhận điều chuyển vào két
    -- 22/10 anh: tiền vào két tính theo ngày thủ quỹ nhận
    begin
      if p_huy then update kt_dieu_chuyen set ngay = ngay_goc, ngay_goc = null where id = p_id and ngay_goc is not null;
      else update kt_dieu_chuyen set ngay_goc = coalesce(ngay_goc, ngay), ngay = v_nay where id = p_id and ngay < v_nay; end if;
    exception when others then null;   -- kỳ đã khoá sổ: giữ ngày cũ
    end;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, case when p_huy then 'huy_tq_nhan' else 'tq_nhan' end, null);
end $function$;

-- phiếu đã nhận trước khi có quy tắc: chuyển sang ngày nhận (4 phiếu 19–22/10)
update kt_dieu_chuyen set ngay_goc = ngay, ngay = (tq_nhan_luc at time zone 'Asia/Ho_Chi_Minh')::date, sua_luc = now(), sua_boi = 'Hệ thống (nộp két theo ngày nhận — anh 22/10)'
 where tq_nhan_luc is not null and not da_xoa and ngay_goc is null and (tq_nhan_luc at time zone 'Asia/Ho_Chi_Minh')::date > ngay;
