-- 21/11/2026 — SOÁT KẾT QUẢ THẬT của mọi lịch gọi Edge Function (anh: "rà lại hết tránh mấy lỗi lịch chạy dạng này"). Monsieur Claude
-- Bệnh chung: lịch pg_cron gọi Edge bằng net.http_post → cron.job_run_details chỉ biết "đã GỬI lệnh" (luôn succeeded); Edge bị cắt 504 / 500 / 520,
-- hay trả lỗi mà không tự ghi nhật ký thì không ai biết. Rà 5 ngày (16–21/11) thấy: kéo thu hoá đơn Kiot 504 mỗi đêm (VIEC 407), kt-sao-ke 500 từ 19/11
-- ("maTT is not defined"), kéo Kiot 15 phút 4 lần 500 / 520 ban đêm không để lại dòng nào, đối chiếu Kiot 23:50 chạy 102–129 / 150 giây.
-- Sửa chung:
--   kt_lich_goi      : mỗi lần lịch gọi Edge ghi 1 dòng (lịch, mã yêu cầu pg_net, lúc gọi) → kt_lich_soat điền kết quả thật.
--   kt_goi_edge(...) : lịch gọi Edge qua hàm này (thay net.http_post trực tiếp). Khoá x-kt-cron vẫn nằm trong lệnh lịch, KHÔNG lưu vào bảng.
--   kt_lich_soat()   : lịch kt-lich-soat phút 08 và 38 — đọc net._http_response (pg_net chỉ giữ ~6 tiếng): mã ≠ 2xx, quá giờ, lỗi mạng, Edge trả "loi",
--                      hoặc quá hạn mà không có phản hồi → ghi lỗi + chuông "Lịch … chạy lỗi" (1 lần / 12 tiếng / lịch). Lịch chạy SQL lỗi (cron failed) cũng báo.
--   kt_ds_lich       : trang Cài đặt → Log hệ thống → Lịch chạy trả thêm kết quả thật lần cuối + số lỗi 7 ngày theo kt_lich_goi.

create table if not exists public.kt_lich_goi (
  id bigserial primary key,
  lich text not null,
  req_id bigint,
  goi_luc timestamptz not null default now(),
  cho_ms int,
  xong boolean not null default false,
  tt int,                 -- mã HTTP trả về
  het_gio boolean,
  loi text,               -- null = chạy đúng
  kq text                 -- 300 ký tự đầu kết quả (để xem nhanh)
);
create index if not exists kt_lich_goi_lich on public.kt_lich_goi (lich, goi_luc desc);
create index if not exists kt_lich_goi_cho on public.kt_lich_goi (goi_luc) where not xong;
alter table public.kt_lich_goi enable row level security;
revoke all on public.kt_lich_goi from anon, authenticated;

create or replace function public.kt_goi_edge(p_lich text, p_ham text, p_body jsonb, p_khoa text, p_cho int default 150000) returns bigint
language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  v := net.http_post(url := 'https://bcrpxfvvjsjpvbksqzls.supabase.co/functions/v1/' || p_ham,
         headers := jsonb_build_object('Content-Type', 'application/json', 'x-kt-cron', p_khoa), body := p_body, timeout_milliseconds := p_cho);
  insert into kt_lich_goi (lich, req_id, cho_ms) values (p_lich, v, p_cho);
  return v;
end $$;
revoke all on function public.kt_goi_edge(text, text, jsonb, text, int) from public, anon, authenticated, service_role;

create or replace function public.kt_json_thu(p text) returns jsonb language plpgsql immutable as $$
begin return p::jsonb; exception when others then return null; end $$;

