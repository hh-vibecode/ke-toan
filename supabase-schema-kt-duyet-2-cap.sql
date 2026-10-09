-- =========================================================================
-- APP KẾ TOÁN — DUYỆT CHI 2 LƯỢT + ĐỀ XUẤT CHI TỪ KIOT (anh chốt 08/10/2026) — Monsieur Claude
-- Anh: "nhân viên đề xuất chi trên kiot, nó đẩy lên app để giám đốc xác nhận cho kế toán xử lý"
--      "kế toán được check và xác nhận lượt 1, check xong qua kế toán giám đốc chỉ cần xác nhận lại"
--
-- Luồng phiếu chi:
--   cho_duyet (chờ KẾ TOÁN kiểm)  --kế toán xác nhận lượt 1-->  cho_gd (chờ GIÁM ĐỐC xác nhận)
--   cho_gd  --giám đốc xác nhận lượt 2-->  cho_tt (chờ thanh toán)  --kế toán-->  da_tt
--   Từ chối được ở lượt 1 / lượt 2; giám đốc có thể "trả lại" về cho kế toán kiểm lại; kế toán mở lại phiếu đã từ chối.
--   Người đã kiểm lượt 1 KHÔNG tự xác nhận lượt 2 (2 người khác nhau).
--   "Đã thanh toán luôn" (kế toán tự chi, không qua duyệt) GIỮ — anh chốt 09/10: không cần giám đốc xác nhận.
--   Phiếu Kiot tự sinh (TTTH trả hàng, PCPN trả NCC lúc nhập) cũng qua đủ 2 lượt — anh chốt 09/10.
--   Phiếu đã được giám đốc xác nhận: chỉ người có quyền giám đốc mới đổi được SỐ TIỀN.
-- Quyền:
--   chi_duyet = kế toán kiểm lượt 1 + thanh toán (Admin / Supreme luôn có).
--   chi_gd    = giám đốc xác nhận lượt 2 — KHÔNG tự có theo Admin; phải tick riêng (tài khoản giamdoc). Supreme luôn có.
-- Đề xuất chi từ Kiot (từ 08/10/2026): phiếu CHI trên sổ quỹ Kiot (không phải chuyển quỹ nội bộ "Chuyển rút" / TTD_ / CTD_ /
--   nội dung có số TK công ty) → thành phiếu chi "chờ kế toán kiểm" trên app (nguon 'kiot', người đề nghị = người tạo trên Kiot,
--   cơ sở = chi nhánh Kiot, TK gợi ý: tiền mặt → két quầy, chuyển khoản → TK Kiot ghép qua kiot_ma).
--   * Kiot không có trạng thái "chờ duyệt" — phiếu Kiot luôn ghi "Đã thanh toán"; app mới là nơi duyệt.
--   * Chống tính 2 lần: phiếu app kế toán đã đánh dấu "Đã tạo phiếu Kiot (4A)" cùng số tiền, lệch ≤ 5 ngày → GHÉP vào phiếu đó,
--     không tạo phiếu mới. Trùng số tiền ±5 ngày với phiếu app khác (chưa đánh dấu 4A) → vẫn tạo nhưng gắn "nghi trùng #id".
--   * Phiếu Kiot bị huỷ: phiếu app chưa thanh toán → Từ chối (ghi "Phiếu Kiot đã huỷ"). Phiếu Kiot đổi số tiền khi app còn chờ
--     kế toán kiểm và chưa ai sửa → cập nhật theo.
--   * Báo cáo tiền chỉ cộng phiếu "Đã thanh toán" → phiếu kéo về chưa làm đổi số tiền ra.
-- Chạy SAU supabase-schema-kt-thong-bao.sql (dùng kt_bao, kt_chan_dong).
-- =========================================================================

alter table public.kt_chi drop constraint if exists kt_chi_trang_thai_check;
alter table public.kt_chi add constraint kt_chi_trang_thai_check
  check (trang_thai in ('cho_duyet','cho_gd','tu_choi','cho_tt','da_tt','tu_choi_tt'));
alter table public.kt_chi drop constraint if exists kt_chi_nguon_check;
alter table public.kt_chi add constraint kt_chi_nguon_check check (nguon in ('app','sheet_cu','kiot'));
alter table public.kt_chi add column if not exists kiem_boi text;              -- kế toán xác nhận lượt 1
alter table public.kt_chi add column if not exists kiem_luc timestamptz;
alter table public.kt_chi add column if not exists kiot_so_quy_id bigint;      -- phiếu sổ quỹ Kiot tương ứng (kéo về hoặc ghép 4A)
alter table public.kt_chi add column if not exists kiot_ma text;               -- mã phiếu Kiot (vd PC000123)
alter table public.kt_chi add column if not exists nghi_trung text;            -- "#12, #34" phiếu app cùng số tiền ±5 ngày
create unique index if not exists kt_chi_kiot_sq_uq on kt_chi(kiot_so_quy_id) where kiot_so_quy_id is not null;

