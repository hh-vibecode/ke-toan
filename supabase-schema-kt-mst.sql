-- TRA MST NGƯỜI MUA (Lập hoá đơn) — 11/11/2026. Monsieur Claude
-- Kế toán: "bình thường khi đánh mã số thuế vào thì hệ thống tự lấy thông tin trên trang thuế về để fill vào các thông tin người mua".
-- Edge kt-mst tra (VietQR — dữ liệu doanh nghiệp từ cơ quan thuế; dự phòng cổng HĐĐT Tổng cục Thuế), lưu đệm ở kt_mst 30 ngày để đỡ gọi lại.
create table if not exists public.kt_mst (
  mst text primary key, ten text, dia_chi text, nguon text, luc timestamptz not null default now(), du_lieu jsonb);
alter table public.kt_mst enable row level security;
revoke all on public.kt_mst from anon, authenticated;

-- kiểm phiên + quyền xem Hoá đơn & Thuế; trả bản đã lưu (≤ 30 ngày) hoặc null
create or replace function public.kt_mst_lay(p_phien text, p_mst text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  return (select jsonb_build_object('mst', mst, 'ten', ten, 'dia_chi', dia_chi, 'nguon', nguon, 'luc', luc) from kt_mst
           where mst = p_mst and luc > now() - interval '30 days');
end $$;
-- Edge lưu kết quả tra (chỉ service_role)
create or replace function public.kt_mst_luu(p_mst text, p_ten text, p_dia_chi text, p_nguon text, p_dl jsonb) returns void
language sql security definer set search_path = public as $$
  insert into kt_mst (mst, ten, dia_chi, nguon, luc, du_lieu) values (p_mst, p_ten, p_dia_chi, p_nguon, now(), p_dl)
  on conflict (mst) do update set ten = excluded.ten, dia_chi = excluded.dia_chi, nguon = excluded.nguon, luc = now(), du_lieu = excluded.du_lieu;
$$;
revoke all on function public.kt_mst_lay(text, text) from public;
grant execute on function public.kt_mst_lay(text, text) to anon, authenticated, service_role;
revoke all on function public.kt_mst_luu(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.kt_mst_luu(text, text, text, text, jsonb) to service_role;
