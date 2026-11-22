-- THƯ VIỆN TÀI LIỆU NCC (29/10/2026, anh gửi ảnh mẫu tab Hồ sơ: cây thư mục + bảng tài liệu + xem trước; "bỏ cột kích thước"). Monsieur Claude
-- • kt_tai_lieu: thông tin từng tệp (kt_chung_tu.id) của NCC — thư mục, số / ký hiệu, ngày ban hành, hiệu lực từ – đến, mô tả, hợp đồng (kt_ho_so) liên kết.
--   Tệp không có dòng ở đây: tệp NCC → "Khác", tệp hồ sơ → "Hợp đồng", ảnh phiếu chi / thu → "Chứng từ giao dịch" (tự gom, không sửa thư mục).
-- • kt_ncc_thu_muc: thư mục thêm tay của từng NCC (cha = tên thư mục mặc định, vd "Hợp đồng").
create table if not exists public.kt_tai_lieu (
  ct_id bigint primary key references kt_chung_tu(id), ncc_id bigint not null references kt_ncc(id), thu_muc text, so_hieu text, ngay_bh date, hl_tu date, hl_den date,
  mo_ta text, ho_so_id bigint references kt_ho_so(id), sua_boi text, sua_luc timestamptz not null default now());
create index if not exists kt_tai_lieu_ncc on public.kt_tai_lieu (ncc_id);
create table if not exists public.kt_ncc_thu_muc (
  id bigserial primary key, ncc_id bigint not null references kt_ncc(id), ten text not null, cha text, tao_boi text, tao_luc timestamptz not null default now(), da_xoa boolean not null default false);
alter table public.kt_tai_lieu enable row level security; alter table public.kt_ncc_thu_muc enable row level security;
revoke all on public.kt_tai_lieu, public.kt_ncc_thu_muc from public, anon, authenticated;
do $$ declare t text;
begin
  foreach t in array array['kt_tai_lieu','kt_ncc_thu_muc'] loop
    execute format('drop trigger if exists kt_chi_xem on public.%I', t);
    execute format('create trigger kt_chi_xem before insert or update or delete on public.%I for each row execute function public.kt_tg_chi_xem()', t);
  end loop;
end $$;

create or replace function public.kt_luu_tai_lieu(p_phien text, p_ct bigint, p_ncc bigint, p_dong jsonb) returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chung_tu;
begin
  u := kt_chan(p_phien, 'ncc', true);
  select * into c from kt_chung_tu where id = p_ct and not da_xoa;
  if c.id is null then raise exception 'Không thấy tài liệu'; end if;
  if not ((c.bang = 'ncc' and c.dong_id = p_ncc) or (c.bang = 'ho_so' and exists (select 1 from kt_ho_so h where h.id = c.dong_id and h.ncc_id = p_ncc))
          or (c.bang in ('chi','thu') and exists (select 1 from kt_v_ncc_phieu v where v.bang = c.bang and v.dong_id = c.dong_id and v.ncc_id = p_ncc))) then
    raise exception 'Tài liệu không thuộc nhà cung cấp này'; end if;
  if (p_dong->>'ho_so_id') is not null and not exists (select 1 from kt_ho_so h where h.id = (p_dong->>'ho_so_id')::bigint and h.ncc_id = p_ncc and not h.da_xoa) then
    raise exception 'Hợp đồng không thuộc nhà cung cấp này'; end if;
  insert into kt_tai_lieu (ct_id, ncc_id, thu_muc, so_hieu, ngay_bh, hl_tu, hl_den, mo_ta, ho_so_id, sua_boi, sua_luc)
  values (p_ct, p_ncc, nullif(trim(p_dong->>'thu_muc'), ''), nullif(trim(p_dong->>'so_hieu'), ''), nullif(p_dong->>'ngay_bh', '')::date, nullif(p_dong->>'hl_tu', '')::date,
    nullif(p_dong->>'hl_den', '')::date, nullif(trim(p_dong->>'mo_ta'), ''), nullif(p_dong->>'ho_so_id', '')::bigint, u.ho_ten, now())
  on conflict (ct_id) do update set thu_muc = excluded.thu_muc, so_hieu = excluded.so_hieu, ngay_bh = excluded.ngay_bh, hl_tu = excluded.hl_tu, hl_den = excluded.hl_den,
    mo_ta = excluded.mo_ta, ho_so_id = excluded.ho_so_id, sua_boi = excluded.sua_boi, sua_luc = now();
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_tai_lieu', p_ct, 'sua', p_dong);
end $$;

