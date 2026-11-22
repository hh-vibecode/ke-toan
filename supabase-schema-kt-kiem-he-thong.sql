-- TỰ KIỂM SUPABASE giữa tháng + cuối tháng (16/10/2026, anh Hải: "chủ động cảnh báo khi có vấn đề, tháng check 1–2 lần giữa tháng và cuối tháng") — Monsieur Claude
-- Project dùng chung 3 app, gói Pro (8 GB dữ liệu, 100 GB kho tệp, 250 GB băng thông / tháng — băng thông KHÔNG đo được từ SQL, xem Dashboard → Usage).
-- Job kt-kiem-he-thong: 09:00 ngày 15 và ngày cuối tháng → ghi nhật ký 'kiem_he_thong' (số đo) + chuông cho Supreme (luôn có tóm tắt; có cảnh báo thì ghi rõ).

-- khoá gọn 8 hàm phụ trợ không cần cho trình duyệt (chỉ dùng bên trong hàm security definer)
revoke execute on function public.kt_bo_dau(text), public.kt_diem_ten(text, text), public.kt_hkd_chi_nhanh(text), public.kt_nhom_cha(text),
  public.kt_ten_tt_chi(text), public.kt_tu_ten(text), public.kt_tg_chi_xem() from public, anon, authenticated;
do $$ begin execute 'revoke execute on function public.kt_chua_kiot(public.kt_chi) from public, anon, authenticated'; exception when others then null; end $$;

