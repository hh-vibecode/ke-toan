-- 02/11/2026: hoá đơn ở tháng hàng đi kèm danh sách phiếu cọc / trả trước (coc_ds: mã, ngày, tiền) để popup nhân sự ghi rõ. — Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_bc_hoa_hong(p_phien text, p_tu date, p_den date)
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
    -- 02/11 anh: tính theo TIỀN VỀ trong tháng (phiếu sổ quỹ chia vào hoá đơn + phân bổ phiếu cục theo khách), không theo tháng hoá đơn; bỏ khoản trả bằng điểm.
    -- Mỗi dòng = 1 hoá đơn × 1 tháng tiền về. Cọc TTDH: dòng riêng ở tháng nhận cọc; đóng / giao: phần cọc tính ở tháng hoá đơn (hàng đi), tiền về sau tính ở tháng tiền về.
    'hd', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ma', ma, 'ngay', ngay, 'thang', th, 'cn', cn, 'nv', nv, 'khach', khach, 'tong', round(tong), 'tra', round(tra),
               'thu', round(thu), 'cuc', round(cuc), 'gc', gc, 'nh', nh, 'la_tra', la_tra, 'sp', sp, 'ma_tra', ma_tra, 'on', onl,
               'coc', round(coc), 'thu_dg', round(thu_dg), 'la_coc', la_coc, 'ma_don', ma_don, 'gt_don', round(gt_don), 'ngay_hd', ngay_hd, 'la_phieu', la_phieu, 'coc_ds', coc_ds) order by ngay, id), '[]') from (
        with cd as materialized (select regexp_replace(substr(q.ma, 3), '-[0-9]+$', '') dh, sum(q.so_tien) tien,
                                         jsonb_agg(jsonb_build_object('ma', q.ma, 'ngay', (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'tien', round(q.so_tien)) order by q.ngay) ds from kt_kiot_so_quy q
                                  where q.ma like 'TTDH%' and q.la_thu and q.trang_thai = '0' group by 1),
             sq as materialized (select ma from kt_kiot_so_quy where la_thu and trang_thai = '0'),
             cuc2 as materialized (select * from kt_hd_thu_cuc2()),
             -- 02/11: tiền khách trả TRƯỚC tháng hoá đơn (phiếu trả trước ghép hoá đơn sau) = cọc → đóng / giao tính ở tháng hàng đi
             pre as materialized (select z.hd, sum(z.tien) tien, jsonb_agg(jsonb_build_object('ma', z.ma, 'ngay', z.ngay, 'tien', round(z.tien)) order by z.ngay) ds from (
                       select c.hoa_don_id hd, c.ma, c.ngay, c.thu tien from cuc2 c where c.hoa_don_id is not null
                       union all select t.id, x->>'ma', (x->>'ngay')::date, (x->>'tien')::numeric from kt_kiot_hd_thu t cross join lateral jsonb_array_elements(t.ds) x join sq on sq.ma = x->>'ma'
                        where coalesce(x->>'pt', '') <> 'Point') z
                     join kt_kiot_hoa_don h on h.id = z.hd where to_char(z.ngay, 'YYYY-MM') < to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') group by 1),
             pay as (select t.id hd, (x->>'ngay')::date ngay, (x->>'tien')::numeric tien, 0::numeric cuc
                       from kt_kiot_hd_thu t cross join lateral jsonb_array_elements(t.ds) x join sq on sq.ma = x->>'ma'
                      where (x->>'ngay')::date between p_tu and p_den and coalesce(x->>'pt', '') <> 'Point'
                     union all select c.hoa_don_id, c.ngay, c.thu, c.thu from cuc2 c where c.hoa_don_id is not null and c.ngay between p_tu and p_den),
             g as (select hd, to_char(ngay, 'YYYY-MM') th, max(ngay) ngay, sum(tien) thu, sum(cuc) cuc from pay group by 1, 2),
             -- hoá đơn đi trong kỳ, tiền đã cọc đủ nên không có tiền về thêm: vẫn cần dòng để tính đóng / giao
             k as (select h.id hd, to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, 0::numeric thu, 0::numeric cuc
                     from kt_kiot_hoa_don h where h.trang_thai in (1, 3) and h.tong > 0 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
                      and (h.dat_hang_id is not null or nullif(h.ma_dat_hang, '') is not null or exists (select 1 from pre where pre.hd = h.id))
                      and not exists (select 1 from g where g.hd = h.id and g.th = to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM'))),
             r as (select * from g union all select * from k)
        select h.id * 100 + substr(r.th, 6)::int id, h.ma, r.ngay, r.th, h.chi_nhanh cn,
               coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)') nv, h.khach_ten khach, h.tong, 0::numeric tra, r.thu, r.cuc,
               case when h.ghi_chu ~ '(đóng hàng|giao hàng|ĐH|GH)' then regexp_replace(h.ghi_chu, '\s+', ' ', 'g') end gc,
               (select jsonb_object_agg(q.nh, q.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x group by 1) q) nh, false la_tra,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x) sp, null::text ma_tra,
               not kt_kenh_off(coalesce(kh.ten, ko.ten), h.chi_nhanh) onl,
               case when r.th = to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') then coalesce(cd.tien, 0) + coalesce(pre.tien, 0) else 0 end coc,
               case when r.th < to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') then 0 else r.thu end + case when r.th = to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') then coalesce(cd.tien, 0) + coalesce(pre.tien, 0) else 0 end thu_dg,
               false la_coc, dg.ma ma_don, null::numeric gt_don, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay_hd, false la_phieu,
               case when r.th = to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') then nullif(coalesce(cd.ds, '[]'::jsonb) || coalesce(pre.ds, '[]'::jsonb), '[]'::jsonb) end coc_ds
          from r join kt_kiot_hoa_don h on h.id = r.hd and h.trang_thai in (1, 3)
          left join kt_kiot_kenh kh on kh.id = h.kenh_id
          left join lateral (select k2.ten from kt_kiot_dat_hang o2 join kt_kiot_kenh k2 on k2.id = o2.kenh_id where h.kenh_id is null and h.dat_hang_id = o2.id limit 1) ko on true
          left join lateral (select o3.ma from kt_kiot_dat_hang o3 where o3.id = h.dat_hang_id or (h.dat_hang_id is null and o3.ma = nullif(h.ma_dat_hang, '')) limit 1) dg on true
          left join cd on cd.dh = dg.ma
          left join pre on pre.hd = h.id
         where r.thu > 0 or coalesce(cd.tien, 0) > 0 or coalesce(pre.tien, 0) > 0
        union all
        -- trả hàng trong kỳ: trừ tiền hoàn ở tháng hoàn, người bán theo hoá đơn gốc
        select -t.id, coalesce(h.ma, '?'), (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM'),
               coalesce(h.chi_nhanh, t.chi_nhanh), coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)'), h.khach_ten, 0, t.tong_tra, -abs(coalesce(t.da_tra, 0)), 0, null,
               (select jsonb_object_agg(q.nh, q.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x group by 1) q), true,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x) sp, t.ma,
               h.id is not null and not kt_kenh_off(coalesce(kh.ten, ko.ten), h.chi_nhanh),
               0, -abs(coalesce(t.da_tra, 0)), false, null, null, null, false, null
          from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
          left join kt_kiot_kenh kh on kh.id = h.kenh_id
          left join lateral (select k2.ten from kt_kiot_dat_hang o2 join kt_kiot_kenh k2 on k2.id = o2.kenh_id where h.kenh_id is null and h.dat_hang_id = o2.id limit 1) ko on true
         where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
           and coalesce(t.da_tra, 0) <> 0
        union all
        -- phiếu cọc TTDH trong kỳ (đơn chưa huỷ): người bán / cơ sở / kênh theo đơn đặt; nhóm hàng theo hoá đơn của đơn
        select 9000000000000 + q.id, q.ma, (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date, to_char((q.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM'),
               o.chi_nhanh, coalesce(nullif(trim(o.nv_ban), ''), '(không ghi)'), o.khach_ten, 0, 0, q.so_tien, 0, null,
               (select jsonb_object_agg(x2.nh, x2.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(hx.chi_tiet, '[]'::jsonb)) x group by 1) x2), false,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(hx.chi_tiet, '[]'::jsonb)) x), null,
               not kt_kenh_off(k3.ten, o.chi_nhanh), 0, 0, true, o.ma, o.tong, null, false, null
          from kt_kiot_so_quy q
          join kt_kiot_dat_hang o on o.ma = regexp_replace(substr(q.ma, 3), '-[0-9]+$', '') and o.trang_thai is distinct from 4
          left join kt_kiot_kenh k3 on k3.id = o.kenh_id
          left join lateral (select h3.chi_tiet from kt_kiot_hoa_don h3 where (h3.dat_hang_id = o.id or h3.ma_dat_hang = o.ma) and h3.trang_thai in (1, 3) limit 1) hx on true
         where q.ma like 'TTDH%' and q.la_thu and q.trang_thai = '0' and (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
        union all
        -- 02/11 anh "tiền về thì tính hết": phiếu thu không tìm được hoá đơn 2026 (hoá đơn trước 2026, trả trước) — người bán + nhóm hàng theo hoá đơn gần nhất của khách
        select 8000000000000 + q.id, q.ma, c.ngay, to_char(c.ngay, 'YYYY-MM'), q.chi_nhanh, coalesce(nullif(trim(l.nv_ban), ''), '(không ghi)'), q.doi_tac, 0, 0, c.thu, c.thu, null,
               (select jsonb_object_agg(x2.nh, x2.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(l.chi_tiet, '[]'::jsonb)) x group by 1) x2), false, null, null,
               l.id is not null and not kt_kenh_off(k4.ten, l.chi_nhanh), 0, 0, false, null, null, null, true, null
          from cuc2 c join kt_kiot_so_quy q on q.ma = c.ma
          left join lateral (select h4.id, h4.nv_ban, h4.chi_tiet, h4.chi_nhanh, h4.kenh_id from kt_kiot_hoa_don h4
                  where h4.khach_id::text = q.goc->>'partnerId' and h4.trang_thai in (1, 3) and h4.tong > 0 order by h4.ngay desc limit 1) l on true
          left join kt_kiot_kenh k4 on k4.id = l.kenh_id
         where c.hoa_don_id is null and c.ngay between p_tu and p_den) z),
    'cau_hinh', (select gia_tri::jsonb from kt_cai_dat where khoa = 'hh_cau_hinh'),
    'sua', (select jsonb_build_object('luc', sua_luc) from kt_cai_dat where khoa = 'hh_cau_hinh'));
end $function$;
