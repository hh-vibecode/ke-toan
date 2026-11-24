-- HOÀN LẠI BẢN v1.447 (VIEC 416 — lô đường biển / đường bộ, công nợ forwarder gồm thuế, Lập phiếu chi từ chi phí lô, Chốt chi phí) — 24/11/2026. Monsieur Claude
-- Kế toán 24/11: "back lại toàn bộ chức năng từ trước khi thực hiện phần này" → về đúng bản v1.446 (VIEC 412), rồi làm theo sơ đồ luồng PO – Công nợ – Thanh toán.
-- Gỡ: trigger khoá khi chốt (3 bảng), trigger tự gắn phiếu chi về đơn vị vận chuyển, hàm chốt / nối phiếu chi / khoản của đơn vị.
-- 3 hàm kt_luu_lo_nk / kt_ds_lo_nk / kt_po_ds lấy lại nguyên văn bản 21/11 (supabase-schema-kt-van-chuyen-nk.sql).
-- GIỮ cột kt_lo_nk.hinh_thuc / chot_luc / chot_boi (app không dùng nữa) — không mất dữ liệu 2 lô Oanh tạo 23/11 (NK-2026-02, NK-2026-03 ghi 'bo').
drop trigger if exists kt_lo_nk_cp_chot on public.kt_lo_nk_cp;
drop trigger if exists kt_lo_nk_don_chot on public.kt_lo_nk_don;
drop trigger if exists kt_lo_nk_chot_lo on public.kt_lo_nk;
drop trigger if exists kt_lo_nk_cp_gan_dv on public.kt_lo_nk_cp;
drop function if exists public.kt_lo_nk_chot_cp_tg();
drop function if exists public.kt_lo_nk_chot_don_tg();
drop function if exists public.kt_lo_nk_chot_lo_tg();
drop function if exists public.kt_lo_nk_cp_gan_dv_tg();
drop function if exists public.kt_lo_nk_cp_noi_chi(text, bigint[], bigint);
drop function if exists public.kt_lo_nk_chot(text, bigint, boolean);
drop function if exists public.kt_lo_nk_cp_cua_dv(text, bigint);

CREATE OR REPLACE FUNCTION public.kt_luu_lo_nk(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_nam text; v_ma text; v_n int;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if nullif(trim(p_dong->>'ten'), '') is null then raise exception 'Nhập tên lô hàng'; end if;
  if nullif(p_dong->>'ty_gia', '') is not null and (p_dong->>'ty_gia')::numeric <= 0 then raise exception 'Tỷ giá phải lớn hơn 0'; end if;
  if nullif(p_dong->>'dv_vc_id', '') is not null and not exists (select 1 from kt_ncc where id = (p_dong->>'dv_vc_id')::bigint and not da_xoa) then raise exception 'Không thấy đơn vị vận chuyển'; end if;
  if v_id is null then
    v_nam := to_char(coalesce(nullif(p_dong->>'ngay_kh', '')::date, current_date), 'YYYY');
    select coalesce(max(nullif(regexp_replace(ma, '^NK-' || v_nam || '-', ''), ma)::int), 0) + 1 into v_n from kt_lo_nk where ma ~ ('^NK-' || v_nam || '-[0-9]+$');
    v_ma := coalesce(nullif(trim(p_dong->>'ma'), ''), 'NK-' || v_nam || '-' || lpad(v_n::text, 2, '0'));
    if exists (select 1 from kt_lo_nk where ma = v_ma) then raise exception 'Mã hồ sơ % đã có', v_ma; end if;
    insert into kt_lo_nk (ma, ten, trang_thai, so_cont, forwarder, ngay_kh, ngay_du_kien, ngay_ve, tien_te, ty_gia, cach_pb, ghi_chu, tao_boi)
    values (v_ma, trim(p_dong->>'ten'), coalesce(nullif(p_dong->>'trang_thai', ''), 'dat_hang'), nullif(trim(p_dong->>'so_cont'), ''), nullif(trim(p_dong->>'forwarder'), ''),
      nullif(p_dong->>'ngay_kh', '')::date, nullif(p_dong->>'ngay_du_kien', '')::date, nullif(p_dong->>'ngay_ve', '')::date,
      coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'), nullif(p_dong->>'ty_gia', '')::numeric, coalesce(nullif(p_dong->>'cach_pb', ''), 'gia_tri'), nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten)
    returning id into v_id;
  else
    if nullif(trim(p_dong->>'ma'), '') is not null and exists (select 1 from kt_lo_nk where ma = trim(p_dong->>'ma') and id <> v_id) then raise exception 'Mã hồ sơ % đã có', trim(p_dong->>'ma'); end if;
    update kt_lo_nk set ma = coalesce(nullif(trim(p_dong->>'ma'), ''), ma), ten = trim(p_dong->>'ten'), trang_thai = coalesce(nullif(p_dong->>'trang_thai', ''), trang_thai),
      so_cont = nullif(trim(p_dong->>'so_cont'), ''), forwarder = nullif(trim(p_dong->>'forwarder'), ''),
      ngay_kh = nullif(p_dong->>'ngay_kh', '')::date, ngay_du_kien = nullif(p_dong->>'ngay_du_kien', '')::date, ngay_ve = nullif(p_dong->>'ngay_ve', '')::date,
      tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te), ty_gia = nullif(p_dong->>'ty_gia', '')::numeric, cach_pb = coalesce(nullif(p_dong->>'cach_pb', ''), cach_pb),
      ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
    if not found then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  end if;
  update kt_lo_nk set cang_di = nullif(trim(p_dong->>'cang_di'), ''), cang_den = nullif(trim(p_dong->>'cang_den'), ''), dv_xuat_khau = nullif(trim(p_dong->>'dv_xuat_khau'), ''),
    dv_nhan_tien = nullif(trim(p_dong->>'dv_nhan_tien'), ''), dv_mo_tk = nullif(trim(p_dong->>'dv_mo_tk'), ''),
    dv_vc_id = nullif(p_dong->>'dv_vc_id', '')::bigint, ma_van_don = nullif(trim(p_dong->>'ma_van_don'), '') where id = v_id;   -- 21/11 đơn vị vận chuyển + mã vận đơn
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.kt_ds_lo_nk(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(to_jsonb(l) || jsonb_build_object(
      'so_don', (select count(*) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa),
      'ncc', (select coalesce(jsonb_agg(distinct n.ten), '[]') from kt_lo_nk_don d join kt_ncc n on n.id = d.ncc_id where d.lo_id = l.id and not d.da_xoa),
      'gia_tri', (select coalesce(sum(kt_lo_nk_don_vnd(d, l)), 0) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa),
      'gia_tri_te', (select sum(d.gia_tri) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa and coalesce(d.tien_te, l.tien_te) = l.tien_te),
      'chi_phi', (select coalesce(sum(c.so_tien), 0) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and c.tinh_gv)
                   + coalesce((select sum((x->>'so_tien')::numeric) from jsonb_array_elements(kt_lo_nk_phi_tt(l.id)) x), 0),
      'chi_phi_khac', (select coalesce(sum(c.so_tien), 0) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and not c.tinh_gv),
      'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'lo_nk' and ct.dong_id = l.id and not ct.da_xoa),
      'dv_vc_ten', (select ten from kt_ncc where id = l.dv_vc_id),
      'phi_vc', (select coalesce(sum(c.so_tien), 0) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and c.loai in ('van_chuyen_qt', 'van_chuyen_nd')),
      'po_ids', (select coalesce(jsonb_agg(distinct d.po_id), '[]') from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa and d.po_id is not null),
      'kk', kt_lo_nk_kk_tong(l))
    order by coalesce(l.ngay_kh, l.tao_luc::date) desc, l.id desc) from kt_lo_nk l where not l.da_xoa), '[]');
