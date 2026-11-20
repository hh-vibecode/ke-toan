-- PHÍ CHUYỂN TIỀN THANH TOÁN TRUNG GIAN TRỪ Ở TÀI KHOẢN TRẢ PHÍ RIÊNG — 20/11/2026. Monsieur Claude
-- Anh: "phần phí chuyển tiền nó lại trừ đi từ TK công ty chứ không cộng vào TK vay". Trước: phí cộng vào số trừ của TK nguồn (TK vay) + vào giải ngân vay.
-- → kt_tt_nn.phi_tk_id (TK trả phí). TK trả phí = phi_tk_id, chưa chọn: TK nguồn nếu là TK thường, TK nguồn là TK vay → CHƯA TRỪ phí (trang báo chọn TK trả phí).
--   kt_v_bien_dong: TK nguồn trừ tiền chuyển (+ phí nếu chính nó trả phí); TK trả phí khác → 1 khoản chi phí riêng. Giải ngân vay = tiền chuyển (không gồm phí trả từ TK khác).
--   Sổ quỹ theo ngày: dòng "Phí chuyển tiền thanh toán trung gian" ở TK trả phí.
alter table kt_tt_nn add column if not exists phi_tk_id bigint;
create or replace function public.kt_tt_nn_tien(t kt_tt_nn) returns numeric language sql immutable as $f$
  select case when t.tien_te = 'VND' then t.so_tien_nt when t.ty_gia > 0 then round(t.so_tien_nt * t.ty_gia) end
$f$;
create or replace function public.kt_tt_nn_tk_phi(t kt_tt_nn) returns bigint language sql stable set search_path to 'public' as $f$
  select coalesce(t.phi_tk_id, case when (select loai from kt_tai_khoan where id = t.tk_id) = 'vay' then null else t.tk_id end)
$f$;
create or replace view public.kt_v_bien_dong as
 SELECT t.tai_khoan_id,
    t.ngay,
    'thu'::text AS kieu,
    t.so_tien AS vao,
    0::numeric AS ra
   FROM kt_thu t
  WHERE NOT t.da_xoa AND t.trang_thai = 'da_duyet'::text
UNION ALL
 SELECT c.tai_khoan_id,
    c.ngay_tt AS ngay,
    'chi'::text AS kieu,
    0 AS vao,
    c.so_tien AS ra
   FROM kt_chi c
  WHERE NOT c.da_xoa AND c.trang_thai = 'da_tt'::text
UNION ALL
 SELECT d.tk_di_id AS tai_khoan_id,
    d.ngay,
    'dc'::text AS kieu,
    0 AS vao,
    d.so_tien AS ra
   FROM kt_dieu_chuyen d
  WHERE NOT d.da_xoa AND NOT kt_dc_cho_nhan(d.tk_nhan_id, d.tq_nhan_luc, d.tao_luc)
UNION ALL
 SELECT d.tk_nhan_id AS tai_khoan_id,
    d.ngay,
    'dc'::text AS kieu,
    d.so_tien AS vao,
    0 AS ra
   FROM kt_dieu_chuyen d
  WHERE NOT d.da_xoa AND NOT kt_dc_cho_nhan(d.tk_nhan_id, d.tq_nhan_luc, d.tao_luc)
UNION ALL
 SELECT n.tai_khoan_id,
    n.ngay,
    'vay'::text AS kieu,
    n.so_tien AS vao,
    0 AS ra
   FROM kt_vay_nhan n
  WHERE NOT n.da_xoa AND n.tai_khoan_id IS NOT NULL
UNION ALL
 SELECT r.tai_khoan_id,
    r.ngay,
    'vay'::text AS kieu,
    0 AS vao,
    r.goc + r.lai AS ra
   FROM kt_vay_tra r
  WHERE NOT r.da_xoa AND r.da_tra AND r.tai_khoan_id IS NOT NULL
UNION ALL
 SELECT tt.tk_id::integer AS tai_khoan_id, tt.ngay, 'chi'::text AS kieu, 0 AS vao,
    kt_tt_nn_tien(tt.*) + CASE WHEN kt_tt_nn_tk_phi(tt.*) = tt.tk_id THEN COALESCE(tt.phi, 0) ELSE 0 END AS ra
   FROM kt_tt_nn tt
  WHERE NOT tt.da_xoa AND tt.tk_id IS NOT NULL AND kt_tt_nn_tien(tt.*) > 0
    AND NOT (EXISTS (SELECT 1 FROM kt_chi c WHERE c.id = tt.chi_id AND NOT c.da_xoa AND c.trang_thai = 'da_tt'::text))
