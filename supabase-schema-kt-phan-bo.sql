-- PHÂN BỔ CHI PHÍ & KỲ GHI NHẬN — làm SAU khi lập phiếu, ở khung chi tiết phiếu chi (kế toán chị Jaycie 14/10/2026). Monsieur Claude
-- "Phần phân bổ chi phí nên để kế toán thực hiện sau, đừng cho vào khi làm phiếu chi cho phức tạp … ai có quyền sẽ được cập nhật ở mục đó."
--   · phan_bo       : chia cho đơn vị chịu chi phí (Tổng công ty / HT / CT / SD) — tự nhập, chia đều, hoặc theo % doanh số thực đạt tháng
--   · phan_bo_thang : chia chi phí ra nhiều tháng [{thang:'YYYY-MM', so_tien}] — CHỈ dùng cho báo cáo Lãi / lỗ;
--                     dòng tiền / số dư vẫn trừ đúng ngày thanh toán (kế toán: "phục vụ báo cáo dòng tiền thì sẽ phải trừ tiền luôn")
-- Quyền: kế toán duyệt chi (chi_duyet). Tổng mỗi phần phải đúng bằng số tiền phiếu.
alter table public.kt_chi add column if not exists phan_bo_thang jsonb;

create or replace function public.kt_luu_phan_bo(p_phien text, p_id bigint, p_phan_bo jsonb, p_phan_bo_thang jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; v_t1 numeric; v_t2 numeric;
begin
  u := kt_chan(p_phien, 'chi');
  if not kt_co_quyen(u, 'chi_duyet') then raise exception 'Chỉ kế toán (quyền duyệt chi) được phân bổ chi phí' using errcode = '42501'; end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi'; end if;
  if jsonb_typeof(p_phan_bo) <> 'array' or jsonb_array_length(p_phan_bo) = 0 then raise exception 'Chọn ít nhất 1 đơn vị chịu chi phí'; end if;
  select sum((x->>'so_tien')::numeric) into v_t1 from jsonb_array_elements(p_phan_bo) x;
  if abs(coalesce(v_t1, 0) - c.so_tien) > 1 then raise exception 'Tổng phân bổ đơn vị (%) khác số tiền phiếu (%)', v_t1, c.so_tien; end if;
  if p_phan_bo_thang is not null and jsonb_typeof(p_phan_bo_thang) = 'array' and jsonb_array_length(p_phan_bo_thang) > 0 then
    select sum((x->>'so_tien')::numeric) into v_t2 from jsonb_array_elements(p_phan_bo_thang) x;
    if abs(coalesce(v_t2, 0) - c.so_tien) > 1 then raise exception 'Tổng phân bổ theo tháng (%) khác số tiền phiếu (%)', v_t2, c.so_tien; end if;
    if exists (select 1 from jsonb_array_elements(p_phan_bo_thang) x where coalesce(x->>'thang', '') !~ '^\d{4}-\d{2}$') then raise exception 'Tháng phân bổ sai dạng'; end if;
  else p_phan_bo_thang := null;
  end if;
  update kt_chi set phan_bo = p_phan_bo, phan_bo_thang = p_phan_bo_thang, sua_luc = now(), sua_boi = u.ho_ten where id = p_id;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_chi', 'phan_bo', jsonb_build_object('id', p_id, 'phan_bo', p_phan_bo, 'phan_bo_thang', p_phan_bo_thang));
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.kt_luu_phan_bo(text, bigint, jsonb, jsonb) from public;
grant execute on function public.kt_luu_phan_bo(text, bigint, jsonb, jsonb) to anon, authenticated;

-- doanh số thực đạt (hoá đơn Kiot hoàn thành − trả hàng) từng cơ sở trong 1 tháng — để chia chi phí theo %
create or replace function public.kt_dt_thang_cs(p_phien text, p_thang text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d1 date := (p_thang || '-01')::date; d2 date := ((p_thang || '-01')::date + interval '1 month')::date - 1;
begin
  perform kt_chan(p_phien, 'chi');
  return coalesce((select jsonb_object_agg(cn, dt) from (
    select h.chi_nhanh cn, sum(h.tong) - coalesce((select sum(t.tong_tra) from kt_kiot_tra_hang t where coalesce(t.trang_thai, 1) = 1 and t.chi_nhanh = h.chi_nhanh
             and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between d1 and d2), 0) dt
      from kt_kiot_hoa_don h where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between d1 and d2 group by 1) x), '{}');
end $$;
revoke execute on function public.kt_dt_thang_cs(text, text) from public;
grant execute on function public.kt_dt_thang_cs(text, text) to anon, authenticated;
