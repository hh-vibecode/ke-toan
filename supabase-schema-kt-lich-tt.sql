-- 26/10/2026 (anh, file "LỊCH THANH TOÁN CÁC KHOẢN CỐ ĐỊNH THT.xlsx"): "bổ sung thêm nhắc lịch thanh toán tự động — xem ở chỗ nào cho hợp lý"
-- → trang Công nợ & Thanh toán → Lịch đến hạn trả: phần THANH TOÁN ĐỊNH KỲ (kt_lich_tt).
--  · mỗi khoản: chu kỳ (số tháng 1 / 3 / 6 / 12), khung hạn KỲ TỚI (han_tu – han_den), người nhận + STK + ngân hàng, số dự kiến (hoặc ghi "tra app")
--  · lịch kt-nhac-lich-tt 08:00 VN mỗi ngày: còn ≤ nhac_truoc ngày tới han_tu → chuông "sắp đến hạn"; qua han_den chưa trả → chuông "quá hạn"
--    (mỗi mốc 1 lần / kỳ); người nhận chuông: Supreme + quyền chi_duyet (kế toán)
--  · "✓ Đã thanh toán kỳ này" → lưu lần trả (kt_lich_tt_tra, có thể gắn phiếu chi) + dời han_tu / han_den sang kỳ sau
--  · KHÔNG lưu mật khẩu đăng nhập (file gốc có) — chỉ link / mã khách hàng. Dữ liệu 9 khoản: file local (có STK thật, repo công khai).
-- — Monsieur Claude
create table if not exists kt_lich_tt (
  id bigserial primary key, khoan text not null, co_so text, nguoi_nhan text,
  thu_huong_ten text, thu_huong_stk text, thu_huong_nh text, thong_tin text,
  chu_ky int not null default 1 check (chu_ky in (1, 2, 3, 6, 12)), han_tu date not null, han_den date not null,
  han_mo_ta text, so_tien numeric, so_tien_ghi text, nhac_truoc int not null default 3,
  ghi_chu text, da_nhac_sap date, da_nhac_qua date, da_xoa boolean not null default false,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz);
create table if not exists kt_lich_tt_tra (
  id bigserial primary key, lich_id bigint not null references kt_lich_tt(id), ky_tu date, ky_den date, ngay date not null default current_date,
  so_tien numeric, chi_id bigint references kt_chi(id), boi text, luc timestamptz not null default now());
alter table kt_lich_tt enable row level security; alter table kt_lich_tt_tra enable row level security;
revoke all on kt_lich_tt, kt_lich_tt_tra from anon, authenticated;

create or replace function public.kt_lich_tt_ds(p_phien text) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'sap_tra');
  return (select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('lan_cuoi', (select to_jsonb(t) from kt_lich_tt_tra t where t.lich_id = l.id order by t.id desc limit 1))
            order by l.han_tu, l.id), '[]') from kt_lich_tt l where not l.da_xoa);
end $f$;

create or replace function public.kt_lich_tt_luu(p_phien text, p jsonb) returns bigint
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung; v_id bigint := nullif(p->>'id', '')::bigint;
begin
  u := kt_chan(p_phien, 'sap_tra', true);
  if coalesce(trim(p->>'khoan'), '') = '' then raise exception 'Ghi tên khoản'; end if;
  if nullif(p->>'han_tu', '') is null then raise exception 'Chọn hạn kỳ tới'; end if;
  if v_id is null then
    insert into kt_lich_tt (khoan, co_so, nguoi_nhan, thu_huong_ten, thu_huong_stk, thu_huong_nh, thong_tin, chu_ky, han_tu, han_den, han_mo_ta, so_tien, so_tien_ghi, nhac_truoc, ghi_chu, tao_boi)
    values (trim(p->>'khoan'), nullif(p->>'co_so', ''), nullif(p->>'nguoi_nhan', ''), nullif(p->>'thu_huong_ten', ''), nullif(p->>'thu_huong_stk', ''), nullif(p->>'thu_huong_nh', ''),
            nullif(p->>'thong_tin', ''), coalesce((p->>'chu_ky')::int, 1), (p->>'han_tu')::date, coalesce(nullif(p->>'han_den', '')::date, (p->>'han_tu')::date),
            nullif(p->>'han_mo_ta', ''), nullif(p->>'so_tien', '')::numeric, nullif(p->>'so_tien_ghi', ''), coalesce((p->>'nhac_truoc')::int, 3), nullif(p->>'ghi_chu', ''), u.ho_ten)
    returning id into v_id;
  else
    update kt_lich_tt set khoan = trim(p->>'khoan'), co_so = nullif(p->>'co_so', ''), nguoi_nhan = nullif(p->>'nguoi_nhan', ''), thu_huong_ten = nullif(p->>'thu_huong_ten', ''),
           thu_huong_stk = nullif(p->>'thu_huong_stk', ''), thu_huong_nh = nullif(p->>'thu_huong_nh', ''), thong_tin = nullif(p->>'thong_tin', ''),
           chu_ky = coalesce((p->>'chu_ky')::int, chu_ky), han_tu = (p->>'han_tu')::date, han_den = coalesce(nullif(p->>'han_den', '')::date, (p->>'han_tu')::date),
           han_mo_ta = nullif(p->>'han_mo_ta', ''), so_tien = nullif(p->>'so_tien', '')::numeric, so_tien_ghi = nullif(p->>'so_tien_ghi', ''),
           nhac_truoc = coalesce((p->>'nhac_truoc')::int, nhac_truoc), ghi_chu = nullif(p->>'ghi_chu', ''), da_nhac_sap = null, da_nhac_qua = null,
           sua_boi = u.ho_ten, sua_luc = now() where id = v_id and not da_xoa;
  end if;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_lich_tt', case when p->>'id' is null then 'them' else 'sua' end, jsonb_build_object('id', v_id, 'khoan', p->>'khoan'));
  return v_id;
