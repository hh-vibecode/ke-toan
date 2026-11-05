-- 05/11/2026 kế toán: "các bạn muốn xem tất cả đề nghị thanh toán đã làm để xem sót khoản nào không — hiện chỉ hiển thị 5 dòng".
-- Trạng thái nhiều phiếu 1 lần theo mã bí mật từng phiếu (máy đã gửi nhớ mã) — giống trang theo dõi #phieu=<mã>, không lộ phiếu người khác. — Monsieur Claude
create or replace function public.kt_xem_de_nghi_ds(p_ds text[])
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('ma', m.ma, 'id', c.id, 'ngay_de_nghi', c.ngay_de_nghi, 'noi_dung', c.noi_dung, 'so_tien', c.so_tien,
           'trang_thai', c.trang_thai, 'ngay_tt', c.ngay_tt) order by c.id desc), '[]')
    from (select distinct unnest(p_ds[1:500]) ma) m
    join kt_chi_phieu p on p.ma_hash = encode(digest(coalesce(m.ma, ''), 'sha256'), 'hex')
    join kt_chi c on c.id = p.chi_id and not c.da_xoa
$$;
revoke execute on function public.kt_xem_de_nghi_ds(text[]) from public;
grant execute on function public.kt_xem_de_nghi_ds(text[]) to anon, authenticated;
