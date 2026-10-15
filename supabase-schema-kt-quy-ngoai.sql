-- QUỸ NGOÀI CỬA HÀNG + PHÂN BỔ THEO DOANH SỐ (15/10/2026, góp ý kế toán). Monsieur Claude
-- 1. Quỹ lặt vặt 2 triệu / cửa hàng ("Tiền Quỹ Ngoài" trên Kiot): cửa hàng chi → ghi phiếu Kiot từ Quỹ ngoài; hết quỹ → đề nghị "thanh toán quỹ ngoài từ … đến …".
--    Từ 08/10 app tạo đề xuất chi cho TỪNG phiếu Kiot Quỹ ngoài → khi duyệt phiếu hoàn quỹ sẽ tính 2 lần. Sửa theo cách quỹ tạm ứng cố định:
--    chi từ Quỹ ngoài không tạo đề xuất; chi phí ghi 1 lần ở phiếu hoàn quỹ (kt_chi.hoan_quy = cửa hàng), khung chi tiết kê các phiếu Kiot trong đợt.
-- 2. Phân bổ "theo % doanh số thực đạt tháng": trước đây tính 1 lần lúc bấm (tháng chưa hết → sai). Giờ đánh dấu ds = tháng trong phan_bo,
--    lịch kt-pb-ds mỗi đêm chia lại theo doanh số mới nhất (tháng này + tháng trước, bỏ qua tháng đã khoá sổ).

alter table public.kt_chi add column if not exists hoan_quy text check (hoan_quy in ('SD', 'HT', 'CT'));
-- đánh dấu các phiếu hoàn quỹ đã có
update kt_chi set hoan_quy = case when noi_dung ~* '(\mHT\M|hiền thủy|hien thuy)' then 'HT' when noi_dung ~* '(\mCT\M|chánh tâm|chanh tam)' then 'CT'
    when noi_dung ~* '(shidai|kho|\mSD\M)' then 'SD'
    -- không ghi cửa hàng trong nội dung → theo đơn vị chịu chi phí (2 Hiền Thủy, 3 Chánh Tâm, 4 Shidai)
    else case (phan_bo->0->>'don_vi_id')::int when 2 then 'HT' when 3 then 'CT' when 4 then 'SD' end end
 where hoan_quy is null and not da_xoa and noi_dung ~* '(thanh toán|tt|hoàn|bù|fill).*(tiền )?quỹ ngoài';

-- Kiot: bỏ chi từ Quỹ ngoài khỏi đề xuất (bản đang chạy 15/10 + 1 điều kiện)
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

-- đề xuất Kiot Quỹ ngoài còn chờ (chưa trả) → từ chối kèm ghi chú (chi phí sẽ nằm trong phiếu hoàn quỹ)
update kt_chi c set trang_thai = 'tu_choi', nguoi_duyet = 'Hệ thống', duyet_luc = now(),
    ghi_chu = concat_ws(' ', c.ghi_chu, '[Chi từ Quỹ ngoài cửa hàng — tính 1 lần khi duyệt phiếu hoàn quỹ, không duyệt riêng]')
  from kt_kiot_so_quy q
 where q.id = c.kiot_so_quy_id and c.nguon = 'kiot' and not c.da_xoa and c.trang_thai in ('cho_duyet', 'cho_gd')
   and coalesce(q.goc->>'account', '') ~* 'quỹ ngoài';

-- đặt / bỏ cửa hàng hoàn quỹ cho 1 phiếu chi (kế toán)
create or replace function public.kt_dat_hoan_quy(p_phien text, p_id bigint, p_cs text) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'chi');
  if not kt_co_quyen(u, 'chi_duyet') then raise exception 'Chỉ kế toán (quyền duyệt chi) được đánh dấu' using errcode = '42501'; end if;
  if p_cs is not null and p_cs not in ('SD', 'HT', 'CT') then raise exception 'Cửa hàng không hợp lệ'; end if;
  update kt_chi set hoan_quy = p_cs where id = p_id and not da_xoa;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'hoan_quy', jsonb_build_object('cs', p_cs));
end $$;

