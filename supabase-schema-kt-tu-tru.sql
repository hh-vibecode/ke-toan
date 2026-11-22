-- ════════════════════════════════════════════════════════════════════════════
-- KHOẢN TÀI KHOẢN TỰ TRỪ (21/10/2026, kế toán qua anh): "một số phiếu là phí vận chuyển qua đơn vị vận chuyển hoặc phí ngân hàng, tài khoản tự trừ tiền,
-- admin phải làm bù phiếu chi, làm bù xong chị lại vào duyệt từ đầu, rồi bấm chi tiền, lại bắt up giao dịch trong khi tài khoản đã tự trừ rồi — làm lại luồng".
-- "Phí vận chuyển qua đơn vị COD: hoàn COD về là tự trừ phí vận chuyển — làm phiếu thu công nợ đủ tiền của khách, rồi 1 phiếu chi tính phí vận chuyển vào chi phí."
-- → Cờ kt_chi.tu_tru (giữ nguyên NGUỒN phiếu: app / sheet đề nghị / sheet cũ…):
--   · kt_chi_tu_tru: tạo khoản tự trừ trên app → ĐÃ THANH TOÁN ngay (tiền đã ra khỏi tài khoản), không kiểm / xác nhận / chi tiền, không bắt ảnh giao dịch.
--   · kt_danh_dau_tu_tru: đánh dấu phiếu có sẵn (vd đồng bộ từ sheet đề nghị, phiếu cũ đang "Thiếu ảnh giao dịch") là tự trừ — phiếu chưa chi thì ghi luôn Đã thanh toán
--     (cần TK bị trừ + loại chi + ngày); bỏ đánh dấu được (phiếu giữ trạng thái hiện tại).
--   · Tự trừ không vào "Thiếu ảnh giao dịch"; vẫn có loại chi + đơn vị chịu chi phí → vào chi phí / P&L như phiếu thường; chuông báo giám đốc.
-- Ai làm: tạo mới / đánh dấu phiếu ĐÃ CHI = người có quyền sửa Chi, kế toán xác nhận, giám đốc, "tự chi không cần duyệt".
--         Đánh dấu phiếu CHƯA CHI (bỏ qua duyệt) = kế toán xác nhận, giám đốc, "tự chi không cần duyệt". Thủ quỹ / nhân viên đề nghị: không.
-- Monsieur Claude
-- ════════════════════════════════════════════════════════════════════════════
alter table public.kt_chi drop constraint if exists kt_chi_nguon_check;   -- bản thử đầu thêm nguồn 'tu_tru' — bỏ, dùng cờ riêng
alter table public.kt_chi add constraint kt_chi_nguon_check check (nguon = any (array['app', 'sheet_cu', 'kiot', 'phieu']));
alter table public.kt_chi add column if not exists tu_tru boolean not null default false;

create or replace function public.kt_thieu_unc(c kt_chi) returns boolean language sql stable set search_path to 'public' as $$
  select c.trang_thai = 'da_tt' and not c.da_xoa and c.ngay_tt >= date '2026-09-01' and coalesce(trim(c.unc), '') = ''
     and not c.tu_tru   -- 21/10: tài khoản tự trừ — không có giao dịch để up
     and not exists (select 1 from kt_chung_tu k where k.bang = 'chi' and k.dong_id = c.id and not k.da_xoa and k.ten_file ilike 'UNC%');
$$;

create or replace function public.kt_quyen_tu_tru(u kt_nguoi_dung, p_bo_duyet boolean) returns boolean language sql stable set search_path to 'public' as $$
  select kt_co_quyen(u, 'chi_duyet') or kt_co_quyen(u, 'chi_gd') or kt_co_quyen(u, 'chi_thang') or (not p_bo_duyet and kt_co_quyen(u, 'chi', true));
$$;

create or replace function public.kt_chi_tu_tru(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint; v_tien numeric := (p_dong->>'so_tien')::numeric; v_ngay date := (p_dong->>'ngay')::date;
  v_tk int := (p_dong->>'tai_khoan_id')::int; v_loai int := (p_dong->>'loai_id')::int; v_pb jsonb := coalesce(p_dong->'phan_bo', '[]'::jsonb);
  v_hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; v_tom text;
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  if not kt_quyen_tu_tru(u, false) then raise exception 'Tài khoản chưa được cấp quyền ghi khoản tự trừ' using errcode = '42501'; end if;
  if v_tien is null or v_tien <= 0 then raise exception 'Số tiền phải lớn hơn 0'; end if;
  if v_ngay is null or v_ngay > v_hom then raise exception 'Ngày tài khoản bị trừ không hợp lệ (không được sau hôm nay)'; end if;
  if coalesce(trim(p_dong->>'noi_dung'), '') = '' then raise exception 'Ghi nội dung khoản bị trừ'; end if;
  if not exists (select 1 from kt_tai_khoan where id = v_tk and hoat_dong and loai <> 'tien_mat') then raise exception 'Chọn tài khoản bị trừ (ngân hàng / ví — két tiền mặt không tự trừ)'; end if;
  if v_loai is null or not exists (select 1 from kt_loai where id = v_loai and nhom = 'chi') then raise exception 'Chọn loại chi'; end if;
  if jsonb_array_length(v_pb) = 0 then raise exception 'Chọn đơn vị chịu chi phí'; end if;
  if (select sum((x->>'so_tien')::numeric) from jsonb_array_elements(v_pb) x) <> v_tien then raise exception 'Tổng phân bổ khác số tiền'; end if;
  insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, phan_bo, co_hd_do, ghi_chu,
      trang_thai, ngay_tt, tai_khoan_id, loai_id, kiot, nguon, tu_tru, tao_boi, nguoi_duyet, duyet_luc)
    values (v_ngay, u.ho_ten, trim(p_dong->>'noi_dung'), v_ngay, v_tien, nullif(trim(p_dong->>'thu_huong_ten'), ''), v_pb,
      coalesce((p_dong->>'co_hd_do')::boolean, false), nullif(trim(p_dong->>'ghi_chu'), ''),
      'da_tt', v_ngay, v_tk, v_loai, 'khong', 'app', true, u.ho_ten, u.ho_ten, now())
    returning id into v_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', v_id, 'them_tu_tru', p_dong);
  v_tom := left(trim(p_dong->>'noi_dung'), 120) || ' · ' || replace(to_char(v_tien, 'FM999G999G999G999'), ',', '.') || ' đ · '
    || coalesce((select ten from kt_tai_khoan where id = v_tk), '');
  perform kt_bao(kt_ai_giam_doc(u.id), u.ho_ten, 'chi_tu_tru', 'Tài khoản tự trừ đã ghi nhận', v_tom, 'chi', v_id);
  return v_id;
