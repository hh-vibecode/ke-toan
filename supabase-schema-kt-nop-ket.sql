-- NỘP KÉT TỪ KIOT (19/10/2026 — kế toán / thủ quỹ hỏi: "tiền mặt quầy chưa nộp két sẽ tự ghi nhận nộp két khi phát sinh phiếu chuyển/rút trên Kiot
-- đúng không? chứng từ nộp tiền hàng ngày thủ quỹ up lên đâu? app đối chiếu phiếu Kiot với phiếu trên app"). Trước: phiếu Kiot nhóm "Chuyển rút" bị BỎ QUA,
-- nộp két chỉ có từ file dòng tiền tới 16/10. Nay: cặp phiếu Kiot CTM… (chi tiền mặt quầy) + TTD_CTM… (thu vào Két 1000009795) còn hiệu lực
-- → điều chuyển "Nộp két" TIỀN MẶT QUẦY → KÉT TIỀN MẶT (nguồn kiot, ma_nguon kiot:CTM…). Đã có điều chuyển quầy→két cùng số tiền, lệch ≤ 4 ngày (từ file / tay)
-- thì chỉ gắn mã Kiot (không tạo trùng). Phiếu Kiot bị huỷ sau đó → ẩn điều chuyển nguồn kiot tương ứng. Thủ quỹ up ảnh nộp tiền vào chính phiếu điều chuyển này,
-- kế toán bấm "Xác nhận" sau khi xem ảnh. Lịch pg_cron kt-nop-ket 15 phút / lần (sau kt-kiot). — Monsieur Claude
alter table public.kt_dieu_chuyen drop constraint if exists kt_dieu_chuyen_nguon_check;
alter table public.kt_dieu_chuyen add constraint kt_dieu_chuyen_nguon_check check (nguon = any (array['app', 'sheet_cu', 'kiot']));

create or replace function public.kt_dong_bo_nop_ket(p_tu date default date '2026-09-01', p_thu boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_quay int; v_ket int; r record; v_dc bigint; n_tao int := 0; n_gan int := 0; n_huy int := 0; n_co int := 0;
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
    if v_dc is not null then n_co := n_co + 1; continue; end if;
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
  return jsonb_build_object('tao_moi', n_tao, 'gan_ma_vao_phieu_co_san', n_gan, 'da_co', n_co, 'an_vi_kiot_huy', n_huy, 'chay_thu', p_thu);
end $$;
revoke all on function public.kt_dong_bo_nop_ket(date, boolean) from public, anon;

-- chạy lần đầu từ 01/09 (gắn mã Kiot vào điều chuyển có sẵn + tạo lần nộp mới), sau đó 15 phút / lần cho 10 ngày gần nhất
select kt_dong_bo_nop_ket(date '2026-09-01', false);
select cron.unschedule('kt-nop-ket') where exists (select 1 from cron.job where jobname = 'kt-nop-ket');
select cron.schedule('kt-nop-ket', '7,22,37,52 * * * *', $c$select public.kt_dong_bo_nop_ket(((now() at time zone 'Asia/Ho_Chi_Minh')::date - 10), false)$c$);
