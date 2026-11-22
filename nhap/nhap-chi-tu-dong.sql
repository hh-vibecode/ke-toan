-- ⚠ NHÁP — CHƯA CHẠY trên CSDL (anh 14/10: "gợi ý cách xử lý thôi"). Chỉ chạy khi anh chọn hướng. Monsieur Claude
-- ════════════════════════════════════════════════════════════════════════════
-- CHI TỰ ĐỘNG & THẺ (14/10/2026) — kế toán (chị Jaycie): "có 1 số khoản tự động của ngân hàng hoặc chi bằng thẻ visa, không đi theo luồng phải làm phiếu,
-- bổ sung luồng để nó gợi ý cách kê khai đủ chi phí".
--   1. Khoản ngân hàng TỰ TRỪ định kỳ (phí QLTK, SMS, phí chuyển lương, phí vay…): mẫu kt_chi_dinh_ky → mỗi tháng báo khoản chưa kê khai,
--      bấm 1 nút ghi phiếu chi ĐÃ THANH TOÁN (nguồn 'tu_dong', không qua đề nghị / duyệt — anh chốt 09/10: chi đã thanh toán luôn không cần GĐ).
--      Gợi ý mẫu từ lịch sử: các phiếu phí ngân hàng (sheet cũ ghi thẳng từ sao kê) lặp lại ≥ 2 tháng.
--   2. THẺ TÍN DỤNG (Visa business): phiếu "trả sao kê thẻ" đang ghi cả cục loại Tài chính → mất chi phí thật trong P&L.
--      TÁCH phiếu theo loại chi thật: phiếu gốc giữ id / ngày / tài khoản (thành dòng đầu), các dòng sau là phiếu mới cùng ngày / tài khoản, tach_tu = id gốc.
--      Tổng tiền không đổi → dòng tiền, số dư không đổi.
--   3. ĐỐI CHIẾU SỐ DƯ SAO KÊ cuối tháng (kt_ton_thuc_te): lệch sổ sách → gợi ý còn khoản tự trừ / thẻ chưa kê.
-- Quyền: xem = trang Chi; ghi (kê khai, mẫu, tách) = chi_duyet (kế toán). Monsieur Claude
-- ════════════════════════════════════════════════════════════════════════════

alter table public.kt_chi drop constraint if exists kt_chi_nguon_check;
alter table public.kt_chi add constraint kt_chi_nguon_check check (nguon = any (array['app', 'sheet_cu', 'kiot', 'phieu', 'tu_dong']));
alter table public.kt_chi add column if not exists tach_tu bigint references public.kt_chi(id);
alter table public.kt_chi add column if not exists dinh_ky_id int;

create table if not exists public.kt_chi_dinh_ky (
  id serial primary key,
  ten text not null,
  tai_khoan_id int not null references public.kt_tai_khoan(id),
  loai_id int not null references public.kt_loai(id),
  don_vi_id int references public.kt_don_vi(id),
  so_tien numeric,                 -- dự kiến (null = mỗi tháng một khác)
  ngay int check (ngay between 1 and 31),
  mau text,                        -- từ khoá nhận ra phiếu đã có trong tháng (không phân biệt hoa thường)
  hoat_dong boolean not null default true,
  tao_boi text, tao_luc timestamptz not null default now()
);
alter table public.kt_chi_dinh_ky enable row level security;
revoke all on public.kt_chi_dinh_ky from anon, authenticated;

