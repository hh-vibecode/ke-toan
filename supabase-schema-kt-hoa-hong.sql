-- 28/10/2026 (anh): "Hoa hồng đẩy vào thành mục 9 của báo cáo quản trị". 3 chính sách (thư mục Desktop "doi soat"):
--   • Vân Ngọc — CS-VH04-16 "Hoa hồng & thưởng nhân viên Sales online lẻ" (file T12): giật cấp phần vượt 1,5% / 1,8% / 2% / 2,5% (mốc 150 / 200 / 300tr).
--   • Nguyên — CS-VH04-13 "Hoa hồng Sales online mảng buôn" (file 9.2026): quỹ team, doanh thu Kiot của Nguyên + Oanh (Oanh hỗ trợ) tính hết cho Nguyên;
--     dưới mốc → 0; 600tr đầu 1,5%, 600tr–1,2 tỷ 2%, trên 1,2 tỷ 2,5%. Hỗ trợ sales mới 7/10/2026–7/1/2027: mốc 300tr thay 600tr.
--   • File "Hoa hồng & thưởng cửa hàng" → phân nhóm sản phẩm: biên cao 2% / biên thấp 0,8% (Hiền Thủy), Chánh Tâm 2% mọi nhóm.
-- Doanh thu tính hoa hồng = THỰC THU: phần khách đã trả trên hoá đơn Kiot (hoàn thành), chia về nhóm hàng theo tỷ trọng dòng hàng;
-- trả hàng trừ theo ngày trả (tiền đã hoàn khách trừ vào thực thu). Cấu hình (người · chính sách · mốc · phân nhóm) lưu kt_cai_dat 'hh_cau_hinh'. — Monsieur Claude
create or replace function public.kt_bc_hoa_hong(p_phien text, p_tu date, p_den date) returns jsonb
 language plpgsql stable security definer set search_path to 'public' as $function$
