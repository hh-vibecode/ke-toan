-- 26/10/2026 kế toán (anh chuyển): "có khoản không cần thanh toán (tiền thuê nhà…) nhưng vẫn phải tính vào chi phí hiệu quả hoạt động — hạch toán P&L thế nào?
-- Lương: ngày 10 tháng sau mới chi, nhưng đã nắm được khoảng bao nhiêu, muốn kê chi phí tạm để hằng tuần có số tạm theo dõi hiệu suất."
-- → CHI PHÍ TẠM TÍNH / TRÍCH TRƯỚC (kt_chi_tam_tinh): ghi chi phí vào P&L tháng X KHÔNG qua phiếu chi, KHÔNG trừ tiền tài khoản.
--   · kiểu 'cho_chi' (sẽ chi sau — lương, thưởng…): khi chi thật, bấm "Tất toán" chọn phiếu chi thật → phiếu chi đó ghi vào tháng của khoản tạm tính
--     (thang_ht), khoản tạm tính thôi tính → P&L tháng X = số thật, không cộng 2 lần.
--   · kiểu 'khong_chi' (không chi tiền — thuê nhà không trả tiền, chi phí phân bổ…): tính P&L luôn, không cần tất toán.
--   · "Lặp hằng tháng": ngày 1 hệ thống tự tạo khoản cùng nội dung / số tiền cho tháng mới (lịch kt-tam-tinh-lap).
-- Nối vào view kt_v_chi_ht (nguồn chung của P&L, chi phí theo cơ sở, báo cáo quản trị): dòng tạm tính có chi_id ÂM (= −id). — Monsieur Claude
create table if not exists kt_chi_tam_tinh (
  id bigserial primary key,
  thang text not null check (thang ~ '^20[0-9]{2}-(0[1-9]|1[0-2])$'),
  loai_id int not null references kt_loai(id), loai_con_id int references kt_loai(id),
  noi_dung text not null, so_tien numeric not null check (so_tien > 0),
  phan_bo jsonb not null default '[]',
  kieu text not null default 'cho_chi' check (kieu in ('cho_chi', 'khong_chi')),
  lap boolean not null default false, lap_tu_id bigint,
  tat_toan_chi_id bigint references kt_chi(id), tat_toan_boi text, tat_toan_luc timestamptz, tat_toan_thang_cu text,   -- tháng hạch toán cũ của phiếu chi (bỏ tất toán thì trả lại)
  ghi_chu text, da_xoa boolean not null default false,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz);
create unique index if not exists kt_chi_tam_tinh_lap on kt_chi_tam_tinh (lap_tu_id, thang) where lap_tu_id is not null and not da_xoa;
alter table kt_chi_tam_tinh add column if not exists tat_toan_thang_cu text;
alter table kt_chi_tam_tinh enable row level security;
revoke all on kt_chi_tam_tinh from anon, authenticated;

