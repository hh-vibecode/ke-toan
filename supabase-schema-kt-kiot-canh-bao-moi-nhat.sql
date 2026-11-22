-- 10/11/2026: chuông "Doanh thu Tn lệch Kiot" chỉ xét lần so MỚI NHẤT của tháng (trước đây lấy lần so lệch cũ). Monsieur Claude
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
