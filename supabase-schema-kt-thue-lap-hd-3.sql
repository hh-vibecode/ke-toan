-- 10/11/2026 anh (ảnh màn Lập hoá đơn meInvoice): "phần tạo đơn sửa thành giao diện dữ liệu như meInvoice, lắp phần hàng hoá đề xuất vào để kéo thả"
-- → đơn lưu thêm thông tin người mua + ký hiệu (cột mua jsonb: ky_hieu, mst, ten_dv, dia_chi, nguoi_mua, sdt, email, cccd, httt, tk_nh, ten_nh). — Monsieur Claude
alter table public.kt_thue_don add column if not exists mua jsonb;

CREATE OR REPLACE FUNCTION public.kt_thue_don_luu(p_phien text, p_don jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
declare u kt_nguoi_dung; v_id bigint := (p_don->>'id')::bigint; v_xoa boolean := coalesce((p_don->>'xoa')::boolean, false);
begin
  u := kt_chan(p_phien, 'hoa_don_thue', true);
  if v_xoa then
    delete from kt_thue_don where id = v_id;
  else
    if coalesce(p_don->>'hkd', '') not in ('CTY', 'CT', 'HT') then raise exception 'Đơn vị không hợp lệ'; end if;
    if jsonb_typeof(p_don->'dong') <> 'array' or jsonb_array_length(p_don->'dong') = 0 then raise exception 'Đơn chưa có dòng hàng nào'; end if;
    -- dòng gõ tay (không mã) + dòng ghi chú (tc = 4) như meInvoice: cần tên; dòng hàng cần số lượng > 0
    if exists (select 1 from jsonb_array_elements(p_don->'dong') d where coalesce(trim(d->>'ten'), trim(d->>'ma'), '') = ''
                 or (coalesce((d->>'tc')::int, 1) <> 4 and coalesce((d->>'sl')::numeric, 0) <= 0)) then
      raise exception 'Mỗi dòng cần tên hàng và số lượng > 0'; end if;
    if v_id is null then
      insert into kt_thue_don (hkd, ngay, khach, mst, gia_tri, gom_thue, thue_suat, bien, dong, tien_hang, tien_thue, tong, trang_thai, so_hd, ghi_chu, tao_boi, ts_nhom, mua)
      select p_don->>'hkd', coalesce((p_don->>'ngay')::date, current_date), nullif(trim(p_don->>'khach'), ''), nullif(trim(p_don->>'mst'), ''),
             (p_don->>'gia_tri')::numeric, coalesce((p_don->>'gom_thue')::boolean, true), (p_don->>'thue_suat')::numeric, coalesce((p_don->>'bien')::numeric, 0),
             p_don->'dong', (p_don->>'tien_hang')::numeric, (p_don->>'tien_thue')::numeric, (p_don->>'tong')::numeric,
             coalesce(nullif(p_don->>'trang_thai', ''), 'Nháp'), nullif(trim(p_don->>'so_hd'), ''), nullif(trim(p_don->>'ghi_chu'), ''), u.ho_ten, coalesce((p_don->>'ts_nhom')::boolean, false), case when jsonb_typeof(p_don->'mua') = 'object' then p_don->'mua' end
      returning id into v_id;
    else
      update kt_thue_don set hkd = p_don->>'hkd', ngay = coalesce((p_don->>'ngay')::date, ngay), khach = nullif(trim(p_don->>'khach'), ''), mst = nullif(trim(p_don->>'mst'), ''),
             gia_tri = (p_don->>'gia_tri')::numeric, gom_thue = coalesce((p_don->>'gom_thue')::boolean, true), thue_suat = (p_don->>'thue_suat')::numeric,
             bien = coalesce((p_don->>'bien')::numeric, 0), dong = p_don->'dong', tien_hang = (p_don->>'tien_hang')::numeric, tien_thue = (p_don->>'tien_thue')::numeric,
             tong = (p_don->>'tong')::numeric, trang_thai = coalesce(nullif(p_don->>'trang_thai', ''), trang_thai), so_hd = nullif(trim(p_don->>'so_hd'), ''),
             ghi_chu = nullif(trim(p_don->>'ghi_chu'), ''), ts_nhom = coalesce((p_don->>'ts_nhom')::boolean, false), mua = case when jsonb_typeof(p_don->'mua') = 'object' then p_don->'mua' else mua end, sua_boi = u.ho_ten, sua_luc = now()
       where id = v_id;
      if not found then raise exception 'Không thấy đơn'; end if;
    end if;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_thue_don', v_id, case when v_xoa then 'xoa' when (p_don->>'id') is null then 'them' else 'sua' end, p_don - 'dong');
  return v_id;
end $$;
