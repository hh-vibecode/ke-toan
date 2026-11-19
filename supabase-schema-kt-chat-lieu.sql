-- CHẤT LIỆU Ở MỌI NƠI — 19/11/2026. Monsieur Claude
-- Kế toán: "bổ sung thêm cột chất liệu ở tất cả các nơi"; anh: "thêm hết nhé, sửa lại form tí xong chốt nó là form mới".
-- Form đặt hàng (kt_gui_de_xuat) nhận thêm chat_lieu của từng dòng. Dòng PO (kt_po.dong jsonb) lưu nguyên dòng nên tự có chat_lieu; báo giá đã có cột (kt-bao-gia-3).
CREATE OR REPLACE FUNCTION public.kt_gui_de_xuat(p_dong jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_ip text := kt_ip_goi(); v_nguoi text := btrim(regexp_replace(coalesce(p_dong->>'nguoi', ''), '\s+', ' ', 'g'));
  v_dong jsonb; v_id bigint; v_ma text; v_loai text := coalesce(p_dong->>'loai', 'bo_sung'); v_nguon text := nullif(p_dong->>'nguon', ''); nhan int[];
begin
  if (select count(*) from kt_de_xuat_mua where ip = v_ip and tao_luc > now() - interval '1 hour') >= 10 then raise exception 'Gửi quá nhiều trong 1 giờ — thử lại sau'; end if;
  if (select count(*) from kt_de_xuat_mua where tao_luc > now() - interval '1 hour') >= 60 then raise exception 'Hệ thống đang nhận quá nhiều đề xuất — thử lại sau'; end if;
  if length(v_nguoi) < 2 then raise exception 'Nhập họ tên người đề xuất'; end if;
  if v_loai not in ('bo_sung', 'khach_dat', 'trung_bay') then raise exception 'Loại đề xuất không hợp lệ'; end if;
  if not exists (select 1 from kt_don_vi where id = nullif(p_dong->>'bo_phan_id', '')::int and hoat_dong) then raise exception 'Chọn cơ sở / bộ phận'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('ma', left(btrim(coalesce(e->>'ma', '')), 40), 'ten', left(btrim(coalesce(e->>'ten', '')), 200),
           'quy_cach', left(btrim(coalesce(e->>'quy_cach', '')), 200), 'sl', greatest(0, coalesce(nullif(e->>'sl', '')::numeric, 0)), 'ghi_chu', left(btrim(coalesce(e->>'ghi_chu', '')), 300),
           'mau', left(btrim(coalesce(e->>'mau', '')), 60), 'kt', left(btrim(coalesce(e->>'kt', '')), 80), 'chat_lieu', left(btrim(coalesce(e->>'chat_lieu', '')), 80), 'dvt', left(btrim(coalesce(e->>'dvt', '')), 20),
           'gia_ban', nullif(e->>'gia_ban', '')::numeric)), '[]')
    into v_dong from jsonb_array_elements(case when jsonb_typeof(p_dong->'dong') = 'array' then p_dong->'dong' else '[]' end) e
   where btrim(coalesce(e->>'ma', '') || coalesce(e->>'ten', '')) <> '';
  if jsonb_array_length(v_dong) = 0 then raise exception 'Nhập ít nhất 1 mặt hàng'; end if;
  if jsonb_array_length(v_dong) > 200 then raise exception 'Tối đa 200 mặt hàng / đơn'; end if;
  if v_loai = 'trung_bay' and coalesce(v_nguon, '') not in ('noi', 'ngoai') then raise exception 'Chọn đặt từ NCC trong nước hay NCC nước ngoài'; end if;
  if v_loai <> 'trung_bay' then v_nguon := null; end if;
  if exists (select 1 from jsonb_array_elements(v_dong) e where (e->>'sl')::numeric <= 0) then raise exception 'Nhập số lượng cho từng mặt hàng'; end if;
  if nullif(p_dong->>'ngay_can', '') is null then raise exception 'Nhập ngày cần hàng'; end if;
  if exists (select 1 from jsonb_array_elements(v_dong) e where e->>'ten' = '') then raise exception 'Nhập tên hàng cho từng dòng'; end if;
  if exists (select 1 from jsonb_array_elements(v_dong) e where e->>'ma' = '' and e->>'mau' = '' and e->>'kt' = '') then raise exception 'Hàng chưa có mã Kiot: nhập màu hoặc kích thước'; end if;
  if v_loai = 'khach_dat' and (coalesce(btrim(p_dong->'khach'->>'ten'), '') = '' or coalesce(btrim(p_dong->'khach'->>'sdt'), '') = '' or coalesce(btrim(p_dong->'khach'->>'ma_don'), '') = ''
       or nullif(p_dong->'khach'->>'coc', '') is null or coalesce(btrim(p_dong->'khach'->>'phieu_coc'), '') = '' or nullif(p_dong->'khach'->>'hen_giao', '') is null) then
    raise exception 'Đơn khách đặt riêng: nhập đủ tên khách, SĐT, mã đơn Kiot, tiền cọc, phiếu thu cọc, hẹn giao'; end if;
  insert into kt_de_xuat_mua (loai, nguoi, bo_phan_id, ngay_can, uu_tien, dong, khach, ghi_chu, ip, ncc_ten, nguon)
  values (v_loai, left(v_nguoi, 100), (p_dong->>'bo_phan_id')::int, nullif(p_dong->>'ngay_can', '')::date, case when p_dong->>'uu_tien' = 'gap' then 'gap' else 'thuong' end,
    v_dong, case when v_loai = 'khach_dat' then jsonb_build_object('ten', left(btrim(p_dong->'khach'->>'ten'), 120), 'sdt', left(btrim(coalesce(p_dong->'khach'->>'sdt', '')), 30),
      'ma_don', left(btrim(coalesce(p_dong->'khach'->>'ma_don', '')), 40), 'coc', nullif(p_dong->'khach'->>'coc', '')::numeric, 'hen_giao', nullif(p_dong->'khach'->>'hen_giao', ''),
      'phieu_coc', left(btrim(coalesce(p_dong->'khach'->>'phieu_coc', '')), 40)) end,
    left(nullif(btrim(p_dong->>'ghi_chu'), ''), 1000), v_ip, nullif(left(btrim(coalesce(p_dong->>'ncc_ten', '')), 150), ''), v_nguon) returning id into v_id;
  v_ma := encode(gen_random_bytes(18), 'hex');
  update kt_de_xuat_mua set ma_hash = encode(digest(v_ma, 'sha256'), 'hex') where id = v_id;
  select array_agg(id) into nhan from kt_nguoi_dung where hoat_dong and (vi_tri in ('supreme', 'admin') or 'ncc:ghi' = any(quyen));
  perform kt_bao(nhan, v_nguoi, 'de_xuat_mua', case v_loai when 'khach_dat' then 'Đơn hàng khách đặt mới' when 'trung_bay' then 'Cửa hàng đặt trưng bày mới' else 'Đề xuất bổ sung cửa hàng mới' end,
    'DX' || lpad(v_id::text, 5, '0') || ' · ' || v_nguoi || ' · ' || jsonb_array_length(v_dong) || ' mặt hàng' || case when p_dong->>'uu_tien' = 'gap' then ' · GẤP' else '' end, 'de_xuat', v_id);
  perform kt_ghi_nhat_ky(v_nguoi, 'kt_de_xuat_mua', v_id, 'them', jsonb_build_object('loai', v_loai, 'so_dong', jsonb_array_length(v_dong)));
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $function$
;
