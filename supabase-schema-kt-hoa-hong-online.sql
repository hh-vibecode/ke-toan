-- 31/10/2026 anh: "báo cáo hoa hồng thêm Nguyễn Hoàng Hải, nhận 1% từ doanh thu online thực tế trong tháng" + "vị trí hỗ trợ vận hành".
-- kt_bc_hoa_hong.hd thêm cờ 'on' (hoá đơn online) — CÙNG luật Tổng quan / P&L: kênh bán hoá đơn Kiot, trống thì kênh đơn đặt hàng gắn;
-- kt_kenh_off (trực tiếp / Khác / trống / Chùa Vẻn) = offline. Dòng trả hàng lấy cờ của hoá đơn gốc. Người hưởng ghi trong kt_cai_dat hh_cau_hinh
-- (nguoi: cs = 'online', tl = 0.01). — Monsieur Claude
create or replace function public.kt_bc_hoa_hong(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cuc jsonb;
begin
  perform kt_chan(p_phien, 'pl');
  -- 29/10 kế toán: thu tiền cả cục gắn khách (không đánh từng hoá đơn) → phân bổ phiếu thu cục vào hoá đơn (kt_hd_thu_cuc)
  select coalesce(jsonb_object_agg(hoa_don_id::text, thu), '{}') into v_cuc from kt_hd_thu_cuc();
  return jsonb_build_object(
    'ban', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'nv', nv, 'nhom', nh, 'dt', round(dt), 'thu', round(thu), 'so', so)), '[]') from (
        with h as (select h.id, to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, h.chi_nhanh cn, coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)') nv,
                          h.tong, least(greatest(coalesce(h.da_tra, 0), 0) + coalesce((v_cuc->>h.id::text)::numeric, 0), h.tong) thu, coalesce(h.chi_tiet, '[]'::jsonb) ct
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
               'thu', round(thu), 'cuc', round(cuc), 'gc', gc, 'nh', nh, 'la_tra', la_tra, 'sp', sp, 'ma_tra', ma_tra, 'on', onl) order by ngay, id), '[]') from (
        select h.id, h.ma, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, h.chi_nhanh cn,
               coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)') nv, h.khach_ten khach, h.tong, coalesce(t.tra, 0) tra,
               greatest(least(greatest(coalesce(h.da_tra, 0), 0) + coalesce((v_cuc->>h.id::text)::numeric, 0), h.tong) - coalesce(t.hoan, 0), 0) thu,
               coalesce((v_cuc->>h.id::text)::numeric, 0) cuc,
               case when h.ghi_chu ~ '(đóng hàng|giao hàng|ĐH|GH)' then regexp_replace(h.ghi_chu, '\s+', ' ', 'g') end gc,
               (select jsonb_object_agg(q.nh, q.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x group by 1) q) nh, false la_tra,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x) sp, null::text ma_tra,
               not kt_kenh_off(coalesce(kh.ten, ko.ten), h.chi_nhanh) onl
          from kt_kiot_hoa_don h
          left join kt_kiot_kenh kh on kh.id = h.kenh_id
          left join lateral (select k2.ten from kt_kiot_dat_hang o2 join kt_kiot_kenh k2 on k2.id = o2.kenh_id where h.kenh_id is null and h.dat_hang_id = o2.id limit 1) ko on true
          left join lateral (select sum(t.tong_tra) tra, sum(greatest(coalesce(t.da_tra, 0), 0)) hoan from kt_kiot_tra_hang t
                 where t.hoa_don_id = h.id and coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den) t on true
         where h.trang_thai in (1, 3) and h.tong > 0 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
        union all
        select -t.id, coalesce(h.ma, '?'), (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM'),
               coalesce(h.chi_nhanh, t.chi_nhanh), coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)'), h.khach_ten, 0, t.tong_tra, -greatest(coalesce(t.da_tra, 0), 0), 0, null,
               (select jsonb_object_agg(q.nh, q.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x group by 1) q), true,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x) sp, t.ma,
               h.id is not null and not kt_kenh_off(coalesce(kh.ten, ko.ten), h.chi_nhanh)
          from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
          left join kt_kiot_kenh kh on kh.id = h.kenh_id
          left join lateral (select k2.ten from kt_kiot_dat_hang o2 join kt_kiot_kenh k2 on k2.id = o2.kenh_id where h.kenh_id is null and h.dat_hang_id = o2.id limit 1) ko on true
         where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
           and (h.id is null or (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date < p_tu)) z),
    'cau_hinh', (select gia_tri::jsonb from kt_cai_dat where khoa = 'hh_cau_hinh'),
    'sua', (select jsonb_build_object('luc', sua_luc) from kt_cai_dat where khoa = 'hh_cau_hinh'));
end $function$;
update kt_cai_dat set gia_tri = (gia_tri::jsonb || jsonb_build_object('nguoi', (gia_tri::jsonb->'nguoi') || '[{"cs": "online", "ten": "Nguyễn Hoàng Hải", "vt": "Hỗ trợ vận hành", "tl": 0.01, "kiot": []}]'::jsonb))::text,
  sua_luc = now()
 where khoa = 'hh_cau_hinh' and not (gia_tri::jsonb->'nguoi' @> '[{"ten": "Nguyễn Hoàng Hải"}]');
