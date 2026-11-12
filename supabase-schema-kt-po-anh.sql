-- ẢNH MẪU DÒNG HÀNG PO — 12/11/2026. Kế toán (anh chuyển): "PO: ảnh mẫu hàng người đặt hàng sẽ tải lên, làm trực tiếp trên app sau đó down về gửi NCC".
-- Ảnh lưu ở kho chứng từ, bang 'po' (dong_id = id PO), quyền theo trang 'ncc'; bang 'de_xuat' để sẵn cho form đề xuất mua hàng / đơn khách đặt riêng công khai.
-- GỠ LẠI phần Trung tâm tài liệu Nhóm 01 đã thêm cùng ngày (anh 12/11: "cái này không nhét vào kế toán đâu, cái này làm riêng, quên cái này đi"):
-- trang hồ sơ pháp lý công ty (bang 'cong_ty', quyền ho_so_cty), cột kt_tai_lieu.ban_goc / bao_sap_het / bao_het, lịch kt-kiem-het-han + hàm báo hết hạn. — Monsieur Claude
select cron.unschedule('kt-kiem-het-han') where exists (select 1 from cron.job where jobname = 'kt-kiem-het-han');
drop function if exists public.kt_kiem_het_han();
drop function if exists public.kt_cty_tl_ds(text);
drop function if exists public.kt_luu_tai_lieu_cty(text, bigint, jsonb);
delete from kt_thong_bao where loai = 'het_han';
-- dữ liệu thử của trang đã gỡ
delete from kt_tai_lieu where ct_id in (select id from kt_chung_tu where bang = 'cong_ty');
delete from kt_nhat_ky where bang in ('kt_chung_tu', 'kt_tai_lieu') and dong_id in (select id from kt_chung_tu where bang = 'cong_ty');
delete from kt_chung_tu where bang = 'cong_ty';
alter table public.kt_tai_lieu drop column if exists ban_goc, drop column if exists bao_sap_het, drop column if exists bao_het;
alter table public.kt_tai_lieu alter column ncc_id set not null;
alter table public.kt_chung_tu drop constraint if exists kt_chung_tu_bang_check;
alter table public.kt_chung_tu add constraint kt_chung_tu_bang_check check (bang = any (array['thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung','bao_loi','ho_so','ncc','lo_nk','po','de_xuat']));

-- kt_luu_tai_lieu, kt_ncc_ct: về bản trước ngày 12/11
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