-- view chung: thêm dòng tạm tính chưa tất toán (giữ nguyên phần phiếu chi)
create or replace view public.kt_v_chi_ht as
 SELECT c.id AS chi_id,
    COALESCE(c.loai_con_id, c.loai_id) AS loai_id,
    COALESCE((pt.value ->> 'thang'::text), c.thang_ht, to_char((COALESCE(c.ngay_su_dung, c.ngay_de_nghi, c.ngay_tt))::timestamp with time zone, 'YYYY-MM'::text)) AS thang,
    ((pb.value ->> 'don_vi_id'::text))::integer AS don_vi_id,
    (COALESCE(((pt.value ->> 'so_tien'::text))::numeric, c.so_tien) * COALESCE((((pb.value ->> 'so_tien'::text))::numeric / NULLIF(c.so_tien, (0)::numeric)), (1)::numeric)) AS tien
   FROM ((kt_chi c
     LEFT JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN ((jsonb_typeof(c.phan_bo_thang) = 'array'::text) AND (jsonb_array_length(c.phan_bo_thang) > 0)) THEN c.phan_bo_thang
            ELSE NULL::jsonb
        END) pt(value) ON (true))
     LEFT JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN ((jsonb_typeof(c.phan_bo) = 'array'::text) AND (jsonb_array_length(c.phan_bo) > 0)) THEN c.phan_bo
            ELSE NULL::jsonb
        END) pb(value) ON (true))
  WHERE ((NOT c.da_xoa) AND (c.trang_thai = ANY (ARRAY['cho_tt'::text, 'da_tt'::text])) AND (NOT c.la_tam_ung) AND (NOT c.khong_hach_toan) AND (c.loai_dn = 'thanh_toan'::text))
 UNION ALL
 SELECT (- t.id) AS chi_id, COALESCE(t.loai_con_id, t.loai_id) AS loai_id, t.thang, ((pb.value ->> 'don_vi_id'::text))::integer AS don_vi_id,
    COALESCE(((pb.value ->> 'so_tien'::text))::numeric, t.so_tien) AS tien
   FROM kt_chi_tam_tinh t
     LEFT JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_array_length(t.phan_bo) > 0 THEN t.phan_bo ELSE NULL::jsonb END) pb(value) ON (true)
  WHERE (NOT t.da_xoa) AND t.tat_toan_chi_id IS NULL;

-- danh sách (trang Chi phí tạm tính) + phiếu chi có thể dùng để tất toán (cùng nhóm loại chi, chi trong 75 ngày sau tháng tạm tính)
create or replace function public.kt_ds_tam_tinh(p_phien text, p_tu text, p_den text) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'chi');
  return (select coalesce(jsonb_agg(to_jsonb(t) || jsonb_build_object('tat_toan_so', case when t.tat_toan_chi_id is not null then 'PC' || lpad(t.tat_toan_chi_id::text, 6, '0') end,
            'tat_toan_tien', (select so_tien from kt_chi where id = t.tat_toan_chi_id)) order by t.thang desc, t.id desc), '[]')
            from kt_chi_tam_tinh t where not t.da_xoa and t.thang between p_tu and p_den);
end $f$;

create or replace function public.kt_luu_tam_tinh(p_phien text, p jsonb) returns bigint
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung; v_id bigint := nullif(p->>'id', '')::bigint; pb jsonb := coalesce(p->'phan_bo', '[]'::jsonb);
begin
  u := kt_chan(p_phien, 'chi', true);
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Nhập số tiền'; end if;
  if nullif(p->>'loai_id', '') is null then raise exception 'Chọn loại chi'; end if;
  if jsonb_array_length(pb) > 0 and abs((select sum((x->>'so_tien')::numeric) from jsonb_array_elements(pb) x) - (p->>'so_tien')::numeric) > 1 then
    raise exception 'Tổng phân bổ phải bằng số tiền'; end if;
  if v_id is null then
    insert into kt_chi_tam_tinh (thang, loai_id, loai_con_id, noi_dung, so_tien, phan_bo, kieu, lap, ghi_chu, tao_boi)
    values (p->>'thang', (p->>'loai_id')::int, nullif(p->>'loai_con_id', '')::int, trim(p->>'noi_dung'), (p->>'so_tien')::numeric, pb,
            coalesce(nullif(p->>'kieu', ''), 'cho_chi'), coalesce((p->>'lap')::boolean, false), nullif(p->>'ghi_chu', ''), u.ho_ten) returning id into v_id;
  else
    update kt_chi_tam_tinh set thang = p->>'thang', loai_id = (p->>'loai_id')::int, loai_con_id = nullif(p->>'loai_con_id', '')::int, noi_dung = trim(p->>'noi_dung'),
           so_tien = (p->>'so_tien')::numeric, phan_bo = pb, kieu = coalesce(nullif(p->>'kieu', ''), kieu), lap = coalesce((p->>'lap')::boolean, lap),
           ghi_chu = nullif(p->>'ghi_chu', ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa and tat_toan_chi_id is null;
    if not found then raise exception 'Khoản đã tất toán hoặc không còn — không sửa được'; end if;
  end if;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_chi_tam_tinh', case when p->>'id' is null then 'them' else 'sua' end, p || jsonb_build_object('id', v_id));
  return v_id;
end $f$;

create or replace function public.kt_xoa_tam_tinh(p_phien text, p_id bigint) returns void
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'chi', true);
  update kt_chi_tam_tinh set da_xoa = true, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_chi_tam_tinh', 'xoa', jsonb_build_object('id', p_id));
