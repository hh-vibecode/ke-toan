-- Chat: "Đã xem" + đánh dấu "✓ Đã xử lý" trên tin (19/10/2026, anh: "thêm đã đọc, thêm cả react đã xử lý"). — Monsieur Claude
create table if not exists public.kt_tin_cam (
  tin_id bigint not null references public.kt_tin_nhan(id) on delete cascade,
  nguoi_id int not null,
  ten text not null,
  luc timestamptz not null default now(),
  primary key (tin_id, nguoi_id)
);
alter table public.kt_tin_cam enable row level security;
revoke all on public.kt_tin_cam from anon, authenticated;

-- tin của kênh: trả {tin: tin mới sau p_sau, cam: đánh dấu "đã xử lý" của các tin từ p_tu, doc: người khác đã xem tới tin nào}
drop function if exists public.kt_chat_ds(text, text, bigint);
create or replace function public.kt_chat_ds(p_phien text, p_kenh text, p_sau bigint default 0, p_tu bigint default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not kt_chat_vao(u, p_kenh) then raise exception 'Không vào được cuộc trò chuyện này' using errcode = '42501'; end if;
  return jsonb_build_object(
    'tin', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'ai', nguoi, 'ai_id', nguoi_id, 'nd', noi_dung, 'luc', tao_luc, 'cua_toi', nguoi_id = u.id) order by id) from (
       select * from kt_tin_nhan where kenh = p_kenh and not da_xoa and id > coalesce(p_sau, 0) order by id desc limit 200) x), '[]'),
    'cam', coalesce((select jsonb_agg(jsonb_build_object('tin_id', c.tin_id, 'ten', c.ten, 'toi', c.nguoi_id = u.id) order by c.luc)
       from kt_tin_cam c join kt_tin_nhan t on t.id = c.tin_id where t.kenh = p_kenh and t.id >= coalesce(p_tu, 0)), '[]'),
    'doc', coalesce((select jsonb_agg(jsonb_build_object('ten', n.ho_ten, 'den', d.doc_den)) from kt_tin_doc d join kt_nguoi_dung n on n.id = d.nguoi_id
       where d.kenh = p_kenh and d.nguoi_id <> u.id and n.ten_dang_nhap not like 'tam-%'), '[]'));
end $$;

-- bấm / bỏ "đã xử lý"
create or replace function public.kt_chat_cam(p_phien text, p_tin_id bigint) returns boolean
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; t kt_tin_nhan;
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang Xem như — không đánh dấu thay người khác'; end if;
  select * into t from kt_tin_nhan where id = p_tin_id and not da_xoa;
  if t.id is null or not kt_chat_vao(u, t.kenh) then raise exception 'Không tìm thấy tin'; end if;
  if exists (select 1 from kt_tin_cam where tin_id = p_tin_id and nguoi_id = u.id) then
    delete from kt_tin_cam where tin_id = p_tin_id and nguoi_id = u.id; return false;
  end if;
  insert into kt_tin_cam (tin_id, nguoi_id, ten) values (p_tin_id, u.id, u.ho_ten); return true;
end $$;
revoke all on function public.kt_chat_ds(text, text, bigint, bigint), public.kt_chat_cam(text, bigint) from public;
grant execute on function public.kt_chat_ds(text, text, bigint, bigint), public.kt_chat_cam(text, bigint) to anon;
