-- HỒ SƠ NHÀ CUNG CẤP & CHỨNG TỪ (29/10/2026 — anh chốt cùng ngày: 1 NCC = 1 bộ hồ sơ, giao diện không dùng kt_ho_so; chứng từ chung của NCC: kt_chung_tu bang 'ncc'; anh: "khoản thu chi từ cùng 1 NCC dồn hết về 1 kho, có NCC thanh toán tới 10 lần"). Monsieur Claude
-- Cấu trúc: NCC (mã duy nhất) → nhiều Hồ sơ gốc (hợp đồng / đơn hàng / kỳ đối soát) → nhiều phiếu chi / thu (từng đợt) → chứng từ.
-- • kt_ncc: NCC Kiot tự đồng bộ (kiot_id) + NCC tạo trên app (nước ngoài, trung gian, dịch vụ). stk = số tài khoản (chỉ số) đã biết của NCC.
-- • kt_ho_so: hồ sơ gốc của 1 NCC; chứng từ chung của hồ sơ lưu kt_chung_tu bang = 'ho_so'.
-- • kt_ncc_gan: phiếu (chi / thu) thuộc NCC nào, hồ sơ nào. Dòng ncc_id null = kế toán đánh dấu "không thuộc NCC" (bỏ gợi ý).
--   Phiếu chi chưa gán mà số TK thụ hưởng trùng số TK đã lưu của NCC → tự vào NCC đó (cach = 'stk').
-- • Bước 4 của phiếu (sau chi tiền): kế toán chọn NCC + hồ sơ ngay trên cửa sổ phiếu (kt_phieu_ho_so / kt_ncc_gan).
-- Quyền: trang 'ncc' (Nhà cung cấp). Gán từ cửa sổ phiếu chi: quyền ncc (sửa) hoặc người xác nhận phiếu chi (chi_duyet).

create table if not exists public.kt_ncc (
  id bigserial primary key, kiot_id bigint unique, ma text, ten text not null,
  loai text not null default 'noi_dia' check (loai in ('noi_dia','nuoc_ngoai','trung_gian','dich_vu')),
  mst text, sdt text, dia_chi text, lien_he text, stk text[] not null default '{}', ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, da_xoa boolean not null default false);
create table if not exists public.kt_ho_so (
  id bigserial primary key, ncc_id bigint not null references kt_ncc(id), ten text not null,
  loai text not null default 'hop_dong' check (loai in ('hop_dong','don_hang','ky_doi_soat','khac')),
  so_hd text, ngay date, gia_tri numeric, trang_thai text not null default 'mo' check (trang_thai in ('mo','xong')), ghi_chu text,
  tao_boi text, tao_luc timestamptz not null default now(), sua_boi text, sua_luc timestamptz, da_xoa boolean not null default false);
create table if not exists public.kt_ncc_gan (
  id bigserial primary key, bang text not null check (bang in ('chi','thu')), dong_id bigint not null,
  ncc_id bigint references kt_ncc(id), ho_so_id bigint references kt_ho_so(id), tao_boi text, tao_luc timestamptz not null default now(),
  unique (bang, dong_id));
create index if not exists kt_ncc_gan_ncc on public.kt_ncc_gan (ncc_id);
create index if not exists kt_ho_so_ncc on public.kt_ho_so (ncc_id);
alter table public.kt_ncc enable row level security; alter table public.kt_ho_so enable row level security; alter table public.kt_ncc_gan enable row level security;
revoke all on public.kt_ncc, public.kt_ho_so, public.kt_ncc_gan from public, anon, authenticated;

-- bỏ dấu: dùng kt_bo_dau(text) có sẵn (supabase-schema-kt-hd-vao.sql)
-- tên "lõi" để so khớp: bỏ dấu, bỏ chữ chung (công ty, TNHH, NCC, TQ...), bỏ ký tự lạ
create or replace function public.kt_ncc_ten_loi(t text) returns text language sql immutable as $$
  select array_to_string(array(select w from unnest(string_to_array(
    regexp_replace(regexp_replace(kt_bo_dau(t), '[^a-z0-9]+', ' ', 'g'),
      '\m(cong ty|co phan|thuong mai|dich vu|san xuat|ho kinh doanh|cua hang|trung quoc|xuat nhap khau|mot thanh vien|viet nam)\M', ' ', 'g'), ' ')) with ordinality z(w, i)
    where w <> '' and w not in ('cty','tnhh','cp','mtv','tm','dv','tmdv','xnk','sx','hkd','ncc','tq','kb','vn') order by i), ' ')
