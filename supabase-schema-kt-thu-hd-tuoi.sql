-- 21/11/2026 — Phiếu thu Kiot chia hoá đơn (kt_kiot_hd_thu) bị đứng từ đêm 18/11. Monsieur Claude
-- Kế toán (chị Jaycie) hỏi "gắn phiếu thu vào đúng đơn": TT012095 (KB Cô Hà Bói, 19/11, 600.000) Kiot đã chia vào HD060508 nhưng Đối soát lỗi
-- mục 7b vẫn báo "gắn thiếu" vì lịch kt-kiot-thu-hd-1/2/3 (00:45 · 00:50 · 00:55, mỗi lượt 3–4 tháng) ban đêm Kiot chậm → quá 150 giây,
-- Edge bị cắt 504 trước khi ghi nhật ký → im lặng. Sửa:
--   1. kt_thu_hd_can_keo(): lượt ban ngày (Edge thu_hd.tu_dong) chỉ kéo khi có phiếu thu cục mới sau lần kéo trước — trả các tháng cần kéo
--      (tháng này + tháng của hoá đơn còn nợ của chính khách đó, tối đa 4 tháng); không có → bỏ qua.
--   2. kt_canh_bao_kiot(): tháng nào quá 26 tiếng chưa kéo lại → chuông.
--   3. Lịch: 6 lượt đêm × 2 tháng + lượt ban ngày mỗi giờ (xem scripts/lich-thu-hd.js — khoá không nằm trong file).

create or replace function public.kt_thu_hd_can_keo() returns int[]
language sql stable security definer set search_path = public as $$
  with moc as (select coalesce(max(t.keo_luc), now() - interval '2 days') - interval '15 minutes' lan
                 from kt_kiot_hd_thu t join kt_kiot_hoa_don h on h.id = t.id
                where h.ngay >= date_trunc('month', now() at time zone 'Asia/Ho_Chi_Minh') at time zone 'Asia/Ho_Chi_Minh'),
       moi as (select distinct (q.goc->>'partnerId')::bigint kh from kt_kiot_so_quy q, moc
                where q.la_thu and q.trang_thai = '0' and q.nhom = 'Tiền khách trả' and q.ma !~ '^TT(HD|DH)'
                  and q.goc->>'partnerType' = 'C' and q.goc->>'partnerId' ~ '^[0-9]+$' and q.ngay >= moc.lan),
       thang as (select distinct (extract(year from age(date_trunc('month', now() at time zone 'Asia/Ho_Chi_Minh'), date_trunc('month', h.ngay at time zone 'Asia/Ho_Chi_Minh'))) * 12
                        + extract(month from age(date_trunc('month', now() at time zone 'Asia/Ho_Chi_Minh'), date_trunc('month', h.ngay at time zone 'Asia/Ho_Chi_Minh'))))::int lui
                   from kt_kiot_hoa_don h left join kt_kiot_hd_thu t on t.id = h.id
                  where h.khach_id in (select kh from moi) and h.trang_thai in (1, 3) and h.tong > 0
                    and h.tong - coalesce(t.tong_thu, greatest(coalesce(h.da_tra, 0), 0)) > 1
                    and h.ngay >= now() - interval '12 months')
  select case when exists (select 1 from moi) then (select array_agg(l order by l) from (select 0 l union select lui from thang where lui between 1 and 11 order by 1 limit 4) z) end
$$;
revoke all on function public.kt_thu_hd_can_keo() from public, anon, authenticated;
grant execute on function public.kt_thu_hd_can_keo() to service_role;

CREATE OR REPLACE FUNCTION public.kt_canh_bao_kiot()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ai int[] := kt_ai_co_quyen('nhat_ky', false, null); v_n int := 0; r record; v_tt text; v_nd text;
  v_cuoi kt_nhat_ky; v_ok timestamptz; v_dc timestamptz;
