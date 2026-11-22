-- 26/10/2026: kt_tach_chi — phiếu tách từ phiếu đã khớp Kiot đánh dấu "không cần phiếu Kiot" (Kiot ghi ở phiếu gốc). Bản đầy đủ đang chạy. Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_tach_chi(p_phien text, p_id bigint, p_so_tien numeric, p_noi_dung text, p_loai_id integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; c kt_chi; cols text; sel text; v_new bigint; tl numeric; n kt_chi;
begin
  u := kt_chan(p_phien, 'chi', true);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  if not kt_co_quyen(u, 'chi_duyet') then raise exception 'Chỉ kế toán tách phiếu' using errcode = '42501'; end if;
  select * into c from kt_chi where id = p_id and not da_xoa for update;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi'; end if;
  if c.trang_thai in ('tu_choi', 'tu_choi_tt') then raise exception 'Phiếu đã từ chối — không tách'; end if;
  if c.la_tam_ung or c.loai_dn = 'hoan_ung' then raise exception 'Không tách phiếu tạm ứng / hoàn ứng'; end if;
  if p_so_tien is null or p_so_tien <= 0 or p_so_tien >= c.so_tien then raise exception 'Số tiền tách phải lớn hơn 0 và nhỏ hơn số tiền phiếu (%)', c.so_tien; end if;
  if coalesce(trim(p_noi_dung), '') = '' then raise exception 'Ghi nội dung phiếu tách'; end if;
  -- phiếu mới: bỏ mã nguồn / liên kết Kiot (khoá duy nhất) và nguồn = 'app' — đồng bộ sheet đề nghị xoá mềm phiếu nguồn sheet_cu không khớp dòng sheet
  select string_agg(quote_ident(column_name), ',' order by ordinal_position),
         string_agg(case column_name when 'ma_nguon' then 'null' when 'kiot_so_quy_id' then 'null' when 'nguon' then quote_literal('app') else quote_ident(column_name) end, ',' order by ordinal_position)
    into cols, sel from information_schema.columns
   where table_schema = 'public' and table_name = 'kt_chi' and column_name <> 'id' and is_generated = 'NEVER';
  execute format('insert into kt_chi (%s) select %s from kt_chi where id = $1 returning id', cols, sel) using p_id into v_new;
  tl := p_so_tien / c.so_tien;
  update kt_chi set so_tien = p_so_tien, noi_dung = left(trim(p_noi_dung), 300),
      phan_bo = case when jsonb_typeof(c.phan_bo) = 'array' then (select coalesce(jsonb_agg(jsonb_set(e, '{so_tien}', to_jsonb(round((e->>'so_tien')::numeric * tl))) order by i), '[]'::jsonb)
                       from jsonb_array_elements(c.phan_bo) with ordinality x(e, i)) else c.phan_bo end,
      phan_bo_thang = case when jsonb_typeof(c.phan_bo_thang) = 'array' and jsonb_array_length(c.phan_bo_thang) > 0 then (select jsonb_agg(jsonb_set(e, '{so_tien}', to_jsonb(round((e->>'so_tien')::numeric * tl))) order by i)
                       from jsonb_array_elements(c.phan_bo_thang) with ordinality x(e, i)) else c.phan_bo_thang end,
      ma_nguon = null, kiot_so_quy_id = null, kiot_ma = null, nghi_trung = null,
      -- 26/10: phiếu gốc đã khớp phiếu Kiot → phần tách không cần phiếu Kiot riêng (tránh lần kéo Kiot sau ghép nhầm phiếu Kiot khác cùng số tiền)
      kiot = case when c.kiot_so_quy_id is not null then 'khong_tao' else c.kiot end,
      kiot_ly_do = case when c.kiot_so_quy_id is not null then 'Tách từ PC' || lpad(p_id::text, 6, '0') || ' — phiếu Kiot ghi ở phiếu gốc' else c.kiot_ly_do end,
      ghi_chu = left(concat_ws(' · ', 'Tách từ PC' || lpad(p_id::text, 6, '0'), c.ghi_chu), 1000),
      tao_boi = u.ho_ten, tao_luc = now(), sua_boi = null, sua_luc = null
   where id = v_new;
  if p_loai_id is not null then update kt_chi set loai_id = p_loai_id where id = v_new; end if;   -- mục con → trigger tách cha + con
  select * into n from kt_chi where id = v_new;
  -- phiếu gốc: phần còn lại (gốc − phần tách, từng dòng phân bổ) → cộng 2 phiếu đúng bằng số cũ
  update kt_chi set so_tien = c.so_tien - p_so_tien,
      phan_bo = case when jsonb_typeof(c.phan_bo) = 'array' then (select coalesce(jsonb_agg(jsonb_set(o.e, '{so_tien}', to_jsonb((o.e->>'so_tien')::numeric - coalesce((m.e->>'so_tien')::numeric, 0))) order by o.i), '[]'::jsonb)
                       from jsonb_array_elements(c.phan_bo) with ordinality o(e, i) left join jsonb_array_elements(n.phan_bo) with ordinality m(e, i) on m.i = o.i) else c.phan_bo end,
      phan_bo_thang = case when jsonb_typeof(c.phan_bo_thang) = 'array' and jsonb_array_length(c.phan_bo_thang) > 0 then (select jsonb_agg(jsonb_set(o.e, '{so_tien}', to_jsonb((o.e->>'so_tien')::numeric - coalesce((m.e->>'so_tien')::numeric, 0))) order by o.i)
                       from jsonb_array_elements(c.phan_bo_thang) with ordinality o(e, i) left join jsonb_array_elements(n.phan_bo_thang) with ordinality m(e, i) on m.i = o.i) else c.phan_bo_thang end,
      ghi_chu = left(concat_ws(' · ', c.ghi_chu, 'Đã tách ' || to_char(p_so_tien, 'FM999G999G999G999') || ' sang PC' || lpad(v_new::text, 6, '0')), 1000),
      sua_boi = u.ho_ten, sua_luc = now()
   where id = p_id;
  -- chứng từ: giữ ở phiếu gốc (kt_chung_tu.duong_dan là khoá duy nhất — bot MeInvoice dựa vào) → phiếu tách hiện link "chứng từ ở phiếu gốc"
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'tach_phieu', jsonb_build_object('phieu_moi', v_new, 'so_tien_tach', p_so_tien, 'con_lai', c.so_tien - p_so_tien));
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', v_new, 'tach_phieu', jsonb_build_object('tu_phieu', p_id, 'so_tien', p_so_tien, 'noi_dung', p_noi_dung));
  return v_new;
end $function$;
