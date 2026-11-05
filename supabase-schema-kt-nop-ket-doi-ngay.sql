-- 05/11/2026 anh (ảnh Kiot CTM004104 03/11 "két lệch, bị thiếu phiếu này"): app đã tạo điều chuyển Nộp két ngày 31/10 (ngày lúc lập phiếu), sau đó Kiot sửa
-- ngày phiếu thành 03/11 — app không cập nhật, thủ quỹ chưa bấm Đã nhận (phiếu chờ nhận chưa tính vào két) và xem tháng 11 thì không thấy phiếu ngày 31/10.
-- Sửa: phiếu nguồn Kiot thủ quỹ chưa nhận → ngày đi theo Kiot. (Trang Điều chuyển: phiếu chờ thủ quỹ nhận của kỳ trước vẫn hiện.) — Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_dong_bo_nop_ket(p_tu date DEFAULT '2026-09-01'::date, p_thu boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_quay int; v_ket int; r record; v_dc bigint; n_tao int := 0; n_gan int := 0; n_huy int := 0; n_co int := 0; n_doi int := 0;
begin
  select id into v_quay from kt_tai_khoan where 'TIEN_MAT_QUAY' = any(kiot_ma) limit 1;
  select id into v_ket from kt_tai_khoan where '1000009795' = any(kiot_ma) limit 1;
  if v_quay is null or v_ket is null then raise exception 'Chưa nối tài khoản quầy / két với Kiot'; end if;
  for r in
    select c.ma, (c.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, c.so_tien, c.chi_nhanh, c.noi_dung,
           c.trang_thai = '0' and t.trang_thai = '0' con_hieu_luc
      from kt_kiot_so_quy c join kt_kiot_so_quy t on t.ma = 'TTD_' || c.ma and t.la_thu and t.tai_khoan = '1000009795'
     where not c.la_thu and c.phuong_thuc = 'Cash' and c.ma like 'CTM%' and (c.ngay at time zone 'Asia/Ho_Chi_Minh')::date >= p_tu
     order by c.ngay
  loop
    select id into v_dc from kt_dieu_chuyen where ma_nguon = 'kiot:' || r.ma;
    if not r.con_hieu_luc then
      if v_dc is not null then n_huy := n_huy + 1;
        if not p_thu then update kt_dieu_chuyen set da_xoa = true, sua_boi = 'Kiot (phiếu nộp két đã huỷ)', sua_luc = now() where id = v_dc and nguon = 'kiot' and not da_xoa; end if; end if;
      continue;
    end if;
    if v_dc is not null then n_co := n_co + 1;
      -- 05/11: Kiot sửa ngày phiếu sau khi app đã tạo điều chuyển (vd CTM004104 31/10 → 03/11) → thủ quỹ CHƯA nhận thì đổi ngày theo Kiot
      if not p_thu then begin
        update kt_dieu_chuyen set ngay = r.ngay, sua_boi = 'Kiot (đổi ngày phiếu nộp két)', sua_luc = now()
         where id = v_dc and nguon = 'kiot' and not da_xoa and tq_nhan_luc is null and ngay <> r.ngay;
        if found then n_doi := n_doi + 1; end if;
      exception when others then null;   -- kỳ đã khoá sổ: giữ ngày cũ
      end; end if;
      continue; end if;
    select id into v_dc from kt_dieu_chuyen where tk_di_id = v_quay and tk_nhan_id = v_ket and so_tien = r.so_tien and abs(ngay - r.ngay) <= 4 and not da_xoa
       and (ma_nguon is null or ma_nguon not like 'kiot:%') order by abs(ngay - r.ngay), id limit 1;   -- file dòng tiền ghi ngày tiền về két, Kiot ghi ngày lập phiếu: lệch ≤ 4 ngày cùng số = 1 lần nộp (giữ ngày trên app)
    if v_dc is not null then n_gan := n_gan + 1;
      if not p_thu then update kt_dieu_chuyen set ma_nguon = 'kiot:' || r.ma, ghi_chu = concat_ws(' ', ghi_chu, '[Khớp phiếu Kiot ' || r.ma || ']') where id = v_dc; end if;
    else n_tao := n_tao + 1;
      if not p_thu then
        insert into kt_dieu_chuyen (ngay, noi_dung, so_tien, tk_di_id, tk_nhan_id, ghi_chu, kiot, nguon, ma_nguon, tao_boi)
        values (r.ngay, left('Nộp két: ' || coalesce(r.chi_nhanh, '') || ' — ' || coalesce(nullif(trim(r.noi_dung), ''), 'nộp doanh thu tiền mặt'), 300),
                r.so_tien, v_quay, v_ket, 'Tự tạo từ phiếu Kiot ' || r.ma || ' + TTD_' || r.ma, 'da_tao', 'kiot', 'kiot:' || r.ma, 'Hệ thống (Kiot nộp két)');
      end if;
    end if;
  end loop;
  return jsonb_build_object('tao_moi', n_tao, 'gan_ma_vao_phieu_co_san', n_gan, 'da_co', n_co, 'doi_ngay', n_doi, 'an_vi_kiot_huy', n_huy, 'chay_thu', p_thu);
end $function$;
