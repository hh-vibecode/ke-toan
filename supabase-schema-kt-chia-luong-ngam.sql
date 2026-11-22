-- 16/11/2026 — CHIA LƯƠNG / BHXH NGẦM (anh: "tách phiếu lương thì không cần tách ra thành phiếu riêng trong luồng duyệt, tách ngầm để hiểu người ta chia
-- chi phí … bỏ nút chia, nút lưu thôi, lưu xong tự ghi nhận chi phí chia ra theo đúng"). Thay bản 13/11 (kt_chia_luong tách mỗi nhóm 1 phiếu bằng kt_tach_chi):
--   • phiếu giữ nguyên 1 phiếu, đủ số tiền, trong luồng duyệt / thanh toán / sổ quỹ;
--   • bảng chia lưu ở kt_chi.chia_cp = {thang, khoan, nhom:[{nhom, loai_id, chia: 'ds' | '<don_vi_id>', so_tien, phan_bo:[{don_vi_id, so_tien}]}], boi, luc};
--   • tầng chi phí kt_v_chi_ht (P&L, báo cáo quản trị, chi phí hạch toán, drill, P&L chi tiết) đọc theo từng nhóm khi tổng các nhóm = số tiền phiếu
--     (sửa số tiền phiếu mà chưa sửa bảng chia → tạm theo loại / phân bổ của phiếu như cũ, giao diện báo lệch);
--   • nhóm "% doanh số" chia theo doanh thu thuần Kiot của tháng hạch toán, lịch kt-pb-ds (kt_pb_ds_tinh_lai) chia lại mỗi đêm tới hết tháng sau;
--   • phiếu: loại chi = loại của nhóm lớn nhất, phan_bo = cộng theo đơn vị của mọi nhóm (để màn cũ đọc phan_bo vẫn đúng tổng theo đơn vị).
-- Kèm: gắn lại bảng chia kế toán đã điền cho PC002017 (lần chia 13/11 bản cũ đã tách 6 phiếu — anh 16/11 bảo xoá 6 phiếu lẻ, dữ liệu phiếu gốc giữ). — Monsieur Claude

alter table public.kt_chi add column if not exists chia_cp jsonb;

-- ghi bảng chia vào phiếu (dùng chung cho RPC + sửa dữ liệu); p_ds rỗng = bỏ chia
create or replace function public.kt_chia_cp_ghi(p_id bigint, p_thang text, p_nhan text, p_ds jsonb, p_nguoi text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; nh jsonb := '[]'::jsonb; pb jsonb; tien numeric; ch text; v jsonb; agg jsonb; lon jsonb;
begin
  if p_ds is null or jsonb_array_length(p_ds) = 0 then
    update kt_chi set chia_cp = null, sua_boi = p_nguoi, sua_luc = now() where id = p_id;
    return null;
  end if;
  for r in select e from jsonb_array_elements(p_ds) e loop
    tien := (r->>'so_tien')::numeric; ch := r->>'chia';
    pb := case when ch = 'ds' then (select jsonb_agg(x - 'ds') from jsonb_array_elements(kt_pb_theo_ds(p_thang, tien)) x)
               else jsonb_build_array(jsonb_build_object('don_vi_id', ch::int, 'so_tien', tien)) end;
    nh := nh || jsonb_build_array(jsonb_build_object('nhom', trim(r->>'nhom'), 'loai_id', (r->>'loai_id')::int, 'chia', ch, 'so_tien', tien, 'phan_bo', pb));
  end loop;
  v := jsonb_build_object('thang', p_thang, 'khoan', trim(p_nhan), 'nhom', nh, 'boi', p_nguoi, 'luc', now());
  select jsonb_agg(jsonb_build_object('don_vi_id', dv, 'so_tien', s) order by dv) into agg
    from (select (x->>'don_vi_id')::int dv, sum((x->>'so_tien')::numeric) s from jsonb_array_elements(nh) g, jsonb_array_elements(g->'phan_bo') x group by 1) z;
  select g into lon from jsonb_array_elements(nh) g order by (g->>'so_tien')::numeric desc limit 1;
  update kt_chi set chia_cp = v, thang_ht = p_thang, phan_bo = agg, phan_bo_thang = null, loai_id = (lon->>'loai_id')::int,
         sua_boi = p_nguoi, sua_luc = now() where id = p_id;
  return v;
end $$;
revoke all on function public.kt_chia_cp_ghi(bigint, text, text, jsonb, text) from public, anon, authenticated;

-- RPC cửa sổ "Chia lương / BHXH" (nút Lưu)
create or replace function public.kt_chia_luong(p_phien text, p_id bigint, p_thang text, p_nhan text, p_ds jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; r jsonb; tien numeric; tong numeric; ch text; v jsonb;
begin
  u := kt_chan(p_phien, 'chi', true);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  if not kt_co_quyen(u, 'chi_duyet') then raise exception 'Chỉ kế toán (quyền xác nhận) chia lương' using errcode = '42501'; end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi'; end if;
  if c.trang_thai in ('tu_choi', 'tu_choi_tt') then raise exception 'Phiếu đã từ chối — không chia'; end if;
  if c.la_tam_ung or c.loai_dn = 'hoan_ung' then raise exception 'Không chia phiếu tạm ứng / hoàn ứng'; end if;
  if jsonb_typeof(p_ds) <> 'array' then raise exception 'Dữ liệu chia không hợp lệ'; end if;
  if jsonb_array_length(p_ds) > 0 then
    if coalesce(p_thang, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Chọn tháng hạch toán'; end if;
    select sum((e->>'so_tien')::numeric) into tong from jsonb_array_elements(p_ds) e;
    if tong is distinct from c.so_tien then raise exception 'Tổng các nhóm (%) phải bằng số tiền phiếu (%)', tong, c.so_tien; end if;
    for r in select e from jsonb_array_elements(p_ds) e loop
      tien := (r->>'so_tien')::numeric; ch := r->>'chia';
      if tien is null or tien <= 0 or tien <> round(tien) then raise exception 'Số tiền từng nhóm phải là số nguyên > 0'; end if;
      if coalesce(trim(r->>'nhom'), '') = '' then raise exception 'Đặt tên từng nhóm'; end if;
      if not exists (select 1 from kt_loai where id = (r->>'loai_id')::int and nhom = 'chi') then raise exception 'Nhóm "%": chọn loại chi', r->>'nhom'; end if;
      if ch is distinct from 'ds' and not exists (select 1 from kt_don_vi where id = nullif(ch, '')::int) then raise exception 'Nhóm "%": chọn cách chia', r->>'nhom'; end if;
    end loop;
  end if;
  if exists (select 1 from kt_khoa_ky where thang = coalesce(nullif(p_thang, ''), c.thang_ht)) then raise exception 'Tháng % đã khoá sổ', coalesce(nullif(p_thang, ''), c.thang_ht); end if;
  v := kt_chia_cp_ghi(p_id, p_thang, p_nhan, p_ds, coalesce(u.ho_ten, u.ten_dang_nhap));
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_chi', p_id, case when v is null then 'bo_chia_luong' else 'chia_luong' end,
          jsonb_build_object('thang', p_thang, 'khoan', p_nhan, 'nhom', p_ds, 'ngam', true));
  return jsonb_build_object('id', p_id, 'chia_cp', v);
end $$;
revoke all on function public.kt_chia_luong(text, bigint, text, text, jsonb) from public;
grant execute on function public.kt_chia_luong(text, bigint, text, text, jsonb) to anon, authenticated;

-- tầng chi phí: phiếu có bảng chia khớp số tiền → mỗi nhóm × đơn vị 1 dòng; còn lại như cũ
create or replace view public.kt_v_chi_ht as
 select c.id as chi_id,
    coalesce(c.loai_con_id, c.loai_id) as loai_id,
    coalesce(pt.value ->> 'thang', c.thang_ht, to_char(coalesce(c.ngay_su_dung, c.ngay_de_nghi, c.ngay_tt)::timestamp with time zone, 'YYYY-MM')) as thang,
    (pb.value ->> 'don_vi_id')::integer as don_vi_id,
    coalesce((pt.value ->> 'so_tien')::numeric, c.so_tien) * coalesce(((pb.value ->> 'so_tien')::numeric) / nullif(c.so_tien, 0::numeric), 1::numeric) as tien
   from kt_chi c
     left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' and jsonb_array_length(c.phan_bo_thang) > 0 then c.phan_bo_thang else null::jsonb end) pt(value) on true
     left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' and jsonb_array_length(c.phan_bo) > 0 then c.phan_bo else null::jsonb end) pb(value) on true
  where not c.da_xoa and c.trang_thai = any (array['cho_tt', 'da_tt']) and not c.la_tam_ung and not c.khong_hach_toan and c.loai_dn = 'thanh_toan'
    and not (c.chia_cp is not null and (select coalesce(sum((g->>'so_tien')::numeric), 0) from jsonb_array_elements(c.chia_cp->'nhom') g) = c.so_tien)
 union all
 select c.id, (g.value ->> 'loai_id')::integer, coalesce(c.chia_cp ->> 'thang', c.thang_ht), (x.value ->> 'don_vi_id')::integer, (x.value ->> 'so_tien')::numeric
   from kt_chi c
     cross join lateral jsonb_array_elements(c.chia_cp -> 'nhom') g(value)
     cross join lateral jsonb_array_elements(g.value -> 'phan_bo') x(value)
  where not c.da_xoa and c.trang_thai = any (array['cho_tt', 'da_tt']) and not c.la_tam_ung and not c.khong_hach_toan and c.loai_dn = 'thanh_toan'
    and c.chia_cp is not null and (select coalesce(sum((g2->>'so_tien')::numeric), 0) from jsonb_array_elements(c.chia_cp->'nhom') g2) = c.so_tien;

-- chia lại nhóm "% doanh số" theo doanh số mới (gọi từ lịch kt-pb-ds)
create or replace function public.kt_chia_cp_lai(p_id bigint) returns boolean
language plpgsql security definer set search_path = public as $$
declare c kt_chi; ds jsonb;
begin
  select * into c from kt_chi where id = p_id;
  if c.chia_cp is null then return false; end if;
  select jsonb_agg(jsonb_build_object('nhom', g->>'nhom', 'loai_id', (g->>'loai_id')::int, 'chia', g->>'chia', 'so_tien', (g->>'so_tien')::numeric) order by i) into ds
    from jsonb_array_elements(c.chia_cp->'nhom') with ordinality x(g, i);
  perform kt_chia_cp_ghi(p_id, c.chia_cp->>'thang', c.chia_cp->>'khoan', ds, coalesce(c.chia_cp->>'boi', 'Hệ thống'));
  -- giữ người / lúc sửa cũ của phiếu (chia lại tự động không tính là sửa tay)
  update kt_chi set sua_boi = c.sua_boi, sua_luc = c.sua_luc,
         chia_cp = chia_cp || jsonb_build_object('boi', c.chia_cp->'boi', 'luc', c.chia_cp->'luc') where id = p_id;
  return (select chia_cp->'nhom' is distinct from c.chia_cp->'nhom' from kt_chi where id = p_id);
end $$;
revoke all on function public.kt_chia_cp_lai(bigint) from public, anon, authenticated;

create or replace function public.kt_pb_ds_tinh_lai()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record; v_pb jsonb; v_n int := 0; v_ids int[] := array[2, 3, 4];
  v_cn text[] := array['đồ thờ hiền thủy', 'đồ thờ chánh tâm', 'tổng kho sỉ shidai']; v_w numeric[]; v_tw numeric; v_con numeric; v_v numeric; v_cuoi int; i int;
begin
  for r in select c.id, c.so_tien, c.phan_bo->0->>'ds' thang from kt_chi c
            where not c.da_xoa and c.chia_cp is null and jsonb_typeof(c.phan_bo) = 'array' and c.phan_bo->0 ? 'ds'
              and c.phan_bo->0->>'ds' >= to_char((now() at time zone 'Asia/Ho_Chi_Minh')::date - interval '1 month', 'YYYY-MM')
              and not exists (select 1 from kt_khoa_ky k where k.thang = c.phan_bo->0->>'ds') loop
    v_w := array[0, 0, 0]::numeric[];
    for i in 1..3 loop
      select greatest(0, coalesce(sum(h.tong), 0) - coalesce((select sum(t.tong_tra) from kt_kiot_tra_hang t where coalesce(t.trang_thai, 1) = 1 and lower(t.chi_nhanh) = v_cn[i]
               and to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') = r.thang), 0))
        into v_v from kt_kiot_hoa_don h where h.trang_thai in (1, 3) and lower(h.chi_nhanh) = v_cn[i] and to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') = r.thang;
      v_w[i] := v_v;
    end loop;
    v_tw := v_w[1] + v_w[2] + v_w[3];
    if v_tw <= 0 then continue; end if;
    v_cuoi := case when v_w[3] > 0 then 3 when v_w[2] > 0 then 2 else 1 end;
    v_pb := '[]'; v_con := r.so_tien;
    for i in 1..3 loop
      if v_w[i] = 0 then continue; end if;
      v_v := case when i = v_cuoi then v_con else round(r.so_tien * v_w[i] / v_tw) end;
      v_con := v_con - v_v;
      v_pb := v_pb || jsonb_build_array(jsonb_build_object('don_vi_id', v_ids[i], 'so_tien', v_v, 'ds', r.thang));
    end loop;
    update kt_chi set phan_bo = v_pb where id = r.id and phan_bo is distinct from v_pb;
    if found then v_n := v_n + 1; end if;
  end loop;
  -- 16/11: phiếu chia lương / BHXH ngầm có nhóm "% doanh số" → chia lại theo doanh số mới tới hết tháng sau
  for r in select c.id from kt_chi c
            where not c.da_xoa and c.chia_cp is not null and exists (select 1 from jsonb_array_elements(c.chia_cp->'nhom') g where g->>'chia' = 'ds')
              and c.chia_cp->>'thang' >= to_char((now() at time zone 'Asia/Ho_Chi_Minh')::date - interval '1 month', 'YYYY-MM')
              and not exists (select 1 from kt_khoa_ky k where k.thang = c.chia_cp->>'thang') loop
    if kt_chia_cp_lai(r.id) then v_n := v_n + 1; end if;
  end loop;
  if v_n > 0 then insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_chi', 'pb_ds_tinh_lai', jsonb_build_object('so_phieu', v_n)); end if;
  return v_n;
end $function$;

-- PC002017: gắn lại bảng chia kế toán đã điền 13/11 (lấy từ nhật ký lần chia), phiếu giữ 1 phiếu đủ tiền
do $$
declare d jsonb;
begin
  select du_lieu into d from kt_nhat_ky where bang = 'kt_chi' and dong_id = 2017 and hanh_dong = 'chia_luong' and not (du_lieu ? 'ngam') order by luc desc limit 1;
  if d is not null and (select chia_cp is null and so_tien = (select sum((e->>'so_tien')::numeric) from jsonb_array_elements(d->'nhom') e) from kt_chi where id = 2017) then
    perform kt_chia_cp_ghi(2017, d->>'thang', d->>'khoan', d->'nhom', 'Hệ thống');
    perform kt_ghi_nhat_ky('Hệ thống', 'kt_chi', 2017, 'chia_luong', jsonb_build_object('thang', d->>'thang', 'khoan', d->>'khoan', 'nhom', d->'nhom', 'ngam', true, 'ly_do', 'Gắn lại bảng chia đã điền (bỏ 6 phiếu lẻ)'));
  end if;
end $$;