-- dữ liệu trang Chi tự động & thẻ cho tháng p_thang ('YYYY-MM')
create or replace function public.kt_ds_chi_tu_dong(p_phien text, p_thang text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u kt_nguoi_dung; v_tu date := (p_thang || '-01')::date; v_den date := ((p_thang || '-01')::date + interval '1 month' - interval '1 day')::date;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'chi') or kt_co_quyen(u, 'chi_duyet')) then raise exception 'Tài khoản chưa được cấp quyền xem chi' using errcode = '42501'; end if;
  return jsonb_build_object(
    'mau', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'ten', m.ten, 'tk', m.tai_khoan_id, 'loai', m.loai_id, 'dv', m.don_vi_id, 'so_tien', m.so_tien,
               'ngay', m.ngay, 'mau', m.mau, 'hoat_dong', m.hoat_dong,
               'phieu', (select jsonb_agg(jsonb_build_object('id', c.id, 'ngay', c.ngay_tt, 'tien', c.so_tien, 'nd', c.noi_dung)) from kt_chi c
                          where not c.da_xoa and c.trang_thai = 'da_tt' and c.tai_khoan_id = m.tai_khoan_id and c.ngay_tt between v_tu and v_den
                            and (c.dinh_ky_id = m.id or (m.mau is not null and m.mau <> '' and c.noi_dung ~* m.mau)))) order by m.ngay nulls last, m.id), '[]')
             from kt_chi_dinh_ky m where m.hoat_dong),
    -- gợi ý mẫu: phiếu phí ngân hàng / tự trừ trong 2026 lặp lại ≥ 2 tháng cùng tài khoản + loại + nội dung (bỏ số)
    'goi_y', (select coalesce(jsonb_agg(x order by (x->>'so_thang')::int desc), '[]') from (
        select jsonb_build_object('tk', tai_khoan_id, 'loai', loai_id, 'mau', k, 'vd', min(noi_dung), 'so_thang', count(distinct to_char(ngay_tt, 'YYYY-MM')),
               'tb', round(avg(so_tien)), 'lan', count(*)) x
          from (select c.*, left(btrim(regexp_replace(regexp_replace(upper(unaccent_vn(c.noi_dung)), '[0-9][0-9.,/:]*', ' ', 'g'), '\s+', ' ', 'g')), 40) k
                  from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt >= date '2026-01-01' and c.tai_khoan_id is not null
                   and c.noi_dung ~* '(thu ph[ií]|ph[ií] (qu[aả]n l[yý]|sms|chuy[eể]n|d[iị]ch v[uụ])|qltk|sms ?banking|^[a-z][0-9]{3}[_ ])') z
         where not exists (select 1 from kt_chi_dinh_ky m where m.hoat_dong and m.tai_khoan_id = z.tai_khoan_id and m.loai_id = z.loai_id and m.mau is not null and z.noi_dung ~* m.mau)
         group by tai_khoan_id, loai_id, k having count(distinct to_char(ngay_tt, 'YYYY-MM')) >= 2 limit 30) g),
    -- phiếu trả sao kê thẻ trong tháng (luật "Trả thẻ tín dụng" hoặc nội dung visa / sao kê) + đã tách chưa
    'the', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ngay', c.ngay_tt, 'tk', c.tai_khoan_id, 'loai', c.loai_id, 'tien', c.so_tien, 'nd', c.noi_dung,
               'con', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'loai', d.loai_id, 'tien', d.so_tien, 'nd', d.noi_dung) order by d.id), '[]') from kt_chi d where d.tach_tu = c.id and not d.da_xoa)) order by c.ngay_tt), '[]')
             from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.tach_tu is null and c.ngay_tt between v_tu and v_den
              and (c.noi_dung ~* (select string_agg(mau, '|') from kt_luat_loai_chi where hoat_dong and ten ilike '%thẻ tín dụng%')
                   or c.noi_dung ~* 'visa|th[ẻe] t[íi]n d[ụu]ng|master ?card')),
    -- số dư cuối tháng: sổ sách vs sao kê (nhập ở kt_ton_thuc_te ngày cuối tháng)
    'so_du', (select coalesce(jsonb_agg(jsonb_build_object('tk', tk.id, 'ten', tk.ten, 'loai', tk.loai,
               'so_sach', tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau and b.ngay <= v_den), 0),
               'sao_ke', (select so_tien from kt_ton_thuc_te t where t.tai_khoan_id = tk.id and t.ngay = v_den)) order by tk.thu_tu, tk.id), '[]')
             from kt_tai_khoan tk where tk.hoat_dong and tk.loai in ('ngan_hang', 'khac') and tk.ngay_ton_dau <= v_den),
    'da_ke', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ngay', c.ngay_tt, 'tk', c.tai_khoan_id, 'loai', c.loai_id, 'tien', c.so_tien, 'nd', c.noi_dung,
               'tach_tu', c.tach_tu, 'dinh_ky', c.dinh_ky_id, 'boi', c.tao_boi) order by c.ngay_tt desc, c.id desc), '[]')
             from kt_chi c where not c.da_xoa and c.nguon = 'tu_dong' and c.ngay_tt between v_tu and v_den));