-- chi_gd KHÔNG đi theo Admin / '*': chỉ Supreme hoặc tick riêng
create or replace function public.kt_co_quyen(u kt_nguoi_dung, p_trang text, p_ghi boolean default false) returns boolean
language sql immutable as $$
  select case when p_trang = 'chi_gd' then u.vi_tri = 'supreme' or 'chi_gd' = any(u.quyen)
    else p_trang is null or u.vi_tri in ('supreme','admin') or '*' = any(u.quyen)
      or (p_trang = any(u.quyen) and (not p_ghi or (p_trang || ':ghi') = any(u.quyen))) end;
$$;

-- Người nhận thông báo: KẾ TOÁN (quyền chi_duyet nhưng không phải giám đốc) · GIÁM ĐỐC (tick chi_gd; không ai thì Supreme)
create or replace function public.kt_ai_ke_toan(p_tru int) returns int[]
language sql stable security definer set search_path = public as $$
  -- nhóm kế toán tính TRƯỚC khi bỏ người đang thao tác (kế toán tự tạo phiếu thì không báo sang giám đốc / anh)
  select array_remove(coalesce(
    nullif(array(select id from kt_nguoi_dung n where hoat_dong and kt_co_quyen(n, 'chi_duyet') and not kt_co_quyen(n, 'chi_gd')), '{}'),
    array(select id from kt_nguoi_dung n where hoat_dong and kt_co_quyen(n, 'chi_duyet'))), coalesce(p_tru, 0));
$$;
create or replace function public.kt_ai_giam_doc(p_tru int) returns int[]
language sql stable security definer set search_path = public as $$
  select array_remove(coalesce(
    nullif(array(select id from kt_nguoi_dung where hoat_dong and 'chi_gd' = any(quyen)), '{}'),
    array(select id from kt_nguoi_dung where hoat_dong and vi_tri = 'supreme')), coalesce(p_tru, 0));
$$;
revoke execute on function public.kt_ai_ke_toan(int) from public, anon, authenticated;
revoke execute on function public.kt_ai_giam_doc(int) from public, anon, authenticated;

create or replace function public.kt_ten_tt_chi(p text) returns text language sql immutable as $$
  select case p when 'cho_duyet' then 'Chờ kế toán kiểm' when 'cho_gd' then 'Chờ giám đốc xác nhận' when 'cho_tt' then 'Chờ thanh toán'
    when 'da_tt' then 'Đã thanh toán' when 'tu_choi' then 'Từ chối' when 'tu_choi_tt' then 'Từ chối thanh toán' else 'Phiếu mới' end;
$$;

