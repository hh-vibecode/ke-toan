-- CHAT trong app kế toán (19/10/2026, anh: "làm cái chat trong nền tảng với mọi người ở trong này").
-- Kênh 'chung' = mọi tài khoản đang dùng; kênh 'u:<id nhỏ>-<id lớn>' = nhắn riêng 2 người. Trình duyệt hỏi định kỳ (không realtime — bảng kt_ có RLS, anon không đọc thẳng).
-- Bảng kt_ bật RLS, chỉ đọc / ghi qua hàm kt_chat_* (tự kiểm phiên + quyền kênh). — Monsieur Claude
create table if not exists public.kt_tin_nhan (
  id bigint generated always as identity primary key,
  kenh text not null,
  nguoi_id int not null,
  nguoi text not null,
  noi_dung text not null,
  tao_luc timestamptz not null default now(),
  da_xoa boolean not null default false
);
create index if not exists kt_tin_nhan_kenh on public.kt_tin_nhan (kenh, id);
alter table public.kt_tin_nhan enable row level security;
revoke all on public.kt_tin_nhan from anon, authenticated;

create table if not exists public.kt_tin_doc (
  nguoi_id int not null,
  kenh text not null,
  doc_den bigint not null default 0,
  primary key (nguoi_id, kenh)
);
alter table public.kt_tin_doc enable row level security;
revoke all on public.kt_tin_doc from anon, authenticated;

-- được vào kênh không
create or replace function public.kt_chat_vao(u kt_nguoi_dung, p_kenh text) returns boolean language sql stable set search_path = public as $$
  select p_kenh = 'chung' or (p_kenh ~ '^u:[0-9]+-[0-9]+$' and u.id::text = any(string_to_array(substring(p_kenh from 3), '-')));
$$;
revoke all on function public.kt_chat_vao(kt_nguoi_dung, text) from public;

-- tổng quan: mọi kênh của tôi + số chưa đọc + tin cuối (nhóm chung + 1-1 với từng người đang dùng)
create or replace function public.kt_chat_tong(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  return coalesce((select jsonb_agg(x order by (x->>'kenh') <> 'chung', x->>'cuoi_luc' desc nulls last, x->>'ten') from (
    select jsonb_build_object('kenh', k.kenh, 'ten', k.ten, 'nguoi_id', k.nid,
      'chua_doc', (select count(*) from kt_tin_nhan t where t.kenh = k.kenh and not t.da_xoa and t.nguoi_id <> u.id
                     and t.id > coalesce((select doc_den from kt_tin_doc d where d.nguoi_id = u.id and d.kenh = k.kenh), 0)),
      'cuoi', (select left(t.nguoi || ': ' || t.noi_dung, 80) from kt_tin_nhan t where t.kenh = k.kenh and not t.da_xoa order by t.id desc limit 1),
      'cuoi_luc', (select max(t.tao_luc) from kt_tin_nhan t where t.kenh = k.kenh and not t.da_xoa)) x
    from (select 'chung' kenh, 'Nhóm chung' ten, null::int nid
          union all
          select 'u:' || least(u.id, n.id) || '-' || greatest(u.id, n.id), n.ho_ten, n.id from kt_nguoi_dung n
           where n.hoat_dong and n.id <> u.id and n.ten_dang_nhap not like 'tam-%') k) y), '[]');
end $$;

-- tin của 1 kênh (sau id, tối đa 200 tin gần nhất)
create or replace function public.kt_chat_ds(p_phien text, p_kenh text, p_sau bigint default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not kt_chat_vao(u, p_kenh) then raise exception 'Không vào được cuộc trò chuyện này' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'ai', nguoi, 'ai_id', nguoi_id, 'nd', noi_dung, 'luc', tao_luc, 'cua_toi', nguoi_id = u.id) order by id) from (
    select * from kt_tin_nhan where kenh = p_kenh and not da_xoa and id > coalesce(p_sau, 0) order by id desc limit 200) x), '[]');
end $$;

create or replace function public.kt_chat_gui(p_phien text, p_kenh text, p_noi_dung text) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint;
begin
  u := kt_chan(p_phien);
  if not kt_chat_vao(u, p_kenh) then raise exception 'Không vào được cuộc trò chuyện này' using errcode = '42501'; end if;
  if coalesce(trim(p_noi_dung), '') = '' then raise exception 'Nhập nội dung'; end if;
  insert into kt_tin_nhan (kenh, nguoi_id, nguoi, noi_dung) values (p_kenh, u.id, u.ho_ten, left(trim(p_noi_dung), 4000)) returning id into v_id;
  insert into kt_tin_doc (nguoi_id, kenh, doc_den) values (u.id, p_kenh, v_id) on conflict (nguoi_id, kenh) do update set doc_den = greatest(kt_tin_doc.doc_den, v_id);
  return v_id;
end $$;

create or replace function public.kt_chat_doc(p_phien text, p_kenh text, p_den bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not kt_chat_vao(u, p_kenh) then return; end if;
  insert into kt_tin_doc (nguoi_id, kenh, doc_den) values (u.id, p_kenh, p_den) on conflict (nguoi_id, kenh) do update set doc_den = greatest(kt_tin_doc.doc_den, p_den);
end $$;

create or replace function public.kt_chat_xoa(p_phien text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  update kt_tin_nhan set da_xoa = true where id = p_id and nguoi_id = u.id;
  if not found then raise exception 'Chỉ xoá được tin của mình'; end if;
end $$;

revoke all on function public.kt_chat_tong(text), public.kt_chat_ds(text, text, bigint), public.kt_chat_gui(text, text, text), public.kt_chat_doc(text, text, bigint), public.kt_chat_xoa(text, bigint) from public;
grant execute on function public.kt_chat_tong(text), public.kt_chat_ds(text, text, bigint), public.kt_chat_gui(text, text, text), public.kt_chat_doc(text, text, bigint), public.kt_chat_xoa(text, bigint) to anon;

-- đang "Xem như" tài khoản khác: không gửi / không đánh dấu đã đọc thay người đó
do $$
declare d text; f text;
begin
  foreach f in array array['kt_chat_gui','kt_chat_doc','kt_chat_xoa'] loop
    d := pg_get_functiondef(('public.' || f)::regproc);
    d := replace(d, $a$  u := kt_chan(p_phien);$a$, $a$  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang Xem như — không gửi / sửa tin thay người khác'; end if;$a$);
    if position('kt.chi_xem' in d) = 0 then raise exception '% khong thay cho', f; end if; execute d;
  end loop;
end $$;
