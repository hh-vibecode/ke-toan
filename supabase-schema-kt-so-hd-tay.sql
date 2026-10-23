-- 23/10/2026 (anh): "cần 1 chỗ khai báo tay mã số hoá đơn — case không bắt được mã, kế toán muốn điền tay sửa lại; 1 slot trong phần hoá đơn đỏ,
-- mặc định là mã gợi ý, nếu đúng thì dùng luôn, không đúng kế toán điền tay lại". Ô "Số hoá đơn" trong khung Hoá đơn đỏ của phiếu chi:
--  · lưu số kế toán khai (kt_chi.so_hd_do) + đánh dấu đã nhận HĐ
--  · thấy ĐÚNG 1 HĐ đầu vào MISA chưa gắn phiếu khác cùng số (ưu tiên số tiền lệch ≤ 1.000 đ; số có chữ thì ký hiệu phải chứa phần chữ) → gắn luôn
--    (thay HĐ đang gắn nếu khác); không thấy thì chỉ lưu số khai tay. Xoá trống = bỏ số khai tay. — Monsieur Claude
alter table kt_chi add column if not exists so_hd_do text;

create or replace function public.kt_dat_so_hd(p_phien text, p_id bigint, p_so text) returns jsonb
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung; c kt_chi; v text := nullif(trim(coalesce(p_so, '')), ''); so text; chu text; h record; n int;
begin
  u := kt_chan(p_phien, 'chi', true);
  select null::text ma_ngoai, null::text so_hd, null::text ky_hieu, null::date ngay, null::text nguoi_mua, null::text mst, null::numeric tong into h;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không thấy phiếu'; end if;
  if v is null then
    update kt_chi set so_hd_do = null, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
    return jsonb_build_object('gan', false);
  end if;
  so := ltrim(regexp_replace(v, '\D', '', 'g'), '0');
  chu := upper(regexp_replace(v, '[^A-Za-z]', '', 'g'));
  with ung as (select t.ma_ngoai, t.so_hd, t.ky_hieu, t.ngay, t.nguoi_mua, t.mst, t.tong from kt_thue_hd t
                where t.nguon like 'misabot:%' and t.ma_ngoai is not null and so <> '' and ltrim(t.so_hd, '0') = so
                  and (chu = '' or upper(coalesce(t.ky_hieu, '')) like '%' || chu || '%')
                  and not exists (select 1 from kt_chi_hd g where g.hd_ma = t.ma_ngoai and g.chi_id <> p_id)),
       tien as (select * from ung where abs(tong - c.so_tien) <= 1000)
  select count(*) into n from (select * from tien union all select * from ung where not exists (select 1 from tien)) z;
  if n = 1 then
    select t.ma_ngoai, t.so_hd, t.ky_hieu, t.ngay, t.nguoi_mua, t.mst, t.tong into h from kt_thue_hd t
     where t.nguon like 'misabot:%' and t.ma_ngoai is not null and ltrim(t.so_hd, '0') = so
       and (chu = '' or upper(coalesce(t.ky_hieu, '')) like '%' || chu || '%')
       and not exists (select 1 from kt_chi_hd g where g.hd_ma = t.ma_ngoai and g.chi_id <> p_id)
     order by abs(t.tong - c.so_tien) limit 1;
    delete from kt_chi_hd where chi_id = p_id and hd_ma <> h.ma_ngoai;
    insert into kt_chi_hd (chi_id, hd_ma, so_hd, ky_hieu, ngay_hd, ncc, mst, tong, cach, boi, ly_do)
      values (p_id, h.ma_ngoai, h.so_hd, h.ky_hieu, h.ngay, h.nguoi_mua, h.mst, h.tong, 'tay', u.ho_ten, 'kế toán khai số HĐ')
      on conflict (chi_id, hd_ma) do update set cach = 'tay', boi = u.ho_ten, ly_do = 'kế toán khai số HĐ', luc = now();
  else
    -- kế toán sửa sang số khác (HĐ gắn trước sai) mà MISA chưa có số này → bỏ HĐ đang gắn, giữ số khai tay
    delete from kt_chi_hd where chi_id = p_id and ltrim(so_hd, '0') <> so;
  end if;
  update kt_chi set so_hd_do = v, co_hd_do = true, hd_do_nhan = true, ngay_nhan_hd = coalesce(ngay_nhan_hd, h.ngay, current_date),
         sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu)
    values (u.ho_ten, 'kt_chi', 'khai_so_hd', jsonb_build_object('chi_id', p_id, 'so', v, 'gan_misa', n = 1, 'hd', h.ma_ngoai));
  return jsonb_build_object('gan', n = 1, 'so_hd', h.so_hd, 'ky_hieu', h.ky_hieu, 'ncc', h.nguoi_mua, 'n', n);
end $f$;