-- Lưu phiếu chi (định nghĩa lại — bản trước ở supabase-schema-kt-thong-bao.sql đã chuyển sang đây)
create or replace function public.kt_luu_chi(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_cu kt_chi; v_moi kt_chi; v_tt text := p_dong->>'trang_thai';
  v_pb jsonb := coalesce(p_dong->'phan_bo', '[]'::jsonb); v_tong numeric;
  v_ghi boolean; v_duyet boolean; v_gd boolean; v_tu text; v_doi boolean; v_tom text;
begin
  u := kt_chan(p_phien);
  v_ghi := kt_co_quyen(u, 'chi', true); v_duyet := kt_co_quyen(u, 'chi_duyet'); v_gd := kt_co_quyen(u, 'chi_gd');
  if not v_ghi and not kt_co_quyen(u, 'chi_de_nghi') then
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
    if not v_ghi and (v_cu.tao_boi is distinct from u.ho_ten or v_cu.trang_thai <> 'cho_duyet') then
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
    or (v_tu = 'moi' and v_tt = 'da_tt' and v_duyet)
    or (v_tu = 'cho_duyet' and v_tt in ('cho_gd','tu_choi') and v_duyet)
    or (v_tu = 'cho_duyet' and v_tt = 'tu_choi' and v_gd)
    or (v_tu = 'cho_gd' and v_tt in ('cho_tt','tu_choi') and v_gd)
    or (v_tu = 'cho_gd' and v_tt = 'cho_duyet' and (v_gd or v_duyet))
    or (v_tu = 'cho_tt' and v_tt in ('da_tt','tu_choi_tt') and v_duyet)
    or (v_tu in ('tu_choi','tu_choi_tt') and v_tt = 'cho_duyet' and v_duyet)) then
    raise exception 'Không chuyển được phiếu từ "%" sang "%" (luồng: kế toán kiểm → giám đốc xác nhận → kế toán thanh toán)',
      kt_ten_tt_chi(v_tu), kt_ten_tt_chi(v_tt) using errcode = '42501';
  end if;
  if v_doi and v_tu = 'cho_gd' and v_tt = 'cho_tt' and v_cu.kiem_boi = u.ho_ten then
    raise exception 'Người đã kiểm lượt 1 không tự xác nhận lượt 2 — cần giám đốc xác nhận' using errcode = '42501';
  end if;
  if v_duyet and p_dong->>'kiot' = 'khong_tao' and coalesce(trim(p_dong->>'kiot_ly_do'), '') = '' then
    raise exception 'Không tạo phiếu Kiot thì phải ghi lý do';
  end if;
  if v_id is null then
    insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, thu_huong_ten, thu_huong_nh,
      thu_huong_stk, phan_bo, han_tt, co_hd_do, ghi_chu, chung_tu, tao_boi)
    values (coalesce((p_dong->>'ngay_de_nghi')::date, (now() at time zone 'Asia/Ho_Chi_Minh')::date),
      coalesce(nullif(trim(p_dong->>'nguoi_de_nghi'),''), u.ho_ten), (p_dong->>'bo_phan_id')::int, trim(p_dong->>'noi_dung'),
      (p_dong->>'ngay_su_dung')::date, (p_dong->>'so_tien')::numeric, nullif(trim(p_dong->>'thu_huong_ten'),''),
      nullif(trim(p_dong->>'thu_huong_nh'),''), nullif(trim(p_dong->>'thu_huong_stk'),''), v_pb, (p_dong->>'han_tt')::date,
      coalesce((p_dong->>'co_hd_do')::boolean,false), nullif(trim(p_dong->>'ghi_chu'),''),
      coalesce(array(select jsonb_array_elements_text(p_dong->'chung_tu')), '{}'), u.ho_ten)
    returning id into v_id;
    v_tt := coalesce(v_tt, 'cho_duyet'); v_doi := true;
  else
    update kt_chi set ngay_de_nghi = coalesce((p_dong->>'ngay_de_nghi')::date, ngay_de_nghi),
      nguoi_de_nghi = coalesce(nullif(trim(p_dong->>'nguoi_de_nghi'),''), nguoi_de_nghi), bo_phan_id = (p_dong->>'bo_phan_id')::int,
      noi_dung = trim(p_dong->>'noi_dung'), ngay_su_dung = (p_dong->>'ngay_su_dung')::date, so_tien = (p_dong->>'so_tien')::numeric,
      thu_huong_ten = nullif(trim(p_dong->>'thu_huong_ten'),''), thu_huong_nh = nullif(trim(p_dong->>'thu_huong_nh'),''),
      thu_huong_stk = nullif(trim(p_dong->>'thu_huong_stk'),''), phan_bo = v_pb, han_tt = (p_dong->>'han_tt')::date,
      co_hd_do = coalesce((p_dong->>'co_hd_do')::boolean,false), ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''),
      chung_tu = coalesce(array(select jsonb_array_elements_text(p_dong->'chung_tu')), '{}'),
      sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id;
  end if;
  update kt_chi set
    trang_thai   = case when v_doi then v_tt else trang_thai end,
    kiem_boi     = case when v_doi and v_tt = 'cho_gd' then u.ho_ten when v_doi and v_tt = 'cho_duyet' then null else kiem_boi end,
    kiem_luc     = case when v_doi and v_tt = 'cho_gd' then now() when v_doi and v_tt = 'cho_duyet' then null else kiem_luc end,
    nguoi_duyet  = case when v_doi and (v_tt in ('cho_tt','tu_choi') or (v_tt = 'da_tt' and v_tu = 'moi')) then u.ho_ten
                        when v_doi and v_tt = 'cho_duyet' then null else nguoi_duyet end,
    duyet_luc    = case when v_doi and (v_tt in ('cho_tt','tu_choi') or (v_tt = 'da_tt' and v_tu = 'moi')) then now()
                        when v_doi and v_tt = 'cho_duyet' then null else duyet_luc end,
    ngay_tt      = case when v_duyet then coalesce((p_dong->>'ngay_tt')::date, case when v_tt = 'da_tt' then ngay_tt end) else ngay_tt end,
    tai_khoan_id = case when v_duyet then coalesce((p_dong->>'tai_khoan_id')::int, tai_khoan_id) else tai_khoan_id end,
    loai_id      = case when v_duyet then coalesce((p_dong->>'loai_id')::int, loai_id) else loai_id end,
    unc          = case when v_duyet then coalesce(nullif(trim(p_dong->>'unc'),''), unc) else unc end,
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
      perform kt_bao(kt_ai_giam_doc(u.id), u.ho_ten, 'chi_cho_gd', 'Kế toán đã kiểm — chờ giám đốc xác nhận', v_tom, 'chi', v_id);
    elsif v_moi.trang_thai = 'cho_tt' then
      perform kt_bao(kt_ai_ke_toan(u.id), u.ho_ten, 'chi_cho_tt', 'Giám đốc đã xác nhận — chờ thanh toán', v_tom, 'chi', v_id);
      perform kt_bao(array(select unnest(kt_ai_ten(array[v_moi.tao_boi], u.id)) except select unnest(kt_ai_ke_toan(u.id))), u.ho_ten, 'chi_duyet', 'Đề nghị chi của anh/chị đã được duyệt', v_tom, 'chi', v_id);
    elsif v_moi.trang_thai = 'da_tt' and v_tu <> 'moi' then
      perform kt_bao(kt_ai_ten(array[v_moi.tao_boi], u.id), u.ho_ten, 'chi_da_tt', 'Phiếu chi đã thanh toán', v_tom, 'chi', v_id);
    elsif v_moi.trang_thai in ('tu_choi','tu_choi_tt') then
      perform kt_bao(kt_ai_ten(array[v_moi.tao_boi, v_cu.kiem_boi], u.id), u.ho_ten, 'chi_tu_choi',
        case when v_moi.trang_thai = 'tu_choi' then 'Đề nghị chi bị từ chối' else 'Phiếu chi bị từ chối thanh toán' end, v_tom, 'chi', v_id);
    end if;
  end if;
  return v_id;
