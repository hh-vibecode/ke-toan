-- 09/11/2026 anh: "có tạo được hoá đơn trên MISA meInvoice sau khi lập đơn trên app không, gửi API ngược lại" → "thế nháp đi".
-- Đơn lập (kt_thue_don, chỉ công ty THT) → Edge Function kt-meinvoice-nhap gọi MISA /invoiceweb/insert tạo HOÁ ĐƠN NHÁP (chưa ký, chưa số);
-- kế toán vào meInvoice kiểm rồi tự ký phát hành. App nhớ RefID nháp (misa_ref) để: đẩy lại (xoá nháp cũ chưa phát hành, tạo nháp mới),
-- xoá nháp, và tự lấy số HĐ khi kế toán đã phát hành (/invoiceweb/getlist) → đơn chuyển "Đã xuất HĐ". — Monsieur Claude
alter table public.kt_thue_don
  add column if not exists misa_ref uuid,
  add column if not exists misa_ky_hieu text,
  add column if not exists misa_luc timestamptz,
  add column if not exists misa_boi text;

-- Edge gọi bằng service_role: kiểm phiên + quyền SỬA trang Hoá đơn & Thuế; p_id có → trả đơn đó; luôn trả các đơn đang chờ phát hành
create or replace function public.kt_thue_don_misa_lay(p_phien text, p_id bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v jsonb;
begin
  u := kt_chan(p_phien, 'hoa_don_thue', p_id is not null);
  if p_id is not null then
    select to_jsonb(d) into v from kt_thue_don d where d.id = p_id;
    if v is null then raise exception 'Không thấy đơn'; end if;
    if v->>'hkd' <> 'CTY' then raise exception 'Chỉ đơn của công ty THT mới đẩy sang MISA meInvoice'; end if;
  end if;
  return jsonb_build_object('nguoi', u.ho_ten, 'don', v,
    'cho', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'ref', d.misa_ref)) from kt_thue_don d
                      where d.misa_ref is not null and coalesce(d.so_hd, '') = ''), '[]'));
end $$;
revoke execute on function public.kt_thue_don_misa_lay(text, bigint) from public, anon, authenticated;
grant execute on function public.kt_thue_don_misa_lay(text, bigint) to service_role;

-- ghi kết quả: p_ref null = đã xoá nháp (bỏ liên kết); p_so_hd = số HĐ MISA đã phát hành → "Đã xuất HĐ"
create or replace function public.kt_thue_don_misa_ghi(p_id bigint, p_ref uuid, p_ky_hieu text, p_nguoi text, p_so_hd text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if nullif(p_so_hd, '') is not null then
    update kt_thue_don set so_hd = p_so_hd, trang_thai = 'Đã xuất HĐ', misa_ky_hieu = coalesce(p_ky_hieu, misa_ky_hieu) where id = p_id;
    perform kt_ghi_nhat_ky('Hệ thống', 'kt_thue_don', p_id, 'misa_phat_hanh', jsonb_build_object('so_hd', p_so_hd, 'ky_hieu', p_ky_hieu));
  else
    update kt_thue_don set misa_ref = p_ref, misa_ky_hieu = case when p_ref is null then null else p_ky_hieu end,
           misa_luc = case when p_ref is null then null else now() end, misa_boi = case when p_ref is null then null else p_nguoi end where id = p_id;
    perform kt_ghi_nhat_ky(coalesce(p_nguoi, 'Hệ thống'), 'kt_thue_don', p_id, case when p_ref is null then 'misa_xoa_nhap' else 'misa_tao_nhap' end,
                           jsonb_build_object('ref', p_ref, 'ky_hieu', p_ky_hieu));
  end if;
end $$;
revoke execute on function public.kt_thue_don_misa_ghi(bigint, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.kt_thue_don_misa_ghi(bigint, uuid, text, text, text) to service_role;
