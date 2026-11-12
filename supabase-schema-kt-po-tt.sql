-- THANH TOÁN PO + PHÍ VẬN CHUYỂN PHIẾU NHẬP — 12/11/2026. AI kế toán soát lỗi (anh chuyển):
-- (3) "Đặt cọc NCC là 1 ô nhập tay trên PO … hồ sơ NCC lại báo đã thanh toán 0" → PO gắn PHIẾU CHI THẬT (kt_po.chi_ids, file kt-po-dinh-gia), trang tính đã trả từ phiếu chi;
-- (1) "đang suy phí vận chuyển từ chênh lệch — phải có chứng từ phí và cờ đã cộng vào giá Kiot có / không / chưa rõ" → kt_pn_phi_vc theo từng phiếu nhập Kiot:
--     đã cộng vào đơn giá Kiot (co / khong / chua_ro), số tiền phí, người nhận, giải trình chênh. Trạng thái đối chiếu tính ở trang. — Monsieur Claude
create table if not exists public.kt_pn_phi_vc (
  ma_pn text primary key, da_cong text not null default 'chua_ro' check (da_cong in ('co', 'khong', 'chua_ro')),
  so_tien numeric, nguoi_nhan text, giai_trinh text, sua_boi text, sua_luc timestamptz not null default now());
alter table public.kt_pn_phi_vc enable row level security;
revoke all on public.kt_pn_phi_vc from anon, authenticated;

-- phiếu chi để gắn PO: của NCC trên PO (kt_v_ncc_phieu) hoặc tìm theo số phiếu / nội dung / người thụ hưởng (thanh toán hộ qua bên thứ 3)
create or replace function public.kt_po_chi_tim(p_phien text, p_ncc bigint, p_q text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'so_tien', c.so_tien, 'tt', c.trang_thai, 'nd', c.noi_dung, 'th', c.thu_huong_ten)
      order by coalesce(c.ngay_tt, c.ngay_de_nghi) desc, c.id desc)
    from (select c.* from kt_chi c where not c.da_xoa and c.trang_thai not in ('tu_choi', 'tu_choi_tt')
            and (case when q is null then exists (select 1 from kt_v_ncc_phieu v where v.bang = 'chi' and v.dong_id = c.id and v.ncc_id = p_ncc)
                      else (('PC' || lpad(c.id::text, 6, '0')) ilike '%' || q || '%' or c.noi_dung ilike '%' || q || '%' or c.thu_huong_ten ilike '%' || q || '%') end)
          order by coalesce(c.ngay_tt, c.ngay_de_nghi) desc, c.id desc limit 40) c), '[]');
end $$;

create or replace function public.kt_pn_phi_ds(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_object_agg(ma_pn, to_jsonb(x) - 'ma_pn') from kt_pn_phi_vc x), '{}');
end $$;
create or replace function public.kt_pn_phi_luu(p_phien text, p_ma_pn text, p_dong jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if not exists (select 1 from kt_kiot_nhap_hang where ma = p_ma_pn) then raise exception 'Không thấy phiếu nhập Kiot %', p_ma_pn; end if;
  insert into kt_pn_phi_vc (ma_pn, da_cong, so_tien, nguoi_nhan, giai_trinh, sua_boi)
  values (p_ma_pn, coalesce(nullif(p_dong->>'da_cong', ''), 'chua_ro'), nullif(p_dong->>'so_tien', '')::numeric, nullif(btrim(p_dong->>'nguoi_nhan'), ''), nullif(btrim(p_dong->>'giai_trinh'), ''), coalesce(u.ho_ten, u.ten_dang_nhap))
  on conflict (ma_pn) do update set da_cong = excluded.da_cong, so_tien = excluded.so_tien, nguoi_nhan = excluded.nguoi_nhan, giai_trinh = excluded.giai_trinh, sua_boi = excluded.sua_boi, sua_luc = now();
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_pn_phi_vc', null, 'sua', p_dong || jsonb_build_object('ma_pn', p_ma_pn));
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_po_chi_tim(text, bigint, text)', 'kt_pn_phi_ds(text)', 'kt_pn_phi_luu(text, text, jsonb)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;