end $$;

-- Đề xuất chi từ Kiot → phiếu chi "chờ kế toán kiểm". Gọi trong kt_dong_bo_kiot (job 3 tiếng). Từ 08/10/2026.
create or replace function public.kt_dong_bo_kiot_chi(p_tu date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_moc date := greatest(p_tu, date '2026-10-08'); v_quay int; r record; c record;
  v_khop bigint; v_nghi text; v_id bigint; v_them int := 0; v_ghep int := 0; v_huy int := 0; v_sua int := 0; v_ds text[] := '{}'; v_ids bigint[] := '{}';
begin
  select id into v_quay from kt_tai_khoan where 'TIEN_MAT_QUAY' = any(kiot_ma) limit 1;
  for r in
    select q.id, q.ma, q.trang_thai, q.nhom, q.noi_dung, q.doi_tac, q.goc->>'user' nguoi,
      (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date d, abs(q.so_tien) tien,
      (select dd.id from kt_don_vi dd where q.chi_nhanh = any(dd.kiot_chi_nhanh) limit 1) dv_id,
      case when q.phuong_thuc = 'Cash' then v_quay else (select t.id from kt_tai_khoan t where q.tai_khoan = any(t.kiot_ma) limit 1) end tk_id,
      q.ma ~ '^(TTD_|CTD_)' or exists (select 1 from kt_tai_khoan t where length(regexp_replace(t.ten, '[^0-9]', '', 'g')) >= 8
             and coalesce(q.noi_dung, '') like '%' || regexp_replace(t.ten, '[^0-9]', '', 'g') || '%') noi_bo
    from kt_kiot_so_quy q
    where not q.la_thu and q.so_tien <> 0 and coalesce(q.nhom, '') <> 'Chuyển rút'
      and (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date >= v_moc
    order by q.ngay, q.id
  loop
    select id, trang_thai, so_tien, sua_boi, nguon into c from kt_chi where kiot_so_quy_id = r.id;
    if found then
      if (r.trang_thai <> '0' or r.noi_bo) and c.nguon = 'kiot' and c.trang_thai in ('cho_duyet','cho_gd','cho_tt') then
        update kt_chi set trang_thai = 'tu_choi', nguoi_duyet = 'Kiot (phiếu đã huỷ)', duyet_luc = now(),
          ghi_chu = concat_ws(' ', ghi_chu, '[Phiếu Kiot ' || r.ma || ' đã huỷ / là chuyển nội bộ]') where id = c.id;
        v_huy := v_huy + 1;
      elsif r.trang_thai = '0' and not r.noi_bo and c.nguon = 'kiot' and c.trang_thai = 'cho_duyet' and c.sua_boi is null and c.so_tien <> r.tien then
        update kt_chi set so_tien = r.tien, phan_bo = case when r.dv_id is null then '[]'::jsonb
          else jsonb_build_array(jsonb_build_object('don_vi_id', r.dv_id, 'so_tien', r.tien)) end where id = c.id;
        v_sua := v_sua + 1;
      end if;
      continue;
    end if;
    if r.trang_thai <> '0' or r.noi_bo then continue; end if;
    -- phiếu Kiot là bản ghi 4A của 1 phiếu app kế toán đã đánh dấu "Đã tạo phiếu Kiot" → ghép, không tạo mới
    select x.id into v_khop from kt_chi x where not x.da_xoa and x.kiot_so_quy_id is null and x.nguon <> 'kiot' and x.kiot = 'da_tao'
      and x.so_tien = r.tien and abs(coalesce(x.ngay_tt, x.ngay_de_nghi) - r.d) <= 5
      order by abs(coalesce(x.ngay_tt, x.ngay_de_nghi) - r.d), x.id limit 1;
    if v_khop is not null then
      update kt_chi set kiot_so_quy_id = r.id, kiot_ma = r.ma where id = v_khop;
      v_ghep := v_ghep + 1; continue;
    end if;
    select string_agg('#' || x.id, ', ' order by x.id) into v_nghi from kt_chi x where not x.da_xoa and x.nguon <> 'kiot'
      and x.trang_thai <> 'tu_choi' and x.so_tien = r.tien and abs(coalesce(x.ngay_tt, x.ngay_de_nghi) - r.d) <= 5;
    insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, so_tien, phan_bo, tai_khoan_id, trang_thai,
      nguon, ma_nguon, tao_boi, kiot_so_quy_id, kiot_ma, kiot, nghi_trung)
    values (r.d, coalesce(nullif(trim(r.nguoi), ''), 'Kiot'), r.dv_id,
      left(concat_ws(' · ', coalesce(nullif(trim(r.nhom), ''), 'Chi khác'), nullif(trim(r.noi_dung), ''), nullif(trim(r.doi_tac), '')), 300),
      r.tien, case when r.dv_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('don_vi_id', r.dv_id, 'so_tien', r.tien)) end,
      r.tk_id, 'cho_duyet', 'kiot', 'kiot:' || r.id, 'Kiot (tự kéo)', r.id, r.ma, 'da_tao', v_nghi)
    returning id into v_id;
    v_them := v_them + 1; v_ids := v_ids || v_id;
    if v_them <= 3 then v_ds := v_ds || (coalesce(nullif(trim(r.nguoi), ''), 'Kiot') || ': ' || replace(to_char(r.tien, 'FM999G999G999G999'), ',', '.') || ' đ'); end if;
  end loop;
  if v_them > 0 then
    perform kt_bao(kt_ai_ke_toan(null), 'Kiot (tự kéo)', 'chi_kiot',
      case when v_them = 1 then 'Đề xuất chi mới từ Kiot — chờ kế toán kiểm' else v_them || ' đề xuất chi mới từ Kiot — chờ kế toán kiểm' end,
      array_to_string(v_ds, ' · ') || case when v_them > 3 then ' …' else '' end, 'chi', case when v_them = 1 then v_ids[1] end);
  end if;
  return jsonb_build_object('them', v_them, 'ghep_4a', v_ghep, 'huy', v_huy, 'sua', v_sua);
end $$;
revoke execute on function public.kt_dong_bo_kiot_chi(date) from public, anon, authenticated;

-- Tài khoản giám đốc: tick quyền xác nhận lượt 2 (giữ toàn quyền Admin)
update kt_nguoi_dung set quyen = array_append(quyen, 'chi_gd') where ten_dang_nhap = 'giamdoc' and not ('chi_gd' = any(quyen));

-- kt_bao_cao (định nghĩa lại — bản gốc ở supabase-schema-kt.sql): thêm đếm / tiền "chờ giám đốc xác nhận" (cho_gd) vào Tổng quan.
CREATE OR REPLACE FUNCTION public.kt_bao_cao(p_phien text, p_tu date, p_den date, p_chi_theo text DEFAULT 'ngay_tt'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'tong_quan');
  with
  bd as (select b.*, tk.ngay_ton_dau from kt_v_bien_dong b join kt_tai_khoan tk on tk.id = b.tai_khoan_id
          where b.ngay >= tk.ngay_ton_dau),
  ton as (
    select tk.id, tk.ten, tk.loai, tk.hoat_dong, tk.thu_tu,
      tk.ton_dau + coalesce(sum(b.vao - b.ra) filter (where b.ngay < p_tu), 0) as dau_ky,
      coalesce(sum(b.vao) filter (where b.ngay between p_tu and p_den and b.kieu = 'thu'), 0) as thu,
      coalesce(sum(b.ra)  filter (where b.ngay between p_tu and p_den and b.kieu = 'chi'), 0) as chi,
      coalesce(sum(b.vao - b.ra) filter (where b.ngay between p_tu and p_den and b.kieu = 'dc'), 0) as dc,
      tk.ton_dau + coalesce(sum(b.vao - b.ra) filter (where b.ngay <= p_den), 0) as cuoi_ky
    from kt_tai_khoan tk left join bd b on b.tai_khoan_id = tk.id
    group by tk.id),
  thu_ky as (select t.*, l.ten loai_ten from kt_thu t join kt_loai l on l.id = t.loai_id
              where not t.da_xoa and t.trang_thai = 'da_duyet' and t.ngay between p_tu and p_den),
  chi_ky as (select c.*, l.ten loai_ten, l.nhom_bc, l.cach_chia from kt_chi c join kt_loai l on l.id = c.loai_id
              where not c.da_xoa and c.trang_thai = 'da_tt'
                and (case when p_chi_theo = 'ngay_su_dung' then coalesce(c.ngay_su_dung, c.ngay_tt) else c.ngay_tt end) between p_tu and p_den),
  -- Tỉ lệ chia chi phí chung = thu (đã duyệt) của từng cơ sở / tổng thu trong kỳ
  thu_dv as (select don_vi_id, sum(so_tien) thu from thu_ky where don_vi_id is not null group by don_vi_id),
  tong_thu as (select nullif(sum(thu), 0) tong from thu_dv),
  chi_rieng as (   -- chi phí riêng: theo phân bổ của phiếu; phiếu không phân bổ → "Chưa phân bổ" (don_vi_id null)
    select (x->>'don_vi_id')::int don_vi_id, c.loai_id, c.loai_ten, (x->>'so_tien')::numeric so_tien
      from chi_ky c cross join lateral jsonb_array_elements(c.phan_bo) x where c.cach_chia = 'rieng'
    union all
    select null, c.loai_id, c.loai_ten, c.so_tien from chi_ky c
     where c.cach_chia = 'rieng' and jsonb_array_length(c.phan_bo) = 0),
  chi_chung as (   -- chi phí chung: chia theo tỉ lệ thu; kỳ không có thu → "Chưa phân bổ"
    select d.don_vi_id, c.loai_id, c.loai_ten, round(c.so_tien * d.thu / tt.tong) so_tien
      from chi_ky c cross join thu_dv d cross join tong_thu tt where c.cach_chia = 'ty_le_thu' and tt.tong is not null
    union all
    select null, c.loai_id, c.loai_ten, c.so_tien from chi_ky c, tong_thu tt where c.cach_chia = 'ty_le_thu' and tt.tong is null),
  chi_dv as (select * from chi_rieng union all select * from chi_chung),
  cno as (select n.*, n.so_tien - n.tra_hang - coalesce((select sum(so_tien) from kt_cong_no_thu
           where cong_no_id = n.id and not da_xoa and ngay <= p_den), 0) con_no
         from kt_cong_no n where not n.da_xoa and n.ngay <= p_den)
  select jsonb_build_object(
    'tu', p_tu, 'den', p_den,
    'tien_vao', (select coalesce(sum(so_tien), 0) from thu_ky),
    'tien_ra',  (select coalesce(sum(so_tien), 0) from chi_ky),
    'dieu_chuyen', (select coalesce(sum(so_tien), 0) from kt_dieu_chuyen where not da_xoa and ngay between p_tu and p_den),
    'ton_dau_ky', (select coalesce(sum(dau_ky), 0) from ton),
    'ton_cuoi_ky', (select coalesce(sum(cuoi_ky), 0) from ton),
    'tai_khoan', (select coalesce(jsonb_agg(to_jsonb(ton) order by thu_tu, id), '[]') from ton
                   where hoat_dong or dau_ky <> 0 or cuoi_ky <> 0 or thu <> 0 or chi <> 0 or dc <> 0),
    'thu_theo_loai', (select coalesce(jsonb_agg(jsonb_build_object('loai', loai_ten, 'so_tien', s) order by s desc), '[]')
                       from (select loai_ten, sum(so_tien) s from thu_ky group by loai_ten) x),
    'chi_theo_loai', (select coalesce(jsonb_agg(jsonb_build_object('loai', loai_ten, 'nhom_bc', nhom_bc, 'cach_chia', cach_chia,
                        'so_tien', s, 'so_phieu', n) order by s desc), '[]')
                       from (select loai_ten, nhom_bc, cach_chia, sum(so_tien) s, count(*) n from chi_ky
                             group by loai_ten, nhom_bc, cach_chia) x),
    'thu_theo_dv', (select coalesce(jsonb_agg(jsonb_build_object('don_vi_id', don_vi_id, 'loai', loai_ten, 'so_tien', s)), '[]')
                     from (select don_vi_id, loai_ten, sum(so_tien) s from thu_ky group by 1, 2) x),
    'chi_theo_dv', (select coalesce(jsonb_agg(jsonb_build_object('don_vi_id', don_vi_id, 'loai', loai_ten, 'so_tien', s)), '[]')
                     from (select don_vi_id, loai_ten, sum(so_tien) s from chi_dv group by 1, 2) x),
    -- Công nợ khách = SỐ KIOT (anh chốt 08/10: "kiot là đủ") — bỏ trang nhập tay khỏi báo cáo. Số Kiot là số HIỆN TẠI.
    'cong_no', (select jsonb_build_object('phai_thu', coalesce(sum(cong_no) filter (where cong_no > 0), 0), 'so_khach_no', count(*) filter (where cong_no > 0),
                  'tra_truoc', coalesce(-sum(cong_no) filter (where cong_no < 0), 0), 'so_tra_truoc', count(*) filter (where cong_no < 0)) from kt_kiot_khach),
    'top_no', (select coalesce(jsonb_agg(jsonb_build_object('khach', ten, 'ma', ma, 'con_no', cong_no) order by cong_no desc), '[]')
                from (select ten, ma, cong_no from kt_kiot_khach where cong_no > 0 order by cong_no desc limit 8) x),
    'dem', jsonb_build_object(
       'cho_duyet', (select count(*) from kt_chi where not da_xoa and trang_thai = 'cho_duyet'),
       'cho_gd',    (select count(*) from kt_chi where not da_xoa and trang_thai = 'cho_gd'),
       'cho_tt',    (select count(*) from kt_chi where not da_xoa and trang_thai = 'cho_tt'),
       'hd_do_chua_nhan', (select count(*) from kt_chi where not da_xoa and trang_thai = 'da_tt' and co_hd_do and not hd_do_nhan),
       'dc_chua_xac_nhan', (select count(*) from kt_dieu_chuyen where not da_xoa and not da_xac_nhan),
       'thu_cho_duyet', (select count(*) from kt_thu where not da_xoa and trang_thai = 'cho_duyet'),
       'tk_am', (select count(*) from ton where cuoi_ky < 0)),
    'sap_tra', (select coalesce(jsonb_agg(to_jsonb(s) order by s.han nulls last), '[]') from kt_sap_tra s
                 where not s.da_xoa and not s.da_tra),
    'kiot_keo_luc', (select max(keo_luc) from kt_kiot_so_quy)
  ) into r;
  -- Ô kiểu Xero (anh chốt 05/10): số dư sao kê mới nhất / khoản phải trả / tuổi nợ phải thu
  r := r || jsonb_build_object(
    'thuc_te', (select coalesce(jsonb_agg(jsonb_build_object('tk', tai_khoan_id, 'ngay', ngay, 'so_tien', so_tien)), '[]') from (
       select distinct on (tai_khoan_id) tai_khoan_id, ngay, so_tien from kt_ton_thuc_te where ngay <= p_den
        order by tai_khoan_id, ngay desc) x),
    'phai_tra', (select jsonb_build_object(
       'cho_duyet_tien', coalesce(sum(so_tien) filter (where trang_thai = 'cho_duyet'), 0),
       'cho_gd_tien', coalesce(sum(so_tien) filter (where trang_thai = 'cho_gd'), 0),
       'cho_tt_tien', coalesce(sum(so_tien) filter (where trang_thai = 'cho_tt'), 0),
       'qua_han', count(*) filter (where han_tt < (now() at time zone 'Asia/Ho_Chi_Minh')::date),
       'qua_han_tien', coalesce(sum(so_tien) filter (where han_tt < (now() at time zone 'Asia/Ho_Chi_Minh')::date), 0))
       from kt_chi where not da_xoa and trang_thai in ('cho_duyet','cho_gd','cho_tt')),
    -- (tuổi nợ theo trang nhập tay — KHÔNG còn hiện từ 08/10 vì công nợ dùng số Kiot; giữ để tra lại số sheet cũ)
    'no_tuoi', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'so_khoan', n, 'con_no', s) order by thu_tu), '[]') from (
       select case when p_den - ngay <= 30 then 'Dưới 30 ngày' when p_den - ngay <= 60 then '31–60 ngày'
                   when p_den - ngay <= 90 then '61–90 ngày' else 'Trên 90 ngày' end nhom,
              min(case when p_den - ngay <= 30 then 1 when p_den - ngay <= 60 then 2 when p_den - ngay <= 90 then 3 else 4 end) thu_tu,
              count(*) n, sum(con_no) s
         from (select n.ngay, n.so_tien - n.tra_hang - coalesce((select sum(t.so_tien) from kt_cong_no_thu t
                 where t.cong_no_id = n.id and not t.da_xoa and t.ngay <= p_den), 0) con_no
               from kt_cong_no n where not n.da_xoa and n.ngay <= p_den) c
        where con_no > 0 group by 1) x));
  return r;