end $f$;

-- phiếu chi gợi ý tất toán: cùng loại chi gốc (hoặc cùng nhóm cha), đã duyệt (chờ chi / đã chi), chưa tất toán khoản khác, đề nghị / chi từ đầu tháng tạm tính → +75 ngày
create or replace function public.kt_tat_toan_goi_y(p_phien text, p_id bigint) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
declare t kt_chi_tam_tinh; cha int;
begin
  perform kt_chan(p_phien, 'chi');
  select * into t from kt_chi_tam_tinh where id = p_id;
  select coalesce(cha_id, id) into cha from kt_loai where id = t.loai_id;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'so', coalesce(c.kiot_ma, 'PC' || lpad(c.id::text, 6, '0')), 'nd', c.noi_dung, 'tien', c.so_tien,
            'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'tt', c.trang_thai) order by abs(c.so_tien - t.so_tien)), '[]')
   from kt_chi c join kt_loai l on l.id = c.loai_id
  where not c.da_xoa and c.trang_thai in ('cho_tt', 'da_tt') and not c.khong_hach_toan and coalesce(l.cha_id, l.id) = cha
    and coalesce(c.ngay_tt, c.ngay_de_nghi) between (t.thang || '-01')::date and (t.thang || '-01')::date + 75
    and not exists (select 1 from kt_chi_tam_tinh z where z.tat_toan_chi_id = c.id and not z.da_xoa)
  limit 30);
end $f$;

-- tất toán: phiếu chi thật ghi vào tháng của khoản tạm tính (thang_ht; phiếu chia nhiều tháng thì giữ), khoản tạm tính thôi tính. p_chi null = bỏ tất toán.
create or replace function public.kt_tat_toan_tam_tinh(p_phien text, p_id bigint, p_chi bigint) returns void
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung; t kt_chi_tam_tinh; cu text;
begin
  u := kt_chan(p_phien, 'chi', true);
  select * into t from kt_chi_tam_tinh where id = p_id and not da_xoa;
  if t.id is null then raise exception 'Không thấy khoản tạm tính'; end if;
  if t.kieu <> 'cho_chi' then raise exception 'Khoản không chi tiền không cần tất toán'; end if;
  -- bỏ / đổi tất toán: trả tháng hạch toán cũ cho phiếu chi trước đó
  if t.tat_toan_chi_id is not null then
    update kt_chi set thang_ht = t.tat_toan_thang_cu, sua_boi = u.ho_ten, sua_luc = now() where id = t.tat_toan_chi_id;
  end if;
  if p_chi is not null then
    if exists (select 1 from kt_chi_tam_tinh where tat_toan_chi_id = p_chi and id <> p_id and not da_xoa) then raise exception 'Phiếu chi này đã tất toán khoản khác'; end if;
    select thang_ht into cu from kt_chi where id = p_chi;
    update kt_chi set thang_ht = t.thang, sua_boi = u.ho_ten, sua_luc = now()
     where id = p_chi and not da_xoa and not coalesce(jsonb_typeof(phan_bo_thang) = 'array' and jsonb_array_length(phan_bo_thang) > 1, false);   -- coalesce: phan_bo_thang null → NULL làm điều kiện sai
  end if;
  update kt_chi_tam_tinh set tat_toan_thang_cu = cu, tat_toan_chi_id = p_chi, tat_toan_boi = case when p_chi is null then null else u.ho_ten end,
         tat_toan_luc = case when p_chi is null then null else now() end where id = p_id;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_chi_tam_tinh', case when p_chi is null then 'bo_tat_toan' else 'tat_toan' end,
    jsonb_build_object('id', p_id, 'chi_id', p_chi, 'thang', t.thang));
