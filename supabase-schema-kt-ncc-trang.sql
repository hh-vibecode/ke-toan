-- TRANG KHÁCH HÀNG & NCC (29/10/2026, anh gửi ảnh mẫu: NCC nội địa / nước ngoài + popup 1 NCC: thông tin · 4 thẻ · Giao dịch / Công nợ / Hồ sơ). Monsieur Claude
-- • kt_ncc thêm email. • kt_ncc_ct thêm hạn nợ NCC + công nợ Kiot chia theo phiếu nhập (kt_cong_no_dt_ct, như trang công nợ cũ).
-- • kt_ds_ncc thêm email / địa chỉ / số phiếu nhập Kiot / Phải trả · Phải thu (ứng trước):
--   NCC Kiot: theo công nợ Kiot (dương = mình nợ NCC, âm = mình trả trước); NCC tạo trên app: theo hồ sơ (giá trị − đã trả; trả vượt / không gắn hồ sơ có giá trị = ứng trước).
alter table public.kt_ncc add column if not exists email text;
-- anh 29/10: kế toán / giám đốc sửa được MỌI thông tin NCC (cả NCC Kiot) — sửa tay thì đồng bộ Kiot không ghi đè tên / SĐT
alter table public.kt_ncc add column if not exists sua_tay boolean not null default false;

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
    'han', coalesce((select nullif(gia_tri, '')::int from kt_cai_dat where khoa = 'han_no_ncc_ngay'), 30),
    'no', case when n.kiot_id is not null then kt_cong_no_dt_ct(p_phien, 'ncc', n.kiot_id) end,
    'nhap', coalesce((select jsonb_agg(jsonb_build_object('ma', h.ma, 'ngay', h.ngay, 'chi_nhanh', h.chi_nhanh, 'tong', h.tong, 'da_tra', h.da_tra, 'trang_thai', h.trang_thai, 'mo_ta', h.mo_ta)
        order by h.ngay desc) from kt_kiot_nhap_hang h where n.kiot_id is not null and h.ncc_id = n.kiot_id), '[]'),
    'ct', coalesce((select jsonb_agg(jsonb_build_object('id', ct.id, 'bang', ct.bang, 'dong_id', ct.dong_id, 'ten', ct.ten_file, 'mime', ct.mime, 'tao_boi', ct.tao_boi, 'tao_luc', ct.tao_luc) order by ct.tao_luc desc)
        from kt_chung_tu ct where not ct.da_xoa and ((ct.bang = 'chi' and ct.dong_id = any (v_chi)) or (ct.bang = 'ho_so' and ct.dong_id = any (v_hs)) or (ct.bang = 'ncc' and ct.dong_id = p_id)
          or (ct.bang = 'thu' and ct.dong_id in (select dong_id from kt_v_ncc_phieu where ncc_id = p_id and bang = 'thu')))), '[]'));
end $function$;

