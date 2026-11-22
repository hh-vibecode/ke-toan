-- ════════════════════════════════════════════════════════════════════════════
-- NHÂN SỰ PHỤ TRÁCH theo bộ phận + NGƯỜI PHỤ TRÁCH CÔNG NỢ (14/10/2026)
-- Anh: "cột Người phụ trách ở công nợ… cho t được phép thêm người, tạo 1 bộ phận trong phân quyền cài đặt, tham khảo bên phân quyền sale
-- của app MKT/Sale" (bảng Nhân sự Sale ở trang Phân quyền: thêm / sửa tên / cho nghỉ, tên ghi ĐÚNG như trên Kiot, gán Sale phụ trách bằng ô chọn).
--   · kt_nhan_su: người phụ trách, thuộc 1 BỘ PHẬN của danh mục (kt_don_vi la_bo_phan), kèm các tên trên Kiot (nếu khác tên chuẩn) · cho nghỉ = ẩn khỏi ô chọn
--   · kt_cong_no_pt: gán tay người phụ trách cho từng khách / NCC công nợ
--   · Người phụ trách hiển thị = gán tay > NV bán hoá đơn gần nhất trên Kiot (quy về tên chuẩn trong Nhân sự) > tên Kiot thô (trước 14/10 chỉ có cái này)
-- Quyền: thêm / sửa nhân sự = Phân quyền (sửa); gán phụ trách = trang Khách hàng / NCC (sửa). Monsieur Claude
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.kt_nhan_su (
  id serial primary key,
  ten text not null unique,
  bo_phan_id int references public.kt_don_vi(id),
  ten_kiot text[] not null default '{}',
  dang_lam boolean not null default true,
  ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now()
);
create table if not exists public.kt_cong_no_pt (
  loai text not null check (loai in ('kh', 'ncc')),
  dt_id bigint not null,
  nhan_su_id int not null references public.kt_nhan_su(id),
  gan_boi text, gan_luc timestamptz not null default now(),
  primary key (loai, dt_id)
);
alter table public.kt_nhan_su enable row level security;
alter table public.kt_cong_no_pt enable row level security;
revoke all on public.kt_nhan_su, public.kt_cong_no_pt from anon, authenticated;

-- danh sách nhân sự (ai đăng nhập cũng đọc được — dùng cho ô chọn) + tên NV bán trên Kiot 2026 CHƯA có trong danh sách (gợi ý thêm)
create or replace function public.kt_ds_nhan_su(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien);
  return jsonb_build_object(
    'ns', (select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'ten', n.ten, 'bo_phan_id', n.bo_phan_id, 'ten_kiot', n.ten_kiot, 'dang_lam', n.dang_lam, 'ghi_chu', n.ghi_chu,
              'so_kh', (select count(*) from kt_cong_no_pt p where p.nhan_su_id = n.id and p.loai = 'kh'),
              'so_ncc', (select count(*) from kt_cong_no_pt p where p.nhan_su_id = n.id and p.loai = 'ncc')) order by n.ten), '[]') from kt_nhan_su n),
    'kiot', (select coalesce(jsonb_agg(jsonb_build_object('ten', nv, 'so_hd', so, 'cn', cn) order by so desc), '[]') from (
        select h.nv_ban nv, count(*) so, mode() within group (order by h.chi_nhanh) cn from kt_kiot_hoa_don h
         where h.ngay >= '2026-01-01' and h.trang_thai = 1 and coalesce(btrim(h.nv_ban), '') <> ''
           and not exists (select 1 from kt_nhan_su n where lower(btrim(h.nv_ban)) = lower(n.ten) or lower(btrim(h.nv_ban)) = any(array(select lower(btrim(x)) from unnest(n.ten_kiot) x)))
         group by 1) x));
end $$;

