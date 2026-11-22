-- Số dư từng tài khoản cho trang "Sổ quỹ & số dư tài khoản" (19/10/2026, anh: "bổ sung quyền nhìn giao dịch từng TK cho admin").
-- Trước: trang gọi kt_bao_cao (chặn theo quyền Tổng quan) → tài khoản chỉ có quyền Sổ quỹ (dong_tien) bị lỗi.
-- Nay hàm riêng, chặn theo quyền dong_tien, chỉ trả số dư tài khoản + số dư thực tế (không lộ doanh thu / chi phí của Tổng quan).
-- (sửa cùng ngày: thêm vay_vao / vay_ra để thẻ Thu / Chi trong kỳ tách riêng khoản vay)
-- Cột Thu / Chi tính cả khoản vay (nhận vay → Thu, trả nợ vay → Chi) cho khớp cột Cuối kỳ. — Monsieur Claude
create or replace function public.kt_so_du_tk(p_phien text, p_tu date, p_den date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'dong_tien');
  return jsonb_build_object(
    'tai_khoan', (with
      bd as (select b.* from kt_v_bien_dong b join kt_tai_khoan tk on tk.id = b.tai_khoan_id where b.ngay >= tk.ngay_ton_dau),
      ton as (
        select tk.id, tk.ten, tk.loai, tk.hoat_dong, tk.thu_tu,
          tk.ton_dau + coalesce(sum(b.vao - b.ra) filter (where b.ngay < p_tu), 0) as dau_ky,
          coalesce(sum(b.vao) filter (where b.ngay between p_tu and p_den and b.kieu in ('thu','vay')), 0) as thu,
          coalesce(sum(b.ra)  filter (where b.ngay between p_tu and p_den and b.kieu in ('chi','vay')), 0) as chi,
          coalesce(sum(b.vao - b.ra) filter (where b.ngay between p_tu and p_den and b.kieu = 'dc'), 0) as dc,
          coalesce(sum(b.vao) filter (where b.ngay between p_tu and p_den and b.kieu = 'vay'), 0) as vay_vao,
          coalesce(sum(b.ra)  filter (where b.ngay between p_tu and p_den and b.kieu = 'vay'), 0) as vay_ra,
          tk.ton_dau + coalesce(sum(b.vao - b.ra) filter (where b.ngay <= p_den), 0) as cuoi_ky
        from kt_tai_khoan tk left join bd b on b.tai_khoan_id = tk.id
        group by tk.id)
      select coalesce(jsonb_agg(to_jsonb(ton) order by thu_tu, id), '[]') from ton
       where hoat_dong or dau_ky <> 0 or cuoi_ky <> 0 or thu <> 0 or chi <> 0 or dc <> 0),
    'thuc_te', (select coalesce(jsonb_agg(jsonb_build_object('tk', tai_khoan_id, 'ngay', ngay, 'so_tien', so_tien)), '[]') from (
       select distinct on (tai_khoan_id) tai_khoan_id, ngay, so_tien from kt_ton_thuc_te where ngay <= p_den
        order by tai_khoan_id, ngay desc) x));
end $$;
revoke all on function public.kt_so_du_tk(text, date, date) from public;
grant execute on function public.kt_so_du_tk(text, date, date) to anon;