create or replace function public.kt_lich_soat() returns int
language plpgsql security definer set search_path = public as $$
declare v_ai int[] := kt_ai_co_quyen('nhat_ky', false, null); v_n int := 0; r record;
begin
  -- 1. điền kết quả thật từ pg_net
  update kt_lich_goi g set xong = true, tt = x.status_code, het_gio = coalesce(x.timed_out, false), kq = left(x.content, 300),
         loi = case when x.error_msg is not null then left(x.error_msg, 300)
                    when coalesce(x.timed_out, false) then 'Quá thời gian chờ ' || round(g.cho_ms / 1000.0) || ' giây'
                    when x.status_code is null or x.status_code not between 200 and 299
                      then 'Mã ' || coalesce(x.status_code::text, '?') || case x.status_code when 504 then ' (Edge chạy quá 150 giây, bị cắt)' when 546 then ' (Edge vượt giới hạn CPU / bộ nhớ)'
                                                                       when 520 then ' (Edge sập giữa chừng)' when 401 then ' (sai khoá)' else '' end
                           || coalesce(': ' || left(nullif(x.content, ''), 200), '')
                    when j.j ? 'loi' and coalesce(j.j->>'loi', '') not in ('', '[]', 'false', 'null') then 'Edge báo lỗi: ' || left(j.j->>'loi', 250)
                    when j.j->'thu_hd' ? 'thang_loi' then 'Edge báo lỗi: tháng ' || (j.j->'thu_hd'->>'thang_loi')
                    when jsonb_typeof(j.j->'so_quy'->'dong_bo') = 'string' then 'Chép phiếu thu Kiot lỗi: ' || left(j.j->'so_quy'->>'dong_bo', 200)
               end
    from net._http_response x left join lateral (select kt_json_thu(x.content) j) j on true
   where x.id = g.req_id and not g.xong;
  -- 2. quá hạn mà không có phản hồi (Edge không trả lời, hoặc pg_net đã xoá trước khi soát)
  update kt_lich_goi set xong = true, loi = 'Không nhận được phản hồi'
   where not xong and goi_luc < now() - make_interval(secs => coalesce(cho_ms, 150000) / 1000.0) - interval '20 minutes';
  -- 3. chuông: lịch Edge lỗi trong 2 tiếng qua + lịch SQL lỗi (cron failed) — cùng tiêu đề chỉ báo 1 lần / 12 tiếng
  for r in
    select 'Lịch ' || lich || ' chạy lỗi' td, count(*) || ' lần trong 2 tiếng, gần nhất ' || to_char(max(goi_luc) at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
             || ': ' || left((array_agg(loi order by goi_luc desc))[1], 200) nd
      from kt_lich_goi where xong and loi is not null and goi_luc > now() - interval '2 hours' group by lich
    union all
    select 'Lịch ' || j.jobname || ' chạy lỗi', count(*) || ' lần trong 2 tiếng, gần nhất ' || to_char(max(d.start_time) at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
             || ': ' || left((array_agg(d.return_message order by d.start_time desc))[1], 200)
      from cron.job_run_details d join cron.job j on j.jobid = d.jobid
     where j.jobname like 'kt-%' and d.status <> 'succeeded' and d.start_time > now() - interval '2 hours' and d.status not in ('running', 'starting')
     group by j.jobname
  loop
    if not exists (select 1 from kt_thong_bao t where t.loai = 'lich_loi' and t.tieu_de = r.td and t.tao_luc > now() - interval '12 hours') then
      perform kt_bao(v_ai, 'Hệ thống', 'lich_loi', r.td, r.nd, 'kt_lich', null);
      v_n := v_n + 1;
    end if;
  end loop;
  delete from kt_lich_goi where goi_luc < now() - interval '45 days';
  return v_n;
end $$;
revoke all on function public.kt_lich_soat() from public, anon, authenticated;

-- trang Lịch chạy: thêm kết quả thật (Edge) cho từng lịch
create or replace function public.kt_ds_lich(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $function$
begin
  perform kt_chan(p_phien, 'nhat_ky');
  return jsonb_build_object(
    'lich', (select coalesce(jsonb_agg(jsonb_build_object('ten', j.jobname, 'lich', j.schedule, 'bat', j.active,
               'cuoi', (select jsonb_build_object('luc', d.start_time, 'xong', d.end_time, 'tt', d.status, 'tb', left(d.return_message, 200))
                          from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1),
               'lan_7n', (select count(*) from cron.job_run_details d where d.jobid = j.jobid and d.start_time > now() - interval '7 day'),
               'loi_7n', (select count(*) from cron.job_run_details d where d.jobid = j.jobid and d.start_time > now() - interval '7 day' and d.status <> 'succeeded'),
               'edge', (select jsonb_build_object('luc', g.goi_luc, 'xong', g.xong, 'tt', g.tt, 'loi', g.loi)
                          from kt_lich_goi g where g.lich = j.jobname order by g.goi_luc desc limit 1),
               'edge_lan_7n', (select count(*) from kt_lich_goi g where g.lich = j.jobname and g.goi_luc > now() - interval '7 day'),
               'edge_loi_7n', (select count(*) from kt_lich_goi g where g.lich = j.jobname and g.loi is not null and g.goi_luc > now() - interval '7 day'),
               'edge_loi_cuoi', (select jsonb_build_object('luc', g.goi_luc, 'loi', g.loi) from kt_lich_goi g
                                  where g.lich = j.jobname and g.loi is not null and g.goi_luc > now() - interval '7 day' order by g.goi_luc desc limit 1))
             order by j.jobname), '[]') from cron.job j where j.jobname like 'kt-%'),
    'may', (select coalesce(jsonb_agg(jsonb_build_object('viec', hanh_dong, 'luc', m, 'lan_24h', n)), '[]') from
             (select hanh_dong, max(luc) m, count(*) filter (where luc > now() - interval '1 day') n from kt_nhat_ky
               where hanh_dong in ('dong_bo_sheet', 'nap_file_dong_tien') and luc > now() - interval '30 day' group by 1) x),
    'chay', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'luc', luc, 'nguoi', nguoi, 'viec', hanh_dong, 'kq', du_lieu) order by id desc), '[]')
               from (select * from kt_nhat_ky where hanh_dong in ('keo_kiot', 'keo_kiot_loi', 'doi_chieu_kiot', 'keo_thu_hd', 'chup_ton_kho', 'keo_meinvoice', 'keo_misabot', 'keo_misabot_loi',
                       'luu_luong', 'kiem_he_thong', 'dong_bo_sheet', 'nap_file_dong_tien') order by id desc limit 200) n));