create or replace function public.kt_kiem_he_thong(p_ep boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ngay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; m jsonb; cb text[] := '{}'; v_truoc jsonb; v_keo timestamptz; v_ai int[];
  db_mb numeric; kt_mb numeric; kho_mb numeric; kho_tep int; nk_mb numeric; cron_mb numeric; cron_loi int; kiot_loi int; rls_tat int; anon_bang int;
begin
  -- chỉ chạy ngày 15 hoặc ngày cuối tháng (lịch gọi 15 và 28–31)
  if not p_ep and extract(day from v_ngay) <> 15 and extract(month from v_ngay + 1) = extract(month from v_ngay) then return null; end if;
  select pg_database_size(current_database()) / 1048576.0 into db_mb;
  select coalesce(sum(pg_total_relation_size(c.oid)), 0) / 1048576.0 into kt_mb from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'kt\_%';
  select count(*), coalesce(sum((metadata->>'size')::bigint), 0) / 1048576.0 into kho_tep, kho_mb from storage.objects where bucket_id = 'kt-chung-tu';
  select pg_total_relation_size('public.kt_nhat_ky') / 1048576.0 into nk_mb;
  select coalesce(sum(pg_total_relation_size(c.oid)), 0) / 1048576.0 into cron_mb from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'cron';
  select count(*) into cron_loi from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname like 'kt-%' and d.status <> 'succeeded' and d.start_time > now() - interval '15 days';
  select count(*) into kiot_loi from kt_nhat_ky where hanh_dong = 'keo_kiot_loi' and luc > now() - interval '15 days';
  select max(luc) into v_keo from kt_nhat_ky where hanh_dong = 'keo_kiot';
  select count(*) into rls_tat from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'kt\_%' and not c.relrowsecurity;
  select count(*) into anon_bang from information_schema.role_table_grants where grantee in ('anon','authenticated') and table_schema = 'public' and table_name like 'kt\_%';
  select du_lieu into v_truoc from kt_nhat_ky where hanh_dong = 'kiem_he_thong' order by id desc limit 1;
  m := jsonb_build_object('ngay', v_ngay, 'db_mb', round(db_mb), 'kt_mb', round(kt_mb), 'kho_mb', round(kho_mb), 'kho_tep', kho_tep, 'nhat_ky_mb', round(nk_mb, 1),
    'cron_mb', round(cron_mb, 1), 'cron_loi_15n', cron_loi, 'kiot_loi_15n', kiot_loi, 'keo_kiot_gan_nhat', v_keo, 'bang_tat_rls', rls_tat, 'anon_doc_bang', anon_bang);
  -- ngưỡng cảnh báo (gói Pro)
  if db_mb > 4096 then cb := cb || ('Dữ liệu cả project ' || round(db_mb) || ' MB — đã quá 50% gói 8 GB'); end if;
  if kho_mb > 51200 then cb := cb || ('Kho chứng từ ' || round(kho_mb / 1024, 1) || ' GB — đã quá 50% gói 100 GB'); end if;
  if v_truoc is not null and kho_mb - coalesce((v_truoc->>'kho_mb')::numeric, 0) > 5120 then cb := cb || ('Kho chứng từ tăng ' || round((kho_mb - (v_truoc->>'kho_mb')::numeric) / 1024, 1) || ' GB từ lần kiểm trước — xem có ai up tệp quá nặng'); end if;
  if v_truoc is not null and db_mb - coalesce((v_truoc->>'db_mb')::numeric, 0) > 1024 then cb := cb || ('Dữ liệu tăng ' || round(db_mb - (v_truoc->>'db_mb')::numeric) || ' MB từ lần kiểm trước'); end if;
  if nk_mb > 500 then cb := cb || ('Nhật ký chỉnh sửa ' || round(nk_mb) || ' MB — nên dọn bản cũ'); end if;
  if cron_mb > 200 then cb := cb || ('Bảng log lịch chạy (cron) ' || round(cron_mb) || ' MB — dùng chung 3 app, báo người quản trị'); end if;
  if cron_loi > 0 then cb := cb || (cron_loi || ' lần chạy lịch kt-* bị lỗi trong 15 ngày'); end if;
  if kiot_loi > 20 then cb := cb || (kiot_loi || ' lần kéo Kiot lỗi trong 15 ngày'); end if;
  if v_keo is null or v_keo < now() - interval '6 hours' then cb := cb || 'Kiot quá 6 giờ chưa kéo được'; end if;
  if rls_tat > 0 then cb := cb || (rls_tat || ' bảng kt_* đang TẮT khoá RLS — rủi ro lộ dữ liệu'); end if;
  if anon_bang > 0 then cb := cb || ('Khoá công khai đọc thẳng được ' || anon_bang || ' quyền trên bảng kt_* — rủi ro lộ dữ liệu'); end if;
  m := m || jsonb_build_object('canh_bao', to_jsonb(cb));
  perform kt_ghi_nhat_ky('Hệ thống', 'kt_he_thong', null, 'kiem_he_thong', m);
  v_ai := array(select id from kt_nguoi_dung where hoat_dong and vi_tri = 'supreme');
  perform kt_bao(v_ai, 'Hệ thống', 'he_thong',
    case when cardinality(cb) > 0 then 'Supabase: ' || cardinality(cb) || ' cảnh báo — cần xem' else 'Supabase ổn (kiểm định kỳ ' || to_char(v_ngay, 'DD/MM') || ')' end,
    case when cardinality(cb) > 0 then array_to_string(cb, ' · ') || ' | ' else '' end
      || 'Dữ liệu ' || round(db_mb) || ' MB (kế toán ' || round(kt_mb) || ' MB) · kho chứng từ ' || round(kho_mb / 1024, 2) || ' GB / ' || kho_tep || ' tệp · lịch lỗi 15 ngày: ' || cron_loi,
    null, null);
  return m;
end $$;
revoke all on function public.kt_kiem_he_thong(boolean) from public, anon, authenticated;

select cron.unschedule('kt-kiem-he-thong') where exists (select 1 from cron.job where jobname = 'kt-kiem-he-thong');
select cron.schedule('kt-kiem-he-thong', '0 2 15,28,29,30,31 * *', 'select public.kt_kiem_he_thong()');   -- 02:00 UTC = 09:00 giờ VN
