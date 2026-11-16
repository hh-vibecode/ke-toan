-- 16/11/2026 kế toán (anh chuyển 2 ảnh góp ý): form đề xuất bỏ NCC / mã NCC / quy cách / đơn giá dự kiến, thêm giá bán cho khách;
-- "Bổ sung cửa hàng" gộp bổ sung + trưng bày; người mua hàng tách theo NCC (gợi ý từ phiếu nhập Kiot gần nhất của mã) → mỗi NCC 1 PO,
-- dòng PO giữ dx_id + dx_i → đề xuất "Đã đặt PO" khi đủ mọi dòng; Đơn khách đặt riêng theo dõi từng mặt hàng (PO nào, về lô / cont nào).
-- Hồ sơ nhập khẩu: cảng đi, cảng đến, đơn vị đứng tên xuất khẩu, đơn vị nhận tiền thanh toán, đơn vị dịch vụ mở tờ khai. — Monsieur Claude

alter table kt_lo_nk add column if not exists cang_di text, add column if not exists cang_den text, add column if not exists dv_xuat_khau text,
  add column if not exists dv_nhan_tien text, add column if not exists dv_mo_tk text;

CREATE OR REPLACE FUNCTION public.kt_gui_de_xuat(p_dong jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_ip text := kt_ip_goi(); v_nguoi text := btrim(regexp_replace(coalesce(p_dong->>'nguoi', ''), '\s+', ' ', 'g'));
  v_dong jsonb; v_id bigint; v_ma text; v_loai text := coalesce(p_dong->>'loai', 'bo_sung'); nhan int[];
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
  if jsonb_array_length(v_dong) > 50 then raise exception 'Tối đa 50 mặt hàng / đề xuất'; end if;
  if exists (select 1 from jsonb_array_elements(v_dong) e where (e->>'sl')::numeric <= 0) then raise exception 'Nhập số lượng cho từng mặt hàng'; end if;
  if nullif(p_dong->>'ngay_can', '') is null then raise exception 'Nhập ngày cần hàng'; end if;
  if exists (select 1 from jsonb_array_elements(v_dong) e where e->>'ten' = '') then raise exception 'Nhập tên hàng cho từng dòng'; end if;
  if exists (select 1 from jsonb_array_elements(v_dong) e where e->>'ma' = '' and e->>'mau' = '' and e->>'kt' = '') then raise exception 'Hàng chưa có mã Kiot: nhập màu hoặc kích thước'; end if;
  if v_loai = 'khach_dat' and (coalesce(btrim(p_dong->'khach'->>'ten'), '') = '' or coalesce(btrim(p_dong->'khach'->>'sdt'), '') = '' or coalesce(btrim(p_dong->'khach'->>'ma_don'), '') = ''
       or nullif(p_dong->'khach'->>'coc', '') is null or coalesce(btrim(p_dong->'khach'->>'phieu_coc'), '') = '' or nullif(p_dong->'khach'->>'hen_giao', '') is null) then
    raise exception 'Đơn khách đặt riêng: nhập đủ tên khách, SĐT, mã đơn Kiot, tiền cọc, phiếu thu cọc, hẹn giao'; end if;
  insert into kt_de_xuat_mua (loai, nguoi, bo_phan_id, ngay_can, uu_tien, dong, khach, ghi_chu, ip, ncc_ten)
  values (v_loai, left(v_nguoi, 100), (p_dong->>'bo_phan_id')::int, nullif(p_dong->>'ngay_can', '')::date, case when p_dong->>'uu_tien' = 'gap' then 'gap' else 'thuong' end,
    v_dong, case when v_loai = 'khach_dat' then jsonb_build_object('ten', left(btrim(p_dong->'khach'->>'ten'), 120), 'sdt', left(btrim(coalesce(p_dong->'khach'->>'sdt', '')), 30),
      'ma_don', left(btrim(coalesce(p_dong->'khach'->>'ma_don', '')), 40), 'coc', nullif(p_dong->'khach'->>'coc', '')::numeric, 'hen_giao', nullif(p_dong->'khach'->>'hen_giao', ''),
      'phieu_coc', left(btrim(coalesce(p_dong->'khach'->>'phieu_coc', '')), 40)) end,
    left(nullif(btrim(p_dong->>'ghi_chu'), ''), 1000), v_ip, nullif(left(btrim(coalesce(p_dong->>'ncc_ten', '')), 150), '')) returning id into v_id;
  v_ma := encode(gen_random_bytes(18), 'hex');
  update kt_de_xuat_mua set ma_hash = encode(digest(v_ma, 'sha256'), 'hex') where id = v_id;
  select array_agg(id) into nhan from kt_nguoi_dung where hoat_dong and (vi_tri in ('supreme', 'admin') or 'ncc:ghi' = any(quyen));
  perform kt_bao(nhan, v_nguoi, 'de_xuat_mua', case v_loai when 'khach_dat' then 'Đơn khách đặt riêng mới' when 'trung_bay' then 'Đề xuất hàng trưng bày mới' else 'Đề xuất bổ sung cửa hàng mới' end,
    'DX' || lpad(v_id::text, 5, '0') || ' · ' || v_nguoi || ' · ' || jsonb_array_length(v_dong) || ' mặt hàng' || case when p_dong->>'uu_tien' = 'gap' then ' · GẤP' else '' end, 'de_xuat', v_id);
  perform kt_ghi_nhat_ky(v_nguoi, 'kt_de_xuat_mua', v_id, 'them', jsonb_build_object('loai', v_loai, 'so_dong', jsonb_array_length(v_dong)));
  return jsonb_build_object('id', v_id, 'ma', v_ma);
end $function$;

CREATE OR REPLACE FUNCTION public.kt_dx_ds(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'loai', d.loai, 'nguoi', d.nguoi, 'ncc', d.ncc_ten, 'bo_phan', (select ten from kt_don_vi where id = d.bo_phan_id), 'ngay_can', d.ngay_can,
      'uu_tien', d.uu_tien, 'khach', d.khach, 'ghi_chu', d.ghi_chu, 'trang_thai', d.trang_thai, 'ly_do', d.ly_do, 'xu_ly_boi', d.xu_ly_boi, 'xu_ly_luc', d.xu_ly_luc, 'tao_luc', d.tao_luc,
      'po_id', d.po_id, 'po', (select so from kt_po where id = d.po_id),
      'po_dong', (select coalesce(jsonb_agg(jsonb_build_object('i', (x->>'dx_i')::int, 'po_id', p.id, 'so', p.so, 'tt', p.trang_thai, 'ncc', p.ncc_ten, 'giao', p.ngay_giao,
          'lo', (select jsonb_build_object('id', l.id, 'ma', l.ma, 'cont', l.so_cont, 'tt', l.trang_thai, 've', coalesce(l.ngay_ve, l.ngay_du_kien)) from kt_lo_nk_don ld join kt_lo_nk l on l.id = ld.lo_id
                  where ld.po_id = p.id and not ld.da_xoa and not l.da_xoa order by l.id desc limit 1))), '[]')
         from kt_po p, jsonb_array_elements(p.dong) x where not p.da_xoa and p.trang_thai <> 'huy' and x->>'dx_id' = d.id::text and x ? 'dx_i'),
      'anh', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ten', c.ten_file, 'mime', c.mime) order by c.id), '[]') from kt_chung_tu c where c.bang = 'de_xuat' and c.dong_id = d.id and not c.da_xoa),
      'dong', (select coalesce(jsonb_agg(e || jsonb_build_object('ton', (select h.ton from kt_kiot_hang h where h.ma = e->>'ma' limit 1), 'ten_kiot', (select h.ten from kt_kiot_hang h where h.ma = e->>'ma' limit 1),
        'ncc_gy', case when coalesce(e->>'ma', '') <> '' then (select jsonb_build_object('ten', n.ncc_ten, 'ma', n.ncc_ma, 'gia', (c->>'gia')::numeric, 'ngay', (n.ngay at time zone 'Asia/Ho_Chi_Minh')::date)
          from kt_kiot_nhap_hang n, jsonb_array_elements(n.chi_tiet) c where n.chi_tiet @> jsonb_build_array(jsonb_build_object('ma', e->>'ma')) and c->>'ma' = e->>'ma'
           and n.trang_thai is distinct from 4 and n.ncc_ten is not null order by n.ngay desc limit 1) end)), '[]')
               from jsonb_array_elements(d.dong) e)) order by (d.trang_thai = 'cho_duyet') desc, (d.uu_tien = 'gap') desc, d.id desc)
    from kt_de_xuat_mua d where not d.da_xoa and (d.trang_thai = 'cho_duyet' or d.tao_luc > now() - interval '120 days')), '[]');
