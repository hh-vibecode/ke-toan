-- CHI TIỀN MẶT TẠI QUẦY TỪ KIOT → PHIẾU CHI ĐÃ CHI (TK QUẦY) — 19/11/2026. Monsieur Claude
-- Anh hỏi "số quỹ quầy app và Kiot không khớp": cộng 3 cửa hàng, thu + nộp két khớp 100% từng ngày; lệch duy nhất = chi tiền mặt tại quầy trên Kiot
-- (vận chuyển, trả NCC, trả khách…) app không có → tồn sổ sách TK quầy cao hơn thực. Anh đồng ý ("auke"): tự kéo các khoản này thành phiếu chi đã chi
-- từ TK quầy, từ mốc số dư 01/09/2026. Loại: vận chuyển → Chi phí đóng gói & vận chuyển (100), trả NCC → Chi thanh toán tiền hàng (5),
-- trả khách → Hoàn hàng đã tính trong trả hàng Kiot (114), thuê kho → 70, sửa chữa → 103, nhóm khác → Chi phí khác (106, kế toán đổi được).
-- Kiot huỷ phiếu → phiếu app tự từ chối; kế toán đã sửa phiếu (sua_boi) → không ghi đè.
CREATE OR REPLACE FUNCTION public.kt_dong_bo_kiot_chi(p_tu date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_moc date := greatest(p_tu, date '2026-10-08'); v_quay int; r record; c record;
  v_khop bigint; v_nghi text; v_id bigint; v_them int := 0; v_ghep int := 0; v_huy int := 0; v_sua int := 0; v_ds text[] := '{}'; v_ids bigint[] := '{}'; v_q int := 0; v_qs int := 0; v_loai int;
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
      and ((q.ngay at time zone 'Asia/Ho_Chi_Minh')::date >= v_moc
        or (q.phuong_thuc = 'Cash' and (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date >= date '2026-09-01'))   -- 19/11: chi tiền mặt tại quầy từ mốc số dư 01/09
    order by q.ngay, q.id
  loop
    select id, trang_thai, so_tien, sua_boi, nguon, tao_boi, tai_khoan_id into c from kt_chi where kiot_so_quy_id = r.id;
    -- 19/11/2026 anh ("auke" — số dư TK quầy phải khớp thực tế): chi tiền mặt TẠI QUẦY trên Kiot (vận chuyển, trả NCC, trả khách…) = phiếu chi ĐÃ CHI
    -- từ TK "TIỀN MẶT QUẦY CỬA HÀNG", ngày chi = ngày Kiot, cơ sở theo chi nhánh, loại theo nhóm Kiot. Ngoại lệ của luật 15/10 (chỉ tiền mặt quầy;
    -- chi chuyển khoản vẫn làm trên app trước). Phiếu tự kéo trước 15/10 còn treo "chờ duyệt" ở KÉT → chuyển thành đã chi ở quầy. — Monsieur Claude
    if found and r.tk_id = v_quay and v_quay is not null and c.nguon = 'kiot' and c.sua_boi is null then
      if r.trang_thai <> '0' or r.noi_bo then
        if c.trang_thai in ('da_tt','cho_duyet','cho_gd','cho_tt') then
          update kt_chi set trang_thai = 'tu_choi', nguoi_duyet = 'Kiot (phiếu đã huỷ)', duyet_luc = now(),
            ghi_chu = concat_ws(' ', ghi_chu, '[Phiếu Kiot ' || r.ma || ' đã huỷ / là chuyển nội bộ]') where id = c.id;
          v_huy := v_huy + 1;
        end if;
      elsif c.trang_thai = 'cho_duyet' or (c.trang_thai = 'da_tt' and c.so_tien <> r.tien) then
        v_loai := case r.nhom when 'Chi phí vận chuyển' then 100 when 'Tiền trả NCC' then 5 when 'Tiền trả khách' then 114
          when 'Chi phí thuê kho bãi, mặt bằng kinh doanh' then 70 when 'Sửa chữa thiết bị, máy móc, bảo dưỡng cơ sở vật chất' then 103 else 106 end;
        update kt_chi set trang_thai = 'da_tt', ngay_tt = r.d, ngay_su_dung = coalesce(ngay_su_dung, r.d), tai_khoan_id = v_quay, so_tien = r.tien,
          loai_id = coalesce(loai_id, v_loai), nguoi_duyet = coalesce(nguoi_duyet, 'Kiot (chi tại quầy)'), duyet_luc = coalesce(duyet_luc, now()),
          phan_bo = case when r.dv_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('don_vi_id', r.dv_id, 'so_tien', r.tien)) end
         where id = c.id;
        v_qs := v_qs + 1;
      end if;
      continue;
    end if;
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
    if r.tk_id = v_quay and v_quay is not null and r.d >= date '2026-09-01' then   -- 19/11: chi tiền mặt tại quầy → phiếu chi đã chi
      v_loai := case r.nhom when 'Chi phí vận chuyển' then 100 when 'Tiền trả NCC' then 5 when 'Tiền trả khách' then 114
        when 'Chi phí thuê kho bãi, mặt bằng kinh doanh' then 70 when 'Sửa chữa thiết bị, máy móc, bảo dưỡng cơ sở vật chất' then 103 else 106 end;
      insert into kt_chi (ngay_de_nghi, ngay_su_dung, nguoi_de_nghi, bo_phan_id, noi_dung, so_tien, phan_bo, tai_khoan_id, loai_id, trang_thai, ngay_tt,
        nguoi_duyet, duyet_luc, nguon, ma_nguon, tao_boi, kiot_so_quy_id, kiot_ma, kiot)
      values (r.d, r.d, coalesce(nullif(trim(r.nguoi), ''), 'Kiot'), r.dv_id,
        left(concat_ws(' · ', coalesce(nullif(trim(r.nhom), ''), 'Chi khác'), nullif(trim(r.noi_dung), ''), nullif(trim(r.doi_tac), ''), 'Kiot ' || r.ma), 300),
        r.tien, case when r.dv_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('don_vi_id', r.dv_id, 'so_tien', r.tien)) end,
        v_quay, v_loai, 'da_tt', r.d, 'Kiot (chi tại quầy)', now(), 'kiot', 'kiot:' || r.id, 'Kiot (tự kéo)', r.id, r.ma, 'da_tao');
      v_q := v_q + 1; continue;
    end if;
    if r.d < v_moc then continue; end if;
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
  return jsonb_build_object('them', v_them, 'ghep_4a', v_ghep, 'huy', v_huy, 'sua', v_sua, 'quay_moi', v_q, 'quay_sua', v_qs);
