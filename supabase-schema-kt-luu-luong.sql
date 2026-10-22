-- 22/10/2026 (anh): Cài đặt → nhóm "Log": thêm "Log lưu lượng" — cuối mỗi ngày kéo dung lượng / lượt dùng Supabase (mọi thứ trang Usage lấy được qua API)
-- + thông tin máy chủ đang thuê, để anh kiểm soát trước khi hết dung lượng; "Log lịch chạy" = các lịch định kỳ (chuyển từ cuối Nhật ký so khớp). — Monsieur Claude
-- Edge Function kt-luu-luong (lịch kt-luu-luong 23:55 VN) gọi API quản trị (secret KT_SB_PAT) rồi rpc kt_ghi_luu_luong(p_api) — phần đo trong CSDL do hàm này tự đo.

create table if not exists kt_luu_luong (ngay date primary key, luc timestamptz not null default now(), du_lieu jsonb not null);
alter table kt_luu_luong enable row level security; revoke all on kt_luu_luong from anon, authenticated;
drop trigger if exists kt_chi_xem on kt_luu_luong;
create trigger kt_chi_xem before insert or delete or update on kt_luu_luong for each row execute function kt_tg_chi_xem();

-- đo trong CSDL (không cần API): dung lượng CSDL cả project / riêng kt_, kho tệp theo bucket, kết nối, lịch chạy 24 giờ, bảng kt_ lớn nhất
create or replace function public.kt_do_luu_luong() returns jsonb language sql stable security definer set search_path = public as $f$
  select jsonb_build_object(
    'db_bytes', pg_database_size(current_database()),
    'kt_bytes', (select coalesce(sum(pg_total_relation_size(c.oid)), 0) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relkind in ('r', 'm') and c.relname like 'kt\_%'),
    'kho', (select coalesce(jsonb_object_agg(bucket_id, jsonb_build_object('tep', n, 'bytes', b)), '{}') from
             (select bucket_id, count(*) n, coalesce(sum((metadata->>'size')::bigint), 0) b from storage.objects group by 1) s),
    'ket_noi', (select count(*) from pg_stat_activity),
    'lich_24h', (select jsonb_build_object('lan', count(*), 'loi', count(*) filter (where d.status <> 'succeeded'),
                   'loi_kt', count(*) filter (where d.status <> 'succeeded' and j.jobname like 'kt-%'))
                  from cron.job_run_details d left join cron.job j on j.jobid = d.jobid where d.start_time > now() - interval '1 day'),
    'bang_lon', (select coalesce(jsonb_agg(jsonb_build_object('ten', relname, 'bytes', b, 'dong', greatest(reltuples, 0)::bigint) order by b desc), '[]') from
                  (select c.relname, c.reltuples, pg_total_relation_size(c.oid) b from pg_class c join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'kt\_%' order by 3 desc limit 8) t)) $f$;
revoke all on function public.kt_do_luu_luong() from public, anon, authenticated;

