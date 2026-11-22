-- HOA HỒNG: THỰC THU THEO SỔ QUỸ (29/10/2026, kế toán: "thực thu đang lấy theo từng hoá đơn, hơi sai — các bạn thu tiền không đánh từng hoá đơn mà thu cả cục gắn với khách;
-- phải lấy thêm dữ liệu sổ quỹ, khớp mã hoá đơn"). Monsieur Claude
-- • Phiếu thu sổ quỹ Kiot "Tiền khách trả" mã TTHD… = thu theo hoá đơn (đã nằm trong "đã trả" của hoá đơn); mã TT0… = thu cục cho khách (partnerId = mã khách), hoá đơn không ghi nhận.
-- • kt_hd_thu_cuc(): phân bổ từng phiếu thu cục (theo ngày) vào hoá đơn còn nợ của chính khách đó, hoá đơn cũ trước, chỉ hoá đơn có ngày ≤ ngày thu (+1 ngày lệch giờ);
--   còn nợ hoá đơn = tổng − đã trả − hàng trả không hoàn tiền. Thu thừa (trả trước / nợ trước khi có dữ liệu) bỏ qua.
-- • kt_bc_hoa_hong: thực thu = min(đã trả + phần thu cục, tổng) − tiền hoàn; hd trả thêm 'cuc' (phần thu cục) để xem trong popup.
create or replace function public.kt_hd_thu_cuc() returns table (hoa_don_id bigint, thu numeric) language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
-- 29/10 (nhanh): 1 lượt duyệt theo khách → thời gian: hoá đơn vào hàng đợi (còn nợ), phiếu thu cục trả dần hoá đơn cũ nhất còn nợ (phiếu thu xếp sau hoá đơn cùng ngày + 1 ngày lệch giờ)
declare r record; v_kh bigint := null; ids bigint[] := '{}'; cons numeric[] := '{}'; thus numeric[] := '{}'; p int := 1; i int; con numeric; a numeric;
begin
  for r in
    with q as (select (q.goc->>'partnerId')::bigint kh, q.ngay + interval '1 day' ngay, q.so_tien from kt_kiot_so_quy q
                where q.la_thu and q.trang_thai = '0' and q.nhom = 'Tiền khách trả' and q.ma !~ '^TTHD' and q.goc->>'partnerType' = 'C' and q.goc->>'partnerId' ~ '^[0-9]+$'),
         tr as (select t.hoa_don_id, sum(greatest(t.tong_tra - greatest(coalesce(t.da_tra, 0), 0), 0)) tra from kt_kiot_tra_hang t where coalesce(t.trang_thai, 1) = 1 and t.hoa_don_id is not null group by 1),
         h as (select h.khach_id kh, h.ngay, h.id, greatest(h.tong - least(greatest(coalesce(h.da_tra, 0), 0), h.tong) - coalesce(tr.tra, 0), 0) con
                 from kt_kiot_hoa_don h left join tr on tr.hoa_don_id = h.id
                where h.trang_thai in (1, 3) and h.tong > 0 and h.khach_id in (select distinct kh from q))
    select kh, ngay, 0 loai, id, con tien from h
    union all select kh, ngay, 1, null, so_tien from q
    order by 1, 2, 3, 4
  loop
    if v_kh is distinct from r.kh then
      for i in 1..coalesce(array_length(ids, 1), 0) loop if thus[i] > 0 then hoa_don_id := ids[i]; thu := thus[i]; return next; end if; end loop;
      v_kh := r.kh; ids := '{}'; cons := '{}'; thus := '{}'; p := 1;
    end if;
    if r.loai = 0 then ids := ids || r.id; cons := cons || r.tien; thus := thus || 0::numeric;
    else
      con := r.tien; i := p;
      while con > 0 and i <= coalesce(array_length(ids, 1), 0) loop
        a := least(cons[i], con);
        if a > 0 then cons[i] := cons[i] - a; thus[i] := thus[i] + a; con := con - a; end if;
        if cons[i] <= 0 then p := i + 1; end if;
        i := i + 1;
      end loop;
    end if;
  end loop;
  for i in 1..coalesce(array_length(ids, 1), 0) loop if thus[i] > 0 then hoa_don_id := ids[i]; thu := thus[i]; return next; end if; end loop;
end $$;
revoke all on function public.kt_hd_thu_cuc() from public, anon, authenticated;

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
    'hd', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ma', ma, 'ngay', ngay, 'thang', th, 'cn', cn, 'nv', nv, 'khach', khach, 'tong', round(tong), 'tra', round(tra),
               'thu', round(thu), 'cuc', round(cuc), 'gc', gc, 'nh', nh, 'la_tra', la_tra, 'sp', sp, 'ma_tra', ma_tra) order by ngay, id), '[]') from (
        select h.id, h.ma, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, h.chi_nhanh cn,
               coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)') nv, h.khach_ten khach, h.tong, coalesce(t.tra, 0) tra,
               greatest(least(greatest(coalesce(h.da_tra, 0), 0) + coalesce((v_cuc->>h.id::text)::numeric, 0), h.tong) - coalesce(t.hoan, 0), 0) thu,
               coalesce((v_cuc->>h.id::text)::numeric, 0) cuc,
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
               coalesce(h.chi_nhanh, t.chi_nhanh), coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)'), h.khach_ten, 0, t.tong_tra, -greatest(coalesce(t.da_tra, 0), 0), 0, null,
               (select jsonb_object_agg(q.nh, q.tien) from (select kt_nhom_cha(coalesce(x->>'nhom', '(không nhóm)')) nh, sum(greatest(coalesce((x->>'tien')::numeric, 0), 0)) tien
                  from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x group by 1) q), true,
               (select string_agg(coalesce(nullif(x->>'ten', ''), x->>'sp', '?') || ' ×' || coalesce(x->>'sl', '1'), ' · ') from jsonb_array_elements(coalesce(h.chi_tiet, '[]'::jsonb)) x) sp, t.ma
          from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
         where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
           and (h.id is null or (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date < p_tu)) z),
    'cau_hinh', (select gia_tri::jsonb from kt_cai_dat where khoa = 'hh_cau_hinh'),
    'sua', (select jsonb_build_object('luc', sua_luc) from kt_cai_dat where khoa = 'hh_cau_hinh'));
end $function$;
