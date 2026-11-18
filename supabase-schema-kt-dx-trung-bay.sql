-- 18/11/2026 kế toán: "đơn đặt hàng cho sales và cửa hàng chia 2 mục: cửa hàng đặt trưng bày · sản phẩm có khách đặt; trưng bày nhảy vào PO (phân biệt NCC trong nước / nước ngoài),
-- khách đặt nhảy vào Khách hàng" → cột nguon (noi / ngoai) cho đơn trưng bày; nâng giới hạn 50 → 200 mặt hàng / đơn (cửa hàng có file order lớn). — Monsieur Claude
alter table kt_de_xuat_mua add column if not exists nguon text;
do $$ begin if not exists (select 1 from pg_constraint where conname = 'kt_de_xuat_mua_nguon_ck') then
  alter table kt_de_xuat_mua add constraint kt_de_xuat_mua_nguon_ck check (nguon is null or nguon in ('noi', 'ngoai')); end if; end $$;

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
           'mau', left(btrim(coalesce(e->>'mau', '')), 60), 'kt', left(btrim(coalesce(e->>'kt', '')), 80), 'dvt', left(btrim(coalesce(e->>'dvt', '')), 20),
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

CREATE OR REPLACE FUNCTION public.kt_dx_ds(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'loai', d.loai, 'nguon', d.nguon, 'nguoi', d.nguoi, 'ncc', d.ncc_ten, 'bo_phan', (select ten from kt_don_vi where id = d.bo_phan_id), 'ngay_can', d.ngay_can,
      'uu_tien', d.uu_tien, 'khach', d.khach, 'ghi_chu', d.ghi_chu, 'trang_thai', d.trang_thai, 'ly_do', d.ly_do, 'xu_ly_boi', d.xu_ly_boi, 'xu_ly_luc', d.xu_ly_luc, 'tao_luc', d.tao_luc,
      'po_id', d.po_id, 'po', (select so from kt_po where id = d.po_id),
      'po_dong', (select coalesce(jsonb_agg(jsonb_build_object('i', (x->>'dx_i')::int, 'po_id', p.id, 'so', p.so, 'tt', p.trang_thai, 'ncc', p.ncc_ten, 'giao', p.ngay_giao,
          'lo', (select jsonb_build_object('id', l.id, 'ma', l.ma, 'cont', l.so_cont, 'tt', l.trang_thai, 've', coalesce(l.ngay_ve, l.ngay_du_kien)) from kt_lo_nk_don ld join kt_lo_nk l on l.id = ld.lo_id
                  where ld.po_id = p.id and not ld.da_xoa and not l.da_xoa order by l.id desc limit 1))), '[]')
         from kt_po p, jsonb_array_elements(p.dong) x where not p.da_xoa and p.trang_thai <> 'huy' and x->>'dx_id' = d.id::text and x ? 'dx_i'),
      'anh', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ten', c.ten_file, 'mime', c.mime) order by c.id), '[]') from kt_chung_tu c where c.bang = 'de_xuat' and c.dong_id = d.id and not c.da_xoa),
      'dong', (select coalesce(jsonb_agg(e || jsonb_build_object('ton', (select h.ton from kt_kiot_hang h where h.ma = e->>'ma' limit 1), 'ten_kiot', (select h.ten from kt_kiot_hang h where h.ma = e->>'ma' limit 1), 'anh_kiot', (select h.anh from kt_kiot_hang h where h.ma = e->>'ma' and h.anh is not null limit 1),
        'ncc_gy', case when coalesce(e->>'ma', '') <> '' then (select jsonb_build_object('ten', n.ncc_ten, 'ma', n.ncc_ma, 'gia', (c->>'gia')::numeric, 'ngay', (n.ngay at time zone 'Asia/Ho_Chi_Minh')::date)
          from kt_kiot_nhap_hang n, jsonb_array_elements(n.chi_tiet) c where n.chi_tiet @> jsonb_build_array(jsonb_build_object('ma', e->>'ma')) and c->>'ma' = e->>'ma'
           and n.trang_thai is distinct from 4 and n.ncc_ten is not null order by n.ngay desc limit 1) end)), '[]')
               from jsonb_array_elements(d.dong) e)) order by (d.trang_thai = 'cho_duyet') desc, (d.uu_tien = 'gap') desc, d.id desc)
    from kt_de_xuat_mua d where not d.da_xoa and (d.trang_thai = 'cho_duyet' or d.tao_luc > now() - interval '120 days')), '[]');
end $function$
;
