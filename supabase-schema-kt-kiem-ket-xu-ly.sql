-- 22/10/2026 (anh): kiểm két 21/10 hiện "thiếu" dù lúc kiểm đã khớp — "lệch thì ghi nhận hôm qua lệch, nay giải quyết rồi thì xem thêm lịch sử xử lý
-- để biết hôm qua thiếu nhưng giờ đã khớp". → mỗi lần kiểm két trả thêm 'xu_ly' = các phiếu thu / chi / điều chuyển của két đó, ngày ≤ ngày kiểm,
-- được thêm / sửa / xoá / xác nhận SAU giờ kiểm (theo nhật ký) → app hiện sổ sách lúc kiểm + sổ sách hiện tại + lịch sử. — Monsieur Claude
create or replace function public.kt_ds_kiem_quy(p_phien text, p_tu date, p_den date) returns jsonb language plpgsql security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'kiem_ket');
  return coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'tk', k.tai_khoan_id, 'ngay', k.ngay, 'so_dem', k.so_dem, 'so_sach', kt_so_du_ngay(k.tai_khoan_id, k.ngay),
      'so_sach_luc_kiem', k.so_sach, 'menh_gia', k.menh_gia, 'ghi_chu', k.ghi_chu, 'nguoi', coalesce(k.sua_boi, k.tao_boi), 'luc', coalesce(k.sua_luc, k.tao_luc),
      'so_anh', (select count(*) from kt_chung_tu c where c.bang = 'kiem_quy' and c.dong_id = k.id and not c.da_xoa),
      'xu_ly', (select coalesce(jsonb_agg(x order by x->>'luc'), '[]') from (
          select jsonb_build_object('luc', n.luc, 'nguoi', n.nguoi, 'viec', n.hanh_dong, 'bang', n.bang, 'id', n.dong_id, 'ngay', coalesce(t.ngay, c.ngay_tt, d.ngay),
                   'nd', left(coalesce(t.noi_dung, c.noi_dung, d.noi_dung), 120), 'xoa', coalesce(t.da_xoa, c.da_xoa, d.da_xoa),
                   'tien', case when t.id is not null then t.so_tien when c.id is not null then -c.so_tien when d.tk_nhan_id = k.tai_khoan_id then d.so_tien else -d.so_tien end) x
            from kt_nhat_ky n
            left join kt_thu t on n.bang = 'kt_thu' and t.id = n.dong_id and t.tai_khoan_id = k.tai_khoan_id
            left join kt_chi c on n.bang = 'kt_chi' and c.id = n.dong_id and c.tai_khoan_id = k.tai_khoan_id
            left join kt_dieu_chuyen d on n.bang = 'kt_dieu_chuyen' and d.id = n.dong_id and k.tai_khoan_id in (d.tk_di_id, d.tk_nhan_id)
           where n.luc > coalesce(k.sua_luc, k.tao_luc) and n.bang in ('kt_thu', 'kt_chi', 'kt_dieu_chuyen')
             and coalesce(t.id, c.id, d.id) is not null and coalesce(t.ngay, c.ngay_tt, d.ngay) <= k.ngay) s)
    ) order by k.ngay desc, k.tai_khoan_id)
    from kt_kiem_quy k where k.ngay between p_tu and p_den), '[]');
end $f$;
