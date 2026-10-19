-- Đổi quyền → tài khoản đó TỰ TẢI LẠI app (như F5), KHÔNG đăng xuất (19/10/2026, anh: "logout có cần thiết k, nếu k thì bắt mọi người F5 lại là được,
-- tất nhiên là trừ TK của tao"). Thay phần "đổi quyền → xoá phiên" trong supabase-schema-kt-he-thong-quyen.sql.
-- Khoá tài khoản / đặt lại mật khẩu vẫn đăng xuất như cũ. — Monsieur Claude
alter table public.kt_nguoi_dung add column if not exists quyen_doi_luc timestamptz not null default now();

do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_luu_nguoi_dung'::regproc); n := length(d);
  d := replace(d, $a$      delete from kt_phien where nguoi_dung_id = v_id;
    end if;
    update kt_nguoi_dung set ten_dang_nhap = lower(trim(p_dong->>'ten_dang_nhap')),$a$, $a$      update kt_nguoi_dung set quyen_doi_luc = now() where id = v_id;   -- app người đó tự tải lại (trừ Supreme)
    end if;
    update kt_nguoi_dung set ten_dang_nhap = lower(trim(p_dong->>'ten_dang_nhap')),$a$);
  if length(d) = n then raise exception 'kt_luu_nguoi_dung: khong thay cho'; end if; execute d;
end $$;

create or replace function public.kt_toi(u kt_nguoi_dung) returns jsonb language sql immutable as $$
  select jsonb_build_object('id', u.id, 'ten_dang_nhap', u.ten_dang_nhap, 'ho_ten', u.ho_ten, 'vi_tri', u.vi_tri,
    'quyen', to_jsonb(u.quyen), 'toan_quyen', u.vi_tri in ('supreme','admin') or '*' = any(u.quyen), 'quyen_doi_luc', u.quyen_doi_luc);
$$;

-- app hỏi mỗi phút: quyền đã đổi sau lúc mình tải trang chưa
create or replace function public.kt_quyen_doi_luc(p_phien text) returns timestamptz
language plpgsql stable security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  return u.quyen_doi_luc;
end $$;
revoke all on function public.kt_quyen_doi_luc(text) from public;
grant execute on function public.kt_quyen_doi_luc(text) to anon;