-- ghi 1 dòng / ngày (giờ VN), gộp số API + số đo; cảnh báo vượt ngưỡng → chuông Supreme / Admin hệ thống
create or replace function public.kt_ghi_luu_luong(p_api jsonb) returns jsonb language plpgsql security definer set search_path = public as $f$
declare d jsonb := kt_do_luu_luong() || jsonb_build_object('api', coalesce(p_api, '{}'::jsonb)); cb text[] := '{}'; v_ngay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_kho bigint; v_dia numeric; v_dia_tong numeric;
begin
  -- ngưỡng gói Pro: CSDL 8 GB, kho tệp 100 GB (vượt tính thêm tiền); đĩa máy chủ tự nới nhưng > 90% là sắp nới
  v_kho := (select coalesce(sum((value->>'bytes')::bigint), 0) from jsonb_each(d->'kho'));
  if (d->>'db_bytes')::bigint > 0.8 * 8 * 1024^3 then cb := cb || ('CSDL ' || round((d->>'db_bytes')::numeric / 1024^3, 2) || ' GB / 8 GB'); end if;
  if v_kho > 0.8 * 100 * 1024^3 then cb := cb || ('Kho tệp ' || round(v_kho / 1024^3, 1) || ' GB / 100 GB'); end if;
  v_dia := (p_api #>> '{disk_util,fs_used_bytes}')::numeric; v_dia_tong := (p_api #>> '{disk_util,fs_size_bytes}')::numeric;
  if v_dia_tong > 0 and v_dia / v_dia_tong > 0.9 then cb := cb || ('Đĩa máy chủ ' || round(100 * v_dia / v_dia_tong) || '%'); end if;
  if (d #>> '{lich_24h,loi_kt}')::int > 0 then cb := cb || ((d #>> '{lich_24h,loi_kt}') || ' lần lịch kt- lỗi trong 24 giờ'); end if;
  if p_api ? 'loi' then cb := cb || ('Không gọi được API Supabase: ' || left(p_api->>'loi', 120)); end if;
  d := d || jsonb_build_object('canh_bao', to_jsonb(cb));
  insert into kt_luu_luong (ngay, luc, du_lieu) values (v_ngay, now(), d) on conflict (ngay) do update set luc = now(), du_lieu = excluded.du_lieu;
  perform kt_ghi_nhat_ky('Hệ thống', 'kt_luu_luong', null, 'luu_luong', jsonb_build_object('db_bytes', d->'db_bytes', 'kho_bytes', v_kho, 'canh_bao', to_jsonb(cb)));
  if cardinality(cb) > 0 then
    perform kt_bao(array(select id from kt_nguoi_dung where hoat_dong and vi_tri = 'supreme'), 'Hệ thống', 'he_thong',
      'Supabase: ' || cardinality(cb) || ' cảnh báo lưu lượng — cần xem', array_to_string(cb, ' · ') || ' | Cài đặt → Log lưu lượng');
  end if;
  return d;
end $f$;
revoke all on function public.kt_ghi_luu_luong(jsonb) from public, anon, authenticated; grant execute on function public.kt_ghi_luu_luong(jsonb) to service_role;

create or replace function public.kt_ds_luu_luong(p_phien text) returns jsonb language plpgsql security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'nhat_ky');
  return jsonb_build_object('nay', kt_do_luu_luong(),
    'ngay', (select coalesce(jsonb_agg(jsonb_build_object('ngay', ngay, 'luc', luc, 'd', du_lieu) order by ngay desc), '[]') from
              (select * from kt_luu_luong order by ngay desc limit 90) x));
end $f$;
revoke all on function public.kt_ds_luu_luong(text) from public; grant execute on function public.kt_ds_luu_luong(text) to anon;

-- Log lịch chạy: mọi lịch kt- + lần chạy cuối (cron.job_run_details) + việc chạy trên máy anh (đồng bộ sheet, file dòng tiền) + lịch sử kéo
create or replace function public.kt_ds_lich(p_phien text) returns jsonb language plpgsql security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'nhat_ky');
  return jsonb_build_object(
    'lich', (select coalesce(jsonb_agg(jsonb_build_object('ten', j.jobname, 'lich', j.schedule, 'bat', j.active,
               'cuoi', (select jsonb_build_object('luc', d.start_time, 'xong', d.end_time, 'tt', d.status, 'tb', left(d.return_message, 200))
                          from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1),
               'lan_7n', (select count(*) from cron.job_run_details d where d.jobid = j.jobid and d.start_time > now() - interval '7 day'),
               'loi_7n', (select count(*) from cron.job_run_details d where d.jobid = j.jobid and d.start_time > now() - interval '7 day' and d.status <> 'succeeded'))
             order by j.jobname), '[]') from cron.job j where j.jobname like 'kt-%'),
    'may', (select coalesce(jsonb_agg(jsonb_build_object('viec', hanh_dong, 'luc', m, 'lan_24h', n)), '[]') from
             (select hanh_dong, max(luc) m, count(*) filter (where luc > now() - interval '1 day') n from kt_nhat_ky
               where hanh_dong in ('dong_bo_sheet', 'nap_file_dong_tien') and luc > now() - interval '30 day' group by 1) x),
    'chay', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'luc', luc, 'nguoi', nguoi, 'viec', hanh_dong, 'kq', du_lieu) order by id desc), '[]')
               from (select * from kt_nhat_ky where hanh_dong in ('keo_kiot', 'keo_kiot_loi', 'doi_chieu_kiot', 'chup_ton_kho', 'keo_meinvoice', 'keo_misabot', 'keo_misabot_loi',
                       'luu_luong', 'kiem_he_thong', 'dong_bo_sheet', 'nap_file_dong_tien') order by id desc limit 200) n));
end $f$;
revoke all on function public.kt_ds_lich(text) from public; grant execute on function public.kt_ds_lich(text) to anon;