begin
  perform kt_chan(p_phien, 'pl');
  return jsonb_build_object(
    'ban', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'nv', nv, 'nhom', nh, 'dt', round(dt), 'thu', round(thu), 'so', so)), '[]') from (
        with h as (select h.id, to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, h.chi_nhanh cn, coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)') nv,
                          h.tong, least(greatest(coalesce(h.da_tra, 0), 0), h.tong) thu, coalesce(h.chi_tiet, '[]'::jsonb) ct
                     from kt_kiot_hoa_don h
                    where h.trang_thai in (1, 3) and h.tong > 0 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
             d as (select h.*, kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, greatest(coalesce((x->>'tien')::numeric, 0), 0) tien
                     from h cross join lateral jsonb_array_elements(case when jsonb_array_length(h.ct) > 0 then h.ct else '[{"tien": 1}]'::jsonb end) x),
             s as (select d.*, sum(tien) over (partition by id) tong_dong from d)
        select th, cn, nv, nh, sum(tong * case when tong_dong > 0 then tien / tong_dong else 0 end) dt,
               sum(thu * case when tong_dong > 0 then tien / tong_dong else 0 end) thu, count(distinct id) so
          from s group by 1, 2, 3, 4) z),
    'tra', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'nv', nv, 'nhom', nh, 'tra', round(tra), 'hoan', round(hoan))), '[]') from (
        with t as (select t.id, to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, coalesce(h.chi_nhanh, t.chi_nhanh) cn,
                          coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)') nv, t.tong_tra, greatest(coalesce(t.da_tra, 0), 0) hoan, coalesce(h.chi_tiet, '[]'::jsonb) ct
                     from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
                    where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
             d as (select t.*, kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, greatest(coalesce((x->>'tien')::numeric, 0), 0) tien
                     from t cross join lateral jsonb_array_elements(case when jsonb_array_length(t.ct) > 0 then t.ct else '[{"tien": 1}]'::jsonb end) x),
             s as (select d.*, sum(tien) over (partition by id) tong_dong from d)
        select th, cn, nv, nh, sum(tong_tra * case when tong_dong > 0 then tien / tong_dong else 0 end) tra,
               sum(hoan * case when tong_dong > 0 then tien / tong_dong else 0 end) hoan
          from s group by 1, 2, 3, 4) z),
    -- 28/10 anh: hoa hồng đóng gói / giao hàng 0,25% theo tên trong ghi chú Kiot ("Người đóng hàng: …", "Diệp ĐH, Tuấn GH") — đơn cửa hàng, thực thu ròng từng hoá đơn
    -- 28/10 (sắp xếp lại mục 9): danh sách hoá đơn để bấm xem chi tiết từng nhân sự (đơn bán, đơn đóng / giao); ghi chú chỉ gửi khi có người đóng / giao
    -- 28/10 anh: "bên trong các tổng hợp truy xuất được các đơn, để sale phản hồi thiếu thì check lại đủ chưa" → MỌI số hoa hồng tính từ danh sách này
    -- (hoá đơn trong kỳ: thực thu ròng = đã trả − tiền hoàn của phiếu trả trong kỳ; phiếu trả trong kỳ của hoá đơn kỳ trước = dòng âm), nh = tiền dòng hàng theo nhóm cha.
    'hd', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ma', ma, 'ngay', ngay, 'thang', th, 'cn', cn, 'nv', nv, 'khach', khach, 'tong', round(tong), 'tra', round(tra),
               'thu', round(thu), 'gc', gc, 'nh', nh, 'la_tra', la_tra, 'sp', sp, 'ma_tra', ma_tra) order by ngay, id), '[]') from (
        select h.id, h.ma, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, h.chi_nhanh cn,
               coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)') nv, h.khach_ten khach, h.tong, coalesce(t.tra, 0) tra,
               greatest(least(greatest(coalesce(h.da_tra, 0), 0), h.tong) - coalesce(t.hoan, 0), 0) thu,
               case when h.ghi_chu ~ '(đóng hàng|giao hàng|ĐH|GH)' then regexp_replace(h.ghi_chu, '\s+', ' ', 'g') end gc,
               (select jsonb_object_agg(q.nh, q.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x group by 1) q) nh, false la_tra,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x) sp, null::text ma_tra
          from kt_kiot_hoa_don h
          left join lateral (select sum(t.tong_tra) tra, sum(greatest(coalesce(t.da_tra, 0), 0)) hoan from kt_kiot_tra_hang t
                 where t.hoa_don_id = h.id and coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den) t on true
         where h.trang_thai in (1, 3) and h.tong > 0 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
        union all
        select -t.id, coalesce(h.ma, '?'), (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM'),
               coalesce(h.chi_nhanh, t.chi_nhanh), coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)'), h.khach_ten, 0, t.tong_tra, -greatest(coalesce(t.da_tra, 0), 0), null,
               (select jsonb_object_agg(q.nh, q.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x group by 1) q), true,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x) sp, t.ma
          from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
         where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
           and (h.id is null or (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date < p_tu)) z),
    'cau_hinh', (select gia_tri::jsonb from kt_cai_dat where khoa = 'hh_cau_hinh'),
    'sua', (select jsonb_build_object('luc', sua_luc) from kt_cai_dat where khoa = 'hh_cau_hinh'));
end $function$;
revoke all on function public.kt_bc_hoa_hong(text, date, date) from public;
grant execute on function public.kt_bc_hoa_hong(text, date, date) to anon, authenticated;

-- lưu cấu hình (quyền sửa trang P&L / báo cáo quản trị)
create or replace function public.kt_luu_hh_cau_hinh(p_phien text, p_cau_hinh jsonb) returns void
 language plpgsql security definer set search_path to 'public' as $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'pl', true);
  if jsonb_typeof(p_cau_hinh) <> 'object' or jsonb_typeof(p_cau_hinh->'nguoi') <> 'array' or jsonb_typeof(p_cau_hinh->'nhom') <> 'object' then
    raise exception 'Cấu hình hoa hồng không hợp lệ';
  end if;
  insert into kt_cai_dat (khoa, gia_tri, sua_luc) values ('hh_cau_hinh', p_cau_hinh::text, now())
  on conflict (khoa) do update set gia_tri = excluded.gia_tri, sua_luc = now();
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_cai_dat', null, 'sua_hoa_hong', p_cau_hinh);
end $function$;
revoke all on function public.kt_luu_hh_cau_hinh(text, jsonb) from public;
grant execute on function public.kt_luu_hh_cau_hinh(text, jsonb) to anon, authenticated;

-- cấu hình mặc định (tên nhân viên) ở file LOCAL supabase-schema-kt-hoa-hong-cau-hinh.local.sql