end $$;

-- lưu mẫu định kỳ (id null = thêm; hoat_dong false = bỏ)
create or replace function public.kt_luu_chi_dinh_ky(p_phien text, p_dong jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung := kt_chan(p_phien, 'chi_duyet'); v_id int := (p_dong->>'id')::int;
begin
  if coalesce(btrim(p_dong->>'ten'), '') = '' or (p_dong->>'tai_khoan_id') is null or (p_dong->>'loai_id') is null then raise exception 'Cần tên, tài khoản, loại chi'; end if;
  if nullif(p_dong->>'mau', '') is not null then perform '' ~* (p_dong->>'mau'); end if;   -- từ khoá sai cú pháp → báo lỗi ngay
  if v_id is null then
    insert into kt_chi_dinh_ky (ten, tai_khoan_id, loai_id, don_vi_id, so_tien, ngay, mau, tao_boi)
    values (btrim(p_dong->>'ten'), (p_dong->>'tai_khoan_id')::int, (p_dong->>'loai_id')::int, nullif(p_dong->>'don_vi_id', '')::int,
            nullif(p_dong->>'so_tien', '')::numeric, nullif(p_dong->>'ngay', '')::int, nullif(btrim(p_dong->>'mau'), ''), u.ho_ten) returning id into v_id;
  else
    update kt_chi_dinh_ky set ten = btrim(p_dong->>'ten'), tai_khoan_id = (p_dong->>'tai_khoan_id')::int, loai_id = (p_dong->>'loai_id')::int,
      don_vi_id = nullif(p_dong->>'don_vi_id', '')::int, so_tien = nullif(p_dong->>'so_tien', '')::numeric, ngay = nullif(p_dong->>'ngay', '')::int,
      mau = nullif(btrim(p_dong->>'mau'), ''), hoat_dong = coalesce((p_dong->>'hoat_dong')::boolean, hoat_dong) where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi_dinh_ky', v_id, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

-- kê khai 1 khoản tự trừ / thẻ → phiếu chi ĐÃ THANH TOÁN, nguồn 'tu_dong'
create or replace function public.kt_ke_khai_tu_dong(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung := kt_chan(p_phien, 'chi_duyet'); v_id bigint; v_tien numeric := (p_dong->>'so_tien')::numeric; v_ngay date := (p_dong->>'ngay')::date;
  v_dv int := nullif(p_dong->>'don_vi_id', '')::int; v_mau int := nullif(p_dong->>'dinh_ky_id', '')::int;
begin
  if v_tien is null or v_tien <= 0 then raise exception 'Số tiền không hợp lệ'; end if;
  if v_ngay is null or (p_dong->>'tai_khoan_id') is null or (p_dong->>'loai_id') is null or coalesce(btrim(p_dong->>'noi_dung'), '') = '' then
    raise exception 'Cần ngày, tài khoản, loại chi, nội dung'; end if;
  if v_mau is not null and exists (select 1 from kt_chi where dinh_ky_id = v_mau and not da_xoa and to_char(ngay_tt, 'YYYY-MM') = to_char(v_ngay, 'YYYY-MM')) then
    raise exception 'Khoản định kỳ này đã kê khai trong tháng'; end if;
  insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, noi_dung, ngay_su_dung, so_tien, phan_bo, co_hd_do, ghi_chu, trang_thai, ngay_tt, tai_khoan_id, loai_id,
    kiot, kiot_ly_do, nguon, tao_boi, nguoi_duyet, duyet_luc, dinh_ky_id)
  values (v_ngay, u.ho_ten, btrim(p_dong->>'noi_dung'), v_ngay, v_tien, case when v_dv is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('don_vi_id', v_dv, 'so_tien', v_tien)) end,
    coalesce((p_dong->>'co_hd_do')::boolean, false), nullif(btrim(p_dong->>'ghi_chu'), ''), 'da_tt', v_ngay, (p_dong->>'tai_khoan_id')::int, (p_dong->>'loai_id')::int,
    'khong_tao', 'Ngân hàng tự trừ / chi bằng thẻ — không qua Kiot', 'tu_dong', u.ho_ten, u.ho_ten, now(), v_mau)
  returning id into v_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', v_id, 'ke_khai_tu_dong', p_dong);
  return v_id;
