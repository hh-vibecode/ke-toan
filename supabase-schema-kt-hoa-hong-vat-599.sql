-- 05/11/2026 anh: "tất cả khoản thu nào vào tài khoản 599 công ty là phải trừ đi VAT hết" + "cái này là phần xử lý riêng".
-- kt_bc_hoa_hong_dl.hd thêm vat (trên tiền về tháng này) / vat_dg (thêm phần cọc / trả trước tính ở tháng hàng đi): phiếu Tiền khách trả vào TK VCB CTY 599
-- (Kiot 1316100, như kt_vat_599 của P&L) × tỷ lệ của chính hoá đơn: 8% + 2% × phần hàng đèn điện thờ / chuông mõ (= 10% cho 2 nhóm này). Trả hàng không đổi.
-- Trình duyệt trừ vat khỏi thực thu (mọi hoa hồng: sales, quỹ cửa hàng, đóng / giao, online) và ghi rõ dòng trừ. — Monsieur Claude
create or replace function public.kt_vat_tl(p_ct jsonb) returns numeric language sql immutable set search_path = public as $$
  select 0.08 + 0.02 * coalesce((select sum((i->>'tien')::numeric) filter (where i->>'nhom' in ('ĐÈN ĐIỆN THỜ', 'CHUÔNG MÕ / PHÁP KHÍ')) / nullif(sum((i->>'tien')::numeric), 0)
                                  from jsonb_array_elements(coalesce(p_ct, '[]'::jsonb)) i), 0)
