-- THANH TOÁN TRUNG GIAN TỰ TRỪ SỐ DƯ TÀI KHOẢN NGUỒN — 19/11/2026. Monsieur Claude
-- Anh: "phần này tách riêng ra khỏi phiếu chi, không liên quan phiếu chi nữa; các khoản ở đây mà thanh toán thì tự ghi nhận và trừ đi ở tài khoản trả tiền
-- tương ứng y như là khoản ở phiếu chi luôn".
-- → kt_v_bien_dong thêm 1 nhánh: mỗi lần thanh toán trung gian (không xoá, có tài khoản nguồn, quy đổi được VND) = 1 khoản CHI của tài khoản nguồn
--   vào ngày chuyển, số tiền = nguyên tệ × tỷ giá (VND thì giữ nguyên) + phí chuyển tiền. Mọi chỗ dùng view (số dư TK, sổ quỹ, Tổng quan, báo cáo dòng tiền,
--   đối soát số dư, so file dòng tiền) tự nhận. Thiếu tỷ giá → CHƯA trừ (trang báo "Chưa trừ — thiếu tỷ giá").
--   Lần cũ còn gắn phiếu chi (chi_id) → phiếu chi đã trừ, không trừ lần 2.
-- → kt_so_quy_ngay: chi tiết sổ quỹ theo ngày hiện thêm dòng "Thanh toán trung gian".
-- → Khoản vay (kt_vay_dong_bo_tt): như phiếu chi đi từ tài khoản vay — lần giải ngân vào CHÍNH tài khoản nguồn (+), lần chuyển đi ra (−);
--   trước đây giải ngân không gắn tài khoản vì lần chuyển không trừ tài khoản nào.

create or replace function public.kt_tt_nn_ra(t kt_tt_nn) returns numeric language sql immutable as $$
  select case when t.tien_te = 'VND' then t.so_tien_nt when t.ty_gia > 0 then round(t.so_tien_nt * t.ty_gia) end + coalesce(t.phi, 0)
$$;

create or replace view public.kt_v_bien_dong as
 SELECT t.tai_khoan_id, t.ngay, 'thu'::text AS kieu, t.so_tien AS vao, 0::numeric AS ra
   FROM kt_thu t WHERE NOT t.da_xoa AND t.trang_thai = 'da_duyet'::text
UNION ALL
 SELECT c.tai_khoan_id, c.ngay_tt AS ngay, 'chi'::text AS kieu, 0 AS vao, c.so_tien AS ra
   FROM kt_chi c WHERE NOT c.da_xoa AND c.trang_thai = 'da_tt'::text
UNION ALL
 SELECT d.tk_di_id AS tai_khoan_id, d.ngay, 'dc'::text AS kieu, 0 AS vao, d.so_tien AS ra
   FROM kt_dieu_chuyen d WHERE NOT d.da_xoa AND NOT kt_dc_cho_nhan(d.tk_nhan_id, d.tq_nhan_luc, d.tao_luc)
UNION ALL
 SELECT d.tk_nhan_id AS tai_khoan_id, d.ngay, 'dc'::text AS kieu, d.so_tien AS vao, 0 AS ra
   FROM kt_dieu_chuyen d WHERE NOT d.da_xoa AND NOT kt_dc_cho_nhan(d.tk_nhan_id, d.tq_nhan_luc, d.tao_luc)
UNION ALL
 SELECT n.tai_khoan_id, n.ngay, 'vay'::text AS kieu, n.so_tien AS vao, 0 AS ra
   FROM kt_vay_nhan n WHERE NOT n.da_xoa AND n.tai_khoan_id IS NOT NULL
UNION ALL
 SELECT r.tai_khoan_id, r.ngay, 'vay'::text AS kieu, 0 AS vao, r.goc + r.lai AS ra
   FROM kt_vay_tra r WHERE NOT r.da_xoa AND r.da_tra AND r.tai_khoan_id IS NOT NULL
UNION ALL
 SELECT tt.tk_id::integer AS tai_khoan_id, tt.ngay, 'chi'::text AS kieu, 0 AS vao, kt_tt_nn_ra(tt) AS ra
   FROM kt_tt_nn tt WHERE NOT tt.da_xoa AND tt.tk_id IS NOT NULL AND tt.chi_id IS NULL AND kt_tt_nn_ra(tt) > 0;

