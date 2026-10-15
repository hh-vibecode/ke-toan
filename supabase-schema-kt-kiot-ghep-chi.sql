-- ĐỀ XUẤT THANH TOÁN TRÊN APP TRƯỚC, KIOT GHI NHẬN SAU (15/10/2026, anh: "luồng cũ làm ở GG sheet rồi đẩy lên Kiot, kéo về từ Kiot để xác nhận là bị ngược"). Monsieur Claude
-- 1. kt_dong_bo_kiot_chi (bản đang chạy 15/10) không tự tạo đề xuất từ phiếu chi Kiot nữa — vẫn ghép 4A, vẫn tự từ chối phiếu Kiot đã huỷ.
CREATE OR REPLACE FUNCTION public.kt_dong_bo_kiot_chi(p_tu date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_moc date := greatest(p_tu, date '2026-10-08'); v_quay int; r record; c record;
  v_khop bigint; v_nghi text; v_id bigint; v_them int := 0; v_ghep int := 0; v_huy int := 0; v_sua int := 0; v_ds text[] := '{}'; v_ids bigint[] := '{}';
begin
  select id into v_quay from kt_tai_khoan where 'TIEN_MAT_QUAY' = any(kiot_ma) limit 1;
  for r in
    select q.id, q.ma, q.trang_thai, q.nhom, q.noi_dung, q.doi_tac, q.goc->>'user' nguoi,
      (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date d, abs(q.so_tien) tien,
      (select dd.id from kt_don_vi dd where q.chi_nhanh = any(dd.kiot_chi_nhanh) limit 1) dv_id,
      case when q.phuong_thuc = 'Cash' then v_quay else (select t.id from kt_tai_khoan t where q.tai_khoan = any(t.kiot_ma) limit 1) end tk_id,
      q.ma ~ '^(TTD_|CTD_)' or exists (select 1 from kt_tai_khoan t where length(regexp_replace(t.ten, '[^0-9]', '', 'g')) >= 8
             and coalesce(q.noi_dung, '') like '%' || regexp_replace(t.ten, '[^0-9]', '', 'g') || '%') noi_bo
    from kt_kiot_so_quy q
    where not q.la_thu and q.so_tien <> 0 and coalesce(q.nhom, '') <> 'Chuyển rút'
      -- 15/10/2026 (kế toán): chi từ 3 Tiền Quỹ Ngoài cửa hàng KHÔNG tạo đề xuất — chi phí ghi 1 lần khi duyệt phiếu hoàn quỹ (tránh tính 2 lần)
      and coalesce(q.goc->>'account', '') !~* 'quỹ ngoài'
      and (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date >= v_moc
    order by q.ngay, q.id
  loop
    select id, trang_thai, so_tien, sua_boi, nguon into c from kt_chi where kiot_so_quy_id = r.id;
    if found then
      if (r.trang_thai <> '0' or r.noi_bo) and c.nguon = 'kiot' and c.trang_thai in ('cho_duyet','cho_gd','cho_tt') then
        update kt_chi set trang_thai = 'tu_choi', nguoi_duyet = 'Kiot (phiếu đã huỷ)', duyet_luc = now(),
          ghi_chu = concat_ws(' ', ghi_chu, '[Phiếu Kiot ' || r.ma || ' đã huỷ / là chuyển nội bộ]') where id = c.id;
        v_huy := v_huy + 1;
      elsif r.trang_thai = '0' and not r.noi_bo and c.nguon = 'kiot' and c.trang_thai = 'cho_duyet' and c.sua_boi is null and c.so_tien <> r.tien then
        update kt_chi set so_tien = r.tien, phan_bo = case when r.dv_id is null then '[]'::jsonb
          else jsonb_build_array(jsonb_build_object('don_vi_id', r.dv_id, 'so_tien', r.tien)) end where id = c.id;
        v_sua := v_sua + 1;
      end if;
      continue;
    end if;
    if r.trang_thai <> '0' or r.noi_bo then continue; end if;
    -- phiếu Kiot là bản ghi 4A của 1 phiếu app kế toán đã đánh dấu "Đã tạo phiếu Kiot" → ghép, không tạo mới
    select x.id into v_khop from kt_chi x where not x.da_xoa and x.kiot_so_quy_id is null and x.nguon <> 'kiot' and x.kiot = 'da_tao'
      and x.so_tien = r.tien and abs(coalesce(x.ngay_tt, x.ngay_de_nghi) - r.d) <= 5
      order by abs(coalesce(x.ngay_tt, x.ngay_de_nghi) - r.d), x.id limit 1;
    if v_khop is not null then
      update kt_chi set kiot_so_quy_id = r.id, kiot_ma = r.ma where id = v_khop;
      v_ghep := v_ghep + 1; continue;
    end if;
    -- 15/10/2026 (anh): đề xuất thanh toán làm TRÊN APP trước, Kiot chỉ ghi nhận sau → KHÔNG tự tạo đề xuất từ phiếu Kiot nữa.
    -- Phiếu Kiot chưa ghép được nằm ở danh sách kt_kiot_chi_chua_ghep để kế toán ghép tay / tạo phiếu.
    continue;
    select string_agg('#' || x.id, ', ' order by x.id) into v_nghi from kt_chi x where not x.da_xoa and x.nguon <> 'kiot'
      and x.trang_thai <> 'tu_choi' and x.so_tien = r.tien and abs(coalesce(x.ngay_tt, x.ngay_de_nghi) - r.d) <= 5;
    insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, so_tien, phan_bo, tai_khoan_id, trang_thai,
      nguon, ma_nguon, tao_boi, kiot_so_quy_id, kiot_ma, kiot, nghi_trung)
    values (r.d, coalesce(nullif(trim(r.nguoi), ''), 'Kiot'), r.dv_id,
      left(concat_ws(' · ', coalesce(nullif(trim(r.nhom), ''), 'Chi khác'), nullif(trim(r.noi_dung), ''), nullif(trim(r.doi_tac), '')), 300),
      r.tien, case when r.dv_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('don_vi_id', r.dv_id, 'so_tien', r.tien)) end,
      r.tk_id, 'cho_duyet', 'kiot', 'kiot:' || r.id, 'Kiot (tự kéo)', r.id, r.ma, 'da_tao', v_nghi)
    returning id into v_id;
    v_them := v_them + 1; v_ids := v_ids || v_id;
    if v_nghi is not null then   -- anh 09/10: mục kiểm tra lỗi riêng cho phiếu nghi trùng
      perform kt_bao(kt_ai_ke_toan(null), 'Kiot (tự kéo)', 'chi_trung', 'Nghi trùng: phiếu Kiot ' || r.ma || ' cùng số tiền với ' || v_nghi,
        coalesce(nullif(trim(r.nguoi), ''), 'Kiot') || ': ' || replace(to_char(r.tien, 'FM999G999G999G999'), ',', '.') || ' đ — bấm để gộp hoặc xác nhận 2 khoản khác nhau', 'chi', v_id);
    end if;
    if v_them <= 3 then v_ds := v_ds || (coalesce(nullif(trim(r.nguoi), ''), 'Kiot') || ': ' || replace(to_char(r.tien, 'FM999G999G999G999'), ',', '.') || ' đ'); end if;
  end loop;
  if v_them > 0 then
    perform kt_bao(kt_ai_ke_toan(null), 'Kiot (tự kéo)', 'chi_kiot',
      case when v_them = 1 then 'Đề xuất chi mới từ Kiot — chờ kế toán kiểm' else v_them || ' đề xuất chi mới từ Kiot — chờ kế toán kiểm' end,
      array_to_string(v_ds, ' · ') || case when v_them > 3 then ' …' else '' end, 'chi', case when v_them = 1 then v_ids[1] end);
  end if;
  return jsonb_build_object('them', v_them, 'ghep_4a', v_ghep, 'huy', v_huy, 'sua', v_sua);
end $function$
;

-- phiếu CHI trên Kiot (từ 08/10) chưa ghép phiếu nào trên app — bỏ chuyển nội bộ, Quỹ ngoài, phiếu huỷ. Kèm gợi ý phiếu app cùng số tiền ±10 ngày.
create or replace function public.kt_kiot_chi_chua_ghep(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'chi');
  return coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'ma', q.ma, 'ngay', (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'so_tien', abs(q.so_tien),
      'cn', q.chi_nhanh, 'nhom', q.nhom, 'noi_dung', q.noi_dung, 'doi_tac', q.doi_tac, 'nguoi', q.goc->>'user', 'tk', q.goc->>'account',
      'goi_y', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'noi_dung', c.noi_dung, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'trang_thai', c.trang_thai)
                 order by abs(coalesce(c.ngay_tt, c.ngay_de_nghi) - (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date)), '[]')
                from kt_chi c where not c.da_xoa and c.kiot_so_quy_id is null and c.nguon <> 'kiot' and c.trang_thai <> 'tu_choi' and c.so_tien = abs(q.so_tien)
                  and abs(coalesce(c.ngay_tt, c.ngay_de_nghi) - (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date) <= 10))
    order by q.ngay desc)
    from kt_kiot_so_quy q
   where not q.la_thu and q.so_tien <> 0 and q.trang_thai = '0' and coalesce(q.nhom, '') <> 'Chuyển rút'
     and (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date >= date '2026-10-08'
     and coalesce(q.goc->>'account', '') !~* 'quỹ ngoài'
     and not (q.ma ~ '^(TTD_|CTD_)' or exists (select 1 from kt_tai_khoan t where length(regexp_replace(t.ten, '[^0-9]', '', 'g')) >= 8
               and coalesce(q.noi_dung, '') like '%' || regexp_replace(t.ten, '[^0-9]', '', 'g') || '%'))
     and not exists (select 1 from kt_chi c where c.kiot_so_quy_id = q.id and not c.da_xoa)), '[]');
