-- 31/10/2026 tối anh: "sale đơn cọc là được tính rồi, miễn là khách cọc" + "tính là tính toàn bộ giá trị đơn ấy" (thay cách 'chỉ tính số tiền cọc' cùng ngày):
-- đơn có phiếu cọc TTDH → tháng cọc lần đầu tính CẢ giá trị đơn cho người bán của đơn; hoá đơn của đơn chỉ tính phần vượt giá trị đơn; đơn huỷ không tính.
-- Dòng cọc: 'thu' = giá trị đơn, 'coc' = tổng tiền cọc thật (để xem). Hoá đơn: 'coc' = giá trị đơn đã tính lúc cọc. — Monsieur Claude
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
               'thu', round(thu), 'cuc', round(cuc), 'gc', gc, 'nh', nh, 'la_tra', la_tra, 'sp', sp, 'ma_tra', ma_tra, 'on', onl,
               'coc', round(coc), 'thu_dg', round(thu_dg), 'la_coc', la_coc, 'ma_don', ma_don) order by ngay, id), '[]') from (
        -- 31/10 kế toán: tiền cọc đơn đặt (phiếu TTDH… = "TT" + mã đơn DH…, có thể đuôi -1 / .01) tính hoa hồng NGAY tháng nhận cọc;
        -- đơn thành hoá đơn chỉ tính phần nhận thêm (trừ cọc); đóng gói / giao hàng vẫn theo cả hoá đơn khi hàng đi (thu_dg)
        -- 31/10 tối anh: "sale đơn cọc là được tính rồi, miễn là khách cọc — tính là tính toàn bộ giá trị đơn ấy" → tháng nhận cọc ĐẦU TIÊN tính CẢ giá trị đơn;
        -- hoá đơn của đơn đó chỉ tính phần vượt giá trị đơn (thường 0) → không tính 2 lần
        with cd as materialized (select regexp_replace(substr(q.ma, 3), '[-.].*$', '') dh, sum(q.so_tien) tien, min(q.ngay) ngay_dau, (array_agg(q.id order by q.ngay, q.id))[1] qid,
                                        (array_agg(q.ma order by q.ngay, q.id))[1] ma_dau
                                   from kt_kiot_so_quy q where q.ma like 'TTDH%' and q.la_thu and q.trang_thai = '0' group by 1)
        select h.id, h.ma, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, h.chi_nhanh cn,
               coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)') nv, h.khach_ten khach, h.tong, coalesce(t.tra, 0) tra,
               greatest(least(greatest(coalesce(h.da_tra, 0), 0) + coalesce((v_cuc->>h.id::text)::numeric, 0), h.tong) - coalesce(t.hoan, 0) - case when cd.dh is not null then coalesce(dg.tong, 0) else 0 end, 0) thu,
               coalesce((v_cuc->>h.id::text)::numeric, 0) cuc,
               case when h.ghi_chu ~ '(đóng hàng|giao hàng|ĐH|GH)' then regexp_replace(h.ghi_chu, '\s+', ' ', 'g') end gc,
               (select jsonb_object_agg(q.nh, q.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x group by 1) q) nh, false la_tra,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x) sp, null::text ma_tra,
               not kt_kenh_off(coalesce(kh.ten, ko.ten), h.chi_nhanh) onl,
               case when cd.dh is not null then coalesce(dg.tong, 0) else 0 end coc, greatest(least(greatest(coalesce(h.da_tra, 0), 0) + coalesce((v_cuc->>h.id::text)::numeric, 0), h.tong) - coalesce(t.hoan, 0), 0) thu_dg,
               false la_coc, dg.ma ma_don
          from kt_kiot_hoa_don h
          left join kt_kiot_kenh kh on kh.id = h.kenh_id
          left join lateral (select k2.ten from kt_kiot_dat_hang o2 join kt_kiot_kenh k2 on k2.id = o2.kenh_id where h.kenh_id is null and h.dat_hang_id = o2.id limit 1) ko on true
          left join lateral (select o3.ma, o3.tong from kt_kiot_dat_hang o3 where o3.id = h.dat_hang_id or (h.dat_hang_id is null and o3.ma = nullif(h.ma_dat_hang, '')) limit 1) dg on true
          left join cd on cd.dh = dg.ma and exists (select 1 from kt_kiot_dat_hang o4 where o4.ma = dg.ma and o4.trang_thai is distinct from 4)
          left join lateral (select sum(t.tong_tra) tra, sum(greatest(coalesce(t.da_tra, 0), 0)) hoan from kt_kiot_tra_hang t
                 where t.hoa_don_id = h.id and coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den) t on true
         where h.trang_thai in (1, 3) and h.tong > 0 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
        union all
        select -t.id, coalesce(h.ma, '?'), (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM'),
               coalesce(h.chi_nhanh, t.chi_nhanh), coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)'), h.khach_ten, 0, t.tong_tra, -greatest(coalesce(t.da_tra, 0), 0), 0, null,
               (select jsonb_object_agg(q.nh, q.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x group by 1) q), true,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x) sp, t.ma,
               h.id is not null and not kt_kenh_off(coalesce(kh.ten, ko.ten), h.chi_nhanh),
               0, -greatest(coalesce(t.da_tra, 0), 0), false, null
          from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
          left join kt_kiot_kenh kh on kh.id = h.kenh_id
          left join lateral (select k2.ten from kt_kiot_dat_hang o2 join kt_kiot_kenh k2 on k2.id = o2.kenh_id where h.kenh_id is null and h.dat_hang_id = o2.id limit 1) ko on true
         where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
           and (h.id is null or (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date < p_tu)
        union all
        -- đơn được cọc lần đầu trong kỳ (đơn chưa huỷ): tính CẢ giá trị đơn; người bán / cơ sở / kênh theo đơn đặt; nhóm hàng theo hoá đơn của đơn (chưa có → chưa rõ nhóm)
        select 9000000000000 + c.qid, c.ma_dau, (c.ngay_dau at time zone 'Asia/Ho_Chi_Minh')::date, to_char((c.ngay_dau at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM'),
               o.chi_nhanh, coalesce(nullif(trim(o.nv_ban), ''), '(không ghi)'), o.khach_ten, 0, 0, o.tong, 0, null,
               (select jsonb_object_agg(x2.nh, x2.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(hx.chi_tiet, '[]'::jsonb)) x group by 1) x2), false,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(hx.chi_tiet, '[]'::jsonb)) x), null,
               not kt_kenh_off(k3.ten, o.chi_nhanh), c.tien, 0, true, o.ma
          from cd c
          join kt_kiot_dat_hang o on o.ma = c.dh and o.trang_thai is distinct from 4 and coalesce(o.tong, 0) > 0
          left join kt_kiot_kenh k3 on k3.id = o.kenh_id
          left join lateral (select h3.chi_tiet from kt_kiot_hoa_don h3 where (h3.dat_hang_id = o.id or h3.ma_dat_hang = o.ma) and h3.trang_thai in (1, 3) limit 1) hx on true
         where (c.ngay_dau at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den) z),
    'cau_hinh', (select gia_tri::jsonb from kt_cai_dat where khoa = 'hh_cau_hinh'),
    'sua', (select jsonb_build_object('luc', sua_luc) from kt_cai_dat where khoa = 'hh_cau_hinh'));
end $function$;
