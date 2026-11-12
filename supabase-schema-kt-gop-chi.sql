-- 12/11/2026 anh (ảnh kế toán hỏi: "2 phiếu này vừa chị tách ra 2 nguồn thanh toán, giờ lại gộp vào thế nào nhỉ") → "thêm chức năng gộp phiếu".
-- kt_gop_chi: tick ≥ 2 phiếu chi CÙNG người thụ hưởng, CÙNG bước duyệt, CHƯA chi tiền → gộp thành 1 phiếu (phiếu giữ lại do kế toán chọn):
--   số tiền = tổng; phân bổ cơ sở / tháng cộng theo từng dòng cùng đơn vị / tháng; HĐ đỏ, chứng từ, phân bổ NCC, chi phí lô nhập khẩu, dòng đề nghị
--   chuyển sang phiếu giữ lại; các phiếu còn lại xoá mềm (ghi chú "Đã gộp vào PC…", còn trong nhật ký). Tài khoản đi tiền / nội dung theo lựa chọn;
--   phiếu đang Chờ chi tiền đổi tài khoản qua kt_doi_tk_chi (báo thủ quỹ như đổi tay). Không gộp: tạm ứng / hoàn ứng, phiếu trả nợ vay / lịch thanh toán,
--   phiếu đã chi / từ chối; phiếu đang liên kết Kiot hoặc sheet chỉ được làm phiếu giữ lại. — Monsieur Claude
create or replace function public.kt_gop_chi(p_phien text, p_ids bigint[], p_giu bigint, p_tk int, p_noi_dung text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; g kt_chi; n int; bo bigint[]; v_tong numeric; v_pb jsonb; v_pbt jsonb; v_tt text; x record; ten text;
begin
  u := kt_chan(p_phien, 'chi', true);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  if not kt_co_quyen(u, 'chi_duyet') then raise exception 'Chỉ kế toán (quyền xác nhận) gộp phiếu' using errcode = '42501'; end if;
  p_ids := array(select distinct unnest(p_ids));
  if coalesce(array_length(p_ids, 1), 0) < 2 then raise exception 'Chọn ít nhất 2 phiếu để gộp'; end if;
  if not p_giu = any(p_ids) then raise exception 'Phiếu giữ lại phải nằm trong các phiếu đã chọn'; end if;
  perform 1 from kt_chi where id = any(p_ids) for update;
  select count(*) into n from kt_chi where id = any(p_ids) and not da_xoa;
  if n <> array_length(p_ids, 1) then raise exception 'Có phiếu đã bị xoá — tải lại trang'; end if;
  for x in select * from kt_chi where id = any(p_ids) loop
    if x.trang_thai not in ('cho_duyet', 'cho_gd', 'cho_tt') then raise exception 'PC% đã chi tiền / từ chối — chỉ gộp phiếu chưa chi', lpad(x.id::text, 6, '0'); end if;
    if x.la_tam_ung or x.loai_dn = 'hoan_ung' then raise exception 'PC% là tạm ứng / hoàn ứng — không gộp', lpad(x.id::text, 6, '0'); end if;
    if exists (select 1 from kt_vay_tra where chi_id = x.id) or exists (select 1 from kt_lich_tt_tra where chi_id = x.id) or exists (select 1 from kt_tam_ung where chi_id = x.id) then
      raise exception 'PC% gắn khoản vay / lịch thanh toán / tạm ứng — không gộp', lpad(x.id::text, 6, '0'); end if;
    if x.id <> p_giu and (x.ma_nguon is not null or x.kiot_so_quy_id is not null) then
      raise exception 'PC% đang liên kết Kiot / sheet đề nghị — chọn phiếu đó làm phiếu giữ lại', lpad(x.id::text, 6, '0'); end if;
  end loop;
  if (select count(distinct trang_thai) from kt_chi where id = any(p_ids)) > 1 then raise exception 'Các phiếu đang ở bước duyệt khác nhau — đưa về cùng bước rồi gộp'; end if;
  if (select count(distinct lower(btrim(coalesce(thu_huong_ten, '')))) from kt_chi where id = any(p_ids)) > 1 then raise exception 'Chỉ gộp phiếu cùng người thụ hưởng'; end if;
  if (select count(distinct jsonb_typeof(coalesce(phan_bo, 'null'))) from kt_chi where id = any(p_ids)) > 1 then raise exception 'Phân bổ cơ sở các phiếu khác kiểu — sửa phân bổ rồi gộp'; end if;
  select * into g from kt_chi where id = p_giu;
  bo := array(select unnest(p_ids) except select p_giu order by 1);
  select sum(so_tien) into v_tong from kt_chi where id = any(p_ids);
  -- phân bổ: cộng các dòng giống nhau (mọi trường trừ so_tien)
  select case when jsonb_typeof(g.phan_bo) = 'array' then coalesce(jsonb_agg(k || jsonb_build_object('so_tien', t) order by k::text), '[]') else g.phan_bo end into v_pb
    from (select e - 'so_tien' k, sum((e->>'so_tien')::numeric) t from kt_chi c, jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' then c.phan_bo else '[]' end) e
           where c.id = any(p_ids) group by 1) z;
  if (select bool_and(jsonb_typeof(phan_bo_thang) = 'array' and jsonb_array_length(phan_bo_thang) > 0) from kt_chi where id = any(p_ids)) then
    select jsonb_agg(k || jsonb_build_object('so_tien', t) order by k::text) into v_pbt
      from (select e - 'so_tien' k, sum((e->>'so_tien')::numeric) t from kt_chi c, jsonb_array_elements(c.phan_bo_thang) e where c.id = any(p_ids) group by 1) z;
  else v_pbt := null; end if;
  -- chuyển các thứ gắn với phiếu bị gộp sang phiếu giữ lại
  update kt_chi_hd set chi_id = p_giu where chi_id = any(bo);
  update kt_chung_tu set dong_id = p_giu where bang = 'kt_chi' and dong_id = any(bo);
  update kt_ncc_phan_bo set chi_id = p_giu where chi_id = any(bo);
  update kt_lo_nk_cp set chi_id = p_giu where chi_id = any(bo);
  update kt_dcp_dong set chi_id = p_giu where chi_id = any(bo);
  update kt_chi set da_xoa = true, sua_boi = coalesce(u.ho_ten, u.ten_dang_nhap), sua_luc = now(),
      ghi_chu = left(concat_ws(' · ', ghi_chu, 'Đã gộp vào PC' || lpad(p_giu::text, 6, '0')), 1000)
   where id = any(bo);
  update kt_chi set so_tien = v_tong, phan_bo = v_pb, phan_bo_thang = case when v_pbt is not null then v_pbt when jsonb_typeof(phan_bo_thang) = 'array' and jsonb_array_length(phan_bo_thang) > 0 then null else phan_bo_thang end,
      noi_dung = coalesce(nullif(left(btrim(p_noi_dung), 300), ''), noi_dung),
      co_hd_do = (select bool_or(co_hd_do) from kt_chi where id = any(p_ids)),
      ghi_chu = left(concat_ws(' · ', ghi_chu, 'Gộp ' || (select string_agg('PC' || lpad(b::text, 6, '0'), ', ') from unnest(bo) b) || ' vào phiếu này'), 1000),
      sua_boi = coalesce(u.ho_ten, u.ten_dang_nhap), sua_luc = now()
   where id = p_giu;
  if p_tk is not null and p_tk is distinct from g.tai_khoan_id then
    if not exists (select 1 from kt_tai_khoan where id = p_tk and hoat_dong) then raise exception 'Tài khoản không hợp lệ'; end if;
    if g.trang_thai = 'cho_tt' then perform kt_doi_tk_chi(p_phien, p_giu, p_tk); else update kt_chi set tai_khoan_id = p_tk where id = p_giu; end if;
  end if;
  ten := coalesce(u.ho_ten, u.ten_dang_nhap);
  perform kt_ghi_nhat_ky(ten, 'kt_chi', p_giu, 'gop_phieu', jsonb_build_object('gop', to_jsonb(bo), 'so_tien', v_tong, 'tk', p_tk));
  for x in select unnest(bo) id loop perform kt_ghi_nhat_ky(ten, 'kt_chi', x.id, 'gop_phieu', jsonb_build_object('vao', p_giu)); end loop;
  return jsonb_build_object('giu', p_giu, 'gop', to_jsonb(bo), 'so_tien', v_tong);
end $$;
revoke execute on function public.kt_gop_chi(text, bigint[], bigint, int, text) from public;
grant execute on function public.kt_gop_chi(text, bigint[], bigint, int, text) to anon, authenticated;
