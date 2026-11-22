-- 03/11/2026 anh: "mấy phần ảnh hoá đơn ấy, xem lại xem" — xem hoá đơn từ phiếu chi / phiếu thu / trang Hoá đơn:
-- (1) kt_hd_xem nhận thêm p_ma (mã MISA ma_ngoai, phiếu đã gắn HĐ thì biết sẵn) → tra đúng 1 HĐ, không nhầm HĐ khác cùng số + ngày;
-- (2) quyền: trang Hoá đơn & Thuế, HOẶC trang Phiếu chi / Phiếu thu khi HĐ đó đã gắn vào phiếu chi / thu (thủ quỹ không có quyền
--     trang Hoá đơn vẫn bấm Xem được HĐ của phiếu mình) — trước chỉ nhận quyền Hoá đơn & Thuế;
-- (3) trả thêm 'pdf' (đã có bản lưu sẵn ở kt-chung-tu chưa) để trang báo đúng "đang mở" / "lấy từ MISA lần đầu";
-- (4) kt_thue_hd_ds trả thêm 'ma' (ma_ngoai) để trang Hoá đơn gửi mã khi bấm xem. — Monsieur Claude
drop function if exists public.kt_hd_xem(text, text, text, date);
create or replace function public.kt_hd_xem(p_phien text, p_so_hd text, p_hkd text, p_ngay date, p_ma text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v jsonb; m text; ks text; hid bigint;
begin
  u := kt_chan(p_phien);   -- chỉ kiểm phiên; quyền kiểm dưới theo HĐ
  -- mã gắn phiếu: phiếu chi (kt_chi_hd.hd_ma) = mã MISA ma_ngoai; phiếu thu (kt_thu_hd.hd_ma) = "ký hiệu-số" HĐ bán ra
  if nullif(p_ma, '') is not null then
    select h.id into hid from kt_thue_hd h where h.ma_ngoai = p_ma order by h.id limit 1;
    if hid is null then select h.id into hid from kt_thue_hd h where h.chieu = 'ra' and h.ky_hieu = split_part(p_ma, '-', 1) and h.so_hd = substr(p_ma, length(split_part(p_ma, '-', 1)) + 2) order by (h.ma_ngoai is null), h.id limit 1; end if;
  else
    select h.id into hid from kt_thue_hd h where h.hkd = p_hkd and h.ngay = p_ngay and (h.so_hd = p_so_hd or ltrim(h.so_hd, '0') = ltrim(p_so_hd, '0'))
     order by (h.ma_ngoai is null), h.id limit 1;
  end if;
  if hid is null then return null; end if;
  select jsonb_build_object('chieu', h.chieu, 'nguon', split_part(h.nguon, ':', 1), 'ma', h.ma_ngoai, 'ky_hieu', h.ky_hieu, 'so_hd', h.so_hd, 'ngay', h.ngay,
           'nguoi_mua', h.nguoi_mua, 'mst', h.mst, 'thanh_tien', h.thanh_tien, 'tien_thue', h.tien_thue, 'tong', h.tong, 'ghi_chu', h.ghi_chu,
           'pdf', exists (select 1 from kt_hd_pdf p where p.ma = h.ma_ngoai)), h.ma_ngoai, h.ky_hieu || '-' || h.so_hd
    into v, m, ks from kt_thue_hd h where h.id = hid;
  if not (kt_co_quyen(u, 'hoa_don_thue')
       or (m is not null and kt_co_quyen(u, 'chi') and exists (select 1 from kt_chi_hd c where c.hd_ma = m))
       or (kt_co_quyen(u, 'thu') and exists (select 1 from kt_thu_hd t where t.hd_ma = ks))) then
    raise exception 'Tài khoản chưa được cấp quyền xem hoá đơn này' using errcode = '42501';
  end if;
  return v;
end $$;
revoke execute on function public.kt_hd_xem(text, text, text, date, text) from public;
grant execute on function public.kt_hd_xem(text, text, text, date, text) to anon, authenticated;

create or replace function public.kt_thue_hd_ds(p_phien text, p_tu date, p_den date, p_chieu text, p_hkd text default null, p_tim text default null)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  select coalesce(jsonb_agg(x order by x->>'ngay' desc, x->>'so_hd' desc), '[]') into r from (
    select jsonb_build_object('hkd', hkd, 'ky_hieu', ky_hieu, 'mau', max(mau), 'so_hd', so_hd, 'ngay', ngay, 'mst', max(mst), 'doi_tac', max(nguoi_mua),
      'thanh_tien', sum(thanh_tien), 'tien_thue', sum(coalesce(tien_thue, 0)), 'tong', sum(coalesce(tong, thanh_tien + coalesce(tien_thue, 0))),
      'so_dong', case when max(nguon) like 'misabot:%' then max(dong) else count(*) end, 'ten', max(ten), 'ghi_chu', max(ghi_chu),
      'nguon', case when max(nguon) like 'meinvoice:%' then 'MISA meInvoice' when max(nguon) like 'misabot:%' then 'MISA Xử lý HĐ' else '3TShop' end,
      'ma', ma_ngoai) x
    from kt_thue_hd
    where chieu = p_chieu and ngay between p_tu and p_den and (p_hkd is null or hkd = p_hkd)
      and (p_tim is null or so_hd ilike '%' || p_tim || '%' or nguoi_mua ilike '%' || p_tim || '%' or mst ilike '%' || p_tim || '%' or ten ilike '%' || p_tim || '%')
    group by hkd, ky_hieu, so_hd, ngay, ma_ngoai limit 2000) t;   -- ma_ngoai: HĐ đầu vào MISA khác NCC có thể trùng ký hiệu + số + ngày
  return r;
end $function$;