CREATE OR REPLACE FUNCTION public.kt_ncc_ct(p_phien text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; n kt_ncc; v_kiot bigint; v_chi bigint[]; v_hs bigint[];
begin
  u := kt_chan(p_phien, 'ncc');
  select * into n from kt_ncc where id = p_id and not da_xoa;
  if n.id is null then raise exception 'Không thấy nhà cung cấp'; end if;
  v_kiot := kt_ncc_kiot(n.loai, n.kiot_id);   -- 31/10 NCC nước ngoài / trung gian: không lấy Kiot
  select coalesce(array_agg(dong_id), '{}') into v_chi from kt_v_ncc_phieu where ncc_id = p_id and bang = 'chi';
  select coalesce(array_agg(id), '{}') into v_hs from kt_ho_so where ncc_id = p_id and not da_xoa;
  return jsonb_build_object(
    'ncc', to_jsonb(n) || jsonb_build_object('nguon', case when v_kiot is null then 'app' else 'kiot' end)
           || coalesce((select jsonb_build_object('cong_no', k.cong_no, 'tong_nhap', k.tong_nhap, 'tong_nhap_tru_tra', k.tong_nhap_tru_tra) from kt_kiot_ncc k where k.id = v_kiot), '{}'),
    'so', kt_ncc_so(p_id),
    'ho_so', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'ten', h.ten, 'loai', h.loai, 'so_hd', h.so_hd, 'ngay', h.ngay, 'gia_tri', h.gia_tri,
        'trang_thai', h.trang_thai, 'ghi_chu', h.ghi_chu, 'tao_boi', h.tao_boi,
        'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'ho_so' and ct.dong_id = h.id and not ct.da_xoa)) order by coalesce(h.ngay, h.tao_luc::date) desc, h.id desc)
      from kt_ho_so h where h.ncc_id = p_id and not h.da_xoa), '[]'),
    'phieu', coalesce((select jsonb_agg(x order by x->>'ngay' desc nulls last, (x->>'id')::bigint desc) from (
        select jsonb_build_object('bang', 'chi', 'id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'noi_dung', c.noi_dung, 'so_tien', c.so_tien,
          'trang_thai', c.trang_thai, 'nguoi_nhan', c.thu_huong_ten, 'stk', c.thu_huong_stk, 'tai_khoan_id', c.tai_khoan_id, 'loai_id', c.loai_id,
          'ho_so_id', p.ho_so_id, 'cach', p.cach, 'tu_gan', exists (select 1 from kt_ncc_gan g where g.bang = 'chi' and g.dong_id = c.id and g.tao_boi = 'Hệ thống (tự gắn)'), 'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'chi' and ct.dong_id = c.id and not ct.da_xoa)) x
          from kt_v_ncc_phieu p join kt_chi c on c.id = p.dong_id where p.bang = 'chi' and p.ncc_id = p_id
        union all
        select jsonb_build_object('bang', 'thu', 'id', t.id, 'ngay', t.ngay, 'noi_dung', t.noi_dung, 'so_tien', t.so_tien, 'trang_thai', t.trang_thai,
          'tai_khoan_id', t.tai_khoan_id, 'loai_id', t.loai_id, 'ho_so_id', p.ho_so_id, 'cach', p.cach,
          'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'thu' and ct.dong_id = t.id and not ct.da_xoa))
          from kt_v_ncc_phieu p join kt_thu t on t.id = p.dong_id where p.bang = 'thu' and p.ncc_id = p_id) z), '[]'),
    'tl', coalesce((select jsonb_object_agg(t.ct_id, jsonb_build_object('thu_muc', t.thu_muc, 'so_hieu', t.so_hieu, 'ngay_bh', t.ngay_bh, 'hl_tu', t.hl_tu, 'hl_den', t.hl_den, 'mo_ta', t.mo_ta, 'ho_so_id', t.ho_so_id, 'sua_boi', t.sua_boi, 'sua_luc', t.sua_luc))
        from kt_tai_lieu t where t.ncc_id = p_id), '{}'),
    'pb', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'chi_id', b.chi_id, 'nhap_id', b.nhap_id, 'so_tien', b.so_tien, 'tao_boi', b.tao_boi)) from kt_ncc_phan_bo b where b.ncc_id = p_id), '[]'),
    'dm', (select nullif(gia_tri, '')::jsonb from kt_cai_dat where khoa = 'tl_danh_muc'),
    'thu_muc', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'ten', m.ten, 'cha', m.cha) order by m.id) from kt_ncc_thu_muc m where m.ncc_id = p_id and not m.da_xoa), '[]'),
    'lo_nk', coalesce((select jsonb_agg(x order by x->>'ma') from (select distinct jsonb_build_object('id', l.id, 'ma', l.ma, 'ten', l.ten, 'trang_thai', l.trang_thai) x from kt_lo_nk_don d join kt_lo_nk l on l.id = d.lo_id where d.ncc_id = p_id and not d.da_xoa and not l.da_xoa) t), '[]'),   -- 30/10 hồ sơ nhập khẩu có đơn của NCC
    'han', coalesce((select nullif(gia_tri, '')::int from kt_cai_dat where khoa = 'han_no_ncc_ngay'), 30),
    'no', case when v_kiot is not null then kt_cong_no_dt_ct(p_phien, 'ncc', v_kiot) end,
    -- 03/11 sổ chi tiết công nợ NCC: tiền trả / thu với NCC trên sổ quỹ Kiot (partnerType S, partnerId = mã NCC Kiot), còn hiệu lực
    'sq', case when v_kiot is not null then coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'ma', q.ma, 'ngay', (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date,
        'tien', q.so_tien, 'thu', q.la_thu, 'nhom', q.nhom, 'nd', q.noi_dung, 'pt', q.phuong_thuc, 'cn', q.chi_nhanh) order by q.ngay)
        from kt_kiot_so_quy q where q.trang_thai = '0' and q.goc->>'partnerType' = 'S' and q.goc->>'partnerId' = v_kiot::text), '[]') end,
    'nhap', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'ngay', h.ngay, 'chi_nhanh', h.chi_nhanh, 'tong', h.tong, 'da_tra', h.da_tra, 'trang_thai', h.trang_thai, 'mo_ta', h.mo_ta,
          'ho_so_id', (select g.ho_so_id from kt_ncc_gan g where g.bang = 'nhap' and g.dong_id = h.id), 'giam_gia', h.giam_gia, 'chi_tiet', h.chi_tiet)
        order by h.ngay desc) from kt_kiot_nhap_hang h where v_kiot is not null and h.ncc_id = v_kiot), '[]'),
    'ct', coalesce((select jsonb_agg(jsonb_build_object('id', ct.id, 'bang', ct.bang, 'dong_id', ct.dong_id, 'ten', ct.ten_file, 'mime', ct.mime, 'tao_boi', ct.tao_boi, 'tao_luc', ct.tao_luc) order by ct.tao_luc desc)
        from kt_chung_tu ct where not ct.da_xoa and ((ct.bang = 'chi' and ct.dong_id = any (v_chi)) or (ct.bang = 'ho_so' and ct.dong_id = any (v_hs)) or (ct.bang = 'ncc' and ct.dong_id = p_id)
          or (ct.bang = 'thu' and ct.dong_id in (select dong_id from kt_v_ncc_phieu where ncc_id = p_id and bang = 'thu')))), '[]'));
end $function$;

-- quyền chứng từ: thêm bang 'po' / 'de_xuat' → trang 'ncc'
CREATE OR REPLACE FUNCTION public.kt_quyen_chung_tu(p_phien text, p_bang text, p_ghi boolean, p_ids bigint[])
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  if p_bang not in ('bao_loi','thu','chi','dieu_chuyen','vay','tai_san','kiem_quy','tam_ung','ho_so','ncc','lo_nk','po','de_xuat') then raise exception 'Bảng chứng từ không hợp lệ'; end if;
  u := kt_chan_dong(p_phien, p_bang, p_ids, p_ghi);
  return u.ho_ten;
end $function$;

CREATE OR REPLACE FUNCTION public.kt_chan_dong(p_phien text, p_bang text, p_ids bigint[], p_ghi boolean)
 RETURNS kt_nguoi_dung
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- 14/10/2026: ảnh kiểm két theo quyền trang Sổ quỹ (dong_tien); 30/10: chứng từ hồ sơ nhập khẩu theo quyền trang Nhà cung cấp
  if kt_co_quyen(u, case p_bang when 'kiem_quy' then 'kiem_ket' when 'lo_nk' then 'ncc' when 'po' then 'ncc' when 'de_xuat' then 'ncc' else p_bang end, p_ghi) then return u; end if;
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
end $function$;
