-- ════════════════════════════════════════════════════════════════════════════
-- BÁO CÁO QUẢN TRỊ: P&L (kết quả kinh doanh) + DÒNG TIỀN theo giao diện mẫu anh gửi 14/10/2026
-- ("Phần mục báo cáo tạm thời xài báo cáo P&L và báo cáo dòng tiền trước mắt").
-- P&L: 1 Doanh thu thuần (Kiot: hoá đơn hoàn thành − trả hàng, theo cơ sở) · 2 Giá vốn (Kiot, bình quân lúc kéo) · 3 LN gộp ·
--      4 Chi phí (phiếu chi đã thanh toán, nhóm "Chi vận hành & quản lí", theo THÁNG PHÂN BỔ nếu có — kt_chi.phan_bo_thang) — mỗi loại chi OPEX 1 dòng
--      (+ lãi vay từ trang Vay & lãi vay nếu có) · 5 Lợi nhuận ròng.
--      KHÔNG gồm: chi nhập hàng (đã là giá vốn), trả gốc vay / chi tài chính, đầu tư (CAPEX).
-- Dòng tiền: thu đã duyệt / chi đã thanh toán theo ngày tiền thực (không phân bổ), xếp HĐKD / Đầu tư / Tài chính; số dư từ mốc tồn đầu (01/09/2026).
-- Monsieur Claude
-- ════════════════════════════════════════════════════════════════════════════

-- 14/10/2026 (sửa theo anh): chi phí P&L hiện ĐÚNG các loại chi OPEX của công ty (Lương & BHXH, Marketing, Mặt bằng, Logistics, Vận hành & Quản lí, Khác),
-- KHÔNG ép theo 6 nhóm chữ của ảnh mẫu. Bỏ cột nhom_pl và loại chi "TAX - Thuế" Claude tự thêm lúc đầu (chưa phiếu nào dùng).
alter table public.kt_loai drop column if exists nhom_pl;
delete from public.kt_loai l where l.ten = 'TAX - Thuế (GTGT, TNCN)' and not exists (select 1 from public.kt_chi c where c.loai_id = l.id);

-- Số liệu P&L theo tháng: doanh thu / giá vốn theo chi nhánh Kiot, chi phí theo loại × đơn vị (tách theo phân bổ đơn vị + tháng)
create or replace function public.kt_bc_pl2(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_t0 text := to_char(p_tu, 'YYYY-MM'); v_t1 text := to_char(p_den, 'YYYY-MM');
begin
  perform kt_chan(p_phien, 'pl');
  return jsonb_build_object(
    'dt', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'dt', dt, 'gv', gv)), '[]') from (
        select to_char((ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, chi_nhanh cn, sum(tong) dt, sum(coalesce(gia_von, 0)) gv
          from kt_kiot_hoa_don where trang_thai = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    -- trả hàng: trừ doanh thu theo ngày trả; giá vốn hàng trả = tiền trả × (giá vốn / tổng) của hoá đơn gốc (như trang Bán hàng)
    'tra', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'tra', tra, 'gv', gv)), '[]') from (
        select to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, t.chi_nhanh cn, sum(t.tong_tra) tra,
               round(sum(t.tong_tra * coalesce(h.gia_von / nullif(h.tong, 0), 0))) gv
          from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
         where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
    'cp', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai_id, 'dv', dv, 'tien', tien)), '[]') from (
        select th, loai_id, dv, round(sum(tien)) tien from (
          select coalesce(pt->>'thang', to_char(c.ngay_tt, 'YYYY-MM')) th, c.loai_id, (pb->>'don_vi_id')::int dv,
                 coalesce((pt->>'so_tien')::numeric, c.so_tien) * coalesce((pb->>'so_tien')::numeric / nullif(c.so_tien, 0), 1) tien
            from kt_chi c join kt_loai l on l.id = c.loai_id
            left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' and jsonb_array_length(c.phan_bo_thang) > 0 then c.phan_bo_thang end) pt on true
            left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' and jsonb_array_length(c.phan_bo) > 0 then c.phan_bo end) pb on true
           where not c.da_xoa and c.trang_thai = 'da_tt' and l.nhom_bc = 'Chi vận hành & quản lí'
             and (case when pt is null then c.ngay_tt between p_tu and p_den else pt->>'thang' between v_t0 and v_t1 end)) z
         group by 1, 2, 3) x),
    'lai_vay', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'lai', s)), '[]') from (
        select to_char(ngay, 'YYYY-MM') th, sum(lai) s from kt_vay_tra where not da_xoa and da_tra and ngay between p_tu and p_den group by 1) x),
    'loai', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'nhom_bc', nhom_bc, 'thu_tu', thu_tu, 'hoat_dong', hoat_dong) order by thu_tu, id), '[]') from kt_loai where nhom = 'chi'));