$$;
create or replace function public.kt_so_tk(t text) returns text language sql immutable as $$ select nullif(regexp_replace(coalesce(t, ''), '\D', '', 'g'), '') $$;

-- phiếu chi / thu đang thuộc NCC nào (gán tay, hoặc tự theo số TK)
create or replace view public.kt_v_ncc_phieu as
  select 'chi'::text bang, c.id dong_id, coalesce(g.ncc_id, s.ncc_id) ncc_id, g.ho_so_id, case when g.id is not null then 'gan' else 'stk' end cach
    from kt_chi c left join kt_ncc_gan g on g.bang = 'chi' and g.dong_id = c.id
    left join lateral (select n.id ncc_id from kt_ncc n where g.id is null and not n.da_xoa and kt_so_tk(c.thu_huong_stk) = any (n.stk) order by n.id limit 1) s on true
   where not c.da_xoa and coalesce(g.ncc_id, s.ncc_id) is not null
  union all
  select 'thu', t.id, g.ncc_id, g.ho_so_id, 'gan' from kt_thu t join kt_ncc_gan g on g.bang = 'thu' and g.dong_id = t.id where not t.da_xoa and g.ncc_id is not null;
revoke all on public.kt_v_ncc_phieu from public, anon, authenticated;

-- đồng bộ danh mục NCC Kiot → kt_ncc (thêm NCC mới, cập nhật mã / tên / SĐT đổi trên Kiot)
create or replace function public.kt_ncc_dong_bo() returns void language plpgsql security definer set search_path = public as $$
begin
  insert into kt_ncc (kiot_id, ma, ten, sdt, loai, tao_boi)
  select k.id, k.ma, k.ten, k.sdt, case when kt_bo_dau(k.ten) ~ '(^|[^a-z])(tq|trung quoc)([^a-z]|$)' then 'nuoc_ngoai' else 'noi_dia' end, 'Hệ thống'
    from kt_kiot_ncc k where not exists (select 1 from kt_ncc n where n.kiot_id = k.id);
  update kt_ncc n set ma = k.ma, ten = k.ten, sdt = coalesce(k.sdt, n.sdt)
    from kt_kiot_ncc k where k.id = n.kiot_id and (n.ma is distinct from k.ma or n.ten is distinct from k.ten);
end $$;
revoke all on function public.kt_ncc_dong_bo() from public, anon, authenticated;

-- tổng hợp 1 NCC (dùng cho danh sách + chi tiết)
create or replace function public.kt_ncc_so(p_ncc bigint) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'so_phieu', count(*),
    'da_tra', coalesce(sum(c.so_tien) filter (where p.bang = 'chi' and c.trang_thai = 'da_tt'), 0),
    'cho_tra', coalesce(sum(c.so_tien) filter (where p.bang = 'chi' and c.trang_thai in ('cho_duyet','cho_gd','cho_tt')), 0),
    'da_thu', coalesce(sum(t.so_tien) filter (where p.bang = 'thu' and t.trang_thai = 'da_duyet'), 0),
    'lan_cuoi', max(coalesce(c.ngay_tt, c.ngay_de_nghi, t.ngay)))
  from kt_v_ncc_phieu p left join kt_chi c on p.bang = 'chi' and c.id = p.dong_id left join kt_thu t on p.bang = 'thu' and t.id = p.dong_id
  where p.ncc_id = p_ncc
$$;
revoke all on function public.kt_ncc_so(bigint) from public, anon, authenticated;

