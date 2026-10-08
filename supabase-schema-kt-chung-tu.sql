-- =========================================================================
-- APP KẾ TOÁN — CHỨNG TỪ (ảnh / PDF) lưu và xem ngay trên app (anh chốt 08/10/2026) — Monsieur Claude
-- File nằm ở Storage bucket RIÊNG TƯ 'kt-chung-tu' (đường dẫn <bảng>/<id phiếu>/<thời điểm>_<tên>).
-- Trang web KHÔNG đụng Storage trực tiếp: Edge Function 'kt-chung-tu' kiểm phiên + quyền trang rồi cấp link ký tên
-- (tải lên / xem / tải về) sống 5 phút. Bảng kt_chung_tu giữ thông tin file; xoá = ẩn (file vẫn còn, có nhật ký).
-- LƯU Ý 08/10: kt_quyen_chung_tu / kt_them_chung_tu / kt_ds_chung_tu / kt_xoa_chung_tu được ĐỊNH NGHĨA LẠI trong
-- supabase-schema-kt-thong-bao.sql (kiểm quyền theo dòng). Chạy file đó SAU file này (scripts/trien-khai-chung-tu.js đã làm vậy).
-- =========================================================================
create table if not exists public.kt_chung_tu (
  id          bigserial primary key,
  bang        text not null check (bang in ('thu','chi','dieu_chuyen','vay','tai_san')),
  dong_id     bigint not null,
  duong_dan   text not null unique,
  ten_file    text not null,
  mime        text,
  kich_thuoc  bigint,
  tao_boi     text, tao_luc timestamptz not null default now(),
  da_xoa      boolean not null default false
);
create index if not exists kt_chung_tu_dong_idx on kt_chung_tu(bang, dong_id) where not da_xoa;
alter table public.kt_chung_tu enable row level security;
revoke all on public.kt_chung_tu from anon, authenticated;

-- Dùng cho Edge Function (service_role): kiểm phiên + quyền trang của bảng chứng từ. Trả họ tên; sai → lỗi.
create or replace function public.kt_quyen_chung_tu(p_phien text, p_bang text, p_ghi boolean) returns text
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  if p_bang not in ('thu','chi','dieu_chuyen','vay','tai_san') then raise exception 'Bảng chứng từ không hợp lệ'; end if;
  u := kt_chan(p_phien, p_bang, p_ghi);
  return u.ho_ten;
end $$;
revoke execute on function public.kt_quyen_chung_tu(text, text, boolean) from public, anon, authenticated;
grant execute on function public.kt_quyen_chung_tu(text, text, boolean) to service_role;

-- Ghi thông tin file SAU khi trình duyệt đã tải lên bằng link ký tên. Đường dẫn bắt buộc đúng <bảng>/<id>/...
create or replace function public.kt_them_chung_tu(p_phien text, p_bang text, p_dong_id bigint, p_duong_dan text,
  p_ten text, p_mime text, p_kich_thuoc bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint;
begin
  u := kt_chan(p_phien, p_bang, true);
  if p_duong_dan not like p_bang || '/' || p_dong_id || '/%' then raise exception 'Đường dẫn chứng từ không hợp lệ'; end if;
  insert into kt_chung_tu (bang, dong_id, duong_dan, ten_file, mime, kich_thuoc, tao_boi)
  values (p_bang, p_dong_id, p_duong_dan, left(p_ten, 200), p_mime, p_kich_thuoc, u.ho_ten) returning id into v_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chung_tu', v_id, 'them', jsonb_build_object('bang', p_bang, 'dong_id', p_dong_id, 'ten', p_ten));
  return v_id;
end $$;

create or replace function public.kt_ds_chung_tu(p_phien text, p_bang text, p_dong_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, p_bang);
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'ten', ten_file, 'mime', mime, 'kich_thuoc', kich_thuoc,
    'tao_boi', tao_boi, 'tao_luc', tao_luc) order by id) from kt_chung_tu where bang = p_bang and dong_id = p_dong_id and not da_xoa), '[]');
end $$;

-- Chứng từ trong kỳ (để tải cả kỳ .zip): thu theo ngày thu · chi theo ngày thanh toán (chưa trả: ngày đề nghị) · điều chuyển theo ngày.
-- Chỉ trả bảng người dùng được xem.
create or replace function public.kt_ds_chung_tu_ky(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'bang', c.bang, 'dong_id', c.dong_id, 'ten', c.ten_file, 'ngay', x.ngay) order by x.ngay, c.id)
    from kt_chung_tu c join lateral (
      select t.ngay from kt_thu t where c.bang = 'thu' and t.id = c.dong_id
      union all select coalesce(h.ngay_tt, h.ngay_de_nghi) from kt_chi h where c.bang = 'chi' and h.id = c.dong_id
      union all select d.ngay from kt_dieu_chuyen d where c.bang = 'dieu_chuyen' and d.id = c.dong_id) x on true
    where not c.da_xoa and x.ngay between p_tu and p_den and kt_co_quyen(u, c.bang)), '[]');
end $$;

create or replace function public.kt_xoa_chung_tu(p_phien text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_bang text;
begin
  select bang into v_bang from kt_chung_tu where id = p_id;
  if v_bang is null then raise exception 'Không tìm thấy chứng từ'; end if;
  u := kt_chan(p_phien, v_bang, true);
  update kt_chung_tu set da_xoa = true where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chung_tu', p_id, 'xoa', null);
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_them_chung_tu(text,text,bigint,text,text,text,bigint)','kt_ds_chung_tu(text,text,bigint)',
    'kt_ds_chung_tu_ky(text,date,date)','kt_xoa_chung_tu(text,bigint)'] loop
    execute 'revoke execute on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;