-- bảng kê phiếu Kiot Quỹ ngoài của đợt hoàn: sau ngày phiếu hoàn quỹ trước (cùng cửa hàng) đến ngày phiếu này
create or replace function public.kt_quy_ngoai_ct(p_phien text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c kt_chi; v_tk text; v_den date; v_tu date;
begin
  perform kt_chan(p_phien, 'chi');
  select * into c from kt_chi where id = p_id;
  if c.hoan_quy is null then return null; end if;
  v_tk := case c.hoan_quy when 'SD' then '1315098' when 'HT' then '1000001093' else '1000001095' end;
  v_den := c.ngay_de_nghi;
  select max(x.ngay_de_nghi) into v_tu from kt_chi x where x.hoan_quy = c.hoan_quy and not x.da_xoa and x.trang_thai <> 'tu_choi' and x.id <> c.id and x.ngay_de_nghi < v_den;
  v_tu := coalesce(v_tu, v_den - 30);
  return jsonb_build_object('cs', c.hoan_quy, 'tu', v_tu, 'den', v_den,
    'ds', coalesce((select jsonb_agg(jsonb_build_object('ngay', (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'ma', q.ma, 'nhom', q.nhom, 'noi_dung', q.noi_dung,
        'doi_tac', q.doi_tac, 'so_tien', q.so_tien, 'la_thu', q.la_thu, 'huy', q.trang_thai <> '0') order by q.ngay, q.id)
      from kt_kiot_so_quy q where q.tai_khoan = v_tk and (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date > v_tu
        and (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date <= v_den), '[]'));
end $$;

-- chia lại phân bổ "theo % doanh số tháng" (lịch đêm). Đơn vị: 2 = Hiền Thủy, 3 = Chánh Tâm, 4 = Shidai (như nút trên app)
create or replace function public.kt_pb_ds_tinh_lai() returns int
language plpgsql security definer set search_path = public as $$
declare r record; v_pb jsonb; v_n int := 0; v_ids int[] := array[2, 3, 4];
  v_cn text[] := array['đồ thờ hiền thủy', 'đồ thờ chánh tâm', 'tổng kho sỉ shidai']; v_w numeric[]; v_tw numeric; v_con numeric; v_v numeric; v_cuoi int; i int;
begin
  for r in select c.id, c.so_tien, c.phan_bo->0->>'ds' thang from kt_chi c
            where not c.da_xoa and jsonb_typeof(c.phan_bo) = 'array' and c.phan_bo->0 ? 'ds'
              and c.phan_bo->0->>'ds' >= to_char((now() at time zone 'Asia/Ho_Chi_Minh')::date - interval '1 month', 'YYYY-MM')
              and not exists (select 1 from kt_khoa_ky k where k.thang = c.phan_bo->0->>'ds') loop
    v_w := array[0, 0, 0]::numeric[];
    for i in 1..3 loop
      select greatest(0, coalesce(sum(h.tong), 0) - coalesce((select sum(t.tong_tra) from kt_kiot_tra_hang t where coalesce(t.trang_thai, 1) = 1 and lower(t.chi_nhanh) = v_cn[i]
               and to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') = r.thang), 0))
        into v_v from kt_kiot_hoa_don h where h.trang_thai = 1 and lower(h.chi_nhanh) = v_cn[i] and to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') = r.thang;
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
  if v_n > 0 then insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_chi', 'pb_ds_tinh_lai', jsonb_build_object('so_phieu', v_n)); end if;
  return v_n;
end $$;
select cron.unschedule('kt-pb-ds') where exists (select 1 from cron.job where jobname = 'kt-pb-ds');
select cron.schedule('kt-pb-ds', '15 17 * * *', 'select public.kt_pb_ds_tinh_lai()');   -- 00:15 giờ VN

revoke execute on function public.kt_pb_ds_tinh_lai() from public, anon, authenticated;
do $$ declare f text; begin
  foreach f in array array['kt_dat_hoan_quy(text, bigint, text)', 'kt_quy_ngoai_ct(text, bigint)'] loop
    execute format('revoke execute on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop; end $$;
