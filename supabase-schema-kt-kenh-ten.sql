-- Tên kênh bán hiển thị (16/10/2026, anh Hải) — Monsieur Claude
--  · không ghi kênh / "Bán trực tiếp"  → "Bán trực tiếp tại cửa hàng"
--  · "Facebook" chung (nhân viên gắn sai) → đi theo chi nhánh: Facebook Chánh Tâm / Hiền Thuỷ / Shidai
--  · "Siêu thị Phật Giáo Hiền Thuỷ" thực chất là Shopee → "Shopee Hiền Thuỷ"
-- Chỉ đổi TÊN hiển thị trong báo cáo, không sửa dữ liệu kéo từ Kiot.
create or replace function public.kt_kenh_ten(p_ten text, p_cn text)
returns text language sql immutable set search_path = public as $$
  select case
    when p_ten is null or p_ten = 'Bán trực tiếp' then 'Bán trực tiếp tại cửa hàng'
    when p_ten in ('Facebook', 'Facebook1') then
      case when p_cn ilike '%Chánh Tâm%' then 'Facebook Chánh Tâm'
           when p_cn ilike '%Shidai%' then 'Facebook Shidai'
           when p_cn ilike '%Hiền%' then 'Facebook Hiền Thuỷ'
           else 'Facebook' end
    when p_ten = 'Siêu thị Phật Giáo Hiền Thuỷ' then 'Shopee Hiền Thuỷ'
    else p_ten end
$$;
revoke all on function public.kt_kenh_ten(text, text) from public, anon, authenticated;

-- vá hàm đang chạy (lấy định nghĩa sống, thay đúng chỗ)
do $$
declare d text;
begin
  d := pg_get_functiondef('public.kt_tq_don'::regproc);
  if position('coalesce(k.ten, ''Không ghi kênh (bán tại quầy)'') ten' in d) = 0 then raise exception 'kt_tq_don: khong thay cho can sua'; end if;
  d := replace(d, 'coalesce(k.ten, ''Không ghi kênh (bán tại quầy)'') ten', 'kt_kenh_ten(k.ten, h.chi_nhanh) ten');
  execute d;

  d := pg_get_functiondef('public.kt_bc_qt'::regproc);
  if position('coalesce(kn.ten, ''Không ghi kênh'') kenh' in d) = 0 or position('coalesce(k.ten, ''Không ghi kênh (bán tại quầy)'') ten' in d) = 0 then raise exception 'kt_bc_qt: khong thay cho can sua'; end if;
  d := replace(d, 'coalesce(kn.ten, ''Không ghi kênh'') kenh', 'kt_kenh_ten(kn.ten, o.chi_nhanh) kenh');
  d := replace(d, 'coalesce(k.ten, ''Không ghi kênh (bán tại quầy)'') ten', 'kt_kenh_ten(k.ten, h.chi_nhanh) ten');
  execute d;
end $$;
