-- TK "TIỀN MẶT QUẦY CỬA HÀNG": chỉnh tồn đầu 01/09 cho khớp hẳn Kiot 3 cửa hàng — 19/11/2026. Monsieur Claude
-- Anh: "chỉnh lại cho khớp hẳn đi, khoản thu chênh coi như clear". Sau khi kéo chi tại quầy (VIEC 394) TK quầy còn thấp hơn Kiot đúng 1 khoản không đổi
-- từ 26/10: tiền quầy Sỉ trước 01/09 (có trên Kiot, thiếu trong tồn đầu chốt theo file) trừ 2 khoản thu chênh 13/10, 19/10 (clear). → cộng phần chênh vào tồn đầu.
do $$ declare v_kiot numeric; v_app numeric; v_lech numeric; begin
  select sum(case when la_thu then so_tien else -so_tien end) into v_kiot from kt_kiot_so_quy
   where trang_thai = '0' and phuong_thuc = 'Cash' and (nhom = 'Chuyển rút' or ma !~ '^(TTD_|CTD_)') and (ngay at time zone 'Asia/Ho_Chi_Minh')::date <= date '2026-11-19';
  select tk.ton_dau + coalesce((select sum(vao - ra) from kt_v_bien_dong b where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau and b.ngay <= date '2026-11-19'), 0)
    into v_app from kt_tai_khoan tk where tk.id = 23;
  v_lech := v_kiot - v_app;
  if abs(v_lech) > 0 and abs(v_lech) < 1000000 then
    update kt_tai_khoan set ton_dau = ton_dau + v_lech where id = 23;
    perform kt_ghi_nhat_ky('Hệ thống', 'kt_tai_khoan', 23, 'sua', jsonb_build_object('ton_dau_cong', v_lech, 'ly_do', 'khớp Kiot 3 cửa hàng 19/11 (anh duyệt)'));
  end if;
end $$;
