-- =========================================================================
-- APP KẾ TOÁN — "Cần giải đáp": câu Claude hỏi mà chưa ai trả lời (Monsieur Claude, 05/10/2026)
-- Anh Hải không làm nghiệp vụ kế toán → câu hỏi viết dễ hiểu, có ví dụ số + lựa chọn bấm sẵn; anh / kế toán trả lời
-- thẳng trên app, phiên Claude sau đọc kt_cau_hoi để làm theo. Số liệu nằm trong CSDL (RLS), KHÔNG lên GitHub.
-- =========================================================================
create table if not exists public.kt_cau_hoi (
  id          serial primary key,
  thu_tu      int not null default 100,
  nhom        text not null,                 -- Số dư · Kiot · Chi · Cách tính · Vận hành
  hoi_ai      text not null default 'ke_toan' check (hoi_ai in ('ke_toan','anh')),
  tieu_de     text not null,
  giai_thich  text not null,                 -- lời dễ hiểu + ví dụ số
  lua_chon    text[] not null default '{}',  -- câu trả lời bấm sẵn
  tra_loi     text,
  tra_loi_boi text,
  tra_loi_luc timestamptz,
  tao_luc     timestamptz not null default now()
);
alter table public.kt_cau_hoi enable row level security;
revoke all on public.kt_cau_hoi from anon, authenticated;

create or replace function public.kt_ds_cau_hoi(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien);
  return coalesce((select jsonb_agg(to_jsonb(c) order by (c.tra_loi is not null), c.thu_tu, c.id) from kt_cau_hoi c), '[]');
end $$;

-- Ai đăng nhập cũng trả lời được (anh Hải đi hỏi kế toán rồi nhập, hoặc kế toán tự nhập). p_tra_loi trống = xoá câu trả lời.
create or replace function public.kt_tra_loi_cau_hoi(p_phien text, p_id int, p_tra_loi text) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  update kt_cau_hoi set tra_loi = nullif(trim(p_tra_loi), ''),
    tra_loi_boi = case when nullif(trim(p_tra_loi), '') is null then null else u.ho_ten end,
    tra_loi_luc = case when nullif(trim(p_tra_loi), '') is null then null else now() end
   where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_cau_hoi', p_id, 'tra_loi', jsonb_build_object('tra_loi', p_tra_loi));
end $$;

revoke execute on function public.kt_ds_cau_hoi(text), public.kt_tra_loi_cau_hoi(text, int, text) from public;
grant execute on function public.kt_ds_cau_hoi(text), public.kt_tra_loi_cau_hoi(text, int, text) to anon, authenticated;

-- kt_bao_cao đếm số câu chưa trả lời (badge menu) — thêm vào 'dem' ở hàm báo cáo qua view nhỏ
create or replace function public.kt_dem_cau_hoi(p_phien text) returns int
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien);
  return (select count(*) from kt_cau_hoi where tra_loi is null);
end $$;
revoke execute on function public.kt_dem_cau_hoi(text) from public;
grant execute on function public.kt_dem_cau_hoi(text) to anon, authenticated;

-- Nội dung câu hỏi nạp bằng script riêng (có số liệu thật) — không ghi vào file này.
