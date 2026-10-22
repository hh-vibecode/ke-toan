-- 22/10/2026 (anh): "tất cả quỹ ngoài và visa công ty đều là khớp với ĐNTT liên quan tới quỹ ngoài của từng cơ sở rồi, nó không xuất hiện lẻ tẻ trong
-- ĐNTT nữa — xem lại phần so khớp P&L, clear được mấy khoản đấy đi". → khoản trong file chi phí công ty trả bằng quỹ ngoài / thẻ Visa công ty được
-- khớp GỘP với các ĐNTT "thanh toán quỹ ngoài" của cơ sở đó / "thanh toán thẻ Visa" của chủ thẻ đó (so tổng theo tháng), không ghép 1-1. — Monsieur Claude

-- dòng "Thanh toán quỹ ngoài …" / "thanh toán thẻ Visa" có sẵn trong file (đợt nạp lại quỹ) chưa ghép được 1-1 với ĐNTT → cũng tính khớp gộp theo nội dung.
-- nhóm theo nguồn thanh toán ghi trong file chi phí công ty
-- p_dv = đơn vị chịu chi phí (sheet CP RIÊNG TỪNG CƠ SỞ) — dùng khi nguồn chỉ ghi "Tiền Quỹ Ngoài" không kèm cơ sở; "LKT" = quỹ ngoài Chánh Tâm (đơn vị chịu ghi Chánh Tâm)
drop function if exists public.kt_dcp_nhom_cp(text);
create or replace function public.kt_dcp_nhom_cp(p text, p_dv text default null) returns text language sql immutable set search_path = public as $f$
  select case
    when t ~ 'quy ngoai|quy tien mat vp' then case when t ~ 'kho|shidai' then 'QN-SD' when t ~ '\yct\y|\ylkt\y' then 'QN-CT' when t ~ '\yht\y' then 'QN-HT' when t ~ '\yvp\y' then 'QN-VP'
                                                    when dv ~ 'chanh tam' then 'QN-CT' when dv ~ 'hien thuy' then 'QN-HT' when dv ~ 'shidai|sales' then 'QN-SD' else 'QN-VP' end
    when t ~ 'visa|the tin dung|\ythe\y' then case when t ~ 'bich phuong' then 'VS-BP' when t ~ 'chuyen' then 'VS-NTC' when t ~ 'oanh' then 'VS-OANH' when t ~ 'hue' then 'VS-HUE' end
  end from (select kt_bo_dau(coalesce(p, '')) t, kt_bo_dau(coalesce(p_dv, '')) dv) x $f$;

-- nhóm của ĐNTT: "thanh toán quỹ ngoài" (cơ sở theo cờ hoàn quỹ / nội dung) · "thanh toán thẻ Visa" (theo chủ thẻ / số tài khoản thẻ)
create or replace function public.kt_dcp_nhom_dn(p_nd text, p_hq text) returns text language sql immutable set search_path = public as $f$
  select case
    when t ~ 'quy ngoai' then case when p_hq in ('HT', 'CT', 'SD') then 'QN-' || p_hq when t ~ 'hien thuy' then 'QN-HT' when t ~ 'chanh tam|\yct\y' then 'QN-CT'
                                    when t ~ 'shidai|\ykho\y|\ysd\y' then 'QN-SD' else 'QN-VP' end
    when t ~ 'visa|the tin dung' and t !~ 'phi dong the' then case when t ~ 'bich phuong' then 'VS-BP' when t ~ 'chuyen|nguyen thi ch|\yntc\y' then 'VS-NTC'
                                    when t ~ 'oanh|dang thi minh' then 'VS-OANH' when t ~ 'hue|nguyen thi hu' then 'VS-HUE'
                                    when t ~ 'ho xuan thinh' then 'VS-HXT' else 'VS-KHAC' end
  end from (select kt_bo_dau(coalesce(p_nd, '')) t) x $f$;

create or replace function public.kt_ds_dcp_pnl(p_phien text) returns jsonb language plpgsql stable security definer set search_path = public as $f$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not kt_co_quyen(u, 'he_thong') then raise exception 'Tài khoản chưa được cấp quyền xem trang này' using errcode = '42501'; end if;
  return jsonb_build_object(
    'chay_luc', (select max(chay_luc) from kt_dcp_dong),
    'phieu', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'so_tien', c.so_tien, 'nd', c.noi_dung, 'th', c.thu_huong_ten, 'tk', c.tai_khoan_id, 'loai', c.loai_id, 'khop', p.khop,
               'nhom', kt_dcp_nhom_dn(c.noi_dung, c.hoan_quy)) order by coalesce(c.ngay_tt, c.ngay_de_nghi)), '[]') from kt_dcp_phieu p join kt_chi c on c.id = p.chi_id),
    'cp', (select coalesce(jsonb_agg(jsonb_build_object('thang', thang, 'ngay', ngay, 'sheet', sheet, 'nhom', danh_muc, 'nd', noi_dung, 'so_tien', so_tien, 'nguon_tt', nguon_tt, 'chi_id', chi_id, 'dong', dong,
               'gop', coalesce(kt_dcp_nhom_cp(nguon_tt, danh_muc), case when chi_id is null then kt_dcp_nhom_dn(noi_dung, null) end)) order by thang, ngay nulls last, id), '[]') from kt_dcp_dong),
    -- mọi ĐNTT quỹ ngoài / thẻ Visa đã chi (kể cả phiếu trả thẻ không nằm trong danh sách phiếu so khớp), 15/12/2025 → 30/09/2026 để thấy đợt gối đầu
    'gop', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ngay', c.ngay_tt, 'so_tien', c.so_tien, 'nd', c.noi_dung, 'nhom', kt_dcp_nhom_dn(c.noi_dung, c.hoan_quy)) order by c.ngay_tt), '[]')
               from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between '2025-12-15' and '2026-09-30' and kt_dcp_nhom_dn(c.noi_dung, c.hoan_quy) is not null),
    -- 22/10 anh: số file chi phí đã chia cho từng cơ sở theo mục P&L (dòng tiêu đề nhóm, lương, giao vận, MKT) — so với 4 P&L
    'pb', (select coalesce(jsonb_agg(jsonb_build_object('thang', thang, 'cs', cs, 'ma', ma, 'so_tien', so_tien, 'nguon', nguon)), '[]') from kt_dcp_pb),
    'pnl', (select coalesce(jsonb_agg(jsonb_build_object('nguon', nguon, 'thang', thang, 'ma', ma, 'ten', ten, 'target', target, 'th', thuc_hien, 'app', app, 'lech', lech) order by nguon, thang, dong), '[]')
               from kt_pnl_cu));   -- 22/10: lấy cả dòng không mã (P&L Thị trường chỉ ghi tên nhóm ở cột A)
end $f$;