end $function$
;

-- phiếu chi tiền mặt tại quầy kéo từ Kiot: không có giao dịch ngân hàng để up ảnh → không báo "Thiếu ảnh giao dịch" (phiếu Kiot là chứng từ)
create or replace function public.kt_thieu_unc(c kt_chi) returns boolean language sql stable set search_path to 'public' as $function$
  select c.trang_thai = 'da_tt' and not c.da_xoa and c.ngay_tt >= date '2026-09-01' and coalesce(trim(c.unc), '') = ''
     and not c.tu_tru   -- 21/10: tài khoản tự trừ — không có giao dịch để up
     and not (c.nguon = 'kiot' and c.kiot_so_quy_id is not null)   -- 19/11: chi tại quầy kéo từ Kiot
     and not exists (select 1 from kt_chung_tu k where k.bang = 'chi' and k.dong_id = c.id and not k.da_xoa and k.ten_file ilike 'UNC%');
$function$;

-- 9 phiếu chi tại quầy (HT 08–14/10) đã có trên app nhưng hệ thống ẩn 16/10 theo luật "phiếu Kiot chỉ để đối chiếu" → mở lại (luật mới: chi tại quầy = phiếu chi đã chi)
update kt_chi c set da_xoa = false, ghi_chu = concat_ws(' ', c.ghi_chu, '[19/11: mở lại — chi tiền mặt tại quầy tính vào TK quầy]')
  from kt_kiot_so_quy q
 where q.id = c.kiot_so_quy_id and c.da_xoa and c.sua_boi is null and c.nguon = 'kiot' and c.trang_thai = 'da_tt' and c.tai_khoan_id = 23
   and q.phuong_thuc = 'Cash' and not q.la_thu and q.trang_thai = '0' and coalesce(q.nhom, '') <> 'Chuyển rút'
   and c.ghi_chu like '%chỉ để đối chiếu%ẩn 16/10%';

-- tab "Quỹ tiền mặt 3 cửa hàng": cột "Còn giữ ở quầy" cộng dồn từ TỒN ĐẦU kỳ (trước đây từ 0 → âm đầu kỳ vì nộp két tiền bán ngày trước kỳ).
-- dau = lũy kế (thu − chi − nộp + nhận) tiền mặt Kiot của cửa hàng từ ngày đầu có dữ liệu tới trước kỳ (cùng cách tính các cột).
create or replace function public.kt_quy_cua_hang(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path to 'public' as $function$
begin
  perform kt_chan(p_phien, 'quy_ch');
  return coalesce((select jsonb_agg(jsonb_build_object('ngay', ng, 'cn', chi_nhanh, 'thu', thu, 'chi', chi, 'nop', nop, 'nhan', nhan, 'dau', dau) order by ng, chi_nhanh) from (
    select x.*, coalesce((select sum(case when q.la_thu then q.so_tien else -q.so_tien end) from kt_kiot_so_quy q
        where q.trang_thai = '0' and q.phuong_thuc = 'Cash' and q.chi_nhanh = x.chi_nhanh and (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date < p_tu
          and (q.nhom = 'Chuyển rút' or q.ma !~ '^(TTD_|CTD_)')), 0) dau
    from (select (ngay at time zone 'Asia/Ho_Chi_Minh')::date ng, chi_nhanh,
      sum(so_tien) filter (where la_thu and coalesce(nhom,'') <> 'Chuyển rút' and ma !~ '^(TTD_|CTD_)') thu,
      sum(so_tien) filter (where not la_thu and coalesce(nhom,'') <> 'Chuyển rút' and ma !~ '^(TTD_|CTD_)') chi,
      sum(so_tien) filter (where not la_thu and nhom = 'Chuyển rút') nop,
      sum(so_tien) filter (where la_thu and nhom = 'Chuyển rút') nhan
    from kt_kiot_so_quy where trang_thai = '0' and phuong_thuc = 'Cash' and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
    group by 1, 2) x) y), '[]');
end $function$;