drop function if exists public.kt_ds_ncc(text);
-- p_tu / p_den: kỳ đang chọn — chỉ dùng đếm phiếu chờ phân (khớp tab Chờ phân hồ sơ)
create or replace function public.kt_ds_ncc(p_phien text, p_tu date default null, p_den date default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc');
  perform kt_ncc_dong_bo();
  return jsonb_build_object('ncc', coalesce((
    with so as (
      select p.ncc_id, count(*) so_phieu,
             coalesce(sum(c.so_tien) filter (where p.bang = 'chi' and c.trang_thai = 'da_tt'), 0) da_tra,
             coalesce(sum(c.so_tien) filter (where p.bang = 'chi' and c.trang_thai in ('cho_duyet','cho_gd','cho_tt')), 0) cho_tra,
             max(coalesce(c.ngay_tt, c.ngay_de_nghi, t.ngay)) lan_cuoi
        from kt_v_ncc_phieu p left join kt_chi c on p.bang = 'chi' and c.id = p.dong_id left join kt_thu t on p.bang = 'thu' and t.id = p.dong_id
       group by p.ncc_id),
    hs as (select ncc_id, count(*) n from kt_ho_so where not da_xoa group by 1)
    select jsonb_agg(jsonb_build_object('id', n.id, 'ma', n.ma, 'ten', n.ten, 'loai', n.loai, 'nguon', case when n.kiot_id is null then 'app' else 'kiot' end,
      'sdt', n.sdt, 'so_tk', cardinality(n.stk), 'cong_no', k.cong_no, 'tong_nhap', k.tong_nhap, 'hoat_dong', coalesce(k.hoat_dong, true),
      'so_phieu', coalesce(so.so_phieu, 0), 'da_tra', coalesce(so.da_tra, 0), 'cho_tra', coalesce(so.cho_tra, 0), 'lan_cuoi', so.lan_cuoi, 'so_hs', coalesce(hs.n, 0))
      order by coalesce(so.so_phieu, 0) desc, coalesce(k.tong_nhap, 0) desc, n.ten)
      from kt_ncc n left join kt_kiot_ncc k on k.id = n.kiot_id left join so on so.ncc_id = n.id left join hs on hs.ncc_id = n.id
     where not n.da_xoa), '[]'),
    'cho', (select count(*) from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and not coalesce(c.ca_nhan, false) and not coalesce(c.la_tam_ung, false)
             and (p_tu is null or c.ngay_tt >= p_tu) and (p_den is null or c.ngay_tt <= p_den)
             and not exists (select 1 from kt_ncc_gan g where g.bang = 'chi' and g.dong_id = c.id)
             and not exists (select 1 from kt_v_ncc_phieu p where p.bang = 'chi' and p.dong_id = c.id)));
end $$;

create or replace function public.kt_ncc_ct(p_phien text, p_id bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; n kt_ncc; v_chi bigint[]; v_hs bigint[];
begin
  u := kt_chan(p_phien, 'ncc');
  select * into n from kt_ncc where id = p_id and not da_xoa;
  if n.id is null then raise exception 'Không thấy nhà cung cấp'; end if;
  select coalesce(array_agg(dong_id), '{}') into v_chi from kt_v_ncc_phieu where ncc_id = p_id and bang = 'chi';
  select coalesce(array_agg(id), '{}') into v_hs from kt_ho_so where ncc_id = p_id and not da_xoa;
  return jsonb_build_object(
    'ncc', to_jsonb(n) || jsonb_build_object('nguon', case when n.kiot_id is null then 'app' else 'kiot' end)
           || coalesce((select jsonb_build_object('cong_no', k.cong_no, 'tong_nhap', k.tong_nhap, 'tong_nhap_tru_tra', k.tong_nhap_tru_tra) from kt_kiot_ncc k where k.id = n.kiot_id), '{}'),
    'so', kt_ncc_so(p_id),
    'ho_so', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'ten', h.ten, 'loai', h.loai, 'so_hd', h.so_hd, 'ngay', h.ngay, 'gia_tri', h.gia_tri,
        'trang_thai', h.trang_thai, 'ghi_chu', h.ghi_chu, 'tao_boi', h.tao_boi,
        'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'ho_so' and ct.dong_id = h.id and not ct.da_xoa)) order by coalesce(h.ngay, h.tao_luc::date) desc, h.id desc)
      from kt_ho_so h where h.ncc_id = p_id and not h.da_xoa), '[]'),
    'phieu', coalesce((select jsonb_agg(x order by x->>'ngay' desc nulls last, (x->>'id')::bigint desc) from (
        select jsonb_build_object('bang', 'chi', 'id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'noi_dung', c.noi_dung, 'so_tien', c.so_tien,
          'trang_thai', c.trang_thai, 'nguoi_nhan', c.thu_huong_ten, 'stk', c.thu_huong_stk, 'tai_khoan_id', c.tai_khoan_id, 'loai_id', c.loai_id,
          'ho_so_id', p.ho_so_id, 'cach', p.cach, 'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'chi' and ct.dong_id = c.id and not ct.da_xoa)) x
          from kt_v_ncc_phieu p join kt_chi c on c.id = p.dong_id where p.bang = 'chi' and p.ncc_id = p_id
        union all
        select jsonb_build_object('bang', 'thu', 'id', t.id, 'ngay', t.ngay, 'noi_dung', t.noi_dung, 'so_tien', t.so_tien, 'trang_thai', t.trang_thai,
          'tai_khoan_id', t.tai_khoan_id, 'loai_id', t.loai_id, 'ho_so_id', p.ho_so_id, 'cach', p.cach,
          'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'thu' and ct.dong_id = t.id and not ct.da_xoa))
          from kt_v_ncc_phieu p join kt_thu t on t.id = p.dong_id where p.bang = 'thu' and p.ncc_id = p_id) z), '[]'),
    'nhap', coalesce((select jsonb_agg(jsonb_build_object('ma', h.ma, 'ngay', h.ngay, 'chi_nhanh', h.chi_nhanh, 'tong', h.tong, 'da_tra', h.da_tra, 'trang_thai', h.trang_thai, 'mo_ta', h.mo_ta)
        order by h.ngay desc) from kt_kiot_nhap_hang h where n.kiot_id is not null and h.ncc_id = n.kiot_id), '[]'),
    'ct', coalesce((select jsonb_agg(jsonb_build_object('id', ct.id, 'bang', ct.bang, 'dong_id', ct.dong_id, 'ten', ct.ten_file, 'mime', ct.mime, 'tao_boi', ct.tao_boi, 'tao_luc', ct.tao_luc) order by ct.tao_luc desc)
        from kt_chung_tu ct where not ct.da_xoa and ((ct.bang = 'chi' and ct.dong_id = any (v_chi)) or (ct.bang = 'ho_so' and ct.dong_id = any (v_hs)) or (ct.bang = 'ncc' and ct.dong_id = p_id)
          or (ct.bang = 'thu' and ct.dong_id in (select dong_id from kt_v_ncc_phieu where ncc_id = p_id and bang = 'thu')))), '[]'));
end $$;

-- gợi ý NCC cho phiếu chi chưa gán: tên người thụ hưởng / nội dung có tên NCC (tên lõi ≥ 5 ký tự)
create or replace function public.kt_ncc_goi_y_chi(p_ids bigint[]) returns table (chi_id bigint, ncc_id bigint, ly_do text, diem int)
language sql stable security definer set search_path = public as $$
  with n as materialized (select id, kt_ncc_ten_loi(ten) l from kt_ncc where not da_xoa),
       c as materialized (select id, kt_ncc_ten_loi(thu_huong_ten) th, ' ' || regexp_replace(kt_bo_dau(noi_dung || ' ' || coalesce(noi_dung_ck, '')), '[^a-z0-9]+', ' ', 'g') || ' ' nd
               from kt_chi where id = any (p_ids)),
       m as (select c.id chi_id, n.id ncc_id,
               case when c.th <> '' and length(c.th) >= 5 and (c.th = n.l or (length(n.l) >= 5 and position(' ' || n.l || ' ' in ' ' || c.th || ' ') > 0) or position(' ' || c.th || ' ' in ' ' || n.l || ' ') > 0) then 'Tên người nhận khớp tên NCC'
                    when length(n.l) >= 6 and position(' ' || n.l || ' ' in c.nd) > 0 then 'Nội dung có tên NCC' end ly_do
               from c cross join n where n.l <> '')
  select chi_id, ncc_id, ly_do, case when ly_do like 'Tên%' then 2 else 1 end from m where ly_do is not null
$$;
revoke all on function public.kt_ncc_goi_y_chi(bigint[]) from public, anon, authenticated;

-- danh sách phiếu chi đã thanh toán CHƯA vào NCC nào (màn "Chờ phân hồ sơ"), kèm gợi ý
create or replace function public.kt_ncc_cho(p_phien text, p_tu date, p_den date) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_ids bigint[];
begin
  u := kt_chan(p_phien, 'ncc');
  select coalesce(array_agg(c.id), '{}') into v_ids from kt_chi c
   where not c.da_xoa and c.trang_thai = 'da_tt' and not coalesce(c.ca_nhan, false) and not coalesce(c.la_tam_ung, false)
     and (p_tu is null or c.ngay_tt >= p_tu) and (p_den is null or c.ngay_tt <= p_den)
     and not exists (select 1 from kt_ncc_gan g where g.bang = 'chi' and g.dong_id = c.id)
     and not exists (select 1 from kt_v_ncc_phieu p where p.bang = 'chi' and p.dong_id = c.id);
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'ngay', c.ngay_tt, 'noi_dung', c.noi_dung, 'so_tien', c.so_tien, 'nguoi_nhan', c.thu_huong_ten,
      'stk', c.thu_huong_stk, 'loai_id', c.loai_id, 'tai_khoan_id', c.tai_khoan_id,
      'goi_y', (select jsonb_agg(jsonb_build_object('ncc_id', g.ncc_id, 'ten', n.ten, 'ly_do', g.ly_do) order by g.diem desc, n.ten) from kt_ncc_goi_y_chi(array[c.id]) g join kt_ncc n on n.id = g.ncc_id))
      order by c.ngay_tt desc, c.id desc) from kt_chi c where c.id = any (v_ids)), '[]');