end $function$;

CREATE OR REPLACE FUNCTION public.kt_dx_xu_ly(p_phien text, p_id bigint, p_tt text, p_ly_do text, p_po bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_tt text := p_tt; v_co int; v_thieu int;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if p_tt = 'da_dat' then
    select count(*) filter (where exists (select 1 from kt_po p, jsonb_array_elements(p.dong) z where not p.da_xoa and p.trang_thai <> 'huy' and z->>'dx_id' = p_id::text and z->>'dx_i' = (e.i - 1)::text)),
           count(*) filter (where not exists (select 1 from kt_po p, jsonb_array_elements(p.dong) z where not p.da_xoa and p.trang_thai <> 'huy' and z->>'dx_id' = p_id::text and z->>'dx_i' = (e.i - 1)::text))
      into v_co, v_thieu from kt_de_xuat_mua d, jsonb_array_elements(d.dong) with ordinality e(v, i) where d.id = p_id;
    if v_co > 0 and v_thieu > 0 then v_tt := 'da_duyet'; end if;   -- mới đặt một phần (còn NCC khác chưa tạo PO)
  end if;
  if p_tt not in ('cho_duyet', 'da_duyet', 'da_dat', 'tu_choi') then raise exception 'Trạng thái không hợp lệ'; end if;
  if p_tt = 'tu_choi' and coalesce(btrim(p_ly_do), '') = '' then raise exception 'Ghi lý do từ chối'; end if;
  update kt_de_xuat_mua set trang_thai = v_tt, ly_do = nullif(btrim(p_ly_do), ''), po_id = coalesce(p_po, case when p_tt in ('da_dat', 'da_duyet') then po_id end),
    xu_ly_boi = coalesce(u.ho_ten, u.ten_dang_nhap), xu_ly_luc = now() where id = p_id and not da_xoa;
  if not found then raise exception 'Không tìm thấy đề xuất'; end if;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_de_xuat_mua', p_id, p_tt, jsonb_build_object('ly_do', p_ly_do, 'po', p_po));
end $function$;

CREATE OR REPLACE FUNCTION public.kt_xem_de_xuat(p_ma text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d kt_de_xuat_mua := kt_dx_theo_ma(p_ma, false);
begin
  return jsonb_build_object('id', d.id, 'loai', d.loai, 'nguoi', d.nguoi, 'tao_luc', d.tao_luc, 'ngay_can', d.ngay_can, 'uu_tien', d.uu_tien, 'dong', d.dong, 'khach', d.khach,
    'trang_thai', d.trang_thai, 'ly_do', d.ly_do, 'xu_ly_luc', d.xu_ly_luc, 'so_file', d.so_file, 'tai_them', d.tao_luc > now() - interval '3 hours',
    'po', (select so from kt_po where id = d.po_id), 'po_tt', (select trang_thai from kt_po where id = d.po_id), 'po_giao', (select ngay_giao from kt_po where id = d.po_id), 'ncc', d.ncc_ten,
    'po_dong', (select coalesce(jsonb_agg(jsonb_build_object('i', (x->>'dx_i')::int, 'so', p.so, 'tt', p.trang_thai, 'giao', p.ngay_giao)), '[]')
       from kt_po p, jsonb_array_elements(p.dong) x where not p.da_xoa and p.trang_thai <> 'huy' and x->>'dx_id' = d.id::text and x ? 'dx_i'));
end $function$;

CREATE OR REPLACE FUNCTION public.kt_luu_lo_nk(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_nam text; v_ma text; v_n int;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if nullif(trim(p_dong->>'ten'), '') is null then raise exception 'Nhập tên lô hàng'; end if;
  if nullif(p_dong->>'ty_gia', '') is not null and (p_dong->>'ty_gia')::numeric <= 0 then raise exception 'Tỷ giá phải lớn hơn 0'; end if;
  if v_id is null then
    v_nam := to_char(coalesce(nullif(p_dong->>'ngay_kh', '')::date, current_date), 'YYYY');
    select coalesce(max(nullif(regexp_replace(ma, '^NK-' || v_nam || '-', ''), ma)::int), 0) + 1 into v_n from kt_lo_nk where ma ~ ('^NK-' || v_nam || '-[0-9]+$');
    v_ma := coalesce(nullif(trim(p_dong->>'ma'), ''), 'NK-' || v_nam || '-' || lpad(v_n::text, 2, '0'));
    if exists (select 1 from kt_lo_nk where ma = v_ma) then raise exception 'Mã hồ sơ % đã có', v_ma; end if;
    insert into kt_lo_nk (ma, ten, trang_thai, so_cont, forwarder, ngay_kh, ngay_du_kien, ngay_ve, tien_te, ty_gia, cach_pb, ghi_chu, tao_boi)
    values (v_ma, trim(p_dong->>'ten'), coalesce(nullif(p_dong->>'trang_thai', ''), 'dat_hang'), nullif(trim(p_dong->>'so_cont'), ''), nullif(trim(p_dong->>'forwarder'), ''),
      nullif(p_dong->>'ngay_kh', '')::date, nullif(p_dong->>'ngay_du_kien', '')::date, nullif(p_dong->>'ngay_ve', '')::date,
      coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'), nullif(p_dong->>'ty_gia', '')::numeric, coalesce(nullif(p_dong->>'cach_pb', ''), 'gia_tri'), nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten)
    returning id into v_id;
  else
    if nullif(trim(p_dong->>'ma'), '') is not null and exists (select 1 from kt_lo_nk where ma = trim(p_dong->>'ma') and id <> v_id) then raise exception 'Mã hồ sơ % đã có', trim(p_dong->>'ma'); end if;
    update kt_lo_nk set ma = coalesce(nullif(trim(p_dong->>'ma'), ''), ma), ten = trim(p_dong->>'ten'), trang_thai = coalesce(nullif(p_dong->>'trang_thai', ''), trang_thai),
      so_cont = nullif(trim(p_dong->>'so_cont'), ''), forwarder = nullif(trim(p_dong->>'forwarder'), ''),
      ngay_kh = nullif(p_dong->>'ngay_kh', '')::date, ngay_du_kien = nullif(p_dong->>'ngay_du_kien', '')::date, ngay_ve = nullif(p_dong->>'ngay_ve', '')::date,
      tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te), ty_gia = nullif(p_dong->>'ty_gia', '')::numeric, cach_pb = coalesce(nullif(p_dong->>'cach_pb', ''), cach_pb),
      ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
    if not found then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  end if;
  update kt_lo_nk set cang_di = nullif(trim(p_dong->>'cang_di'), ''), cang_den = nullif(trim(p_dong->>'cang_den'), ''), dv_xuat_khau = nullif(trim(p_dong->>'dv_xuat_khau'), ''),
    dv_nhan_tien = nullif(trim(p_dong->>'dv_nhan_tien'), ''), dv_mo_tk = nullif(trim(p_dong->>'dv_mo_tk'), '') where id = v_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $function$;