end $$;

-- tách 1 phiếu (trả sao kê thẻ) theo loại chi thật: p_dong = [{loai_id, so_tien, noi_dung, don_vi_id}] — tổng phải bằng phiếu gốc
create or replace function public.kt_tach_phieu_chi(p_phien text, p_id bigint, p_dong jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung := kt_chan(p_phien, 'chi_duyet'); c kt_chi; v_tong numeric; x jsonb; i int := 0; v_dv int;
begin
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu %', p_id; end if;
  if c.trang_thai <> 'da_tt' then raise exception 'Chỉ tách phiếu đã thanh toán'; end if;
  if c.tach_tu is not null or exists (select 1 from kt_chi where tach_tu = p_id and not da_xoa) then raise exception 'Phiếu này đã tách rồi'; end if;
  if jsonb_typeof(p_dong) <> 'array' or jsonb_array_length(p_dong) < 2 then raise exception 'Cần ít nhất 2 dòng'; end if;
  select sum((e->>'so_tien')::numeric) into v_tong from jsonb_array_elements(p_dong) e;
  if v_tong <> c.so_tien then raise exception 'Tổng các dòng (%) phải bằng số tiền phiếu (%)', v_tong, c.so_tien; end if;
  if exists (select 1 from jsonb_array_elements(p_dong) e where (e->>'so_tien')::numeric <= 0 or (e->>'loai_id') is null or coalesce(btrim(e->>'noi_dung'), '') = '') then
    raise exception 'Mỗi dòng cần loại chi, số tiền > 0, nội dung'; end if;
  for x in select * from jsonb_array_elements(p_dong) loop
    i := i + 1; v_dv := nullif(x->>'don_vi_id', '')::int;
    if i = 1 then
      update kt_chi set loai_id = (x->>'loai_id')::int, so_tien = (x->>'so_tien')::numeric, noi_dung = btrim(x->>'noi_dung'),
        phan_bo = case when v_dv is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('don_vi_id', v_dv, 'so_tien', (x->>'so_tien')::numeric)) end,
        phan_bo_thang = null, ghi_chu = concat_ws(' ', ghi_chu, '[Tách sao kê thẻ: ' || jsonb_array_length(p_dong) || ' dòng, gốc ' || replace(to_char(c.so_tien, 'FM999G999G999G999'), ',', '.') || ' đ — "' || left(c.noi_dung, 80) || '"]'),
        sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
    else
      insert into kt_chi (ngay_de_nghi, nguoi_de_nghi, bo_phan_id, noi_dung, ngay_su_dung, so_tien, phan_bo, co_hd_do, trang_thai, ngay_tt, tai_khoan_id, loai_id,
        kiot, kiot_ly_do, nguon, tao_boi, nguoi_duyet, duyet_luc, kiem_boi, kiem_luc, tach_tu)
      values (c.ngay_de_nghi, c.nguoi_de_nghi, c.bo_phan_id, btrim(x->>'noi_dung'), c.ngay_su_dung, (x->>'so_tien')::numeric,
        case when v_dv is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('don_vi_id', v_dv, 'so_tien', (x->>'so_tien')::numeric)) end,
        false, 'da_tt', c.ngay_tt, c.tai_khoan_id, (x->>'loai_id')::int, c.kiot, c.kiot_ly_do, 'tu_dong', u.ho_ten, c.nguoi_duyet, c.duyet_luc, c.kiem_boi, c.kiem_luc, p_id);
    end if;
  end loop;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'tach_phieu', jsonb_build_object('goc', to_jsonb(c), 'dong', p_dong));
  return i;
end $$;

revoke execute on function public.kt_ds_chi_tu_dong(text, text), public.kt_luu_chi_dinh_ky(text, jsonb), public.kt_ke_khai_tu_dong(text, jsonb), public.kt_tach_phieu_chi(text, bigint, jsonb) from public;
grant execute on function public.kt_ds_chi_tu_dong(text, text), public.kt_luu_chi_dinh_ky(text, jsonb), public.kt_ke_khai_tu_dong(text, jsonb), public.kt_tach_phieu_chi(text, bigint, jsonb) to anon, authenticated;
