-- ════════════════════════════════════════════════════════════════════════════
-- HOÁ ĐƠN ĐẦU VÀO CÔNG TY THT từ MISA "Xử lý hóa đơn" (meInvoice Bot) + TỰ GHÉP với phiếu chi "chưa nhận HĐ" (14/10/2026)
-- Kế toán hỏi 14/10: "Mục chưa nhận hoá đơn là hệ thống tự lấy thông tin trên MISA chứ không lấy ở Google Sheet đúng không?" → anh: "xử lý luôn".
-- · Edge Function kt-meinvoice-bot (chỉ ĐỌC MISA) gọi kt_nap_misabot mỗi tháng: lưu vào kt_thue_hd (hkd 'CTY', chieu 'vao', MỖI HOÁ ĐƠN 1 DÒNG,
--   nguồn 'misabot:YYYY-MM', thay nguyên tháng mỗi lần nạp). ma = null để KHÔNG lẫn vào kho sổ thuế (mã hàng NCC khác mã sổ thuế).
-- · kt_ghep_hd_vao: phiếu chi đã thanh toán, có HĐ đỏ, chưa đánh dấu nhận ↔ hoá đơn đầu vào cùng SỐ TIỀN (lệch ≤ 1.000đ), ngày HĐ trong
--   [ngày trả − 45, ngày trả + 60], TÊN người bán gần với tên thụ hưởng hoặc nội dung / ghi chú phiếu chi
--   (tên thụ hưởng hay là nhân viên ứng tiền, không phải NCC). Chỉ TỰ GHÉP khi 1 phiếu ↔ đúng 1 hoá đơn và tên khớp ≥ 50%;
--   còn lại là GỢI Ý để kế toán bấm xác nhận. Ghép xong: phiếu chi hd_do_nhan = true, ngày nhận = ngày hoá đơn.
-- Monsieur Claude
-- ════════════════════════════════════════════════════════════════════════════

alter table public.kt_thue_hd add column if not exists ma_ngoai text;   -- InvoiceId của MISA (khoá ghép phiếu chi)
create index if not exists kt_thue_hd_ma_ngoai_idx on public.kt_thue_hd (ma_ngoai) where ma_ngoai is not null;

-- phiếu chi ↔ hoá đơn đầu vào đã ghép (tự động / kế toán xác nhận)
create table if not exists public.kt_chi_hd (
  chi_id bigint not null references public.kt_chi(id) on delete cascade,
  hd_ma text not null,                    -- kt_thue_hd.ma_ngoai
  so_hd text, ky_hieu text, ngay_hd date, ncc text, mst text, tong numeric,
  cach text not null check (cach in ('tu_dong', 'tay')),
  diem numeric, boi text, luc timestamptz not null default now(),
  primary key (chi_id, hd_ma));
create unique index if not exists kt_chi_hd_hd_idx on public.kt_chi_hd (hd_ma);
alter table public.kt_chi_hd enable row level security;
revoke all on public.kt_chi_hd from anon, authenticated;