create or replace function public.kt_luu_nhan_su(p_phien text, p_dong jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung := kt_chan(p_phien, 'phan_quyen', true); v_id int := (p_dong->>'id')::int; v_ten text := btrim(regexp_replace(coalesce(p_dong->>'ten', ''), '\s+', ' ', 'g'));
  v_kt text[] := coalesce(array(select btrim(x) from jsonb_array_elements_text(coalesce(p_dong->'ten_kiot', '[]'::jsonb)) x where btrim(x) <> ''), '{}');
begin
  if length(v_ten) < 2 then raise exception 'Nhập họ tên'; end if;
  if (p_dong->>'bo_phan_id') is not null and not exists (select 1 from kt_don_vi where id = (p_dong->>'bo_phan_id')::int and la_bo_phan) then raise exception 'Bộ phận không hợp lệ'; end if;
  if exists (select 1 from kt_nhan_su where lower(ten) = lower(v_ten) and id is distinct from v_id) then raise exception 'Đã có "%" trong danh sách', v_ten; end if;
  if v_id is null then
    insert into kt_nhan_su (ten, bo_phan_id, ten_kiot, ghi_chu, tao_boi) values (v_ten, (p_dong->>'bo_phan_id')::int, v_kt, nullif(btrim(p_dong->>'ghi_chu'), ''), u.ho_ten) returning id into v_id;
  else
    update kt_nhan_su set ten = v_ten, bo_phan_id = (p_dong->>'bo_phan_id')::int, ten_kiot = v_kt, ghi_chu = nullif(btrim(p_dong->>'ghi_chu'), ''),
      dang_lam = coalesce((p_dong->>'dang_lam')::boolean, dang_lam) where id = v_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_nhan_su', v_id, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

-- gán / bỏ gán người phụ trách cho nhiều khách / NCC (p_nhan_su_id null = bỏ gán, về mặc định theo Kiot)
create or replace function public.kt_gan_phu_trach(p_phien text, p_loai text, p_ids bigint[], p_nhan_su_id int) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; n int;
begin
  if p_loai not in ('kh', 'ncc') then raise exception 'Loại không hợp lệ'; end if;
  u := kt_chan(p_phien, case when p_loai = 'ncc' then 'ncc' else 'khach_hang' end, true);
  if p_nhan_su_id is null then
    delete from kt_cong_no_pt where loai = p_loai and dt_id = any(p_ids); get diagnostics n = row_count;
  else
    if not exists (select 1 from kt_nhan_su where id = p_nhan_su_id and dang_lam) then raise exception 'Nhân sự không có hoặc đã nghỉ'; end if;
    insert into kt_cong_no_pt (loai, dt_id, nhan_su_id, gan_boi) select p_loai, x, p_nhan_su_id, u.ho_ten from unnest(p_ids) x
      on conflict (loai, dt_id) do update set nhan_su_id = excluded.nhan_su_id, gan_boi = excluded.gan_boi, gan_luc = now();
    get diagnostics n = row_count;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_cong_no_pt', null, 'gan_phu_trach', jsonb_build_object('loai', p_loai, 'ids', p_ids, 'nhan_su_id', p_nhan_su_id));
  return n;
end $$;

revoke execute on function public.kt_ds_nhan_su(text), public.kt_luu_nhan_su(text, jsonb), public.kt_gan_phu_trach(text, text, bigint[], int) from public;
grant execute on function public.kt_ds_nhan_su(text), public.kt_luu_nhan_su(text, jsonb), public.kt_gan_phu_trach(text, text, bigint[], int) to anon, authenticated;

-- công nợ: thêm người phụ trách theo Nhân sự (định nghĩa đầy đủ thay bản trong supabase-schema-kt-cong-no-kiot.sql)
CREATE OR REPLACE FUNCTION public.kt_cong_no_dt(p_phien text, p_loai text DEFAULT 'kh'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; r jsonb; han int;
begin
  perform kt_chan(p_phien, case when p_loai = 'ncc' then 'ncc' else 'khach_hang' end);
  select coalesce(nullif(gia_tri, '')::int, 30) into han from kt_cai_dat where khoa = case when p_loai = 'ncc' then 'han_no_ncc_ngay' else 'han_no_kh_ngay' end;
  han := coalesce(han, 30);
  with dt as (
    select id, ma, ten, sdt, cong_no no, tong_mua tong from kt_kiot_khach where p_loai = 'kh' and cong_no <> 0
    union all select id, ma, ten, sdt, cong_no, tong_nhap from kt_kiot_ncc where p_loai = 'ncc' and cong_no <> 0),
  ct as (   -- hoá đơn bán (khách) / phiếu nhập (NCC) đã hoàn thành
    select khach_id dt_id, id, ngay, chi_nhanh, tong, nv_ban nv from kt_kiot_hoa_don where p_loai = 'kh' and trang_thai = 1 and tong > 0
    union all select ncc_id, id, ngay, chi_nhanh, tong, null from kt_kiot_nhap_hang where p_loai = 'ncc' and trang_thai = 3 and tong > 0),
  lk as (select ct.*, d.no, sum(ct.tong) over (partition by ct.dt_id order by ct.ngay desc, ct.id desc) cum
           from ct join dt d on d.id = ct.dt_id where d.no > 0),
  pb as (select dt_id, chi_nhanh, (ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, tong, least(tong, no - (cum - tong)) phan from lk where cum - tong < no),
  g as (select dt_id, sum(phan) da_gan, sum(tong) tong_ct, min(ngay) cu_nhat, count(*) so_ct, (array_agg(chi_nhanh order by ngay desc))[1] cn,
          sum(phan) filter (where hom - ngay <= 30) b1, sum(phan) filter (where hom - ngay between 31 and 60) b2,
          sum(phan) filter (where hom - ngay between 61 and 90) b3, sum(phan) filter (where hom - ngay > 90) b4
          from pb group by 1),
  cn_cuoi as (select distinct on (dt_id) dt_id, chi_nhanh, nv from ct order by dt_id, ngay desc),
  -- người phụ trách (14/10/2026): gán tay (kt_cong_no_pt) > NV bán phiếu gần nhất quy về tên trong Nhân sự (tên hoặc tên trên Kiot) > tên Kiot thô
  ns as (select id, ten, bo_phan_id, array(select lower(btrim(x)) from unnest(ten_kiot || ten) x) ten_kt from kt_nhan_su)
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'ma', d.ma, 'ten', d.ten, 'sdt', d.sdt, 'no', d.no, 'tong', d.tong,
      'cn', coalesce(g.cn, c.chi_nhanh), 'so_ct', coalesce(g.so_ct, 0), 'cu_nhat', g.cu_nhat, 'tuoi', hom - g.cu_nhat,
      'b1', coalesce(g.b1, 0), 'b2', coalesce(g.b2, 0), 'b3', coalesce(g.b3, 0), 'b4', coalesce(g.b4, 0),
      'truoc_2026', greatest(d.no - coalesce(g.da_gan, 0), 0), 'nv', coalesce(ng.ten, nk.ten, c.nv), 'nv_id', coalesce(ng.id, nk.id), 'nv_gan', pt.nhan_su_id is not null, 'nv_kiot', c.nv, 'han', han,
      -- tổng các chứng từ đang tính nợ (+ phần nợ trước 2026) · đã thanh toán = tổng − còn nợ · đến hạn = chứng từ nợ cũ nhất + số ngày được nợ
      'tong_ct', coalesce(g.tong_ct, 0) + greatest(d.no - coalesce(g.da_gan, 0), 0), 'den_han', g.cu_nhat + han,
      'qua_han', case when d.no > 0 and g.cu_nhat is not null then greatest(hom - (g.cu_nhat + han), 0) end) order by d.no desc), '[]') into r
    from dt d left join g on g.dt_id = d.id left join cn_cuoi c on c.dt_id = d.id
    left join kt_cong_no_pt pt on pt.loai = p_loai and pt.dt_id = d.id left join ns ng on ng.id = pt.nhan_su_id
    left join lateral (select n.id, n.ten from ns n where c.nv is not null and lower(btrim(c.nv)) = any(n.ten_kt) limit 1) nk on true;
  return r;
end $function$;