end $function$;

CREATE OR REPLACE FUNCTION public.kt_po_ds(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'ncc');
  return jsonb_build_object(
    'po', coalesce((select jsonb_agg(to_jsonb(p) - 'da_xoa' order by p.ngay desc, p.id desc) from kt_po p where not p.da_xoa), '[]'),
    'ben_mua', (select gia_tri from kt_cai_dat where khoa = 'po_ben_mua'),
    -- phiếu chi đã gắn vào PO (số tiền VND, trạng thái thật trên Thu chi)
    'chi', coalesce((select jsonb_object_agg(c.id, jsonb_build_object('ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'so_tien', c.so_tien, 'tt', c.trang_thai, 'nd', c.noi_dung, 'th', c.thu_huong_ten))
      from kt_chi c where not c.da_xoa and c.id in (select (e)::bigint from kt_po p, jsonb_array_elements_text(p.chi_ids) e where not p.da_xoa)), '{}'),
    -- 21/11 kế toán: PO hiện lô vận chuyển chứa nó (đơn vị, mã vận đơn, các mốc ngày, phí vận chuyển + phiếu chi của phí)
    'lo', coalesce((select jsonb_object_agg(x.po_id, x.ds) from (select d.po_id, jsonb_agg(distinct jsonb_build_object('id', l.id, 'ma', l.ma, 'ten', l.ten, 'trang_thai', l.trang_thai,
        'dv_vc_id', l.dv_vc_id, 'dv_vc_ten', (select ten from kt_ncc where id = l.dv_vc_id), 'forwarder', l.forwarder, 'ma_van_don', l.ma_van_don, 'so_cont', l.so_cont,
        'ngay_kh', l.ngay_kh, 'ngay_du_kien', l.ngay_du_kien, 'ngay_ve', l.ngay_ve, 'so_po', (select count(distinct d2.po_id) from kt_lo_nk_don d2 where d2.lo_id = l.id and not d2.da_xoa and d2.po_id is not null),
        'cp', (select coalesce(jsonb_agg(jsonb_build_object('loai', c.loai, 'nd', c.noi_dung, 'so_tien', c.so_tien, 'chi_id', c.chi_id, 'ngay', c.ngay, 'dvn', c.don_vi_nhan) order by c.ngay nulls last, c.id), '[]')
                 from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa))) ds
      from kt_lo_nk_don d join kt_lo_nk l on l.id = d.lo_id and not l.da_xoa where not d.da_xoa and d.po_id is not null group by d.po_id) x), '{}'));
end $function$;