end $$;

-- bước 4 trên cửa sổ phiếu: đang thuộc NCC / hồ sơ nào + gợi ý
create or replace function public.kt_phieu_ho_so(p_phien text, p_bang text, p_id bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; p record;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'ncc') or kt_co_quyen(u, 'chi_duyet') or kt_co_quyen(u, p_bang)) then raise exception 'Tài khoản chưa được cấp quyền xem hồ sơ NCC' using errcode = '42501'; end if;
  select * into p from kt_v_ncc_phieu v where v.bang = p_bang and v.dong_id = p_id;
  return jsonb_build_object('ncc_id', p.ncc_id, 'ho_so_id', p.ho_so_id, 'cach', p.cach,
    'khong', exists (select 1 from kt_ncc_gan g where g.bang = p_bang and g.dong_id = p_id and g.ncc_id is null),
    'ncc_ten', (select ten from kt_ncc where id = p.ncc_id), 'ho_so_ten', (select ten from kt_ho_so where id = p.ho_so_id),
    'goi_y', case when p_bang = 'chi' and p.ncc_id is null then (select jsonb_agg(jsonb_build_object('ncc_id', g.ncc_id, 'ten', n.ten, 'ly_do', g.ly_do) order by g.diem desc, n.ten)
       from kt_ncc_goi_y_chi(array[p_id]) g join kt_ncc n on n.id = g.ncc_id) end,
    'ho_so', case when p.ncc_id is not null then (select jsonb_agg(jsonb_build_object('id', h.id, 'ten', h.ten) order by h.id desc) from kt_ho_so h where h.ncc_id = p.ncc_id and not h.da_xoa) end);
