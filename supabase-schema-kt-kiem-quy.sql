-- KIỂM KÉT TIỀN MẶT CUỐI NGÀY (14/10/2026 — kế toán chị Jaycie: "két tiền mặt công ty có thủ quỹ cầm, cuối mỗi ngày chụp sổ up lên, dùng làm đối chiếu"). Monsieur Claude
-- Thủ quỹ nhập số đếm (có thể đếm theo mệnh giá) + ảnh sổ quỹ → app lưu số sổ sách cuối ngày đó, tính chênh lệch,
-- đồng thời ghi kt_ton_thuc_te (tồn thực tế) → Đối soát lỗi nhóm "Số dư sổ sách lệch số dư thực tế" tự báo nếu lệch.
-- Ảnh sổ: kho chứng từ (bang = 'kiem_quy'), quyền theo trang Sổ quỹ (dong_tien).
create table if not exists public.kt_kiem_quy (
  id bigserial primary key, tai_khoan_id int not null references kt_tai_khoan(id), ngay date not null,
  so_dem numeric not null, so_sach numeric, menh_gia jsonb, ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, unique (tai_khoan_id, ngay));
alter table public.kt_kiem_quy enable row level security;
revoke all on public.kt_kiem_quy from anon, authenticated;

-- chứng từ: thêm loại 'kiem_quy' (+ 'tam_ung' cho Tạm ứng & hoàn ứng)
alter table public.kt_chung_tu drop constraint if exists kt_chung_tu_bang_check;
alter table public.kt_chung_tu add constraint kt_chung_tu_bang_check check (bang = any (array['thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung']));
create or replace function public.kt_chan_dong(p_phien text, p_bang text, p_ids bigint[], p_ghi boolean) returns kt_nguoi_dung
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  -- 14/10/2026: ảnh kiểm két theo quyền trang Sổ quỹ (dong_tien)
  if kt_co_quyen(u, case p_bang when 'kiem_quy' then 'dong_tien' else p_bang end, p_ghi) then return u; end if;
  if p_bang = 'chi' and kt_co_quyen(u, 'chi_de_nghi') and cardinality(p_ids) > 0
     and not exists (select 1 from unnest(p_ids) i where not exists (
       select 1 from kt_chi c where c.id = i and c.tao_boi = u.ho_ten and not c.da_xoa)) then
    return u;
  end if;
  raise exception 'Tài khoản chưa được cấp quyền % trang này', case when p_ghi then 'sửa' else 'xem' end using errcode = '42501';
end $$;

-- số dư sổ sách của 1 tài khoản cuối 1 ngày
create or replace function public.kt_so_du_ngay(p_tk int, p_ngay date) returns numeric language sql stable set search_path = public as $$
  select tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau and b.ngay <= p_ngay), 0)
    from kt_tai_khoan tk where tk.id = p_tk;
$$;

create or replace function public.kt_luu_kiem_quy(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_tk int := (p_dong->>'tai_khoan_id')::int; v_ngay date := (p_dong->>'ngay')::date; v_dem numeric := (p_dong->>'so_dem')::numeric; v_id bigint; v_ss numeric;
begin
  u := kt_chan(p_phien, 'dong_tien', true);
  if v_tk is null or v_ngay is null or v_dem is null then raise exception 'Cần tài khoản, ngày, số đếm'; end if;
  if v_ngay > (now() at time zone 'Asia/Ho_Chi_Minh')::date then raise exception 'Không kiểm két cho ngày tương lai'; end if;
  v_ss := kt_so_du_ngay(v_tk, v_ngay);
  insert into kt_kiem_quy (tai_khoan_id, ngay, so_dem, so_sach, menh_gia, ghi_chu, tao_boi)
  values (v_tk, v_ngay, v_dem, v_ss, p_dong->'menh_gia', nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten)
  on conflict (tai_khoan_id, ngay) do update set so_dem = excluded.so_dem, so_sach = excluded.so_sach, menh_gia = excluded.menh_gia, ghi_chu = excluded.ghi_chu,
    sua_boi = u.ho_ten, sua_luc = now()
  returning id into v_id;
  -- tồn thực tế cho đối soát số dư
  insert into kt_ton_thuc_te (tai_khoan_id, ngay, so_tien, ghi_boi) values (v_tk, v_ngay, v_dem, u.ho_ten)
  on conflict (tai_khoan_id, ngay) do update set so_tien = excluded.so_tien, ghi_boi = excluded.ghi_boi, ghi_luc = now();
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_kiem_quy', v_id, 'ghi', jsonb_build_object('tk', v_tk, 'ngay', v_ngay, 'so_dem', v_dem, 'so_sach', v_ss));
  return v_id;
end $$;
revoke execute on function public.kt_luu_kiem_quy(text, jsonb) from public;
grant execute on function public.kt_luu_kiem_quy(text, jsonb) to anon, authenticated;

-- danh sách kiểm két trong kỳ (số sổ sách tính lại theo phiếu hiện tại — phiếu sửa muộn vẫn ra đúng chênh lệch)
create or replace function public.kt_ds_kiem_quy(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'dong_tien');
  return coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'tk', k.tai_khoan_id, 'ngay', k.ngay, 'so_dem', k.so_dem, 'so_sach', kt_so_du_ngay(k.tai_khoan_id, k.ngay),
      'so_sach_luc_kiem', k.so_sach, 'menh_gia', k.menh_gia, 'ghi_chu', k.ghi_chu, 'nguoi', coalesce(k.sua_boi, k.tao_boi), 'luc', coalesce(k.sua_luc, k.tao_luc),
      'so_anh', (select count(*) from kt_chung_tu c where c.bang = 'kiem_quy' and c.dong_id = k.id and not c.da_xoa)) order by k.ngay desc, k.tai_khoan_id)
    from kt_kiem_quy k where k.ngay between p_tu and p_den), '[]');
end $$;
revoke execute on function public.kt_ds_kiem_quy(text, date, date) from public;
grant execute on function public.kt_ds_kiem_quy(text, date, date) to anon, authenticated;
