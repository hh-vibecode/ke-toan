-- KHO BÁO GIÁ NCC (NCC nước ngoài → tab Kho báo giá) — 12/11/2026, nối tiếp khung VIEC 330 (anh: "tiếp"). Trước là dữ liệu mẫu tính tại trang, chưa lưu;
-- giờ lưu bảng kt_bao_gia: 1 mẫu hàng nhiều báo giá của nhiều NCC, giữ lịch sử (sửa = cập nhật dòng đó, báo giá mới = dòng mới), la_mau = dữ liệu mẫu.
-- Quyền theo trang 'ncc' (như PO). — Monsieur Claude
create table if not exists public.kt_bao_gia (
  id bigserial primary key, ma_tht text, ten text not null, ncc_id bigint references kt_ncc(id), ncc_ten text,
  gia numeric not null, tien_te text not null default 'CNY' check (tien_te in ('VND', 'USD', 'CNY')), moq numeric, tg_sx int, ngay date not null default current_date,
  hieu_luc date, anh text, ghi_chu text, la_mau boolean not null default false,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, da_xoa boolean not null default false);
create index if not exists kt_bao_gia_ma on public.kt_bao_gia (ma_tht) where not da_xoa;
alter table public.kt_bao_gia enable row level security;
revoke all on public.kt_bao_gia from anon, authenticated;

create or replace function public.kt_bg_ds(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(to_jsonb(b) - 'da_xoa' order by b.ma_tht, b.ngay desc, b.id desc) from kt_bao_gia b where not b.da_xoa), '[]');
end $$;

create or replace function public.kt_bg_luu(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v bigint := nullif(p_dong->>'id', '')::bigint; ten text;
begin
  u := kt_chan(p_phien, 'ncc', true); ten := coalesce(u.ho_ten, u.ten_dang_nhap);
  if coalesce(btrim(p_dong->>'ten'), '') = '' then raise exception 'Nhập tên mẫu hàng'; end if;
  if coalesce(nullif(p_dong->>'gia', '')::numeric, 0) <= 0 then raise exception 'Nhập giá báo'; end if;
  if v is null then
    insert into kt_bao_gia (ma_tht, ten, ncc_id, ncc_ten, gia, tien_te, moq, tg_sx, ngay, hieu_luc, anh, ghi_chu, tao_boi)
    values (nullif(btrim(p_dong->>'ma_tht'), ''), btrim(p_dong->>'ten'), nullif(p_dong->>'ncc_id', '')::bigint, p_dong->>'ncc_ten', (p_dong->>'gia')::numeric,
      coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'), nullif(p_dong->>'moq', '')::numeric, nullif(p_dong->>'tg_sx', '')::int, coalesce(nullif(p_dong->>'ngay', '')::date, current_date),
      nullif(p_dong->>'hieu_luc', '')::date, p_dong->>'anh', p_dong->>'ghi_chu', ten) returning id into v;
  else
    update kt_bao_gia set ma_tht = nullif(btrim(p_dong->>'ma_tht'), ''), ten = btrim(p_dong->>'ten'), ncc_id = nullif(p_dong->>'ncc_id', '')::bigint, ncc_ten = p_dong->>'ncc_ten',
      gia = (p_dong->>'gia')::numeric, tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te), moq = nullif(p_dong->>'moq', '')::numeric, tg_sx = nullif(p_dong->>'tg_sx', '')::int,
      ngay = coalesce(nullif(p_dong->>'ngay', '')::date, ngay), hieu_luc = nullif(p_dong->>'hieu_luc', '')::date, anh = p_dong->>'anh', ghi_chu = p_dong->>'ghi_chu',
      la_mau = false, sua_boi = ten, sua_luc = now()
    where id = v and not da_xoa;
    if not found then raise exception 'Không tìm thấy báo giá'; end if;
  end if;
  perform kt_ghi_nhat_ky(ten, 'kt_bao_gia', v, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v;
end $$;

-- xoá 1 báo giá, hoặc p_id null = xoá toàn bộ báo giá mẫu
create or replace function public.kt_bg_xoa(p_phien text, p_id bigint) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; n int;
begin
  u := kt_chan(p_phien, 'ncc', true);
  update kt_bao_gia set da_xoa = true, sua_boi = coalesce(u.ho_ten, u.ten_dang_nhap), sua_luc = now() where not da_xoa and (id = p_id or (p_id is null and la_mau));
  get diagnostics n = row_count;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_bao_gia', p_id, 'xoa', jsonb_build_object('so_dong', n, 'mau', p_id is null));
  return n;
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_bg_ds(text)', 'kt_bg_luu(text, jsonb)', 'kt_bg_xoa(text, bigint)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;
