-- LUỒNG CHI MỚI có THỦ QUỸ (16/10/2026, anh Hải) — Monsieur Claude
-- Người đề nghị → GIÁM ĐỐC hoặc KẾ TOÁN xác nhận (1 bước) + CHỌN TÀI KHOẢN ĐI TIỀN →
--   · KÉT TIỀN MẶT + 3 tài khoản CÔNG TY (VCB CTY ×2, VIB CTY) → THỦ QUỸ chi tiền, up ảnh giao dịch → Đã thanh toán
--   · tài khoản CÁ NHÂN (còn lại) → GIÁM ĐỐC chi tiền, up ảnh giao dịch → Đã thanh toán (y như bước thủ quỹ)
-- Chưa có ảnh giao dịch (tệp UNC_…) thì không chuyển Đã thanh toán.
-- Quyền mới `chi_tt` = thủ quỹ chi tiền + up ảnh (Admin / '*' có sẵn). Thủ quỹ CHỈ thấy phiếu đã xác nhận xong, còn bước chi tiền (và phiếu đã chi) của két / TK công ty; báo chuông khi có phiếu chờ chi. Tài khoản `thuquy` mật khẩu = mật khẩu tài khoản ketoan (chép mã băm).
-- Vá trên định nghĩa đang chạy (có phiên song song), không chép đè cả hàm.

-- 1. tài khoản tiền: cờ "thủ quỹ chi"
alter table public.kt_tai_khoan add column if not exists thu_quy_chi boolean not null default false;
update public.kt_tai_khoan set thu_quy_chi = (id in (1, 2, 3, 15));   -- VCB CTY, VCB CTY, VIB CTY, KÉT TIỀN MẶT (anh xác nhận 16/10)

-- 2. tài khoản Thủ quỹ (mật khẩu giống tài khoản kế toán)
insert into public.kt_nguoi_dung (ten_dang_nhap, ho_ten, vi_tri, quyen, mk_hash)
select 'thuquy', 'Thủ quỹ', 'nhan_vien', array['chi_tt']::text[], mk_hash from public.kt_nguoi_dung where ten_dang_nhap = 'ketoan'
on conflict (ten_dang_nhap) do nothing;

-- 3. chứng từ: thủ quỹ được xem / up ảnh cho phiếu đang chờ chi tiền hoặc đã thanh toán
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_chan_dong'::regproc); n := length(d);
  d := replace(d, $a$  if p_bang = 'chi' and kt_co_quyen(u, 'chi_de_nghi') and cardinality(p_ids) > 0$a$,
                  $a$  -- 16/10: thủ quỹ (chi_tt) — phiếu chờ chi tiền / đã thanh toán
  if p_bang = 'chi' and kt_co_quyen(u, 'chi_tt') and cardinality(p_ids) > 0
     and not exists (select 1 from unnest(p_ids) i where not exists (
       select 1 from kt_chi c join kt_tai_khoan t on t.id = c.tai_khoan_id where c.id = i and c.trang_thai in ('cho_tt','da_tt') and t.thu_quy_chi and not c.da_xoa)) then
    return u;
  end if;
  if p_bang = 'chi' and kt_co_quyen(u, 'chi_de_nghi') and cardinality(p_ids) > 0$a$);
  if length(d) = n then raise exception 'kt_chan_dong: khong thay cho'; end if;
  execute d;
end $$;