create or replace function public.kt_nap_misabot(p_thang text, p_ds jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_thang !~ '^\d{4}-\d{2}$' then raise exception 'tháng sai: %', p_thang; end if;
  delete from kt_thue_hd where nguon = 'misabot:' || p_thang;
  insert into kt_thue_hd (hkd, chieu, so_hd, mau, ky_hieu, ngay, mst, nguoi_mua, ten, sl, thanh_tien, tien_thue, tong, ghi_chu, nguon, dong, ma_ngoai)
  select 'CTY', 'vao', x->>'so_hd', x->>'mau', x->>'ky_hieu', (x->>'ngay')::date, nullif(x->>'mst', ''), x->>'ncc', left(x->>'ten', 500),
         null, (x->>'thanh_tien')::numeric, (x->>'tien_thue')::numeric, (x->>'tong')::numeric,
         nullif(x->>'ghi_chu', ''), 'misabot:' || p_thang, nullif(x->>'so_dong', '')::int, x->>'id'
    from jsonb_array_elements(p_ds) x;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.kt_nap_misabot(text, jsonb) from public, anon, authenticated;
grant execute on function public.kt_nap_misabot(text, jsonb) to service_role;

-- bỏ dấu tiếng Việt + chữ thường (không dùng extension unaccent — Supabase dùng chung, không cài thêm)
create or replace function public.kt_bo_dau(p text) returns text language sql immutable as $$
  select lower(translate(coalesce(p, ''),
    'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ',
    'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD'));
$$;
-- tên → mảng từ khoá: bỏ cụm chung (công ty, TNHH, một thành viên, cổ phần, thương mại, dịch vụ...) rồi bỏ từ chung / từ < 3 chữ
create or replace function public.kt_tu_ten(p text) returns text[] language sql immutable as $$
  select coalesce(array_agg(distinct w), '{}') from unnest(regexp_split_to_array(
      regexp_replace(regexp_replace(' ' || kt_bo_dau(p) || ' ', '[^a-z0-9]+', ' ', 'g'),
        ' (cong ty|cty|tnhh|mot thanh vien|mtv|trach nhiem huu han|co phan|cp|thuong mai|tmdv|tm|dich vu|dv|san xuat|sx|xuat nhap khau|xnk|kinh doanh|ho kinh doanh|hkd|chi nhanh|cn|tap doan|dau tu|phat trien|giai phap|cong nghe|viet nam|vn|quoc te|tai|tinh|thanh pho|tp|ha noi)(?= )', '', 'g'),
      ' ')) w
   where length(w) >= 3 and w not in ('cong', 'nhanh', 'thanh', 'toan', 'tien', 'hang', 'hoa', 'don', 'phi', 'mua', 'ban', 'chi', 'cho', 'cua', 'cac', 'nam',
     'thang', 'ngay', 'lan', 'dot', 'cty', 'tnhh', 'van', 'tai', 'kho', 'thiet', 'may', 'moi', 'tong', 'nguyen', 'tran', 'pham', 'thi', 'duc', 'minh', 'mot', 'vien', 'benh', 'nhan', 'hai', 'phong');
$$;
create or replace function public.kt_diem_ten(a text, b text) returns numeric language sql immutable as $$
  select case when cardinality(x) = 0 or cardinality(y) = 0 then 0
              else round((select count(*) from unnest(x) w where w = any(y))::numeric / least(cardinality(x), cardinality(y)), 2) end
    from (select kt_tu_ten(a) x, kt_tu_ten(b) y) t;
$$;

-- cặp ứng viên phiếu chi ↔ hoá đơn đầu vào (chưa ghép)
create or replace function public.kt_ung_vien_hd_vao() returns table (chi_id bigint, hd_ma text, so_hd text, ky_hieu text, ngay_hd date, ncc text, mst text,
  tong numeric, diem numeric, n_hd int, n_chi int)
language sql stable security definer set search_path = public as $$
  with c as (select id, so_tien, ngay_tt, coalesce(thu_huong_ten, '') ten, coalesce(noi_dung, '') || ' ' || coalesce(ghi_chu, '') nd from kt_chi
              where not da_xoa and trang_thai = 'da_tt' and co_hd_do and not coalesce(hd_do_nhan, false)
                and not exists (select 1 from kt_chi_hd g where g.chi_id = kt_chi.id)),
       h as (select ma_ngoai, so_hd, ky_hieu, ngay, nguoi_mua ncc, mst, tong from kt_thue_hd
              where nguon like 'misabot:%' and ma_ngoai is not null and not exists (select 1 from kt_chi_hd g where g.hd_ma = kt_thue_hd.ma_ngoai)),
       p as (select c.id chi_id, h.*, greatest(kt_diem_ten(c.ten, h.ncc), kt_diem_ten(c.nd, h.ncc)) diem from c join h
               on abs(h.tong - c.so_tien) <= 1000 and h.ngay between c.ngay_tt - 45 and c.ngay_tt + 60)
  select chi_id, ma_ngoai, so_hd, ky_hieu, ngay, ncc, mst, tong, diem,
         (count(*) over (partition by chi_id))::int, (count(*) over (partition by ma_ngoai))::int from p;
$$;
revoke execute on function public.kt_ung_vien_hd_vao() from public, anon, authenticated;

-- tự ghép: 1 ↔ 1 và tên khớp ≥ 50%. p_ghi = false → chỉ đếm (chạy thử)
create or replace function public.kt_ghep_hd_vao(p_ghi boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int := 0; r record;
begin
  for r in select * from kt_ung_vien_hd_vao() where n_hd = 1 and n_chi = 1 and diem >= 0.5 loop
    n := n + 1;
    if p_ghi then
      insert into kt_chi_hd (chi_id, hd_ma, so_hd, ky_hieu, ngay_hd, ncc, mst, tong, cach, diem, boi)
        values (r.chi_id, r.hd_ma, r.so_hd, r.ky_hieu, r.ngay_hd, r.ncc, r.mst, r.tong, 'tu_dong', r.diem, 'Hệ thống') on conflict do nothing;
      update kt_chi set hd_do_nhan = true, ngay_nhan_hd = coalesce(ngay_nhan_hd, r.ngay_hd), sua_boi = 'Hệ thống', sua_luc = now() where id = r.chi_id;
    end if;
  end loop;
  if p_ghi and n > 0 then
    insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_chi', 'ghep_hd_vao', jsonb_build_object('so_phieu', n));
  end if;
  return jsonb_build_object('tu_ghep', n, 'goi_y', (select count(distinct chi_id) from kt_ung_vien_hd_vao() where not (n_hd = 1 and n_chi = 1 and diem >= 0.5)));
end $$;
revoke execute on function public.kt_ghep_hd_vao(boolean) from public, anon, authenticated;
grant execute on function public.kt_ghep_hd_vao(boolean) to service_role;

-- Trình duyệt: gợi ý hoá đơn cho các phiếu chi chưa nhận HĐ + hoá đơn đã ghép (quyền xem trang Chi)
create or replace function public.kt_hd_vao_goi_y(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'chi');
  return jsonb_build_object(
    'goi_y', (select coalesce(jsonb_agg(jsonb_build_object('chi_id', chi_id, 'hd_ma', hd_ma, 'so_hd', so_hd, 'ky_hieu', ky_hieu, 'ngay', ngay_hd,
        'ncc', ncc, 'mst', mst, 'tong', tong, 'diem', diem) order by chi_id, diem desc), '[]') from kt_ung_vien_hd_vao()),
    'da_ghep', (select coalesce(jsonb_agg(jsonb_build_object('chi_id', chi_id, 'hd_ma', hd_ma, 'so_hd', so_hd, 'ky_hieu', ky_hieu, 'ngay', ngay_hd,
        'ncc', ncc, 'mst', mst, 'tong', tong, 'cach', cach, 'boi', boi, 'luc', luc)), '[]') from kt_chi_hd),
    'keo_luc', (select max(keo_luc) from kt_thue_hd where nguon like 'misabot:%'));
end $$;

-- Kế toán xác nhận / bỏ ghép (quyền SỬA trang Chi)
create or replace function public.kt_ghep_hd_tay(p_phien text, p_chi bigint, p_hd text, p_bo boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; h record;
begin
  u := kt_chan(p_phien, 'chi', true);
  if p_bo then
    delete from kt_chi_hd where chi_id = p_chi and hd_ma = p_hd;
    if not exists (select 1 from kt_chi_hd where chi_id = p_chi) then
      update kt_chi set hd_do_nhan = false, ngay_nhan_hd = null, sua_boi = u.ho_ten, sua_luc = now() where id = p_chi;
    end if;
  else
    select ma_ngoai, so_hd, ky_hieu, ngay, nguoi_mua ncc, mst, tong into h from kt_thue_hd where ma_ngoai = p_hd and nguon like 'misabot:%' limit 1;
    if h.ma_ngoai is null then raise exception 'Không thấy hoá đơn này'; end if;
    if exists (select 1 from kt_chi_hd where hd_ma = p_hd and chi_id <> p_chi) then raise exception 'Hoá đơn này đã ghép với phiếu chi khác'; end if;
    insert into kt_chi_hd (chi_id, hd_ma, so_hd, ky_hieu, ngay_hd, ncc, mst, tong, cach, diem, boi)
      values (p_chi, h.ma_ngoai, h.so_hd, h.ky_hieu, h.ngay, h.ncc, h.mst, h.tong, 'tay', null, u.ho_ten) on conflict do nothing;
    update kt_chi set hd_do_nhan = true, ngay_nhan_hd = coalesce(ngay_nhan_hd, h.ngay), sua_boi = u.ho_ten, sua_luc = now() where id = p_chi and not da_xoa;
  end if;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu)
    values (u.ho_ten, 'kt_chi', case when p_bo then 'bo_ghep_hd_vao' else 'ghep_hd_vao_tay' end, jsonb_build_object('chi_id', p_chi, 'hd', p_hd));
end $$;
revoke execute on function public.kt_hd_vao_goi_y(text), public.kt_ghep_hd_tay(text, bigint, text, boolean) from public;
grant execute on function public.kt_hd_vao_goi_y(text), public.kt_ghep_hd_tay(text, bigint, text, boolean) to anon, authenticated;

-- danh sách HĐ: nhận nguồn MISA Xử lý hoá đơn
create or replace function public.kt_thue_hd_ds(p_phien text, p_tu date, p_den date, p_chieu text, p_hkd text default null, p_tim text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'hoa_don_thue');
  select coalesce(jsonb_agg(x order by x->>'ngay' desc, x->>'so_hd' desc), '[]') into r from (
    select jsonb_build_object('hkd', hkd, 'ky_hieu', ky_hieu, 'mau', max(mau), 'so_hd', so_hd, 'ngay', ngay, 'mst', max(mst), 'doi_tac', max(nguoi_mua),
      'thanh_tien', sum(thanh_tien), 'tien_thue', sum(coalesce(tien_thue, 0)), 'tong', sum(coalesce(tong, thanh_tien + coalesce(tien_thue, 0))),
      'so_dong', case when max(nguon) like 'misabot:%' then max(dong) else count(*) end, 'ten', max(ten), 'ghi_chu', max(ghi_chu),
      'nguon', case when max(nguon) like 'meinvoice:%' then 'MISA meInvoice' when max(nguon) like 'misabot:%' then 'MISA Xử lý HĐ' else '3TShop' end) x
    from kt_thue_hd
    where chieu = p_chieu and ngay between p_tu and p_den and (p_hkd is null or hkd = p_hkd)
      and (p_tim is null or so_hd ilike '%' || p_tim || '%' or nguoi_mua ilike '%' || p_tim || '%' or mst ilike '%' || p_tim || '%' or ten ilike '%' || p_tim || '%')
    group by hkd, ky_hieu, so_hd, ngay, ma_ngoai limit 2000) t;   -- ma_ngoai: HĐ đầu vào MISA khác NCC có thể trùng ký hiệu + số + ngày
  return r;
end $$;