end $f$;

create or replace function public.kt_lich_tt_xoa(p_phien text, p_id bigint) returns void
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'sap_tra', true);
  update kt_lich_tt set da_xoa = true, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_lich_tt', 'xoa', jsonb_build_object('id', p_id));
end $f$;

-- đã thanh toán kỳ này → ghi lần trả, dời sang kỳ sau (cộng chu_ky tháng), xoá dấu đã nhắc
create or replace function public.kt_lich_tt_da_tra(p_phien text, p_id bigint, p_so_tien numeric, p_chi bigint) returns void
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung; l kt_lich_tt;
begin
  u := kt_chan(p_phien, 'sap_tra', true);
  select * into l from kt_lich_tt where id = p_id and not da_xoa;
  if l.id is null then raise exception 'Không thấy khoản'; end if;
  insert into kt_lich_tt_tra (lich_id, ky_tu, ky_den, so_tien, chi_id, boi) values (p_id, l.han_tu, l.han_den, p_so_tien, p_chi, u.ho_ten);
  update kt_lich_tt set han_tu = (han_tu + make_interval(months => chu_ky))::date, han_den = (han_den + make_interval(months => chu_ky))::date,
         da_nhac_sap = null, da_nhac_qua = null, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_lich_tt', 'da_tra', jsonb_build_object('id', p_id, 'ky', l.han_tu, 'so_tien', p_so_tien, 'chi_id', p_chi));
end $f$;

-- nhắc mỗi sáng
create or replace function public.kt_lich_tt_nhac() returns int
  language plpgsql security definer set search_path = public as $f$
declare n int := 0; l record; hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; loai text; td text;
begin
  for l in select * from kt_lich_tt where not da_xoa and (
             (han_tu - nhac_truoc <= hom and hom <= han_den and da_nhac_sap is distinct from han_tu)
          or (hom > han_den and da_nhac_qua is distinct from han_tu)) loop
    if hom > l.han_den then loai := 'qua'; td := 'Quá hạn thanh toán · ' || l.khoan || coalesce(' · ' || l.co_so, '');
    else loai := 'sap'; td := 'Sắp đến hạn thanh toán · ' || l.khoan || coalesce(' · ' || l.co_so, ''); end if;
    insert into kt_thong_bao (nguoi_dung_id, tu, loai, tieu_de, noi_dung, bang, dong_id)
    select nd.id, 'Hệ thống', 'lich_tt', td,
           'Hạn ' || to_char(l.han_tu, 'DD/MM') || case when l.han_den <> l.han_tu then '–' || to_char(l.han_den, 'DD/MM') else '' end
             || coalesce(' · dự kiến ' || replace(to_char(l.so_tien, 'FM999,999,999,999'), ',', '.'), coalesce(' · ' || l.so_tien_ghi, '')) || coalesce(' · ' || l.nguoi_nhan, ''),
           'lich_tt', l.id
      from kt_nguoi_dung nd where nd.hoat_dong and (nd.vi_tri = 'supreme' or kt_co_quyen(nd, 'chi_duyet'));
    if loai = 'qua' then update kt_lich_tt set da_nhac_qua = han_tu where id = l.id; else update kt_lich_tt set da_nhac_sap = han_tu where id = l.id; end if;
    n := n + 1;
  end loop;
  return n;
end $f$;
revoke all on function public.kt_lich_tt_nhac() from anon, authenticated, public;
select cron.unschedule('kt-nhac-lich-tt') where exists (select 1 from cron.job where jobname = 'kt-nhac-lich-tt');
select cron.schedule('kt-nhac-lich-tt', '0 1 * * *', $c$select public.kt_lich_tt_nhac()$c$);