create or replace function public.kt_so_quy_ngay(p_phien text, p_tk integer, p_ngay date)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
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
             'vao', 0, 'ra', kt_tt_nn_ra(tt), 'doi', tt.ben_nhan)
      from kt_tt_nn tt where not tt.da_xoa and tt.tk_id = p_tk and tt.ngay = p_ngay and tt.chi_id is null and kt_tt_nn_ra(tt) > 0) s), '[]');
end $function$;

create or replace function kt_vay_dong_bo_tt(p_id bigint) returns void language plpgsql security definer set search_path = public as $$
declare t kt_tt_nn; tien numeric;
begin
  select * into t from kt_tt_nn where id = p_id;
  if found and t.chi_id is not null and t.vay_id is not null and not coalesce(t.da_xoa, false) then
    update kt_chi set vay_id = t.vay_id where id = t.chi_id and vay_id is distinct from t.vay_id;   -- khoản vay đi theo phiếu chi
  end if;
  tien := kt_tt_nn_ra(t);
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
end $$;
drop trigger if exists kt_vay_tg_tt on kt_tt_nn;
create trigger kt_vay_tg_tt after update of vay_id, chi_id, ngay, so_tien_nt, tien_te, ty_gia, phi, tk_id, ben_nhan, da_xoa on kt_tt_nn
  for each row when (new.vay_id is not null or old.vay_id is not null) execute function kt_vay_tg_tt();
-- đồng bộ lại các lần đã gắn khoản vay (giải ngân cũ chưa gắn tài khoản)
do $$ declare r record; begin for r in select id from kt_tt_nn where vay_id is not null loop perform kt_vay_dong_bo_tt(r.id); end loop; end $$;

-- Nghi trùng: lần thanh toán đã có phiếu chi cùng tài khoản, cùng số tiền (± 10 ngày, phiếu chưa gắn lần nào khác) → trang báo "Nghi trùng PC…",
-- bấm "Dùng phiếu chi này" = gắn chi_id (phiếu chi đã trừ, lần thanh toán không trừ lần 2).
create or replace function public.kt_tt_nn_ds(p_phien text) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $function$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(to_jsonb(t) - 'da_xoa' || jsonb_build_object('tk', (select ten from kt_tai_khoan where id = t.tk_id), 'tk_loai', (select loai from kt_tai_khoan where id = t.tk_id),
      'ra', kt_tt_nn_ra(t),
      'chi', (select jsonb_build_object('id', c.id, 'so_tien', c.so_tien, 'tt', c.trang_thai, 'ngay', c.ngay_tt) from kt_chi c where c.id = t.chi_id and not c.da_xoa),
      'nghi_trung', case when t.chi_id is null and t.tk_id is not null and kt_tt_nn_ra(t) > 0 then (select jsonb_agg(jsonb_build_object('id', c.id, 'ngay', c.ngay_tt, 'nd', left(c.noi_dung, 80)) order by abs(c.ngay_tt - t.ngay))
          from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.tai_khoan_id = t.tk_id and c.ngay_tt between t.ngay - 10 and t.ngay + 10
           and abs(c.so_tien - kt_tt_nn_ra(t)) < 1 and not exists (select 1 from kt_tt_nn o where o.chi_id = c.id and not o.da_xoa)) end) order by t.ngay desc, t.id desc)
    from kt_tt_nn t where not t.da_xoa), '[]');
end $function$;

-- 19/11: lần 6 (VCB DTMO, NCC đèn đồng, tạo 19/11) trùng PC002040 (13/11, cùng TK, cùng số tiền, "Đèn điện đồng…") → gắn để chỉ trừ 1 lần
update kt_tt_nn set chi_id = 2040, sua_boi = 'Hệ thống', sua_luc = now() where id = 6 and chi_id is null
  and exists (select 1 from kt_chi c, kt_tt_nn t where t.id = 6 and c.id = 2040 and not c.da_xoa and c.tai_khoan_id = t.tk_id and abs(c.so_tien - kt_tt_nn_ra(t)) < 1);