end $$;

-- đánh dấu / bỏ đánh dấu phiếu có sẵn. Phiếu chưa chi: ghi luôn Đã thanh toán với TK bị trừ + loại chi + ngày (lấy từ p_dong, thiếu thì lấy trên phiếu)
create or replace function public.kt_danh_dau_tu_tru(p_phien text, p_id bigint, p_dong jsonb default '{}'::jsonb, p_bo boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; v_tk int; v_loai int; v_ngay date; v_hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; v_tom text;
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi'; end if;
  if c.trang_thai in ('tu_choi', 'tu_choi_tt') then raise exception 'Phiếu đã bị từ chối — mở lại trước'; end if;
  if not kt_quyen_tu_tru(u, c.trang_thai <> 'da_tt') then
    raise exception '%', case when c.trang_thai <> 'da_tt' then 'Phiếu chưa chi: chỉ kế toán xác nhận / giám đốc / người được tự chi đánh dấu tự trừ (bỏ qua duyệt)'
      else 'Tài khoản chưa được cấp quyền đánh dấu tự trừ' end using errcode = '42501'; end if;
  if p_bo then
    update kt_chi set tu_tru = false, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
    perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'bo_tu_tru', null);
    return;
  end if;
  v_tk := coalesce((p_dong->>'tai_khoan_id')::int, c.tai_khoan_id); v_loai := coalesce((p_dong->>'loai_id')::int, c.loai_id);
  v_ngay := coalesce((p_dong->>'ngay')::date, c.ngay_tt, c.ngay_su_dung, c.ngay_de_nghi);
  if not exists (select 1 from kt_tai_khoan where id = v_tk and loai <> 'tien_mat') then raise exception 'Chọn tài khoản bị trừ (ngân hàng / ví — két tiền mặt không tự trừ)'; end if;
  if c.trang_thai <> 'da_tt' then
    if v_loai is null and not c.khong_hach_toan then raise exception 'Chọn loại chi'; end if;
    if v_ngay is null or v_ngay > v_hom then raise exception 'Ngày tài khoản bị trừ không hợp lệ'; end if;
    if not c.khong_hach_toan and jsonb_array_length(coalesce(c.phan_bo, '[]'::jsonb)) = 0 then raise exception 'Phiếu chưa có đơn vị chịu chi phí — sửa phiếu trước'; end if;
  end if;
  update kt_chi set tu_tru = true, tai_khoan_id = v_tk, loai_id = coalesce(v_loai, loai_id),
      trang_thai = 'da_tt', ngay_tt = case when trang_thai = 'da_tt' then ngay_tt else v_ngay end,
      nguoi_duyet = case when trang_thai = 'da_tt' then nguoi_duyet else u.ho_ten end, duyet_luc = case when trang_thai = 'da_tt' then duyet_luc else now() end,
      kiot = case when trang_thai = 'da_tt' then kiot else coalesce(kiot, 'khong') end, lap_lenh_luc = null, lap_lenh_boi = null,
      sua_boi = u.ho_ten, sua_luc = now()
   where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, case when c.trang_thai = 'da_tt' then 'danh_dau_tu_tru' else 'tu_tru_ghi_da_tt' end, p_dong);
  if c.trang_thai <> 'da_tt' then
    v_tom := left(c.noi_dung, 120) || ' · ' || replace(to_char(c.so_tien, 'FM999G999G999G999'), ',', '.') || ' đ';
    perform kt_bao(kt_ai_giam_doc(u.id), u.ho_ten, 'chi_tu_tru', 'Tài khoản tự trừ đã ghi nhận', v_tom, 'chi', p_id);
  end if;
end $$;
revoke execute on function public.kt_chi_tu_tru(text, jsonb), public.kt_danh_dau_tu_tru(text, bigint, jsonb, boolean) from public;
grant execute on function public.kt_chi_tu_tru(text, jsonb), public.kt_danh_dau_tu_tru(text, bigint, jsonb, boolean) to anon, authenticated;