end $function$;
revoke all on function public.kt_ds_lich(text) from public; grant execute on function public.kt_ds_lich(text) to anon;

-- ═══ Phần 2 (21/11, anh: "báo lịch chạy mỗi lần chuẩn hơn, có hệ thống rà lại các lần chạy lỗi để xử lý lần 2 lần 3") ═══
-- Mỗi lần gọi lưu thêm Edge + body (KHÔNG lưu khoá) → lần lỗi được tự chạy lại:
--   lần 2: ≥ 5 phút sau lần lỗi · lần 3: ≥ 20 phút sau lần 2 · hết 3 lần vẫn lỗi → chuông "Lịch … lỗi sau 3 lần".
--   KHÔNG chạy lại: mã 401 / 403 (sai khoá / quyền — chạy lại vẫn hỏng → báo ngay); lượt sau của chính lịch đó đã chạy đúng (vd kéo Kiot 15 phút);
--   lịch đó đang có lượt chưa xong (chờ xong rồi xét).
--   Lịch SQL (cron failed) cũng chạy lại tối đa 2 lần nữa, ghi vào kt_lich_goi (loai 'sql').
-- xu_ly: null (đúng) · 'chay_lai' (đã gọi lại, xem dòng lan + 1) · 'lan_sau_ok' · 'het_lan' · 'khong_chay_lai'.
alter table public.kt_lich_goi add column if not exists ham text, add column if not exists body jsonb, add column if not exists loai text not null default 'edge',
  add column if not exists lan int not null default 1, add column if not exists goc_id bigint, add column if not exists xu_ly text, add column if not exists ok_luc timestamptz;