end $$;

-- danh sách NCC gọn (ô chọn NCC ở bước 4)
create or replace function public.kt_ncc_chon(p_phien text) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'ncc') or kt_co_quyen(u, 'chi_duyet') or kt_co_quyen(u, 'chi') or kt_co_quyen(u, 'thu')) then raise exception 'Tài khoản chưa được cấp quyền' using errcode = '42501'; end if;
  perform kt_ncc_dong_bo();
  return coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'ma', n.ma, 'ten', n.ten, 'loai', n.loai,
      'hs', (select jsonb_agg(jsonb_build_object('id', h.id, 'ten', h.ten) order by h.id desc) from kt_ho_so h where h.ncc_id = n.id and not h.da_xoa)) order by n.ten)
    from kt_ncc n where not n.da_xoa), '[]');
end $$;

-- gán phiếu: p_kieu 'gan' (vào NCC / hồ sơ) · 'khong' (không thuộc NCC nào — bỏ gợi ý) · 'bo' (gỡ gán, về như chưa phân)
-- p_nho_stk: lưu số TK thụ hưởng của các phiếu chi vào NCC → phiếu sau chuyển vào số TK đó tự vào NCC
create or replace function public.kt_ncc_gan_phieu(p_phien text, p_bang text, p_ids bigint[], p_kieu text, p_ncc bigint, p_ho_so bigint, p_nho_stk boolean default false)
returns int language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_ncc bigint := p_ncc; v_n int := 0; i bigint;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'ncc', true) or (p_bang = 'chi' and kt_co_quyen(u, 'chi_duyet')) or (p_bang = 'thu' and kt_co_quyen(u, 'thu', true))) then
    raise exception 'Tài khoản chưa được cấp quyền gán hồ sơ NCC' using errcode = '42501'; end if;
  if p_bang not in ('chi','thu') or p_kieu not in ('gan','khong','bo') then raise exception 'Tham số không hợp lệ'; end if;
  if p_ho_so is not null then select ncc_id into v_ncc from kt_ho_so where id = p_ho_so and not da_xoa;
    if v_ncc is null then raise exception 'Không thấy hồ sơ'; end if;
    if p_ncc is not null and p_ncc <> v_ncc then raise exception 'Hồ sơ không thuộc NCC đã chọn'; end if; end if;
  if p_kieu = 'gan' and v_ncc is null then raise exception 'Chọn nhà cung cấp'; end if;
  foreach i in array p_ids loop
    if p_kieu = 'bo' then delete from kt_ncc_gan where bang = p_bang and dong_id = i;
    else
      insert into kt_ncc_gan (bang, dong_id, ncc_id, ho_so_id, tao_boi) values (p_bang, i, case when p_kieu = 'gan' then v_ncc end, case when p_kieu = 'gan' then p_ho_so end, u.ho_ten)
      on conflict (bang, dong_id) do update set ncc_id = excluded.ncc_id, ho_so_id = excluded.ho_so_id, tao_boi = excluded.tao_boi, tao_luc = now();
    end if;
    perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, i, 'ho_so_ncc', jsonb_build_object('kieu', p_kieu, 'ncc_id', v_ncc, 'ho_so_id', p_ho_so));
    v_n := v_n + 1;
  end loop;
  if p_kieu = 'gan' and p_nho_stk and p_bang = 'chi' then
    update kt_ncc n set stk = (select array_agg(distinct s) from unnest(n.stk || array(select kt_so_tk(c.thu_huong_stk) from kt_chi c where c.id = any (p_ids) and kt_so_tk(c.thu_huong_stk) is not null)) s),
           sua_boi = u.ho_ten, sua_luc = now() where n.id = v_ncc;
  end if;
  return v_n;
