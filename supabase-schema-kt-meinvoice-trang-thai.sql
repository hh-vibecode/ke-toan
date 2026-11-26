-- 26/11/2026 kế toán: "trừ VAT P&L lấy đúng theo hoá đơn đã xuất trên meInvoice trong tháng".
-- Bản kéo HĐ ra (Edge kt-meinvoice) trước chỉ lưu số tiền + "Điều chỉnh / thay thế HĐ ..." → không phân biệt HĐ bị huỷ / bị thay thế / điều chỉnh.
-- Nay lưu thêm các trường trạng thái MISA trả về trong /invoice/paging (tài liệu "InvoiceStatus"):
--   EInvoiceStatus 1 gốc · 2 bị huỷ · 3 thay thế · 5 điều chỉnh; RefInvoiceStatus 3 / 5 + EInvoiceStatus 1 = bị thay thế / bị điều chỉnh;
--   ReferenceType 0 gốc · 1 thay thế · 2 điều chỉnh · 5 chiết khấu thương mại; PublishStatus 1 đã phát hành. — Monsieur Claude
alter table kt_thue_hd add column if not exists misa jsonb;

create or replace function public.kt_nap_meinvoice(p_thang text, p_ds jsonb) returns integer language plpgsql security definer set search_path = public as $function$
declare n int;
begin
  if p_thang !~ '^\d{4}-\d{2}$' then raise exception 'tháng sai: %', p_thang; end if;
  delete from kt_thue_hd where nguon = 'meinvoice:' || p_thang;
  insert into kt_thue_hd (hkd, chieu, so_hd, mau, ky_hieu, ngay, mst, nguoi_mua, ten, thanh_tien, tien_thue, tong, ghi_chu, nguon, ma_ngoai, misa)
  select 'CTY', 'ra', x->>'so_hd', x->>'mau', x->>'ky_hieu', (x->>'ngay')::date, nullif(x->>'mst', ''), x->>'nguoi_mua', x->>'ten',
         (x->>'thanh_tien')::numeric, (x->>'tien_thue')::numeric, (x->>'tong')::numeric, nullif(x->>'ghi_chu', ''), 'meinvoice:' || p_thang, nullif(x->>'ma', ''),
         nullif(x->'misa', '{}'::jsonb)
    from jsonb_array_elements(p_ds) x;
  get diagnostics n = row_count;
  return n;
end $function$;
revoke all on function public.kt_nap_meinvoice(text, jsonb) from public, anon, authenticated;
notify pgrst, 'reload schema';