drop function if exists public.kt_goi_edge(text, text, jsonb, text, int);
create or replace function public.kt_goi_edge(p_lich text, p_ham text, p_body jsonb, p_khoa text, p_cho int default 150000, p_lan int default 1, p_goc bigint default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  v := net.http_post(url := 'https://bcrpxfvvjsjpvbksqzls.supabase.co/functions/v1/' || p_ham,
         headers := jsonb_build_object('Content-Type', 'application/json', 'x-kt-cron', p_khoa), body := p_body, timeout_milliseconds := p_cho);
  insert into kt_lich_goi (lich, req_id, cho_ms, ham, body, lan, goc_id) values (p_lich, v, p_cho, p_ham, p_body, p_lan, p_goc);
  return v;
end $$;
revoke all on function public.kt_goi_edge(text, text, jsonb, text, int, int, int8) from public, anon, authenticated, service_role;

create or replace function public.kt_lich_soat() returns int
language plpgsql security definer set search_path = public as $$
declare v_ai int[] := kt_ai_co_quyen('nhat_ky', false, null); v_n int := 0; r record; v_khoa text; v_lenh text; v_id bigint;
begin
  -- 1. điền kết quả thật từ pg_net (giữ nguyên như phần 1)
  update kt_lich_goi g set xong = true, tt = x.status_code, het_gio = coalesce(x.timed_out, false), kq = left(x.content, 300),
         loi = case when x.error_msg is not null then left(x.error_msg, 300)
                    when coalesce(x.timed_out, false) then 'Quá thời gian chờ ' || round(g.cho_ms / 1000.0) || ' giây'
                    when x.status_code is null or x.status_code not between 200 and 299
                      then 'Mã ' || coalesce(x.status_code::text, '?') || case x.status_code when 504 then ' (Edge chạy quá 150 giây, bị cắt)' when 546 then ' (Edge vượt giới hạn CPU / bộ nhớ)'
                                                                       when 520 then ' (Edge sập giữa chừng)' when 401 then ' (sai khoá)' else '' end
                           || coalesce(': ' || left(nullif(x.content, ''), 200), '')
                    when j.j ? 'loi' and coalesce(j.j->>'loi', '') not in ('', '[]', 'false', 'null') then 'Edge báo lỗi: ' || left(j.j->>'loi', 250)
                    when j.j->'thu_hd' ? 'thang_loi' then 'Edge báo lỗi: tháng ' || (j.j->'thu_hd'->>'thang_loi')
                    when jsonb_typeof(j.j->'so_quy'->'dong_bo') = 'string' then 'Chép phiếu thu Kiot lỗi: ' || left(j.j->'so_quy'->>'dong_bo', 200)
               end
    from net._http_response x left join lateral (select kt_json_thu(x.content) j) j on true
   where x.id = g.req_id and not g.xong;
  update kt_lich_goi set xong = true, loi = 'Không nhận được phản hồi'
   where not xong and goi_luc < now() - make_interval(secs => coalesce(cho_ms, 150000) / 1000.0) - interval '20 minutes';
  update kt_lich_goi set ok_luc = now() where xong and loi is null and ok_luc is null;

  -- 2. lịch SQL lỗi (cron failed) → ghi 1 dòng để rà như lịch Edge (mỗi lần lỗi 1 dòng, không ghi trùng)
  insert into kt_lich_goi (lich, loai, goi_luc, xong, loi, body)
  select j.jobname, 'sql', d.start_time, true, left(coalesce(d.return_message, 'lỗi'), 300), jsonb_build_object('runid', d.runid)
    from cron.job_run_details d join cron.job j on j.jobid = d.jobid
   where j.jobname like 'kt-%' and d.status = 'failed' and d.start_time > now() - interval '3 hours'
     and not exists (select 1 from kt_lich_goi g where g.loai = 'sql' and g.body->>'runid' = d.runid::text);

  -- 3. rà các lần lỗi chưa xử lý → chạy lại / kết luận
  select coalesce(substring(command from 'x-kt-cron'', ''([0-9a-f]+)'''), substring(command from 'kt_goi_edge\(''kt-kiot'', ''kt-kiot'', ''\{\}''::jsonb, ''([0-9a-f]+)'''))
    into v_khoa from cron.job where jobname = 'kt-kiot';
  for r in select g.* from kt_lich_goi g where g.xong and g.loi is not null and g.xu_ly is null order by g.goi_luc loop
    if exists (select 1 from kt_lich_goi s where s.lich = r.lich and s.id <> r.id and s.lan = 1 and s.goi_luc > r.goi_luc and s.xong and s.loi is null) then
      update kt_lich_goi set xu_ly = 'lan_sau_ok' where id = r.id;   -- lượt định kỳ sau đã chạy đúng
    elsif r.tt in (401, 403) then
      update kt_lich_goi set xu_ly = 'khong_chay_lai' where id = r.id;
      perform kt_bao(v_ai, 'Hệ thống', 'lich_loi', 'Lịch ' || r.lich || ' bị từ chối', left(r.loi, 220) || ' — không tự chạy lại được, cần kiểm khoá / quyền', 'kt_lich', r.id);
      v_n := v_n + 1;
    elsif r.lan >= 3 then
      update kt_lich_goi set xu_ly = 'het_lan' where id = r.id;
      if not exists (select 1 from kt_thong_bao t where t.loai = 'lich_loi' and t.tieu_de = 'Lịch ' || r.lich || ' lỗi sau 3 lần' and t.tao_luc > now() - interval '12 hours') then
        perform kt_bao(v_ai, 'Hệ thống', 'lich_loi', 'Lịch ' || r.lich || ' lỗi sau 3 lần',
          'Lần 3 lúc ' || to_char(r.goi_luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ': ' || left(r.loi, 200), 'kt_lich', r.id);
        v_n := v_n + 1;
      end if;
    elsif exists (select 1 from kt_lich_goi s where s.lich = r.lich and not s.xong) then
      null;   -- lịch đang có lượt chạy → lần soát sau xét
    elsif r.goi_luc > now() - (case when r.lan = 1 then interval '5 minutes' else interval '20 minutes' end) then
      null;   -- chưa đủ giãn cách
    elsif r.loai = 'sql' then
      select command into v_lenh from cron.job where jobname = r.lich;
      begin
        execute v_lenh;
        insert into kt_lich_goi (lich, loai, xong, ok_luc, lan, goc_id, body) values (r.lich, 'sql', true, now(), r.lan + 1, coalesce(r.goc_id, r.id), r.body) returning id into v_id;
      exception when others then
        insert into kt_lich_goi (lich, loai, xong, loi, lan, goc_id, body) values (r.lich, 'sql', true, left(sqlerrm, 300), r.lan + 1, coalesce(r.goc_id, r.id), r.body) returning id into v_id;
      end;
      update kt_lich_goi set xu_ly = 'chay_lai' where id = r.id;
    elsif r.ham is not null and v_khoa is not null then
      perform kt_goi_edge(r.lich, r.ham, coalesce(r.body, '{}'::jsonb), v_khoa, coalesce(r.cho_ms, 170000), r.lan + 1, coalesce(r.goc_id, r.id));
      update kt_lich_goi set xu_ly = 'chay_lai' where id = r.id;
    else
      update kt_lich_goi set xu_ly = 'khong_chay_lai' where id = r.id;   -- dòng cũ không lưu Edge / body
    end if;
  end loop;
  delete from kt_lich_goi where goi_luc < now() - interval '45 days';
  return v_n;
end $$;
revoke all on function public.kt_lich_soat() from public, anon, authenticated;

-- trang Lịch chạy: thêm danh sách từng lần gọi 3 ngày (kèm lần thử, cách xử lý)
create or replace function public.kt_ds_lich_goi(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'nhat_ky');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'lich', lich, 'loai', loai, 'luc', goi_luc, 'xong', xong, 'tt', tt, 'loi', loi, 'lan', lan, 'goc', goc_id,
            'xu_ly', xu_ly, 'giay', (kt_json_thu(kq)->>'giay'), 'kq', left(kq, 160)) order by goi_luc desc), '[]')
            from (select * from kt_lich_goi where goi_luc > now() - interval '3 days' order by goi_luc desc limit 1500) x);
end $$;
revoke all on function public.kt_ds_lich_goi(text) from public; grant execute on function public.kt_ds_lich_goi(text) to anon;
