-- 22/10/2026 kế toán: "cho chị nhóm cha nhóm con, nhìn cho dễ" — Cài đặt → Loại thu / chi xếp cây nhóm cha → mục con.
-- kt_luu_danh_muc (bảng loai) nhận thêm mã, nhóm cha, "là nhóm" (chỉ đổi khi form gửi lên). Monsieur Claude
create or replace function public.kt_luu_danh_muc(p_phien text, p_bang text, p_dong jsonb)
 returns integer language plpgsql security definer set search_path to 'public' as $function$
declare u kt_nguoi_dung; v_id int := (p_dong->>'id')::int; v_cha int := nullif(p_dong->>'cha_id','')::int; v_nhom text;
begin
  u := kt_chan(p_phien, 'danh_muc', true);
  if coalesce(trim(p_dong->>'ten'), '') = '' then raise exception 'Thiếu tên'; end if;
  if p_bang = 'tai_khoan' then
    if v_id is null then
      insert into kt_tai_khoan (ten, loai, ton_dau, ngay_ton_dau, thu_tu, hoat_dong)
      values (trim(p_dong->>'ten'), coalesce(p_dong->>'loai','ngan_hang'), coalesce((p_dong->>'ton_dau')::numeric,0),
        coalesce((p_dong->>'ngay_ton_dau')::date, date '2026-08-01'), coalesce((p_dong->>'thu_tu')::int,100),
        coalesce((p_dong->>'hoat_dong')::boolean,true)) returning id into v_id;
    else
      update kt_tai_khoan set ten = trim(p_dong->>'ten'), loai = coalesce(p_dong->>'loai', loai),
        ton_dau = coalesce((p_dong->>'ton_dau')::numeric, ton_dau),
        ngay_ton_dau = coalesce((p_dong->>'ngay_ton_dau')::date, ngay_ton_dau),
        thu_tu = coalesce((p_dong->>'thu_tu')::int, thu_tu), hoat_dong = coalesce((p_dong->>'hoat_dong')::boolean, hoat_dong),
        kiot_ma = case when p_dong ? 'kiot_ma' then array(select jsonb_array_elements_text(p_dong->'kiot_ma')) else kiot_ma end
       where id = v_id;
    end if;
  elsif p_bang = 'don_vi' then
    if v_id is null then
      insert into kt_don_vi (ten, la_co_so, la_bo_phan, thu_tu, hoat_dong)
      values (trim(p_dong->>'ten'), coalesce((p_dong->>'la_co_so')::boolean,true), coalesce((p_dong->>'la_bo_phan')::boolean,false),
        coalesce((p_dong->>'thu_tu')::int,100), coalesce((p_dong->>'hoat_dong')::boolean,true)) returning id into v_id;
    else
      update kt_don_vi set ten = trim(p_dong->>'ten'), la_co_so = coalesce((p_dong->>'la_co_so')::boolean, la_co_so),
        la_bo_phan = coalesce((p_dong->>'la_bo_phan')::boolean, la_bo_phan),
        thu_tu = coalesce((p_dong->>'thu_tu')::int, thu_tu), hoat_dong = coalesce((p_dong->>'hoat_dong')::boolean, hoat_dong),
        kiot_chi_nhanh = case when p_dong ? 'kiot_chi_nhanh'
          then array(select jsonb_array_elements_text(p_dong->'kiot_chi_nhanh')) else kiot_chi_nhanh end
       where id = v_id;
    end if;
  elsif p_bang = 'loai' then
    v_nhom := coalesce((select nhom from kt_loai where id = v_id), p_dong->>'nhom');
    if v_cha is not null then
      if v_cha = v_id then raise exception 'Nhóm cha không được là chính nó'; end if;
      if not exists (select 1 from kt_loai where id = v_cha and nhom = v_nhom) then raise exception 'Nhóm cha phải cùng nhóm % ', case when v_nhom = 'thu' then 'thu' else 'chi' end; end if;
      if v_id is not null and exists (with recursive t as (select id, cha_id from kt_loai where id = v_cha union all select l.id, l.cha_id from kt_loai l join t on l.id = t.cha_id) select 1 from t where id = v_id)
        then raise exception 'Nhóm cha đang nằm trong loại này — chọn nhóm khác'; end if;
    end if;
    if v_id is null then
      insert into kt_loai (nhom, ten, nhom_bc, cach_chia, thu_tu, hoat_dong, ma, cha_id, la_nhom)
      values (p_dong->>'nhom', trim(p_dong->>'ten'), nullif(trim(p_dong->>'nhom_bc'),''), coalesce(p_dong->>'cach_chia','rieng'),
        coalesce((p_dong->>'thu_tu')::int,100), coalesce((p_dong->>'hoat_dong')::boolean,true),
        nullif(trim(p_dong->>'ma'),''), v_cha, coalesce((p_dong->>'la_nhom')::boolean,false)) returning id into v_id;
    else
      update kt_loai set ten = trim(p_dong->>'ten'), nhom_bc = nullif(trim(p_dong->>'nhom_bc'),''),
        cach_chia = coalesce(p_dong->>'cach_chia', cach_chia), thu_tu = coalesce((p_dong->>'thu_tu')::int, thu_tu),
        hoat_dong = coalesce((p_dong->>'hoat_dong')::boolean, hoat_dong),
        ma = case when p_dong ? 'ma' then nullif(trim(p_dong->>'ma'),'') else ma end,
        cha_id = case when p_dong ? 'cha_id' then v_cha else cha_id end,
        la_nhom = coalesce((p_dong->>'la_nhom')::boolean, la_nhom)
       where id = v_id;
    end if;
  else
    raise exception 'Danh mục không hợp lệ';
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $function$;