create or replace function public.kt_luu_thu_muc(p_phien text, p_ncc bigint, p_ten text, p_cha text) returns bigint language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_id bigint;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if nullif(trim(p_ten), '') is null then raise exception 'Nhập tên thư mục'; end if;
  insert into kt_ncc_thu_muc (ncc_id, ten, cha, tao_boi) values (p_ncc, trim(p_ten), nullif(trim(p_cha), ''), u.ho_ten) returning id into v_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_ncc_thu_muc', v_id, 'them', jsonb_build_object('ncc_id', p_ncc, 'ten', p_ten, 'cha', p_cha));
  return v_id;
end $$;
grant execute on function public.kt_luu_tai_lieu(text, bigint, bigint, jsonb), public.kt_luu_thu_muc(text, bigint, text, text) to anon, authenticated;

CREATE OR REPLACE FUNCTION public.kt_ncc_ct(p_phien text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    'tl', coalesce((select jsonb_object_agg(t.ct_id, jsonb_build_object('thu_muc', t.thu_muc, 'so_hieu', t.so_hieu, 'ngay_bh', t.ngay_bh, 'hl_tu', t.hl_tu, 'hl_den', t.hl_den, 'mo_ta', t.mo_ta, 'ho_so_id', t.ho_so_id, 'sua_boi', t.sua_boi, 'sua_luc', t.sua_luc))
        from kt_tai_lieu t where t.ncc_id = p_id), '{}'),
    'thu_muc', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'ten', m.ten, 'cha', m.cha) order by m.id) from kt_ncc_thu_muc m where m.ncc_id = p_id and not m.da_xoa), '[]'),
    'han', coalesce((select nullif(gia_tri, '')::int from kt_cai_dat where khoa = 'han_no_ncc_ngay'), 30),
    'no', case when n.kiot_id is not null then kt_cong_no_dt_ct(p_phien, 'ncc', n.kiot_id) end,
    'nhap', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'ngay', h.ngay, 'chi_nhanh', h.chi_nhanh, 'tong', h.tong, 'da_tra', h.da_tra, 'trang_thai', h.trang_thai, 'mo_ta', h.mo_ta,
          'ho_so_id', (select g.ho_so_id from kt_ncc_gan g where g.bang = 'nhap' and g.dong_id = h.id))
        order by h.ngay desc) from kt_kiot_nhap_hang h where n.kiot_id is not null and h.ncc_id = n.kiot_id), '[]'),
    'ct', coalesce((select jsonb_agg(jsonb_build_object('id', ct.id, 'bang', ct.bang, 'dong_id', ct.dong_id, 'ten', ct.ten_file, 'mime', ct.mime, 'tao_boi', ct.tao_boi, 'tao_luc', ct.tao_luc) order by ct.tao_luc desc)
        from kt_chung_tu ct where not ct.da_xoa and ((ct.bang = 'chi' and ct.dong_id = any (v_chi)) or (ct.bang = 'ho_so' and ct.dong_id = any (v_hs)) or (ct.bang = 'ncc' and ct.dong_id = p_id)
          or (ct.bang = 'thu' and ct.dong_id in (select dong_id from kt_v_ncc_phieu where ncc_id = p_id and bang = 'thu')))), '[]'));
end $function$;
