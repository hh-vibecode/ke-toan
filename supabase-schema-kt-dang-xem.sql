-- AI ĐANG TRONG APP KẾ TOÁN (19/10/2026, anh: "app kế toán thêm cho t cái này — bên MKT có sẵn, cái hiển thị người đang trong app, lấy icon bên nó").
-- Cách làm như app MKT (bảng dang_xem của MKT — KHÔNG dùng chung): mỗi trình duyệt 1 dòng, 30 giây báo danh, quá 90 giây không báo = đã thoát.
-- Bảng kt_ bật RLS, anon không đọc thẳng; trình duyệt chỉ gọi hàm kt_bao_danh (tự kiểm phiên đăng nhập). — Monsieur Claude
create table if not exists public.kt_dang_xem (
  ma          text primary key,          -- mã trình duyệt (localStorage)
  nguoi_dung_id int not null,
  ten         text not null,
  trang       text,
  con         int,                        -- con vật (thu/a01..a30.png)
  last_seen   timestamptz not null default now()
);
create index if not exists kt_dang_xem_last on public.kt_dang_xem (last_seen desc);
alter table public.kt_dang_xem enable row level security;
revoke all on public.kt_dang_xem from anon, authenticated;

-- báo danh + trả danh sách người đang trong app (1 lần gọi / 30 giây). p_roi = true: rời app (đăng xuất / đóng tab)
create or replace function public.kt_bao_danh(p_phien text, p_ma text, p_trang text default null, p_con int default null, p_roi boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if coalesce(trim(p_ma), '') = '' or length(p_ma) > 64 then raise exception 'Mã trình duyệt không hợp lệ'; end if;
  if p_roi then delete from kt_dang_xem where ma = p_ma; return '[]'::jsonb; end if;
  -- lúc Xem như: không báo danh (không hiện admin thành người khác), chỉ xem danh sách
  if coalesce(current_setting('kt.chi_xem', true), '') <> '1' then
    insert into kt_dang_xem (ma, nguoi_dung_id, ten, trang, con, last_seen)
    values (p_ma, u.id, u.ho_ten, left(p_trang, 60), p_con, now())
    on conflict (ma) do update set nguoi_dung_id = excluded.nguoi_dung_id, ten = excluded.ten, trang = excluded.trang,
      con = coalesce(excluded.con, kt_dang_xem.con), last_seen = now();
  end if;
  delete from kt_dang_xem where last_seen < now() - interval '1 day';   -- dọn tab đóng đột ngột
  return coalesce((select jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'trang', trang, 'con', con, 'toi', nguoi_dung_id = u.id) order by last_seen desc)
    from (select * from kt_dang_xem where last_seen > now() - interval '90 seconds' order by last_seen desc limit 50) x), '[]');
end $$;
revoke all on function public.kt_bao_danh(text, text, text, int, boolean) from public;
grant execute on function public.kt_bao_danh(text, text, text, int, boolean) to anon;