end $$;

create or replace function public.kt_luu_ncc(p_phien text, p_dong jsonb) returns bigint language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_stk text[];
begin
  u := kt_chan(p_phien, 'ncc', true);
  select coalesce(array_agg(distinct s), '{}') into v_stk from (select kt_so_tk(x) s from jsonb_array_elements_text(coalesce(p_dong->'stk', '[]')) x) z where s is not null;
  if v_id is null then
    if nullif(trim(p_dong->>'ten'), '') is null then raise exception 'Nhập tên nhà cung cấp'; end if;
    insert into kt_ncc (ten, loai, mst, sdt, dia_chi, lien_he, stk, ghi_chu, tao_boi)
    values (trim(p_dong->>'ten'), coalesce(nullif(p_dong->>'loai', ''), 'nuoc_ngoai'), nullif(trim(p_dong->>'mst'), ''), nullif(trim(p_dong->>'sdt'), ''),
      nullif(trim(p_dong->>'dia_chi'), ''), nullif(trim(p_dong->>'lien_he'), ''), v_stk, nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten) returning id into v_id;
    update kt_ncc set ma = 'NCCA' || lpad(v_id::text, 4, '0') where id = v_id;
  else
    -- NCC Kiot: tên / mã / SĐT theo Kiot (không sửa ở đây)
    update kt_ncc set ten = case when kiot_id is null then coalesce(nullif(trim(p_dong->>'ten'), ''), ten) else ten end,
      loai = coalesce(nullif(p_dong->>'loai', ''), loai), mst = nullif(trim(p_dong->>'mst'), ''), dia_chi = nullif(trim(p_dong->>'dia_chi'), ''),
      lien_he = nullif(trim(p_dong->>'lien_he'), ''), sdt = case when kiot_id is null then nullif(trim(p_dong->>'sdt'), '') else sdt end,
      stk = v_stk, ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_ncc', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

create or replace function public.kt_luu_ho_so(p_phien text, p_dong jsonb) returns bigint language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'ncc', true) or kt_co_quyen(u, 'chi_duyet')) then raise exception 'Tài khoản chưa được cấp quyền sửa hồ sơ NCC' using errcode = '42501'; end if;
  if nullif(trim(p_dong->>'ten'), '') is null then raise exception 'Nhập tên hồ sơ'; end if;
  if v_id is null then
    if not exists (select 1 from kt_ncc where id = (p_dong->>'ncc_id')::bigint and not da_xoa) then raise exception 'Chọn nhà cung cấp'; end if;
    insert into kt_ho_so (ncc_id, ten, loai, so_hd, ngay, gia_tri, ghi_chu, tao_boi)
    values ((p_dong->>'ncc_id')::bigint, trim(p_dong->>'ten'), coalesce(nullif(p_dong->>'loai', ''), 'hop_dong'), nullif(trim(p_dong->>'so_hd'), ''),
      nullif(p_dong->>'ngay', '')::date, nullif(p_dong->>'gia_tri', '')::numeric, nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten) returning id into v_id;
  else
    update kt_ho_so set ten = trim(p_dong->>'ten'), loai = coalesce(nullif(p_dong->>'loai', ''), loai), so_hd = nullif(trim(p_dong->>'so_hd'), ''),
      ngay = nullif(p_dong->>'ngay', '')::date, gia_tri = nullif(p_dong->>'gia_tri', '')::numeric, ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''),
      trang_thai = coalesce(nullif(p_dong->>'trang_thai', ''), trang_thai), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_ho_so', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $$;