end $$;

-- ghép tay: phiếu Kiot ↔ phiếu chi app (kế toán)
create or replace function public.kt_ghep_chi_kiot(p_phien text, p_chi bigint, p_kiot bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; q kt_kiot_so_quy;
begin
  u := kt_chan(p_phien, 'chi');
  if not kt_co_quyen(u, 'chi_duyet') then raise exception 'Chỉ kế toán (quyền duyệt chi) được ghép' using errcode = '42501'; end if;
  select * into q from kt_kiot_so_quy where id = p_kiot;
  if q.id is null then raise exception 'Không thấy phiếu Kiot'; end if;
  if exists (select 1 from kt_chi where kiot_so_quy_id = p_kiot and not da_xoa) then raise exception 'Phiếu Kiot % đã ghép phiếu khác', q.ma; end if;
  update kt_chi set kiot_so_quy_id = q.id, kiot_ma = q.ma, kiot = 'da_tao' where id = p_chi and not da_xoa and kiot_so_quy_id is null;
  if not found then raise exception 'Phiếu chi #% không ghép được (đã ghép phiếu Kiot khác hoặc đã xoá)', p_chi; end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_chi, 'ghep_kiot', jsonb_build_object('kiot', q.ma));
end $$;

-- tạo phiếu chi từ 1 phiếu Kiot (khoản đã chi trên Kiot mà chưa đề nghị trên app) — như cách tự tạo trước 15/10, nhưng do kế toán bấm
create or replace function public.kt_tao_chi_tu_kiot(p_phien text, p_kiot bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; q kt_kiot_so_quy; v_dv int; v_tk int; v_id bigint; v_tien numeric;
begin
  u := kt_chan(p_phien, 'chi');
  if not kt_co_quyen(u, 'chi_duyet') then raise exception 'Chỉ kế toán (quyền duyệt chi) được tạo' using errcode = '42501'; end if;
  select * into q from kt_kiot_so_quy where id = p_kiot;
  if q.id is null then raise exception 'Không thấy phiếu Kiot'; end if;
  if exists (select 1 from kt_chi where kiot_so_quy_id = p_kiot and not da_xoa) then raise exception 'Phiếu Kiot % đã có phiếu chi', q.ma; end if;
  v_tien := abs(q.so_tien);
  select d.id into v_dv from kt_don_vi d where q.chi_nhanh = any(d.kiot_chi_nhanh) limit 1;
  v_tk := case when q.phuong_thuc = 'Cash' then (select id from kt_tai_khoan where 'TIEN_MAT_QUAY' = any(kiot_ma) limit 1)
               else (select t.id from kt_tai_khoan t where q.tai_khoan = any(t.kiot_ma) limit 1) end;
  insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, so_tien, phan_bo, tai_khoan_id, trang_thai, nguon, ma_nguon, tao_boi, kiot_so_quy_id, kiot_ma, kiot)
  values ((q.ngay at time zone 'Asia/Ho_Chi_Minh')::date, coalesce(nullif(trim(q.goc->>'user'), ''), 'Kiot'), v_dv,
    left(concat_ws(' · ', coalesce(nullif(trim(q.nhom), ''), 'Chi khác'), nullif(trim(q.noi_dung), ''), nullif(trim(q.doi_tac), '')), 300), v_tien,
    case when v_dv is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('don_vi_id', v_dv, 'so_tien', v_tien)) end,
    v_tk, 'cho_duyet', 'kiot', 'kiot:' || q.id, u.ho_ten, q.id, q.ma, 'da_tao') returning id into v_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', v_id, 'tao_tu_kiot', jsonb_build_object('kiot', q.ma));
  return v_id;
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_kiot_chi_chua_ghep(text)', 'kt_ghep_chi_kiot(text, bigint, bigint)', 'kt_tao_chi_tu_kiot(text, bigint)'] loop
    execute format('revoke execute on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop; end $$;