end $$;

-- Chi tiết 1 nhóm chi phí (bấm dòng 4.x / 6): các phiếu chi đã thanh toán, tiền đã tách theo tháng phân bổ + đơn vị
create or replace function public.kt_pl_ct(p_phien text, p_loai int[], p_tu date, p_den date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_t0 text := to_char(p_tu, 'YYYY-MM'); v_t1 text := to_char(p_den, 'YYYY-MM');
begin
  perform kt_chan(p_phien, 'pl');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ngay', ngay_tt, 'so', so, 'nd', noi_dung, 'th', thu_huong_ten, 'loai', loai_id,
           'dv', dv, 'tien', tien) order by ngay_tt desc, id desc), '[]') from (
    select c.id, c.ngay_tt, coalesce(c.kiot_ma, 'PC' || lpad(c.id::text, 6, '0')) so, c.noi_dung, c.thu_huong_ten, c.loai_id, (pb->>'don_vi_id')::int dv,
           round(sum(coalesce((pt->>'so_tien')::numeric, c.so_tien) * coalesce((pb->>'so_tien')::numeric / nullif(c.so_tien, 0), 1))) tien
      from kt_chi c
      left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' and jsonb_array_length(c.phan_bo_thang) > 0 then c.phan_bo_thang end) pt on true
      left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' and jsonb_array_length(c.phan_bo) > 0 then c.phan_bo end) pb on true
     where not c.da_xoa and c.trang_thai = 'da_tt' and c.loai_id = any(p_loai)
       and (case when pt is null then c.ngay_tt between p_tu and p_den else pt->>'thang' between v_t0 and v_t1 end)
     group by 1, 2, 3, 4, 5, 6, 7 limit 2000) x);
end $$;

-- Báo cáo dòng tiền theo tháng: thu (đã duyệt) / chi (đã thanh toán) theo loại × đơn vị, số dư đầu kỳ (chỉ từ mốc tồn đầu)
create or replace function public.kt_bc_lctt(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u kt_nguoi_dung; v_moc date;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'dong_tien') or kt_co_quyen(u, 'pl')) then raise exception 'Tài khoản chưa được cấp quyền xem dòng tiền' using errcode = '42501'; end if;
  select max(ngay_ton_dau) into v_moc from kt_tai_khoan where hoat_dong;
  return jsonb_build_object(
    'moc', v_moc,
    -- số dư (tổng các tài khoản — điều chuyển nội bộ tự triệt tiêu) tại ngày dau_ngay = max(p_tu, mốc tồn đầu); trước mốc không có số dư
    'dau_ngay', greatest(p_tu, v_moc),
    'dau', case when greatest(p_tu, v_moc) <= p_den then (select sum(tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b
                 where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau and b.ngay < greatest(p_tu, v_moc)), 0)) from kt_tai_khoan tk) end,
    'thu', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai_id, 'dv', don_vi_id, 'tien', s)), '[]') from (
        select to_char(ngay, 'YYYY-MM') th, loai_id, don_vi_id, sum(so_tien) s from kt_thu
         where not da_xoa and trang_thai = 'da_duyet' and ngay between p_tu and p_den group by 1, 2, 3) x),
    'chi', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai_id, 'dv', dv, 'tien', s)), '[]') from (
        select to_char(c.ngay_tt, 'YYYY-MM') th, c.loai_id, (pb->>'don_vi_id')::int dv,
               round(sum(c.so_tien * coalesce((pb->>'so_tien')::numeric / nullif(c.so_tien, 0), 1))) s
          from kt_chi c left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' and jsonb_array_length(c.phan_bo) > 0 then c.phan_bo end) pb on true
         where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between p_tu and p_den group by 1, 2, 3) x),
    -- biến động ròng theo tháng (để ra số dư cuối từng tháng, chỉ phần từ mốc)
    'rong', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'rong', s)), '[]') from (
        select to_char(b.ngay, 'YYYY-MM') th, sum(b.vao - b.ra) s from kt_v_bien_dong b join kt_tai_khoan tk on tk.id = b.tai_khoan_id
         where b.ngay between p_tu and p_den and b.ngay >= tk.ngay_ton_dau group by 1) x),
    'loai', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'nhom', nhom, 'nhom_bc', nhom_bc)), '[]') from kt_loai));
end $$;

revoke execute on function public.kt_bc_pl2(text, date, date), public.kt_pl_ct(text, int[], date, date), public.kt_bc_lctt(text, date, date) from public;
grant execute on function public.kt_bc_pl2(text, date, date), public.kt_pl_ct(text, int[], date, date), public.kt_bc_lctt(text, date, date) to anon, authenticated;