-- xoá hồ sơ: ẩn hồ sơ, các phiếu trong hồ sơ vẫn thuộc NCC (chỉ bỏ hồ sơ)
create or replace function public.kt_xoa_ho_so(p_phien text, p_id bigint) returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc', true);
  update kt_ho_so set da_xoa = true, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  update kt_ncc_gan set ho_so_id = null where ho_so_id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_ho_so', p_id, 'xoa', null);
end $$;

-- chứng từ chung của hồ sơ: bang 'ho_so' theo quyền trang ncc
create or replace function public.kt_quyen_chung_tu(p_phien text, p_bang text, p_ghi boolean, p_ids bigint[])
returns text language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  if p_bang not in ('bao_loi','thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung','ho_so','ncc') then raise exception 'Bảng chứng từ không hợp lệ'; end if;
  u := kt_chan_dong(p_phien, p_bang, p_ids, p_ghi);
  return u.ho_ten;
end $$;
create or replace function public.kt_chan_dong(p_phien text, p_bang text, p_ids bigint[], p_ghi boolean)
returns kt_nguoi_dung language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  -- 24/10: ảnh báo lỗi — người báo (báo lỗi của chính mình) hoặc quyền trang Log
  if p_bang = 'bao_loi' then
    if kt_co_quyen(u, 'nhat_ky', false) then return u; end if;
    if cardinality(p_ids) > 0 and not exists (select 1 from unnest(p_ids) i where not exists (select 1 from kt_bao_loi b where b.id = i and b.nguoi = u.ho_ten)) then return u; end if;
    raise exception 'Tài khoản chưa được cấp quyền xem báo lỗi' using errcode = '42501';
  end if;
  -- 29/10: chứng từ hồ sơ NCC theo quyền trang Nhà cung cấp (người xác nhận phiếu chi cũng tải được ở bước 4)
  if p_bang = 'ho_so' then
    if kt_co_quyen(u, 'ncc', p_ghi) or kt_co_quyen(u, 'chi_duyet') then return u; end if;
    raise exception 'Tài khoản chưa được cấp quyền % hồ sơ NCC', case when p_ghi then 'sửa' else 'xem' end using errcode = '42501';
  end if;
  -- 14/10/2026: ảnh kiểm két theo quyền trang Sổ quỹ (dong_tien)
  if kt_co_quyen(u, case p_bang when 'kiem_quy' then 'kiem_ket' else p_bang end, p_ghi) then return u; end if;
  -- 16/10: thủ quỹ (chi_tt) — phiếu chờ chi tiền / đã thanh toán
  if p_bang = 'chi' and kt_co_quyen(u, 'chi_tt') and cardinality(p_ids) > 0
     and not exists (select 1 from unnest(p_ids) i where not exists (
       select 1 from kt_chi c join kt_tai_khoan t on t.id = c.tai_khoan_id where c.id = i and c.trang_thai in ('cho_tt','da_tt') and t.thu_quy_chi and not c.da_xoa)) then
    return u;
  end if;
  if p_bang = 'chi' and kt_co_quyen(u, 'chi_de_nghi') and cardinality(p_ids) > 0
     and not exists (select 1 from unnest(p_ids) i where not exists (
       select 1 from kt_chi c where c.id = i and c.tao_boi = u.ho_ten and not c.da_xoa)) then
    return u;
  end if;
  raise exception 'Tài khoản chưa được cấp quyền % trang này', case when p_ghi then 'sửa' else 'xem' end using errcode = '42501';
end $$;

