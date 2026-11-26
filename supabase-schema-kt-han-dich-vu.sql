-- HẠN DỊCH VỤ & KHOÁ (26/11/2026, anh: "xem set báo trước 1 vs 2 tuần hết hạn trên popup thông báo ở màn hình app").
-- Kiot / MISA KHÔNG trả ngày hết hạn qua API → danh sách nhập tay (Cài đặt → Danh mục → Hạn dịch vụ & khoá).
-- Báo: (1) chuông mỗi sáng 8:00 VN khi còn đúng 14 / 7 ngày + ngày hết hạn + mỗi ngày khi đã quá hạn (lịch kt-han-dich-vu);
--      (2) popup giữa màn hình khi mở app, 1 lần / ngày / người, khi có mục còn ≤ 14 ngày. Người nhận: ai có quyền hệ thống (Supreme / Admin / GĐ). — Monsieur Claude
create table if not exists public.kt_han_dich_vu (
  id bigserial primary key,
  ten text not null,
  dung_cho text,
  het_han date,
  ghi_chu text,
  da_xoa boolean not null default false,
  tao_luc timestamptz not null default now(),
  sua_luc timestamptz not null default now(),
  sua_boi text
);
alter table public.kt_han_dich_vu enable row level security;
revoke all on public.kt_han_dich_vu from anon, authenticated;

insert into public.kt_han_dich_vu (ten, dung_cho, ghi_chu, sua_boi)
select v.ten, v.dc, v.gc, 'Hệ thống' from (values
  ('KiotViet', 'Hoá đơn, thu chi, khách, NCC, tồn kho', 'Đổi khoá API thì cập nhật khoá máy chủ'),
  ('MISA meInvoice', 'Hoá đơn bán ra, mua vào, đơn nháp', 'Đổi mật khẩu thì cập nhật khoá máy chủ')
) v(ten, dc, gc)
where not exists (select 1 from public.kt_han_dich_vu);

create or replace function public.kt_han_hom_nay() returns date language sql stable as $$
  select (now() at time zone 'Asia/Ho_Chi_Minh')::date;
$$;

-- danh sách (trang Cài đặt): kèm số ngày còn lại
create or replace function public.kt_han_ds(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'he_thong');
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'dung_cho', dung_cho, 'het_han', het_han, 'ghi_chu', ghi_chu,
      'con', het_han - kt_han_hom_nay(), 'sua_luc', sua_luc, 'sua_boi', sua_boi) order by het_han nulls last, ten)
    from kt_han_dich_vu where not da_xoa), '[]');
end $$;

-- popup khi mở app: chỉ mục còn ≤ 14 ngày (kể cả quá hạn); người không có quyền hệ thống → rỗng, không báo lỗi
create or replace function public.kt_han_sap(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not kt_co_quyen(u, 'he_thong') then return '[]'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'het_han', het_han, 'con', het_han - kt_han_hom_nay()) order by het_han)
    from kt_han_dich_vu where not da_xoa and het_han is not null and het_han - kt_han_hom_nay() <= 14), '[]');
end $$;

-- thêm / sửa (p_dong có id = sửa)
create or replace function public.kt_han_luu(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := nullif(p_dong->>'id', '')::bigint; v_ten text := trim(coalesce(p_dong->>'ten', ''));
begin
  u := kt_chan(p_phien, 'he_thong', true);
  if v_ten = '' then raise exception 'Chưa nhập tên dịch vụ'; end if;
  if v_id is null then
    insert into kt_han_dich_vu (ten, dung_cho, het_han, ghi_chu, sua_boi)
    values (left(v_ten, 120), left(nullif(trim(p_dong->>'dung_cho'), ''), 300), nullif(p_dong->>'het_han', '')::date, left(nullif(trim(p_dong->>'ghi_chu'), ''), 500), u.ho_ten)
    returning id into v_id;
  else
    update kt_han_dich_vu set ten = left(v_ten, 120), dung_cho = left(nullif(trim(p_dong->>'dung_cho'), ''), 300), het_han = nullif(p_dong->>'het_han', '')::date,
      ghi_chu = left(nullif(trim(p_dong->>'ghi_chu'), ''), 500), sua_luc = now(), sua_boi = u.ho_ten
    where id = v_id and not da_xoa;
    if not found then raise exception 'Không tìm thấy dịch vụ'; end if;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_han_dich_vu', v_id, case when p_dong ? 'id' and p_dong->>'id' <> '' then 'sua' else 'them' end, p_dong);
  return v_id;
end $$;

create or replace function public.kt_han_xoa(p_phien text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'he_thong', true);
  update kt_han_dich_vu set da_xoa = true, sua_luc = now(), sua_boi = u.ho_ten where id = p_id and not da_xoa;
  if not found then raise exception 'Không tìm thấy dịch vụ'; end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_han_dich_vu', p_id, 'xoa', null);
end $$;

revoke all on function public.kt_han_hom_nay() from public, anon, authenticated;
revoke all on function public.kt_han_ds(text) from public;
revoke all on function public.kt_han_sap(text) from public;
revoke all on function public.kt_han_luu(text, jsonb) from public;
revoke all on function public.kt_han_xoa(text, bigint) from public;
grant execute on function public.kt_han_ds(text) to anon;
grant execute on function public.kt_han_sap(text) to anon;
grant execute on function public.kt_han_luu(text, jsonb) to anon;
grant execute on function public.kt_han_xoa(text, bigint) to anon;

-- chuông mỗi sáng 8:00 VN: còn 14 / 7 ngày, ngày hết hạn, và mỗi ngày khi đã quá hạn
create or replace function public.kt_han_bao_hang_ngay() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; v_ai int[] := kt_ai_co_quyen('he_thong', false, 0);
begin
  for r in select *, het_han - kt_han_hom_nay() con from kt_han_dich_vu
           where not da_xoa and het_han is not null and (het_han - kt_han_hom_nay() in (14, 7) or het_han <= kt_han_hom_nay()) loop
    perform kt_bao(v_ai, 'Hệ thống', 'han_dv',
      case when r.con > 0 then r.ten || ' còn ' || r.con || ' ngày hết hạn' when r.con = 0 then r.ten || ' hết hạn hôm nay'
           else r.ten || ' đã hết hạn ' || (-r.con) || ' ngày' end,
      'Hết hạn ' || to_char(r.het_han, 'DD/MM/YYYY') || ' — gia hạn rồi cập nhật ngày mới ở Cài đặt → Hạn dịch vụ & khoá', 'kt_han', r.id);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.kt_han_bao_hang_ngay() from public, anon, authenticated;
select cron.unschedule('kt-han-dich-vu') where exists (select 1 from cron.job where jobname = 'kt-han-dich-vu');
select cron.schedule('kt-han-dich-vu', '0 1 * * *', 'select public.kt_han_bao_hang_ngay()');
