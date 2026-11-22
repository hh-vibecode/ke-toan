-- 14/11/2026 kế toán: bảng kê chi phí nhập khẩu (forwarder) "thì ném vào đâu??" → Hồ sơ nhập khẩu → tab Chi phí → "Tải bảng kê (Excel)":
-- trình duyệt đọc file, kế toán xem trước / sửa, rồi lưu NHIỀU khoản chi phí 1 lần (1 giao dịch — lỗi 1 dòng thì không lưu dòng nào).
-- Mỗi dòng đi qua kt_luu_lo_nk_cp có sẵn (cùng kiểm quyền 'ncc' ghi, kiểm hồ sơ, nhật ký). — Monsieur Claude
create or replace function public.kt_luu_lo_nk_cp_nhieu(p_phien text, p_lo bigint, p_ds jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0;
begin
  perform kt_chan(p_phien, 'ncc', true);
  if jsonb_typeof(p_ds) is distinct from 'array' or jsonb_array_length(p_ds) = 0 then raise exception 'Không có dòng chi phí nào'; end if;
  if jsonb_array_length(p_ds) > 200 then raise exception 'Tối đa 200 dòng mỗi lần'; end if;
  if not exists (select 1 from kt_lo_nk where id = p_lo and not da_xoa) then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  for r in select value from jsonb_array_elements(p_ds) loop
    perform kt_luu_lo_nk_cp(p_phien, (r - 'id' - 'chi_id') || jsonb_build_object('lo_id', p_lo));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.kt_luu_lo_nk_cp_nhieu(text, bigint, jsonb) from public;
grant execute on function public.kt_luu_lo_nk_cp_nhieu(text, bigint, jsonb) to anon, authenticated;
