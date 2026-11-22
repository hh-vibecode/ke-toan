-- Thủ quỹ theo dõi hoá đơn đỏ xuất về 2 HKD (19/10/2026, anh: "TK thủ quỹ theo dõi thủ công toàn bộ hoá đơn đỏ xuất về 2 HKD,
-- bổ sung phần lọc theo HKD để thủ quỹ follow đi đòi hoá đơn"). — Monsieur Claude
-- 1) Thủ quỹ (chi_tt) thấy mọi phiếu ĐÃ CHI có cần hoá đơn đỏ (trước chỉ thấy phiếu chi từ két / TK công ty)
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_ds'::regproc); n := length(d);
  d := replace(d, $a$or (kt_co_quyen(u, 'chi_tt') and c.trang_thai in ('cho_tt','da_tt') and exists (select 1 from kt_tai_khoan t where t.id = c.tai_khoan_id and t.thu_quy_chi))$a$,
                  $a$or (kt_co_quyen(u, 'chi_tt') and c.trang_thai in ('cho_tt','da_tt') and exists (select 1 from kt_tai_khoan t where t.id = c.tai_khoan_id and t.thu_quy_chi))
          or (kt_co_quyen(u, 'chi_tt') and c.trang_thai = 'da_tt' and c.co_hd_do)$a$);
  if length(d) = n then raise exception 'kt_ds: khong thay cho'; end if; execute d;
end $$;

-- 2) Đánh dấu hoá đơn đỏ (cần / chưa nhận / đã nhận + ngày) và "hoá đơn xuất về" — kế toán (chi:ghi) hoặc thủ quỹ (chi_tt)
create or replace function public.kt_dat_hd_do(p_phien text, p_id bigint, p_trang text default null, p_ngay date default null, p_hd_ve text default null)
returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi;
begin
  u := kt_chan(p_phien);
  if not kt_co_quyen(u, 'chi', true) and not kt_co_quyen(u, 'chi_tt') then
    raise exception 'Tài khoản chưa được cấp quyền cập nhật hoá đơn phiếu chi' using errcode = '42501';
  end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi #%', p_id; end if;
  if not kt_co_quyen(u, 'chi', true) and not (c.trang_thai = 'da_tt' and (c.co_hd_do or p_trang is not null)) then
    raise exception 'Thủ quỹ chỉ cập nhật hoá đơn của phiếu đã chi' using errcode = '42501';
  end if;
  if p_trang is not null and p_trang not in ('khong','chua','da') then raise exception 'Trạng thái hoá đơn không hợp lệ'; end if;
  update kt_chi set
    co_hd_do     = case when p_trang is null then co_hd_do else p_trang <> 'khong' end,
    hd_do_nhan   = case when p_trang is null then hd_do_nhan else p_trang = 'da' end,
    ngay_nhan_hd = case when p_trang = 'da' then coalesce(p_ngay, ngay_nhan_hd, (now() at time zone 'Asia/Ho_Chi_Minh')::date)
                        when p_trang is null then ngay_nhan_hd else null end,
    hd_ve        = case when p_hd_ve is null then hd_ve else nullif(p_hd_ve, '') end,
    sua_boi = u.ho_ten, sua_luc = now()
   where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'sua', jsonb_strip_nulls(jsonb_build_object('hoa_don', p_trang, 'ngay_nhan_hd', p_ngay, 'hd_ve', p_hd_ve)));
end $$;
revoke all on function public.kt_dat_hd_do(text, bigint, text, date, text) from public;
grant execute on function public.kt_dat_hd_do(text, bigint, text, date, text) to anon;
