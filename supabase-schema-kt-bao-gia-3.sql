-- BÁO GIÁ NCC THEO MẪU PO — 19/11/2026. Monsieur Claude
-- Kế toán 19/11: báo giá "thiết kế lại đúng như PO, bỏ đúng cột số lượng đặt"; bỏ MOQ; thêm Chất liệu, Kích thước (cả file mẫu);
-- "ở phần đặt hàng nút thêm vào báo giá luôn, đỡ phải tạo lại sản phẩm đó trên báo giá lần nữa".
-- → kt_bao_gia thêm mau / kt / chat_lieu (cột như dòng PO: mau, kt, quy_cach); kt_bg_luu + kt_bg_nhap ghi 3 cột này;
--   kt_bg_nhap nhận thêm anh_ct / anh (dòng PO / đơn đặt đã có ảnh → báo giá dùng luôn ảnh đó). kt_bg_ds trả to_jsonb(b) nên tự có cột mới.
-- MOQ: cột giữ trong bảng (dữ liệu cũ), app thôi hiện / thôi nhập.
alter table public.kt_bao_gia add column if not exists mau text, add column if not exists kt text, add column if not exists chat_lieu text;

create or replace function public.kt_bg_luu(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v bigint := nullif(p_dong->>'id', '')::bigint; v_ten text; c kt_bao_gia;
begin
  u := kt_chan(p_phien, 'ncc', true); v_ten := coalesce(u.ho_ten, u.ten_dang_nhap);
  if coalesce(btrim(p_dong->>'ten'), '') = '' then raise exception 'Nhập tên hàng'; end if;
  if coalesce(nullif(p_dong->>'gia', '')::numeric, 0) <= 0 then raise exception 'Nhập đơn giá'; end if;
  if nullif(p_dong->>'ncc_id', '') is null then raise exception 'Chọn nhà cung cấp'; end if;
  if v is null then
    insert into kt_bao_gia (ma_tht, ma_ncc, ten, nhom, mau, kt, chat_lieu, quy_cach, dvt, ncc_id, ncc_ten, gia, tien_te, tg_sx, ngay, anh, anh_ct, ghi_chu, tao_boi)
    values (nullif(btrim(p_dong->>'ma_tht'), ''), nullif(btrim(p_dong->>'ma_ncc'), ''), btrim(p_dong->>'ten'), nullif(btrim(p_dong->>'nhom'), ''),
      nullif(btrim(p_dong->>'mau'), ''), nullif(btrim(p_dong->>'kt'), ''), nullif(btrim(p_dong->>'chat_lieu'), ''), nullif(btrim(p_dong->>'quy_cach'), ''),
      nullif(btrim(p_dong->>'dvt'), ''), (p_dong->>'ncc_id')::bigint, p_dong->>'ncc_ten', (p_dong->>'gia')::numeric, coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'),
      nullif(p_dong->>'tg_sx', '')::int, coalesce(nullif(p_dong->>'ngay', '')::date, current_date), nullif(p_dong->>'anh', ''),
      nullif(p_dong->>'anh_ct', '')::bigint, nullif(btrim(p_dong->>'ghi_chu'), ''), v_ten) returning id into v;
  else
    select * into c from kt_bao_gia where id = v and not da_xoa;
    if not found then raise exception 'Không tìm thấy sản phẩm báo giá'; end if;
    update kt_bao_gia set ma_tht = nullif(btrim(p_dong->>'ma_tht'), ''), ma_ncc = nullif(btrim(p_dong->>'ma_ncc'), ''), ten = btrim(p_dong->>'ten'), nhom = nullif(btrim(p_dong->>'nhom'), ''),
      mau = nullif(btrim(p_dong->>'mau'), ''), kt = nullif(btrim(p_dong->>'kt'), ''), chat_lieu = nullif(btrim(p_dong->>'chat_lieu'), ''),
      quy_cach = nullif(btrim(p_dong->>'quy_cach'), ''), dvt = nullif(btrim(p_dong->>'dvt'), ''), ncc_id = (p_dong->>'ncc_id')::bigint, ncc_ten = p_dong->>'ncc_ten',
      gia = (p_dong->>'gia')::numeric, tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te), tg_sx = nullif(p_dong->>'tg_sx', '')::int,
      ngay = coalesce(nullif(p_dong->>'ngay', '')::date, ngay), anh = coalesce(nullif(p_dong->>'anh', ''), anh), anh_ct = coalesce(nullif(p_dong->>'anh_ct', '')::bigint, anh_ct),
      ghi_chu = nullif(btrim(p_dong->>'ghi_chu'), ''), la_mau = false, sua_boi = v_ten, sua_luc = now(),
      lich_su = case when c.gia is distinct from (p_dong->>'gia')::numeric or c.tien_te is distinct from coalesce(nullif(p_dong->>'tien_te', ''), c.tien_te)
                     then c.lich_su || jsonb_build_array(jsonb_build_object('gia', c.gia, 'tien_te', c.tien_te, 'ngay', c.ngay)) else c.lich_su end
    where id = v;
  end if;
  perform kt_ghi_nhat_ky(v_ten, 'kt_bao_gia', v, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v;
end $$;

create or replace function public.kt_bg_nhap(p_phien text, p_ncc bigint, p_ncc_ten text, p_ds jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_ten text; r jsonb; c kt_bao_gia; v bigint; ids bigint[] := '{}'; moi int := 0; cn int := 0;
begin
  u := kt_chan(p_phien, 'ncc', true); v_ten := coalesce(u.ho_ten, u.ten_dang_nhap);
  if p_ncc is null then raise exception 'Chọn nhà cung cấp'; end if;
  if jsonb_typeof(p_ds) <> 'array' or jsonb_array_length(p_ds) = 0 then raise exception 'File không có dòng nào'; end if;
  if jsonb_array_length(p_ds) > 2000 then raise exception 'Tối đa 2000 dòng / lần'; end if;
  for r in select * from jsonb_array_elements(p_ds) loop
    if coalesce(btrim(r->>'ten'), '') = '' and coalesce(btrim(r->>'ma_ncc'), '') = '' then ids := ids || null::bigint; continue; end if;
    c := null;
    select * into c from kt_bao_gia b where not b.da_xoa and b.ncc_id = p_ncc and (
        (nullif(btrim(r->>'ma_ncc'), '') is not null and lower(b.ma_ncc) = lower(btrim(r->>'ma_ncc')))
     or (nullif(btrim(r->>'ma_ncc'), '') is null and nullif(btrim(r->>'ma_tht'), '') is not null and b.ma_tht = btrim(r->>'ma_tht'))
     or (nullif(btrim(r->>'ma_ncc'), '') is null and nullif(btrim(r->>'ma_tht'), '') is null and lower(b.ten) = lower(btrim(r->>'ten'))))
     order by b.id limit 1;
    if c.id is null then
      insert into kt_bao_gia (ma_tht, ma_ncc, ten, nhom, mau, kt, chat_lieu, quy_cach, dvt, ncc_id, ncc_ten, gia, tien_te, moq, ngay, anh, anh_ct, ghi_chu, tao_boi)
      values (nullif(btrim(r->>'ma_tht'), ''), nullif(btrim(r->>'ma_ncc'), ''), coalesce(nullif(btrim(r->>'ten'), ''), btrim(r->>'ma_ncc')), nullif(btrim(r->>'nhom'), ''),
        nullif(btrim(r->>'mau'), ''), nullif(btrim(r->>'kt'), ''), nullif(btrim(r->>'chat_lieu'), ''),
        nullif(btrim(r->>'quy_cach'), ''), nullif(btrim(r->>'dvt'), ''), p_ncc, p_ncc_ten, nullif(r->>'gia', '')::numeric, coalesce(nullif(r->>'tien_te', ''), 'CNY'),
        nullif(r->>'moq', '')::numeric, coalesce(nullif(r->>'ngay', '')::date, current_date), nullif(r->>'anh', ''), nullif(r->>'anh_ct', '')::bigint,
        nullif(btrim(r->>'ghi_chu'), ''), v_ten) returning id into v;
      moi := moi + 1;
    else
      v := c.id;
      update kt_bao_gia set ma_tht = coalesce(nullif(btrim(r->>'ma_tht'), ''), ma_tht), ten = coalesce(nullif(btrim(r->>'ten'), ''), ten), nhom = coalesce(nullif(btrim(r->>'nhom'), ''), nhom),
        mau = coalesce(nullif(btrim(r->>'mau'), ''), mau), kt = coalesce(nullif(btrim(r->>'kt'), ''), kt), chat_lieu = coalesce(nullif(btrim(r->>'chat_lieu'), ''), chat_lieu),
        quy_cach = coalesce(nullif(btrim(r->>'quy_cach'), ''), quy_cach), dvt = coalesce(nullif(btrim(r->>'dvt'), ''), dvt),
        gia = coalesce(nullif(r->>'gia', '')::numeric, gia), tien_te = coalesce(nullif(r->>'tien_te', ''), tien_te), moq = coalesce(nullif(r->>'moq', '')::numeric, moq),
        ngay = coalesce(nullif(r->>'ngay', '')::date, current_date), anh = coalesce(anh, nullif(r->>'anh', '')), anh_ct = coalesce(anh_ct, nullif(r->>'anh_ct', '')::bigint),
        ghi_chu = coalesce(nullif(btrim(r->>'ghi_chu'), ''), ghi_chu), la_mau = false, sua_boi = v_ten, sua_luc = now(),
        lich_su = case when nullif(r->>'gia', '') is not null and (c.gia is distinct from (r->>'gia')::numeric or c.tien_te is distinct from coalesce(nullif(r->>'tien_te', ''), c.tien_te))
                       then c.lich_su || jsonb_build_array(jsonb_build_object('gia', c.gia, 'tien_te', c.tien_te, 'ngay', c.ngay)) else c.lich_su end
      where id = v;
      cn := cn + 1;
    end if;
    ids := ids || v;
  end loop;
  perform kt_ghi_nhat_ky(v_ten, 'kt_bao_gia', null, 'nhap_file', jsonb_build_object('ncc', p_ncc, 'moi', moi, 'cap_nhat', cn));
  return jsonb_build_object('ids', to_jsonb(ids), 'moi', moi, 'cap_nhat', cn);
end $$;