$$;
revoke all on function public.kt_vat_tl(jsonb) from public, anon, authenticated;
create or replace function public.kt_bc_hoa_hong_dl(p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cuc jsonb;
begin
  
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
               'coc', round(coc), 'thu_dg', round(thu_dg), 'la_coc', la_coc, 'ma_don', ma_don, 'gt_don', round(gt_don), 'ngay_hd', ngay_hd, 'la_phieu', la_phieu, 'coc_ds', coc_ds, 'tra_ds', tra_ds, 'con', round(con), 'on_mkt', on_mkt, 'vat', round(vat), 'vat_dg', round(vat_dg)) order by ngay, id), '[]') from (
        with cd as materialized (select regexp_replace(substr(q.ma, 3), '-[0-9]+$', '') dh, sum(q.so_tien) tien,
                                         jsonb_agg(jsonb_build_object('ma', q.ma, 'ngay', (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'tien', round(q.so_tien)) order by q.ngay) ds from kt_kiot_so_quy q
                                  where q.ma like 'TTDH%' and q.la_thu and q.trang_thai = '0' group by 1),
             sq as materialized (select ma from kt_kiot_so_quy where la_thu and trang_thai = '0'),
             -- 05/11 anh: "tất cả khoản thu vào tài khoản 599 công ty phải trừ VAT" — cùng luật P&L (kt_vat_599): Tiền khách trả vào TK VCB CTY 599 (Kiot 1316100)
             t599 as materialized (select ma from kt_kiot_so_quy where la_thu and trang_thai = '0' and tai_khoan = '1316100' and nhom = 'Tiền khách trả'),
             -- 02/11 anh: "anh Chính HP là khách online" — khách online = khách từng có hoá đơn / đơn đặt kênh online trên Kiot
             kon as materialized (select khach_id from kt_khach_nguon),   -- 02/11: bảng nguồn khách chung (kênh Kiot + Pancake + app MKT)
             cuc2 as materialized (select * from kt_hd_thu_cuc2()),
             -- 02/11 anh "có cọc trước thì phải có trả nốt": mọi lần trả của hoá đơn (mọi ngày) để ghi phần trả nốt
             pall as materialized (select c.hoa_don_id hd, c.ma, c.ngay, c.thu tien from cuc2 c where c.hoa_don_id is not null
                       union all select t.id, x->>'ma', (x->>'ngay')::date, (x->>'tien')::numeric from kt_kiot_hd_thu t cross join lateral jsonb_array_elements(t.ds) x join sq on sq.ma = x->>'ma'
                        where coalesce(x->>'pt', '') <> 'Point' and x->>'ma' not like 'TTDH%'),
             -- 02/11: tiền khách trả TRƯỚC tháng hoá đơn (phiếu trả trước ghép hoá đơn sau) = cọc → đóng / giao tính ở tháng hàng đi
             pre as materialized (select z.hd, sum(z.tien) tien, jsonb_agg(jsonb_build_object('ma', z.ma, 'ngay', z.ngay, 'tien', round(z.tien)) order by z.ngay) ds from (
                       select c.hoa_don_id hd, c.ma, c.ngay, c.thu tien from cuc2 c where c.hoa_don_id is not null
                       union all select t.id, x->>'ma', (x->>'ngay')::date, (x->>'tien')::numeric from kt_kiot_hd_thu t cross join lateral jsonb_array_elements(t.ds) x join sq on sq.ma = x->>'ma'
                        where coalesce(x->>'pt', '') <> 'Point') z
                     join kt_kiot_hoa_don h on h.id = z.hd where to_char(z.ngay, 'YYYY-MM') < to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') group by 1),
             pay as (select t.id hd, (x->>'ngay')::date ngay, (x->>'tien')::numeric tien, 0::numeric cuc, case when x->>'ma' in (select ma from t599) then (x->>'tien')::numeric else 0 end t5
                       from kt_kiot_hd_thu t cross join lateral jsonb_array_elements(t.ds) x join sq on sq.ma = x->>'ma'
                      where (x->>'ngay')::date between p_tu and p_den and coalesce(x->>'pt', '') <> 'Point'
                     union all select c.hoa_don_id, c.ngay, c.thu, c.thu, case when c.ma in (select ma from t599) then c.thu else 0 end from cuc2 c where c.hoa_don_id is not null and c.ngay between p_tu and p_den),
             g as (select hd, to_char(ngay, 'YYYY-MM') th, max(ngay) ngay, sum(tien) thu, sum(cuc) cuc, sum(t5) t5 from pay group by 1, 2),
             -- hoá đơn đi trong kỳ, tiền đã cọc đủ nên không có tiền về thêm: vẫn cần dòng để tính đóng / giao
             k as (select h.id hd, to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, 0::numeric thu, 0::numeric cuc, 0::numeric t5
                     from kt_kiot_hoa_don h where h.trang_thai in (1, 3) and h.tong > 0 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
                      and (h.dat_hang_id is not null or nullif(h.ma_dat_hang, '') is not null or exists (select 1 from pre where pre.hd = h.id))
                      and not exists (select 1 from g where g.hd = h.id and g.th = to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM'))),
             r as (select * from g union all select * from k)
        select h.id * 100 + substr(r.th, 6)::int id, h.ma, r.ngay, r.th, h.chi_nhanh cn,
               coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)') nv, h.khach_ten khach, h.tong, 0::numeric tra, r.thu, r.cuc,
               case when h.ghi_chu ~ '(đóng hàng|giao hàng|ĐH|GH)' then trim(h.ghi_chu) end gc,
               (select jsonb_object_agg(q.nh, q.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x group by 1) q) nh, false la_tra,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x) sp, null::text ma_tra,
               (not kt_kenh_off(coalesce(kh.ten, ko.ten), h.chi_nhanh) or h.khach_ten ~* '(shopee|tiktok|lazada|tiki)' or h.khach_id in (select khach_id from kon)) onl,
               case when r.th = to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') then coalesce(cd.tien, 0) + coalesce(pre.tien, 0) else 0 end coc,
               case when r.th < to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') then 0 else r.thu end + case when r.th = to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') then coalesce(cd.tien, 0) + coalesce(pre.tien, 0) else 0 end thu_dg,
               false la_coc, dg.ma ma_don, null::numeric gt_don, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay_hd, false la_phieu,
               case when r.th = to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') then nullif(coalesce(cd.ds, '[]'::jsonb) || coalesce(pre.ds, '[]'::jsonb), '[]'::jsonb) end coc_ds,
               tn.ds tra_ds, case when tn.coc > 0 then greatest(h.tong - tn.coc - coalesce(tn.tien, 0) - coalesce(th.tra, 0), 0) end con,
               kt_hd_online(h.id, h.dat_hang_id) on_mkt,
               round(r.t5 * kt_vat_tl(h.chi_tiet)) vat,
               round(((case when r.th < to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') then 0 else r.t5 end)
                 + (case when r.th = to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') then (select coalesce(sum((e->>'tien')::numeric), 0) from jsonb_array_elements(coalesce(cd.ds, '[]'::jsonb) || coalesce(pre.ds, '[]'::jsonb)) e where e->>'ma' in (select ma from t599)) else 0 end))
                 * kt_vat_tl(h.chi_tiet)) vat_dg
          from r join kt_kiot_hoa_don h on h.id = r.hd and h.trang_thai in (1, 3)
          left join kt_kiot_kenh kh on kh.id = h.kenh_id
          left join lateral (select k2.ten from kt_kiot_dat_hang o2 join kt_kiot_kenh k2 on k2.id = o2.kenh_id where h.kenh_id is null and h.dat_hang_id = o2.id limit 1) ko on true
          left join lateral (select o3.ma from kt_kiot_dat_hang o3 where o3.id = h.dat_hang_id or (h.dat_hang_id is null and o3.ma = nullif(h.ma_dat_hang, '')) limit 1) dg on true
          left join cd on cd.dh = dg.ma
          left join pre on pre.hd = h.id
          left join lateral (select coalesce(cd.tien, 0) + coalesce(pre.tien, 0) coc, sum(p.tien) tien,
                                    jsonb_agg(jsonb_build_object('ma', p.ma, 'ngay', p.ngay, 'tien', round(p.tien)) order by p.ngay) filter (where p.hd is not null) ds
                               from (select 1) o left join pall p on p.hd = h.id and to_char(p.ngay, 'YYYY-MM') >= to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM')
                              where r.th = to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') and coalesce(cd.tien, 0) + coalesce(pre.tien, 0) > 0) tn on true
          left join lateral (select sum(greatest(t.tong_tra - abs(coalesce(t.da_tra, 0)), 0) + abs(coalesce(t.da_tra, 0))) tra from kt_kiot_tra_hang t
                              where t.hoa_don_id = h.id and coalesce(t.trang_thai, 1) = 1 and tn.coc > 0) th on true
         where r.thu > 0 or coalesce(cd.tien, 0) > 0 or coalesce(pre.tien, 0) > 0
        union all
        -- trả hàng trong kỳ: trừ tiền hoàn ở tháng hoàn, người bán theo hoá đơn gốc
        select -t.id, coalesce(h.ma, '?'), (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM'),
               coalesce(h.chi_nhanh, t.chi_nhanh), coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)'), h.khach_ten, 0, t.tong_tra, -abs(coalesce(t.da_tra, 0)), 0, null,
               (select jsonb_object_agg(q.nh, q.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x group by 1) q), true,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x) sp, t.ma,
               h.id is not null and (not kt_kenh_off(coalesce(kh.ten, ko.ten), h.chi_nhanh) or h.khach_ten ~* '(shopee|tiktok|lazada|tiki)' or h.khach_id in (select khach_id from kon)),
               0, -abs(coalesce(t.da_tra, 0)), false, null, null, null, false, null, null, null, h.id is not null and kt_hd_online(h.id, h.dat_hang_id), 0, 0
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
               (not kt_kenh_off(k3.ten, o.chi_nhanh) or o.khach_ten ~* '(shopee|tiktok|lazada|tiki)' or o.khach_id in (select khach_id from kon)), 0, 0, true, o.ma, o.tong, null, false, null, null, null, kt_hd_online(null, o.id),
               case when q.ma in (select ma from t599) then round(q.so_tien * kt_vat_tl(hx.chi_tiet)) else 0 end, 0
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
               (l.id is not null and not kt_kenh_off(k4.ten, l.chi_nhanh) or q.doi_tac ~* '(shopee|tiktok|lazada|tiki)' or (q.goc->>'partnerId') ~ '^[0-9]+$' and (q.goc->>'partnerId')::bigint in (select khach_id from kon)), 0, 0, false, null, null, null, true, null, null, null, l.id is not null and kt_hd_online(l.id, l.dat_hang_id),
               case when q.ma in (select ma from t599) then round(c.thu * kt_vat_tl(l.chi_tiet)) else 0 end, 0
          from cuc2 c join kt_kiot_so_quy q on q.ma = c.ma
          left join lateral (select h4.id, h4.nv_ban, h4.chi_tiet, h4.chi_nhanh, h4.kenh_id, h4.dat_hang_id from kt_kiot_hoa_don h4
                  where h4.khach_id::text = q.goc->>'partnerId' and h4.trang_thai in (1, 3) and h4.tong > 0 order by h4.ngay desc limit 1) l on true
          left join kt_kiot_kenh k4 on k4.id = l.kenh_id
         where c.hoa_don_id is null and c.ngay between p_tu and p_den) z),
    'dt_sale', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('thang', th, 'nv', nv, 'dt', round(dt), 'ma', ma, 'ngay', ngay, 'loai', loai, 'khach', khach,
          'kiot', kiot, 'dh', dh, 'th_dat', th_dat)) order by ngay, ma), '[]') from (
        with coc as materialized (select distinct regexp_replace(substr(q.ma, 3), '-[0-9]+$', '') dh from kt_kiot_so_quy q where q.ma like 'TTDH%' and q.la_thu and q.trang_thai = '0'),
             dc as materialized (select o.id, o.ma, o.ngay, o.nv_ban, o.tong from kt_kiot_dat_hang o
                                  where o.trang_thai is distinct from 4 and (coalesce(o.da_tra, 0) > 0 or o.ma in (select dh from coc))),
             hh as (select h.*, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date d,
                           (select dc.ma || '|' || to_char((dc.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') from dc
                             where dc.id = h.dat_hang_id or (h.dat_hang_id is null and dc.ma = nullif(h.ma_dat_hang, '')) order by dc.ngay limit 1) dcm
                      from kt_kiot_hoa_don h where h.trang_thai in (1, 3) and h.tong > 0 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
             x as (select to_char((o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, coalesce(nullif(trim(o.nv_ban), ''), '(không ghi)') nv, o.tong dt,
                          o.ma, (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, 'dat' loai, o.khach_ten khach, null::numeric kiot, null::text dh, null::text th_dat
                     from kt_kiot_dat_hang o join dc on dc.id = o.id where (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
                   union all
                   select to_char(h.d, 'YYYY-MM'), coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)'), case when h.dcm is null then h.tong else 0 end, h.ma, h.d,
                          case when h.dcm is null then 'hd' else 'hd_coc' end, h.khach_ten, h.tong, split_part(h.dcm, '|', 1), nullif(split_part(h.dcm, '|', 2), '')
                     from hh h
                   union all
                   select to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM'), coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)'), -t.tong_tra, t.ma, (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'tra', h.khach_ten,
                          null, h.ma, null
                     from kt_kiot_tra_hang t join kt_kiot_hoa_don h on h.id = t.hoa_don_id
                    where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den)
        select * from x) z),
    'cau_hinh', (select gia_tri::jsonb from kt_cai_dat where khoa = 'hh_cau_hinh'),
    'sua', (select jsonb_build_object('luc', sua_luc) from kt_cai_dat where khoa = 'hh_cau_hinh'));
end $function$;

-- 05/11/2026 anh: "bổ sung chính sách hoa hồng cho nhân sự Oanh Bùi" (QC-VH03-18-2026, Sales Admin / CSKH) + "ghi tên đầy đủ vào"
-- → người hưởng cs 'ht_ds' Bùi Thị Kim Oanh, phạm vi = team sỉ (người hưởng sales Nguyễn Trung Khánh Nguyên: đơn Nguyên + Oanh), áp từ T9/2026 (ngày ban hành 01/09/2026).
update kt_cai_dat set gia_tri = (gia_tri::jsonb || jsonb_build_object('nguoi', (gia_tri::jsonb->'nguoi')
    || '[{"cs": "ht_ds", "ten": "Bùi Thị Kim Oanh", "vt": "Sales Admin", "pv": ["Nguyễn Trung Khánh Nguyên"], "tu": "2026-09", "kiot": []}]'::jsonb))::text, sua_luc = now()
 where khoa = 'hh_cau_hinh' and not (gia_tri::jsonb->'nguoi' @> '[{"cs": "ht_ds", "ten": "Bùi Thị Kim Oanh"}]');
