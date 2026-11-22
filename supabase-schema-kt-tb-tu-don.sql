-- 21/10/2026 (anh: "cái nào xử lý xong thì clear cả trong này luôn"): thông báo việc đã xử lý xong tự đánh dấu đã đọc
-- (phiếu đã qua bước / đã xoá / đã xác nhận). Gọi mỗi lần đếm / mở chuông. Thông báo bình luận, kết quả (đã duyệt, từ chối…) giữ nguyên. — Monsieur Claude
create or replace function public.kt_don_thong_bao(p_uid integer) returns void
 language sql security definer set search_path = public as $$
  update kt_thong_bao b set da_doc = true
   where not b.da_doc and (p_uid is null or b.nguoi_dung_id = p_uid) and (
     (b.bang = 'chi' and b.dong_id is not null and exists (select 1 from kt_chi c where c.id = b.dong_id and (
        c.da_xoa
        or (b.loai in ('chi_moi','chi_kiot') and c.trang_thai <> 'cho_duyet')
        or (b.loai = 'chi_cho_gd' and c.trang_thai <> 'cho_gd')
        or (b.loai = 'chi_cho_tt' and c.trang_thai <> 'cho_tt')
        or (b.loai = 'chi_lap_lenh' and (c.trang_thai <> 'cho_tt' or c.lap_lenh_luc is null))
        or (b.loai = 'chi_trung' and (c.nghi_trung is null or c.trang_thai in ('tu_choi','tu_choi_tt'))))))
     or (b.bang = 'chi' and b.dong_id is not null and b.loai in ('chi_moi','chi_kiot','chi_cho_gd','chi_cho_tt','chi_trung','chi_lap_lenh')
         and not exists (select 1 from kt_chi c where c.id = b.dong_id))
     or (b.loai = 'chi_kiot' and b.dong_id is null
         and not exists (select 1 from kt_chi c where not c.da_xoa and c.nguon = 'kiot' and c.trang_thai = 'cho_duyet'))
     or (b.bang = 'dieu_chuyen' and b.loai = 'dc_moi' and exists (select 1 from kt_dieu_chuyen d where d.id = b.dong_id and (d.da_xoa or d.da_xac_nhan))));
$$;
revoke all on function public.kt_don_thong_bao(integer) from public, anon;

create or replace function public.kt_dem_thong_bao(p_phien text)
 returns integer language plpgsql security definer set search_path to 'public' as $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  perform kt_don_thong_bao(u.id);
  return (select count(*) from kt_thong_bao where nguoi_dung_id = u.id and not da_doc);
end $function$;

select kt_don_thong_bao(null);
