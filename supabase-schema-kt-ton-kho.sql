-- =========================================================================
-- APP KẾ TOÁN — CHỤP TỒN KHO CUỐI NGÀY (09/10/2026) — Monsieur Claude
-- Kiot chỉ cho số tồn HIỆN TẠI → muốn có tồn kho tại ngày cuối kỳ thì app tự chụp mỗi tối:
--   23:20 (giờ VN) lịch 'kt-kiot-hang-dem' kéo ĐẦY ĐỦ hàng hoá (tồn + giá vốn từng chi nhánh, ~70 giây)
--     — cần vì Kiot KHÔNG đổi "ngày sửa" sản phẩm khi bán / nhập, nên lần kéo 3 tiếng (chỉ phần sửa) để số tồn cũ
--     (kiểm 09/10: 7/15 mặt hàng bán gần đây lệch; kéo đầy đủ xong 15/15 khớp).
--   23:40 lịch 'kt-ton-kho' gọi kt_chup_ton_kho():
--     · kt_ton_kho_ngay: mỗi ngày × chi nhánh 1 dòng (số mặt hàng còn tồn, tổng số lượng, giá trị = Σ tồn × giá vốn).
--     · kt_ton_kho_thang: NGÀY CUỐI THÁNG chụp chi tiết từng mặt hàng (chỉ dòng tồn ≠ 0, ~4.500 dòng / tháng).
-- Tồn kho trước ngày bắt đầu chụp (09/10/2026) KHÔNG lấy lại được.
-- =========================================================================
create table if not exists public.kt_ton_kho_ngay (
  ngay        date not null,
  chi_nhanh   text not null,
  so_mat_hang int not null,
  so_luong    numeric not null,
  gia_tri     numeric not null,
  chup_luc    timestamptz not null default now(),
  primary key (ngay, chi_nhanh)
);
create table if not exists public.kt_ton_kho_thang (
  thang     date not null,          -- ngày cuối tháng
  hang_id   bigint not null,
  ma        text,
  ten       text,
  chi_nhanh text not null,
  ton       numeric not null,
  gia_von   numeric,
  primary key (thang, hang_id, chi_nhanh)
);
alter table public.kt_ton_kho_ngay enable row level security;
alter table public.kt_ton_kho_thang enable row level security;
revoke all on public.kt_ton_kho_ngay, public.kt_ton_kho_thang from anon, authenticated;

create or replace function public.kt_chup_ton_kho() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ngay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; v_n int; v_ct int := 0;
begin
  insert into kt_ton_kho_ngay (ngay, chi_nhanh, so_mat_hang, so_luong, gia_tri, chup_luc)
  select v_ngay, e->>'cn', count(*) filter (where (e->>'ton')::numeric <> 0), coalesce(sum((e->>'ton')::numeric), 0),
         coalesce(sum((e->>'ton')::numeric * coalesce((e->>'gia_von')::numeric, 0)), 0), now()
    from kt_kiot_hang h, jsonb_array_elements(h.ton) e where e->>'cn' is not null group by e->>'cn'
  on conflict (ngay, chi_nhanh) do update set so_mat_hang = excluded.so_mat_hang, so_luong = excluded.so_luong,
    gia_tri = excluded.gia_tri, chup_luc = excluded.chup_luc;
  get diagnostics v_n = row_count;
  if extract(day from v_ngay + 1) = 1 then   -- ngày cuối tháng → chụp chi tiết
    delete from kt_ton_kho_thang where thang = v_ngay;
    insert into kt_ton_kho_thang (thang, hang_id, ma, ten, chi_nhanh, ton, gia_von)
    select v_ngay, h.id, h.ma, h.ten, e->>'cn', (e->>'ton')::numeric, (e->>'gia_von')::numeric
      from kt_kiot_hang h, jsonb_array_elements(h.ton) e where e->>'cn' is not null and (e->>'ton')::numeric <> 0;
    get diagnostics v_ct = row_count;
  end if;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu)
  values ('Hệ thống', 'kt_ton_kho_ngay', 'chup_ton_kho', jsonb_build_object('ngay', v_ngay, 'chi_nhanh', v_n, 'chi_tiet_cuoi_thang', v_ct));
  return jsonb_build_object('ngay', v_ngay, 'chi_nhanh', v_n, 'chi_tiet_cuoi_thang', v_ct);
end $$;
revoke execute on function public.kt_chup_ton_kho() from public, anon, authenticated;