end $function$
;

-- kt_luu_nguoi_dung (định nghĩa lại — bản gốc ở supabase-schema-kt.sql): chỉ Supreme cấp / bỏ quyền chi_gd và đặt lại mật khẩu tài khoản có chi_gd.
CREATE OR REPLACE FUNCTION public.kt_luu_nguoi_dung(p_phien text, p_dong jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare u kt_nguoi_dung; v_id int := (p_dong->>'id')::int; v_mk text := nullif(p_dong->>'mk_moi', ''); v_cu kt_nguoi_dung;
  v_vt text := coalesce(p_dong->>'vi_tri', 'nhan_vien');
  v_q text[] := coalesce(array(select jsonb_array_elements_text(p_dong->'quyen')), '{}');
begin
  u := kt_chan(p_phien, 'phan_quyen', true);
  if v_id is not null then select * into v_cu from kt_nguoi_dung where id = v_id; end if;
  if (v_vt = 'supreme' or v_cu.vi_tri = 'supreme') and u.vi_tri <> 'supreme' then
    raise exception 'Chỉ Supreme mới sửa được tài khoản Supreme';
  end if;
  -- Quyền GIÁM ĐỐC XÁC NHẬN CHI (lượt 2): chỉ Supreme cấp / bỏ, và chỉ Supreme đặt lại mật khẩu tài khoản đó
  -- (nếu không, Admin có thể tự cấp hoặc đăng nhập thay giám đốc để tự duyệt cả 2 lượt) — 08/10/2026
  if u.vi_tri <> 'supreme' and ('chi_gd' = any(v_q)) <> coalesce('chi_gd' = any(v_cu.quyen), false) then
    raise exception 'Chỉ anh Hải (Supreme) được cấp / bỏ quyền giám đốc xác nhận chi' using errcode = '42501';
  end if;
  if u.vi_tri <> 'supreme' and v_mk is not null and v_id <> u.id and coalesce('chi_gd' = any(v_cu.quyen), false) then
    raise exception 'Chỉ anh Hải (Supreme) được đặt lại mật khẩu tài khoản giám đốc' using errcode = '42501';
  end if;
  if v_mk is not null and length(v_mk) < 8 then raise exception 'Mật khẩu phải từ 8 ký tự'; end if;
  if v_id = u.id and (coalesce((p_dong->>'hoat_dong')::boolean, true) = false or v_vt <> u.vi_tri) then
    raise exception 'Không tự khoá hoặc tự đổi vị trí của chính mình';
  end if;
  if v_id is null then
    if v_mk is null then raise exception 'Tài khoản mới cần mật khẩu'; end if;
    insert into kt_nguoi_dung (ten_dang_nhap, ho_ten, vi_tri, quyen, mk_hash, hoat_dong)
    values (lower(trim(p_dong->>'ten_dang_nhap')), trim(p_dong->>'ho_ten'), v_vt, v_q, crypt(v_mk, gen_salt('bf')),
      coalesce((p_dong->>'hoat_dong')::boolean, true)) returning id into v_id;
  else
    update kt_nguoi_dung set ten_dang_nhap = lower(trim(p_dong->>'ten_dang_nhap')), ho_ten = trim(p_dong->>'ho_ten'),
      vi_tri = v_vt, quyen = v_q, hoat_dong = coalesce((p_dong->>'hoat_dong')::boolean, true),
      mk_hash = case when v_mk is null then mk_hash else crypt(v_mk, gen_salt('bf')) end,
      doi_mk_luc = case when v_mk is null then doi_mk_luc else now() end,
      sai_lien = case when v_mk is null then sai_lien else 0 end, khoa_den = case when v_mk is null then khoa_den end
     where id = v_id;
    -- khoá tài khoản / đặt lại mật khẩu → đăng xuất mọi phiên của người đó
    if v_mk is not null or coalesce((p_dong->>'hoat_dong')::boolean, true) = false then
      delete from kt_phien where nguoi_dung_id = v_id;
    end if;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_nguoi_dung', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end,
    (p_dong - 'mk_moi') || jsonb_build_object('dat_mat_khau', v_mk is not null));
  return v_id;
end $function$
;
