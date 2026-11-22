-- ════════════════════════════════════════════════════════════════════════════
-- CẢNH BÁO KÉO / SO KHỚP KIOT VÀO CHUÔNG APP (14/10/2026)
-- Anh: "duy trì việc đối chiếu với Kiot, có vấn đề gì báo t luôn hoặc báo vào app" (chuông trong app — anh chốt 08/10 không đẩy về điện thoại).
-- kt_canh_bao_kiot(): gọi cuối mỗi lần chạy Edge Function kt-kiot + lịch pg_cron 'kt-kiot-canh-bao' mỗi giờ (bắt cả trường hợp hàm kéo không chạy được).
-- Báo người có quyền xem Nhật ký (Supreme / Admin có sẵn). Cùng 1 vấn đề chỉ báo lại sau 12 tiếng nếu vẫn còn.
--   1. Lần kéo Kiot gần nhất LỖI            (loai kiot_loi)
--   2. Quá 4 tiếng không có lần kéo thành công (kiot_loi)
--   3. Tháng soát còn lệch chưa tự bù được (app thừa phiếu Kiot không còn) — 2 tháng gần nhất (kiot_lech)
--   4. Tồn kho lần so gần nhất lệch > 1% giá trị hoặc còn cộng trùng đơn vị quy đổi (kiot_lech)
--   5. Lịch so khớp 23:50 không chạy quá 26 tiếng (kiot_loi)
-- Monsieur Claude
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.kt_canh_bao_kiot() returns int
language plpgsql security definer set search_path = public as $$
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
  for r in select distinct on (thang) * from kt_kiot_doi_chieu where loai = 'thang' and so_lech > so_sua order by thang desc, luc desc limit 2 loop
    insert into _kt_cb values ('kiot_lech', 'Doanh thu T' || ltrim(substr(r.thang, 6), '0') || '/' || substr(r.thang, 1, 4) || ' lệch Kiot',
      (r.so_lech - r.so_sua) || ' phiếu app có mà Kiot không còn trong tháng (' ||
      coalesce((select string_agg(x, ', ') from (select jsonb_array_elements_text(r.ket_qua->'hd'->'thua') x limit 5) z), '') || ') — cần xem');
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
end $$;
revoke execute on function public.kt_canh_bao_kiot() from public, anon, authenticated;
grant execute on function public.kt_canh_bao_kiot() to service_role;
-- lịch: phút 5 mỗi giờ
select cron.unschedule('kt-kiot-canh-bao') where exists (select 1 from cron.job where jobname = 'kt-kiot-canh-bao');
select cron.schedule('kt-kiot-canh-bao', '5 * * * *', $c$select public.kt_canh_bao_kiot()$c$);