UNION ALL
 SELECT kt_tt_nn_tk_phi(tt.*)::integer AS tai_khoan_id, tt.ngay, 'chi'::text AS kieu, 0 AS vao, tt.phi AS ra
   FROM kt_tt_nn tt
  WHERE NOT tt.da_xoa AND COALESCE(tt.phi, 0) > 0 AND kt_tt_nn_tk_phi(tt.*) IS NOT NULL AND kt_tt_nn_tk_phi(tt.*) IS DISTINCT FROM tt.tk_id AND kt_tt_nn_tien(tt.*) > 0
    AND NOT (EXISTS (SELECT 1 FROM kt_chi c WHERE c.id = tt.chi_id AND NOT c.da_xoa AND c.trang_thai = 'da_tt'::text));
CREATE OR REPLACE FUNCTION public.kt_tt_nn_luu(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v bigint := nullif(p_dong->>'id', '')::bigint; pb jsonb; tong numeric := coalesce(nullif(p_dong->>'so_tien_nt', '')::numeric, 0);
  v_te text := coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'); v_pte text := nullif(p_dong->>'pb_tien_te', ''); v_pty numeric := nullif(p_dong->>'pb_ty_gia', '')::numeric;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if tong <= 0 then raise exception 'Nhập số tiền nguyên tệ'; end if;
  if nullif(p_dong->>'ty_gia', '') is not null and (p_dong->>'ty_gia')::numeric <= 0 then raise exception 'Tỷ giá phải lớn hơn 0'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('ncc_id', nullif(e->>'ncc_id', '')::bigint, 'ncc_ten', e->>'ncc_ten', 'po_id', nullif(e->>'po_id', '')::bigint,
           'so_tien_nt', (e->>'so_tien_nt')::numeric, 'ghi_chu', nullif(btrim(e->>'ghi_chu'), ''))), '[]') into pb
    from jsonb_array_elements(coalesce(p_dong->'phan_bo', '[]')) e where coalesce(nullif(e->>'so_tien_nt', '')::numeric, 0) > 0;
  if exists (select 1 from jsonb_array_elements(pb) e where e->>'ncc_id' is null) then raise exception 'Mỗi dòng phân bổ chọn nhà cung cấp'; end if;
  -- 19/11 kế toán: "giải ngân bằng tiền đô, bên Yongkang nhận rồi quy đổi đô sang tệ 1 lần nữa mới phân bổ cho từng NCC" → phân bổ theo tiền tệ riêng + tỷ giá đổi (1 tiền chuyển = pb_ty_gia tiền phân bổ)
  if v_pte is null or v_pte = v_te then v_pte := null; v_pty := null;
  elsif coalesce(v_pty, 0) <= 0 then raise exception 'Nhập tỷ giá đổi % sang % để phân bổ', v_te, v_pte; end if;
  if (select coalesce(sum((e->>'so_tien_nt')::numeric), 0) from jsonb_array_elements(pb) e) > round(tong * coalesce(v_pty, 1), 2) + 0.01 then raise exception 'Tổng phân bổ lớn hơn số tiền chuyển%', case when v_pty is not null then ' (đã quy đổi sang ' || v_pte || ')' else '' end; end if;
  if v is null then
    insert into kt_tt_nn (ngay, tk_id, chi_id, ben_nhan, tien_te, so_tien_nt, ty_gia, phi, phan_bo, ghi_chu, tao_boi, pb_tien_te, pb_ty_gia, phi_tk_id)
    values (coalesce(nullif(p_dong->>'ngay', '')::date, current_date), nullif(p_dong->>'tk_id', '')::bigint, nullif(p_dong->>'chi_id', '')::bigint, nullif(btrim(p_dong->>'ben_nhan'), ''),
      coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'), tong, nullif(p_dong->>'ty_gia', '')::numeric, nullif(p_dong->>'phi', '')::numeric, pb, nullif(btrim(p_dong->>'ghi_chu'), ''), u.ho_ten, v_pte, v_pty, nullif(p_dong->>'phi_tk_id', '')::bigint)
    returning id into v;
  else
    update kt_tt_nn set ngay = coalesce(nullif(p_dong->>'ngay', '')::date, ngay), tk_id = nullif(p_dong->>'tk_id', '')::bigint, chi_id = nullif(p_dong->>'chi_id', '')::bigint,
      ben_nhan = nullif(btrim(p_dong->>'ben_nhan'), ''), tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te), so_tien_nt = tong, ty_gia = nullif(p_dong->>'ty_gia', '')::numeric,
      phi = nullif(p_dong->>'phi', '')::numeric, phi_tk_id = nullif(p_dong->>'phi_tk_id', '')::bigint, phan_bo = pb, pb_tien_te = v_pte, pb_ty_gia = v_pty, ghi_chu = nullif(btrim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v and not da_xoa;
    if not found then raise exception 'Không thấy lần thanh toán'; end if;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_tt_nn', v, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v;
end $function$
;
CREATE OR REPLACE FUNCTION public.kt_vay_dong_bo_tt(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t kt_tt_nn; tien numeric;
begin
  select * into t from kt_tt_nn where id = p_id;
  if found and t.chi_id is not null and t.vay_id is not null and not coalesce(t.da_xoa, false) then
    update kt_chi set vay_id = t.vay_id where id = t.chi_id and vay_id is distinct from t.vay_id;   -- khoản vay đi theo phiếu chi
  end if;
  tien := kt_tt_nn_tien(t) + case when kt_tt_nn_tk_phi(t) = t.tk_id then coalesce(t.phi, 0) else 0 end;   -- 20/11: phí trả từ TK khác thì không tính vào giải ngân
  if found and t.vay_id is not null and t.chi_id is null and not coalesce(t.da_xoa, false) and tien > 0
     and exists (select 1 from kt_vay v where v.id = t.vay_id and not v.da_xoa) then
    -- 19/11: giải ngân vào chính tài khoản nguồn (lần chuyển đã trừ tài khoản đó) — như phiếu chi đi từ tài khoản vay
    insert into kt_vay_nhan (vay_id, ngay, so_tien, tai_khoan_id, ghi_chu, tao_boi, tt_id)
    values (t.vay_id, t.ngay, tien, t.tk_id, 'Từ thanh toán trung gian ' || coalesce(t.ben_nhan, '') || ' · ' || t.so_tien_nt || ' ' || t.tien_te, 'Hệ thống', t.id)
    on conflict (tt_id) where tt_id is not null do update set vay_id = excluded.vay_id, ngay = excluded.ngay, so_tien = excluded.so_tien,
      tai_khoan_id = excluded.tai_khoan_id, ghi_chu = excluded.ghi_chu, da_xoa = false;
  else
    update kt_vay_nhan set da_xoa = true where tt_id = p_id and not da_xoa;
  end if;
end $function$
;
CREATE OR REPLACE FUNCTION public.kt_so_quy_ngay(p_phien text, p_tk integer, p_ngay date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'tong_quan') or kt_co_quyen(u, 'so_du') or kt_co_quyen(u, 'so_quy')) then raise exception 'Tài khoản chưa được cấp quyền xem dòng tiền' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'kieu', (x->>'id')::bigint) from (
    select jsonb_build_object('kieu', 'thu', 'id', t.id, 'nd', t.noi_dung, 'vao', t.so_tien, 'ra', 0, 'ca_nhan', t.khong_hach_toan) x
      from kt_thu t where not t.da_xoa and t.trang_thai = 'da_duyet' and t.tai_khoan_id = p_tk and t.ngay = p_ngay and not kt_an_thu(u, t.noi_dung)
    union all select jsonb_build_object('kieu', 'chi', 'id', c.id, 'nd', c.noi_dung, 'vao', 0, 'ra', c.so_tien, 'ca_nhan', c.khong_hach_toan, 'doi', c.thu_huong_ten)
      from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.tai_khoan_id = p_tk and c.ngay_tt = p_ngay and not kt_an_thu(u, c.noi_dung)
    union all select jsonb_build_object('kieu', 'dc', 'id', d.id, 'nd', d.noi_dung, 'vao', 0, 'ra', d.so_tien, 'ca_nhan', d.khong_hach_toan, 'doi', 'sang ' || (select ten from kt_tai_khoan where id = d.tk_nhan_id))
      from kt_dieu_chuyen d where not d.da_xoa and d.tk_di_id = p_tk and d.ngay = p_ngay and not kt_an_thu(u, d.noi_dung) and not kt_dc_cho_nhan(d.tk_nhan_id, d.tq_nhan_luc, d.tao_luc)
    union all select jsonb_build_object('kieu', 'dc', 'id', d.id, 'nd', d.noi_dung, 'vao', d.so_tien, 'ra', 0, 'ca_nhan', d.khong_hach_toan, 'doi', 'từ ' || (select ten from kt_tai_khoan where id = d.tk_di_id))
      from kt_dieu_chuyen d where not d.da_xoa and d.tk_nhan_id = p_tk and d.ngay = p_ngay and not kt_an_thu(u, d.noi_dung) and not kt_dc_cho_nhan(d.tk_nhan_id, d.tq_nhan_luc, d.tao_luc)
    union all select jsonb_build_object('kieu', 'vay', 'id', n.id, 'nd', 'Nhận tiền vay · ' || v.ten, 'vao', n.so_tien, 'ra', 0)
      from kt_vay_nhan n join kt_vay v on v.id = n.vay_id where not n.da_xoa and n.tai_khoan_id = p_tk and n.ngay = p_ngay
    union all select jsonb_build_object('kieu', 'vay', 'id', r.id, 'nd', 'Trả nợ vay · ' || v.ten, 'vao', 0, 'ra', r.goc + r.lai)
      from kt_vay_tra r join kt_vay v on v.id = r.vay_id where not r.da_xoa and r.da_tra and r.tai_khoan_id = p_tk and r.ngay = p_ngay
    union all select jsonb_build_object('kieu', 'tt', 'id', tt.id, 'nd', 'Thanh toán trung gian · ' || tt.so_tien_nt || ' ' || tt.tien_te
             || case when tt.tien_te <> 'VND' then ' × ' || tt.ty_gia else '' end || case when coalesce(tt.phi, 0) > 0 then ' + phí ' || tt.phi else '' end
             || coalesce(' · ' || (select string_agg(distinct e->>'ncc_ten', ', ') from jsonb_array_elements(tt.phan_bo) e), ''),
             'vao', 0, 'ra', kt_tt_nn_tien(tt) + case when kt_tt_nn_tk_phi(tt) = tt.tk_id then coalesce(tt.phi, 0) else 0 end, 'doi', tt.ben_nhan)
      from kt_tt_nn tt where not tt.da_xoa and tt.tk_id = p_tk and tt.ngay = p_ngay and not exists (select 1 from kt_chi c where c.id = tt.chi_id and not c.da_xoa and c.trang_thai = 'da_tt') and kt_tt_nn_ra(tt) > 0
    union all select jsonb_build_object('kieu', 'tt', 'id', tt.id, 'nd', 'Phí chuyển tiền thanh toán trung gian · ' || coalesce(tt.ben_nhan, ''), 'vao', 0, 'ra', tt.phi, 'doi', tt.ben_nhan)
      from kt_tt_nn tt where not tt.da_xoa and kt_tt_nn_tk_phi(tt) = p_tk and kt_tt_nn_tk_phi(tt) is distinct from tt.tk_id and tt.ngay = p_ngay and coalesce(tt.phi, 0) > 0
        and not exists (select 1 from kt_chi c where c.id = tt.chi_id and not c.da_xoa and c.trang_thai = 'da_tt')) s), '[]');
end $function$
;
drop trigger if exists kt_vay_tg_tt on kt_tt_nn;
create trigger kt_vay_tg_tt after update of vay_id, chi_id, ngay, so_tien_nt, tien_te, ty_gia, phi, phi_tk_id, tk_id, ben_nhan, da_xoa on kt_tt_nn
  for each row when (new.vay_id is not null or old.vay_id is not null) execute function kt_vay_tg_tt();
do $$ declare r record; begin for r in select id from kt_tt_nn where vay_id is not null loop perform kt_vay_dong_bo_tt(r.id); end loop; end $$;
