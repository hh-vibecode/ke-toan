-- =========================================================================
-- APP KẾ TOÁN — Kiot MỞ RỘNG theo luồng mới 08/10/2026 (Monsieur Claude)
-- Khách hàng · NCC · hàng hoá + tồn kho từng chi nhánh · hoá đơn bán + chi tiết · trả hàng · nhập hàng.
-- Luồng kéo RIÊNG app kế toán (Edge Function kt-kiot, 3 tiếng / lần, chỉ kéo phần Kiot SỬA từ lần trước — lastModifiedFrom).
-- Bảng RLS bật, KHÔNG policy (chỉ hàm kt_* đọc). Chứng từ (hoá đơn / trả / nhập) chỉ giữ từ 01/09/2026.
-- =========================================================================
create table if not exists public.kt_kiot_khach (
  id bigint primary key, ma text, ten text, sdt text, loai int, chi_nhanh_id bigint,
  cong_no numeric(16,0), tong_mua numeric(16,0), tong_mua_tru_tra numeric(16,0),
  tao_kiot timestamptz, sua_kiot timestamptz, keo_luc timestamptz not null default now()
);
create index if not exists kt_kiot_khach_no_idx on kt_kiot_khach(cong_no) where cong_no <> 0;

create table if not exists public.kt_kiot_ncc (
  id bigint primary key, ma text, ten text, sdt text, hoat_dong boolean,
  cong_no numeric(16,0), tong_nhap numeric(16,0), tong_nhap_tru_tra numeric(16,0),
  tao_kiot timestamptz, sua_kiot timestamptz, keo_luc timestamptz not null default now()
);

create table if not exists public.kt_kiot_hang (
  id bigint primary key, ma text, ten text, nhom_id bigint, nhom text, don_vi text, gia_ban numeric(16,0), hoat_dong boolean,
  ton jsonb not null default '[]',          -- [{"cn":"Đồ thờ Hiền Thủy","ton":3,"gia_von":120000}] từng chi nhánh
  tong_ton numeric, gia_tri_ton numeric(16,0),
  tao_kiot timestamptz, sua_kiot timestamptz, keo_luc timestamptz not null default now()
);

create table if not exists public.kt_kiot_hoa_don (
  id bigint primary key, ma text not null, ngay timestamptz not null, chi_nhanh text, nv_ban text,
  khach_id bigint, khach_ma text, khach_ten text, ma_dat_hang text,
  tong numeric(16,0), da_tra numeric(16,0), trang_thai int, trang_thai_ten text,
  chi_tiet jsonb not null default '[]',     -- [{"sp":id,"ma","ten","nhom","sl","gia","giam","tien","sl_tra"}]
  gia_von numeric(16,0),                    -- Σ sl × giá vốn bình quân của mặt hàng tại chi nhánh LÚC KÉO (Kiot không trả giá vốn lúc bán)
  sua_kiot timestamptz, keo_luc timestamptz not null default now()
);
create index if not exists kt_kiot_hoa_don_ngay_idx on kt_kiot_hoa_don(ngay);

create table if not exists public.kt_kiot_tra_hang (
  id bigint primary key, ma text not null, hoa_don_id bigint, ngay timestamptz not null, chi_nhanh text,
  tong_tra numeric(16,0), phi_tra numeric(16,0), da_tra numeric(16,0), trang_thai int, trang_thai_ten text,
  chi_tiet jsonb not null default '[]', sua_kiot timestamptz, keo_luc timestamptz not null default now()
);
create index if not exists kt_kiot_tra_hang_ngay_idx on kt_kiot_tra_hang(ngay);

create table if not exists public.kt_kiot_nhap_hang (
  id bigint primary key, ma text not null, ngay timestamptz not null, chi_nhanh text,
  ncc_id bigint, ncc_ma text, ncc_ten text, tong numeric(16,0), da_tra numeric(16,0), giam_gia numeric(16,0),
  trang_thai int, mo_ta text, chi_tiet jsonb not null default '[]', sua_kiot timestamptz, keo_luc timestamptz not null default now()
);
create index if not exists kt_kiot_nhap_hang_ngay_idx on kt_kiot_nhap_hang(ngay);

do $$ declare t text; begin
  foreach t in array array['kt_kiot_khach','kt_kiot_ncc','kt_kiot_hang','kt_kiot_hoa_don','kt_kiot_tra_hang','kt_kiot_nhap_hang'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- Tính giá vốn hoá đơn chưa có (hoặc tính lại cả kỳ): Σ sl × giá vốn bình quân mặt hàng tại chi nhánh bán.
create or replace function public.kt_tinh_gia_von(p_tat_ca boolean default false) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update kt_kiot_hoa_don h set gia_von = x.gv
    from (select h2.id, coalesce(sum((d->>'sl')::numeric * coalesce(
             (select (t->>'gia_von')::numeric from kt_kiot_hang p, jsonb_array_elements(p.ton) t
               where p.id = (d->>'sp')::bigint and t->>'cn' = h2.chi_nhanh limit 1), 0)), 0) gv
            from kt_kiot_hoa_don h2 cross join lateral jsonb_array_elements(h2.chi_tiet) d
           where p_tat_ca or h2.gia_von is null group by h2.id) x
   where h.id = x.id;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.kt_tinh_gia_von(boolean) from public, anon, authenticated;
grant execute on function public.kt_tinh_gia_von(boolean) to service_role;