begin
  -- báo 1 lần / 12 tiếng cho cùng tiêu đề
  create temp table if not exists _kt_cb (loai text, tieu_de text, noi_dung text) on commit drop;
  delete from _kt_cb;
  select * into v_cuoi from kt_nhat_ky where hanh_dong in ('keo_kiot', 'keo_kiot_loi', 'doi_chieu_kiot') order by id desc limit 1;
  if v_cuoi.hanh_dong = 'keo_kiot_loi' then
    insert into _kt_cb values ('kiot_loi', 'Kéo Kiot bị lỗi', left(coalesce(v_cuoi.du_lieu->>'loi', ''), 200) || ' · lúc ' || to_char(v_cuoi.luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'));
  end if;
  select max(luc) into v_ok from kt_nhat_ky where hanh_dong = 'keo_kiot';
  if v_ok is null or v_ok < now() - interval '4 hours' then
    insert into _kt_cb values ('kiot_loi', 'Quá 4 tiếng chưa kéo được Kiot',
      'Lần kéo thành công gần nhất: ' || coalesce(to_char(v_ok at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), 'chưa có') || ' — số Kiot trên app đang cũ');
  end if;
  select max(luc) into v_dc from kt_kiot_doi_chieu where loai = 'thang';
  if v_dc is null or v_dc < now() - interval '26 hours' then
    insert into _kt_cb values ('kiot_loi', 'Lịch so khớp doanh thu Kiot không chạy', 'Lần so gần nhất: ' || coalesce(to_char(v_dc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), 'chưa có'));
  end if;
  -- 09/11 anh: thông báo "1 phiếu app có mà Kiot không còn ()" — ngoặc trống vì chỉ đọc hoá đơn, phiếu lệch là ĐƠN ĐẶT (DH002954, Kiot đã xoá).
  -- Nay ghi mã ở mọi nhóm (HĐ, trả hàng, đơn đặt, phiếu nhập, sổ quỹ) + tình trạng Kiot (đã xoá / đổi ngày) lần so ghi được; bấm thông báo mở bảng phiếu lệch.
  -- 10/11 anh (chuông T10 vẫn báo đơn báo giá DH002954): trước lọc so_lech > so_sua RỒI mới lấy lần mới nhất → lần so cũ (trước khi sửa) cứ bị báo lại
  -- dù lần so mới nhất đã khớp. Nay lấy lần so MỚI NHẤT của 2 tháng gần nhất trước, rồi mới xét còn lệch không. — Monsieur Claude
  for r in select * from (select distinct on (thang) * from kt_kiot_doi_chieu where loai = 'thang' order by thang desc, luc desc limit 2) z where z.so_lech > z.so_sua loop
    select string_agg(nh.ten || ' ' || e.x || coalesce(' (' || case k.tt when 'xoa' then 'Kiot đã xoá' when 'doi' then 'Kiot đổi sang ' || coalesce(k.ngay, 'tháng khác') end || ')', ''), ', ')
      into v_nd
      from (values ('hd', 'HĐ', 1), ('th', 'trả hàng', 2), ('dh', 'đơn đặt', 3), ('nh', 'phiếu nhập', 4), ('sq', 'sổ quỹ', 5)) nh(k, ten, tt)
      cross join lateral (select jsonb_array_elements_text(coalesce(r.ket_qua->nh.k->'thua', '[]')) x) e
      left join lateral (select z->>'tt' tt, z->>'ngay' ngay from jsonb_array_elements(coalesce(r.ket_qua->nh.k->'thua_kt', '[]')) z where z->>'ma' = e.x limit 1) k on true;
    insert into _kt_cb values ('kiot_lech', 'Doanh thu T' || ltrim(substr(r.thang, 6), '0') || '/' || substr(r.thang, 1, 4) || ' lệch Kiot',
      (r.so_lech - r.so_sua) || ' phiếu app có mà Kiot không còn trong tháng: ' || coalesce(left(v_nd, 300), 'xem chi tiết') || ' — bấm xem');
  end loop;
  -- 21/11/2026 (anh: "check lại phần gắn hoá đơn" — TT012095 Kiot đã chia vào HD060508 mà Đối soát vẫn báo gắn thiếu):
  -- bảng phiếu thu chia hoá đơn (kt_kiot_hd_thu, lịch kt-kiot-thu-hd-*) đứng từ 18/11 vì lượt đêm quá 150 giây → 504, KHÔNG ghi nhật ký → không ai biết.
  -- Nay tháng nào (12 tháng gần nhất) quá 26 tiếng chưa kéo lại được thì báo chuông. — Monsieur Claude
  select string_agg('T' || ltrim(substr(th, 6), '0'), ', ' order by th desc), min(lan) into v_nd, v_ok from (
    select to_char(h.ngay at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM') th, max(t.keo_luc) lan
      from kt_kiot_hd_thu t join kt_kiot_hoa_don h on h.id = t.id
     where h.ngay >= greatest('2026-01-01'::timestamptz, date_trunc('month', now() at time zone 'Asia/Ho_Chi_Minh') - interval '11 months')
     group by 1) z where lan < now() - interval '26 hours';
  if v_nd is not null then
    insert into _kt_cb values ('kiot_loi', 'Phiếu thu chia hoá đơn Kiot chưa cập nhật',
      'Tháng ' || v_nd || ' quá 26 tiếng chưa kéo lại (cũ nhất ' || to_char(v_ok at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ') — Đối soát "phiếu thu gắn thiếu" và hoa hồng có thể sai');
  end if;
  -- chỉ báo khi lần so tồn mới nhất (trước khi ghi đè) lệch đáng kể
  select luc, ket_qua into r from kt_kiot_doi_chieu where loai = 'ton' order by luc desc limit 1;
  if found then
    select abs(coalesce(sum((v->>'gt')::numeric), 0) - coalesce((select sum((a->>'gt')::numeric) from jsonb_each(r.ket_qua->'app') e(k, a)), 0))
             / nullif(sum((v->>'gt')::numeric), 0) into v_tt from jsonb_each(r.ket_qua->'kiot') e(k, v);
    if coalesce(v_tt::numeric, 0) > 0.01 or coalesce((r.ket_qua->>'dv_phu')::numeric, 0) > 0 then
      insert into _kt_cb values ('kiot_lech', 'Tồn kho app lệch Kiot ' || round(v_tt::numeric * 100, 1) || '%',
        'Lần so ' || to_char(r.luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ': ' || coalesce(r.ket_qua->>'so_dong_lech', '0') || ' dòng lệch (đã ghi đè theo Kiot) — xem nguyên nhân');
    end if;
  end if;
  for r in select * from _kt_cb c where not exists (select 1 from kt_thong_bao t where t.loai = c.loai and t.tieu_de = c.tieu_de and t.tao_luc > now() - interval '12 hours') loop
    perform kt_bao(v_ai, 'Hệ thống', r.loai, r.tieu_de, r.noi_dung, 'kt_kiot', null);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

-- 4. "Đã trả" của hoá đơn (kt_kiot_hoa_don.da_tra) chỉ lấy lúc kéo hoá đơn; khách trả sau thì Kiot không đổi ngày sửa → app giữ số cũ
--    (21/11: 116 hoá đơn thấp hơn Kiot 313,9 triệu, vd HD060508 ghi 0 dù TT012095 đã trả đủ). Sau mỗi lượt kéo phiếu thu chia hoá đơn,
--    ghi lại đã trả = tổng Kiot đã chia (chỉ khi lượt chia mới hơn lần kéo hoá đơn). Hoa hồng T10 / T11 thử trước–sau: không đổi.
create or replace function public.kt_thu_hd_dong_bo_da_tra() returns int
language sql security definer set search_path = public as $$
  with u as (update kt_kiot_hoa_don h set da_tra = t.tong_thu from kt_kiot_hd_thu t
              where t.id = h.id and abs(coalesce(h.da_tra, 0) - t.tong_thu) > 1 and t.keo_luc >= h.keo_luc returning 1)
  select count(*)::int from u
$$;
revoke all on function public.kt_thu_hd_dong_bo_da_tra() from public, anon, authenticated;
grant execute on function public.kt_thu_hd_dong_bo_da_tra() to service_role;