end $f$;

-- lặp hằng tháng (lịch kt-tam-tinh-lap chạy 00:10 giờ VN MỖI ĐÊM — cron UTC không đặt được "ngày 1 giờ VN"; hàm không tạo trùng): khoản lap của tháng trước → tạo khoản tháng này (giữ chuỗi bằng lap_tu_id = khoản gốc)
create or replace function public.kt_tam_tinh_lap(p_thang text default to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM')) returns int
  language plpgsql security definer set search_path = public as $f$
declare n int; truoc text := to_char((p_thang || '-01')::date - 1, 'YYYY-MM');
begin
  insert into kt_chi_tam_tinh (thang, loai_id, loai_con_id, noi_dung, so_tien, phan_bo, kieu, lap, lap_tu_id, ghi_chu, tao_boi)
  select p_thang, t.loai_id, t.loai_con_id, t.noi_dung, t.so_tien, t.phan_bo, t.kieu, true, coalesce(t.lap_tu_id, t.id), t.ghi_chu, 'Hệ thống (lặp hằng tháng)'
    from kt_chi_tam_tinh t where t.thang = truoc and t.lap and not t.da_xoa
     and not exists (select 1 from kt_chi_tam_tinh z where z.lap_tu_id = coalesce(t.lap_tu_id, t.id) and z.thang = p_thang and not z.da_xoa);
  get diagnostics n = row_count;
  if n > 0 then insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_chi_tam_tinh', 'lap_thang', jsonb_build_object('thang', p_thang, 'so', n)); end if;
  return n;
end $f$;
revoke all on function public.kt_tam_tinh_lap(text) from anon, authenticated, public;
select cron.unschedule('kt-tam-tinh-lap') where exists (select 1 from cron.job where jobname = 'kt-tam-tinh-lap');
select cron.schedule('kt-tam-tinh-lap', '10 17 * * *', $c$select public.kt_tam_tinh_lap()$c$);

-- P&L bấm ô xem phiếu: thêm dòng tạm tính (số "TT…", trạng thái 'tam_tinh')
create or replace function public.kt_pl_ct(p_phien text, p_loai integer[], p_tu date, p_den date) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
declare v_t0 text := to_char(p_tu, 'YYYY-MM'); v_t1 text := to_char(p_den, 'YYYY-MM');
begin
  perform kt_chan(p_phien, 'pl');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ngay', ngay, 'so', so, 'nd', noi_dung, 'th', thu_huong_ten, 'loai', loai_id,
           'dv', dv, 'tien', tien, 'thang', thang, 'tt', trang_thai) order by ngay desc nulls last, id desc), '[]') from (
    select c.id, coalesce(c.ngay_tt, c.ngay_de_nghi) ngay, coalesce(c.kiot_ma, 'PC' || lpad(c.id::text, 6, '0')) so, c.noi_dung, c.thu_huong_ten, h.loai_id,
           h.don_vi_id dv, h.thang, c.trang_thai, round(sum(h.tien)) tien
      from kt_v_chi_ht h join kt_chi c on c.id = h.chi_id
     where h.chi_id > 0 and h.loai_id = any(p_loai) and h.thang between v_t0 and v_t1
     group by 1, 2, 3, 4, 5, 6, 7, 8, 9
    union all
    select h.chi_id, (t.thang || '-01')::date, 'TT' || lpad(t.id::text, 6, '0'), '[Tạm tính] ' || t.noi_dung, null, h.loai_id, h.don_vi_id, h.thang, 'tam_tinh', round(sum(h.tien))
      from kt_v_chi_ht h join kt_chi_tam_tinh t on t.id = -h.chi_id
     where h.chi_id < 0 and h.loai_id = any(p_loai) and h.thang between v_t0 and v_t1
     group by 1, 2, 3, 4, 5, 6, 7, 8, 9 limit 3000) x);
end $f$;