-- 3b. danh sách phiếu chi: thủ quỹ chỉ thấy phiếu chờ chi tiền / đã chi của két + TK công ty
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_ds'::regproc); n := length(d);
  d := replace(d, $a$    if not v_tat and not kt_co_quyen(u, 'chi_de_nghi') then$a$, $a$    if not v_tat and not kt_co_quyen(u, 'chi_de_nghi') and not kt_co_quyen(u, 'chi_tt') then$a$);
  d := replace(d, $a$      where not da_xoa and (v_tat or c.tao_boi = u.ho_ten) and ($a$,
                  $a$      where not da_xoa and (v_tat or c.tao_boi = u.ho_ten
          or (kt_co_quyen(u, 'chi_tt') and c.trang_thai in ('cho_tt','da_tt') and exists (select 1 from kt_tai_khoan t where t.id = c.tai_khoan_id and t.thu_quy_chi))) and ($a$);
  if length(d) - n < 150 then raise exception 'kt_ds: khong thay cho'; end if;
  execute d;
end $$;

-- 4. kt_luu_chi
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_luu_chi'::regproc);
  -- khai báo
  n := length(d);
  d := replace(d, $a$v_ghi boolean; v_duyet boolean; v_gd boolean; v_tu text; v_doi boolean; v_tom text;$a$,
                  $a$v_ghi boolean; v_duyet boolean; v_gd boolean; v_tu text; v_doi boolean; v_tom text; v_tq boolean; v_tqc boolean; v_tk int;$a$);
  d := replace(d, $a$v_gd := kt_co_quyen(u, 'chi_gd');$a$, $a$v_gd := kt_co_quyen(u, 'chi_gd'); v_tq := kt_co_quyen(u, 'chi_tt');$a$);
  if length(d) = n then raise exception 'kt_luu_chi: khai bao'; end if;
  -- thủ quỹ được gọi hàm (không tạo đề nghị)
  n := length(d);
  d := replace(d, $a$if not v_ghi and not kt_co_quyen(u, 'chi_de_nghi') then$a$, $a$if not v_ghi and not v_tq and not kt_co_quyen(u, 'chi_de_nghi') then$a$);
  d := replace(d, $a$if not v_ghi and (v_cu.tao_boi is distinct from u.ho_ten or v_cu.trang_thai <> 'cho_duyet') then$a$,
                  $a$if not v_ghi and not (v_tq and v_cu.trang_thai in ('cho_tt','da_tt')) and (v_cu.tao_boi is distinct from u.ho_ten or v_cu.trang_thai <> 'cho_duyet') then$a$);
  if length(d) = n then raise exception 'kt_luu_chi: quyen goi'; end if;
  -- thủ quỹ không sửa nội dung đề nghị (chỉ người có quyền ghi / người tạo)
  n := length(d);
  d := replace(d, $a$  else
    update kt_chi set ngay_de_nghi = coalesce((p_dong->>'ngay_de_nghi')::date, ngay_de_nghi),$a$,
                  $a$  elsif v_ghi or v_cu.tao_boi = u.ho_ten then
    update kt_chi set ngay_de_nghi = coalesce((p_dong->>'ngay_de_nghi')::date, ngay_de_nghi),$a$);
  if length(d) = n then raise exception 'kt_luu_chi: sua noi dung'; end if;
  -- chuyển trạng thái: xác nhận 1 bước (GĐ hoặc kế toán) → chờ chi tiền; chi tiền: thủ quỹ (TK công ty / két) hoặc GĐ (TK cá nhân)
  n := length(d);
  d := replace(d, $a$    or (v_tu = 'cho_duyet' and v_tt = 'cho_tt' and v_gd)   -- 16/10: giám đốc duyệt thẳng qua 2 bước$a$,
                  $a$    or (v_tu = 'cho_duyet' and v_tt = 'cho_tt' and (v_gd or v_duyet))   -- 16/10: GĐ / kế toán xác nhận 1 bước + chọn TK đi tiền
    or (v_tu = 'cho_gd' and v_tt = 'cho_tt' and v_duyet)$a$);
  d := replace(d, $a$    or (v_tu = 'cho_tt' and v_tt in ('da_tt','tu_choi_tt') and v_duyet)$a$,
                  $a$    or (v_tu = 'cho_tt' and v_tt = 'tu_choi_tt' and (v_duyet or v_gd))
    or (v_tu = 'cho_tt' and v_tt = 'da_tt' and (v_tq or v_gd))$a$);
  if length(d) = n then raise exception 'kt_luu_chi: chuyen trang thai'; end if;
  -- kiểm thêm: xác nhận phải có TK đi tiền; chi tiền đúng người theo loại TK + phải có ảnh giao dịch
  n := length(d);
  d := replace(d, $a$  if v_duyet and p_dong->>'kiot' = 'khong_tao'$a$,
                  $a$  v_tk := coalesce((p_dong->>'tai_khoan_id')::int, v_cu.tai_khoan_id);
  if v_doi and v_tt = 'cho_tt' and v_tk is null then
    raise exception 'Chọn tài khoản đi tiền trước khi xác nhận' using errcode = '42501';
  end if;
  if v_doi and v_tu = 'cho_tt' and v_tt = 'da_tt' then
    select coalesce(thu_quy_chi, false) into v_tqc from kt_tai_khoan where id = v_tk;
    if coalesce(v_tqc, false) and not v_tq then raise exception 'Tài khoản công ty / két tiền mặt: thủ quỹ chi tiền và up ảnh giao dịch' using errcode = '42501'; end if;
    if not coalesce(v_tqc, false) and not v_gd then raise exception 'Tài khoản cá nhân: giám đốc chi tiền và up ảnh giao dịch' using errcode = '42501'; end if;
    if not exists (select 1 from kt_chung_tu k where k.bang = 'chi' and k.dong_id = v_id and not k.da_xoa and k.ten_file ilike 'UNC%')
       and coalesce(nullif(trim(p_dong->>'unc'), ''), v_cu.unc, '') = '' then
      raise exception 'Up ảnh giao dịch (uỷ nhiệm chi / phiếu chi tiền mặt) trước khi bấm Đã chi tiền';
    end if;
  end if;
  if v_duyet and p_dong->>'kiot' = 'khong_tao'$a$);
  if length(d) = n then raise exception 'kt_luu_chi: kiem them'; end if;
  -- trường thanh toán: GĐ / thủ quỹ cũng ghi được (trước chỉ kế toán)
  n := length(d);
  d := replace(d, $a$ngay_tt      = case when v_duyet then$a$, $a$ngay_tt      = case when v_duyet or v_gd or v_tq then$a$);
  d := replace(d, $a$tai_khoan_id = case when v_duyet then$a$, $a$tai_khoan_id = case when v_duyet or v_gd or v_tq then$a$);
  d := replace(d, $a$loai_id      = case when v_duyet then$a$, $a$loai_id      = case when v_duyet or v_gd or v_tq then$a$);
  d := replace(d, $a$unc          = case when v_duyet then$a$, $a$unc          = case when v_duyet or v_gd or v_tq then$a$);
  if length(d) = n then raise exception 'kt_luu_chi: truong thanh toan'; end if;
  -- thông báo bước chờ chi tiền: thủ quỹ (TK công ty / két) hoặc giám đốc (TK cá nhân)
  n := length(d);
  d := replace(d, $a$      perform kt_bao(kt_ai_ke_toan(u.id), u.ho_ten, 'chi_cho_tt', 'Giám đốc đã xác nhận — chờ thanh toán', v_tom, 'chi', v_id);$a$,
                  $a$      if coalesce((select thu_quy_chi from kt_tai_khoan where id = v_moi.tai_khoan_id), false) then
        perform kt_bao(array(select id from kt_nguoi_dung where hoat_dong and 'chi_tt' = any(quyen) and id <> u.id), u.ho_ten, 'chi_cho_tt', 'Đã xác nhận — thủ quỹ chi tiền', v_tom, 'chi', v_id);
      else
        perform kt_bao(kt_ai_giam_doc(u.id), u.ho_ten, 'chi_cho_tt', 'Đã xác nhận — giám đốc chi từ tài khoản cá nhân', v_tom, 'chi', v_id);
      end if;$a$);
  if length(d) = n then raise exception 'kt_luu_chi: thong bao'; end if;
  execute d;
end $$;