-- tìm phiếu để gán vào 1 NCC: p_q trống → gợi ý (phiếu chi chưa vào NCC nào, khớp tên NCC này); có p_q → tìm theo số phiếu / nội dung / người nhận / số tiền
create or replace function public.kt_ncc_tim(p_phien text, p_ncc bigint, p_q text) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_ids bigint[]; q text := kt_bo_dau(trim(coalesce(p_q, ''))); v_so numeric := nullif(regexp_replace(coalesce(p_q, ''), '\D', '', 'g'), '')::numeric;
begin
  u := kt_chan(p_phien, 'ncc');
  if q = '' then
    select coalesce(array_agg(c.id), '{}') into v_ids from kt_chi c
     where not c.da_xoa and c.trang_thai not in ('tu_choi','tu_choi_tt') and not coalesce(c.ca_nhan, false) and not coalesce(c.la_tam_ung, false)
       and not exists (select 1 from kt_ncc_gan g where g.bang = 'chi' and g.dong_id = c.id)
       and not exists (select 1 from kt_v_ncc_phieu p where p.bang = 'chi' and p.dong_id = c.id);
    return coalesce((select jsonb_agg(jsonb_build_object('bang', 'chi', 'id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'noi_dung', c.noi_dung, 'so_tien', c.so_tien,
        'trang_thai', c.trang_thai, 'nguoi_nhan', c.thu_huong_ten, 'stk', c.thu_huong_stk, 'ly_do', g.ly_do) order by coalesce(c.ngay_tt, c.ngay_de_nghi) desc, c.id desc)
      from kt_ncc_goi_y_chi(v_ids) g join kt_chi c on c.id = g.chi_id where g.ncc_id = p_ncc), '[]');
  end if;
  return coalesce((select jsonb_agg(x order by x->>'ngay' desc nulls last) from (
      select jsonb_build_object('bang', 'chi', 'id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'noi_dung', c.noi_dung, 'so_tien', c.so_tien, 'trang_thai', c.trang_thai,
        'nguoi_nhan', c.thu_huong_ten, 'stk', c.thu_huong_stk, 'ncc_ten', (select n.ten from kt_v_ncc_phieu p join kt_ncc n on n.id = p.ncc_id where p.bang = 'chi' and p.dong_id = c.id)) x
        from kt_chi c where not c.da_xoa and c.trang_thai not in ('tu_choi','tu_choi_tt')
         and (kt_bo_dau(coalesce(c.noi_dung, '') || ' ' || coalesce(c.thu_huong_ten, '') || ' ' || coalesce(c.noi_dung_ck, '')) like '%' || q || '%'
              or 'pc' || lpad(c.id::text, 6, '0') = q or (v_so >= 1000 and c.so_tien = v_so) or kt_so_tk(c.thu_huong_stk) = kt_so_tk(p_q))
      union all
      select jsonb_build_object('bang', 'thu', 'id', t.id, 'ngay', t.ngay, 'noi_dung', t.noi_dung, 'so_tien', t.so_tien, 'trang_thai', t.trang_thai,
        'ncc_ten', (select n.ten from kt_v_ncc_phieu p join kt_ncc n on n.id = p.ncc_id where p.bang = 'thu' and p.dong_id = t.id))
        from kt_thu t where not t.da_xoa and coalesce(t.nguon, '') <> 'kiot'
         and (kt_bo_dau(coalesce(t.noi_dung, '')) like '%' || q || '%' or 'pt' || lpad(t.id::text, 6, '0') = q or (v_so >= 1000 and t.so_tien = v_so))
      limit 60) z), '[]');
end $$;

grant execute on function public.kt_ncc_tim(text, bigint, text) to anon, authenticated;
grant execute on function public.kt_ds_ncc(text, date, date), public.kt_ncc_ct(text, bigint), public.kt_ncc_cho(text, date, date), public.kt_phieu_ho_so(text, text, bigint),
  public.kt_ncc_chon(text), public.kt_ncc_gan_phieu(text, text, bigint[], text, bigint, bigint, boolean), public.kt_luu_ncc(text, jsonb),
  public.kt_luu_ho_so(text, jsonb), public.kt_xoa_ho_so(text, bigint) to anon, authenticated;

-- 29/10 (sửa lỗi): bảng kt_chung_tu chỉ nhận một số loại → tải chứng từ hồ sơ / NCC báo "Giá trị nhập chưa hợp lệ". Thêm 'ho_so', 'ncc'.
alter table public.kt_chung_tu drop constraint if exists kt_chung_tu_bang_check;
alter table public.kt_chung_tu add constraint kt_chung_tu_bang_check check (bang = any (array['thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung','bao_loi','ho_so','ncc']));