CREATE OR REPLACE FUNCTION public.kt_luu_ncc(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_stk text[];
begin
  u := kt_chan(p_phien, 'ncc', true);
  select coalesce(array_agg(distinct s), '{}') into v_stk from (select kt_so_tk(x) s from jsonb_array_elements_text(coalesce(p_dong->'stk', '[]')) x) z where s is not null;
  if v_id is null then
    if nullif(trim(p_dong->>'ten'), '') is null then raise exception 'Nhập tên nhà cung cấp'; end if;
    insert into kt_ncc (ten, loai, mst, sdt, email, dia_chi, lien_he, stk, ghi_chu, tao_boi)
    values (trim(p_dong->>'ten'), coalesce(nullif(p_dong->>'loai', ''), 'nuoc_ngoai'), nullif(trim(p_dong->>'mst'), ''), nullif(trim(p_dong->>'sdt'), ''), nullif(trim(p_dong->>'email'), ''),
      nullif(trim(p_dong->>'dia_chi'), ''), nullif(trim(p_dong->>'lien_he'), ''), v_stk, nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten) returning id into v_id;
    update kt_ncc set ma = 'NCCA' || lpad(v_id::text, 4, '0') where id = v_id;
  else
    update kt_ncc set sua_tay = sua_tay or (kiot_id is not null and (coalesce(nullif(trim(p_dong->>'ten'), ''), ten) is distinct from ten or nullif(trim(p_dong->>'sdt'), '') is distinct from sdt))
     where id = v_id and not da_xoa;
    update kt_ncc set ten = coalesce(nullif(trim(p_dong->>'ten'), ''), ten),
      loai = coalesce(nullif(p_dong->>'loai', ''), loai), mst = nullif(trim(p_dong->>'mst'), ''), email = nullif(trim(p_dong->>'email'), ''), dia_chi = nullif(trim(p_dong->>'dia_chi'), ''),
      lien_he = nullif(trim(p_dong->>'lien_he'), ''), sdt = nullif(trim(p_dong->>'sdt'), ''),
      stk = v_stk, ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_ncc', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $function$;

drop function if exists public.kt_ds_ncc(text, date, date);
create or replace function public.kt_ds_ncc(p_phien text, p_tu date default null, p_den date default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc');
  perform kt_ncc_dong_bo();
  return (with p as materialized (select * from kt_v_ncc_phieu),
    so as (
      select p.ncc_id, count(*) so_phieu,
             coalesce(sum(c.so_tien) filter (where p.bang = 'chi' and c.trang_thai = 'da_tt'), 0) da_tra,
             coalesce(sum(c.so_tien) filter (where p.bang = 'chi' and c.trang_thai in ('cho_duyet','cho_gd','cho_tt')), 0) cho_tra,
             max(coalesce(c.ngay_tt, c.ngay_de_nghi, t.ngay)) lan_cuoi
        from p left join kt_chi c on p.bang = 'chi' and c.id = p.dong_id left join kt_thu t on p.bang = 'thu' and t.id = p.dong_id
       group by p.ncc_id),
    hs as (select ncc_id, count(*) n from kt_ho_so where not da_xoa group by 1),
    nh as (select ncc_id, count(*) n from kt_kiot_nhap_hang where trang_thai = 3 group by 1),
    -- NCC tạo trên app: phải trả = Σ hồ sơ (giá trị − đã trả) còn dương; ứng trước = đã trả − phần nằm trong giá trị hồ sơ
    ht as (select h.ncc_id, h.gia_tri, coalesce(sum(c.so_tien) filter (where c.trang_thai = 'da_tt'), 0) tra from kt_ho_so h
             left join p on p.ho_so_id = h.id and p.bang = 'chi' left join kt_chi c on c.id = p.dong_id where not h.da_xoa group by h.id, h.ncc_id, h.gia_tri),
    hn as (select ncc_id, sum(greatest(gia_tri - tra, 0)) phai_tra, sum(least(tra, gia_tri)) trong from ht where gia_tri is not null group by 1)
    select jsonb_build_object('ncc', coalesce((
      select jsonb_agg(jsonb_build_object('id', n.id, 'ma', n.ma, 'ten', n.ten, 'loai', n.loai, 'nguon', case when n.kiot_id is null then 'app' else 'kiot' end,
        'sdt', n.sdt, 'so_tk', cardinality(n.stk), 'cong_no', k.cong_no, 'tong_nhap', k.tong_nhap, 'hoat_dong', coalesce(k.hoat_dong, true),
        'so_phieu', coalesce(so.so_phieu, 0), 'da_tra', coalesce(so.da_tra, 0), 'cho_tra', coalesce(so.cho_tra, 0), 'lan_cuoi', so.lan_cuoi, 'so_hs', coalesce(hs.n, 0),
        'email', n.email, 'dia_chi', n.dia_chi, 'so_nhap', coalesce(nh.n, 0),
        'phai_tra', case when n.kiot_id is not null then greatest(coalesce(k.cong_no, 0), 0) else coalesce(hn.phai_tra, 0) end,
        'phai_thu', case when n.kiot_id is not null then greatest(-coalesce(k.cong_no, 0), 0) else greatest(coalesce(so.da_tra, 0) - coalesce(hn.trong, 0), 0) end)
        order by coalesce(so.so_phieu, 0) desc, coalesce(k.tong_nhap, 0) desc, n.ten)
        from kt_ncc n left join kt_kiot_ncc k on k.id = n.kiot_id left join so on so.ncc_id = n.id left join hs on hs.ncc_id = n.id left join nh on nh.ncc_id = n.kiot_id left join hn on hn.ncc_id = n.id
       where not n.da_xoa), '[]'),
      'cho', (select count(*) from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and not coalesce(c.ca_nhan, false) and not coalesce(c.la_tam_ung, false)
               and (p_tu is null or c.ngay_tt >= p_tu) and (p_den is null or c.ngay_tt <= p_den)
               and c.id not in (select dong_id from kt_ncc_gan where bang = 'chi') and c.id not in (select dong_id from p where bang = 'chi'))));
end $$;
grant execute on function public.kt_ds_ncc(text, date, date) to anon, authenticated;

-- đồng bộ NCC Kiot: bỏ qua NCC kế toán đã sửa tay
create or replace function public.kt_ncc_dong_bo() returns void language plpgsql security definer set search_path = public as $$
declare v_luc timestamptz; v_moi timestamptz;
begin
  select max(keo_luc) into v_moi from kt_kiot_ncc;
  select nullif(gia_tri, '')::timestamptz into v_luc from kt_cai_dat where khoa = 'kt_ncc_dong_bo_luc';
  if v_luc is not null and v_moi is not null and v_luc >= v_moi
     and not exists (select 1 from kt_kiot_ncc k where not exists (select 1 from kt_ncc n where n.kiot_id = k.id)) then return; end if;
  begin
    insert into kt_ncc (kiot_id, ma, ten, sdt, loai, tao_boi)
    select k.id, k.ma, k.ten, k.sdt, case when kt_bo_dau(k.ten) ~ '(^|[^a-z])(tq|trung quoc)([^a-z]|$)' then 'nuoc_ngoai' else 'noi_dia' end, 'Hệ thống'
      from kt_kiot_ncc k where not exists (select 1 from kt_ncc n where n.kiot_id = k.id);
    update kt_ncc n set ma = k.ma, ten = k.ten, sdt = coalesce(k.sdt, n.sdt)
      from kt_kiot_ncc k where k.id = n.kiot_id and not n.sua_tay and (n.ma is distinct from k.ma or n.ten is distinct from k.ten);
    update kt_cai_dat set gia_tri = coalesce(v_moi, now())::text, sua_luc = now() where khoa = 'kt_ncc_dong_bo_luc';
    if not found then insert into kt_cai_dat (khoa, gia_tri, sua_luc) values ('kt_ncc_dong_bo_luc', coalesce(v_moi, now())::text, now()); end if;
  exception when others then null;   -- phiên chỉ xem / tranh ghi: bỏ qua, lần sau đồng bộ
  end;
end $$;
revoke all on function public.kt_ncc_dong_bo() from public, anon, authenticated;
