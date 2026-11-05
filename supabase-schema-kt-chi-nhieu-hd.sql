-- 05/11/2026 anh: "hoá đơn thu chi đều cho nhập được nhiều hoá đơn, vì nhiều khoản hoá đơn công ty nó là nhiều phiếu".
-- Phiếu thu đã nhiều–nhiều (supabase-schema-kt-ghep-hd-thu-2.sql). Phiếu chi trước: 1 HĐ chỉ 1 phiếu (unique hd_ma + hàm chặn "đã ghép phiếu khác"),
-- ô Số hoá đơn 1 số (lưu số mới là xoá HĐ cũ). Nay: 1 HĐ gắn nhiều phiếu chi (trả nhiều đợt), 1 phiếu nhiều HĐ — ô Số hoá đơn nhập nhiều số cách dấu phẩy.
-- Job tự ghép (kt_ghep_hd_vao) vẫn chỉ ghép HĐ chưa gắn phiếu nào (chắc ăn); gắn thêm phiếu thứ 2 do kế toán. — Monsieur Claude
drop index if exists kt_chi_hd_hd_idx;
create index if not exists kt_chi_hd_hd2 on kt_chi_hd (hd_ma);

create or replace function public.kt_ghep_hd_tay(p_phien text, p_chi bigint, p_hd text, p_bo boolean default false) returns void
  language plpgsql security definer set search_path = public as $f$
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
    insert into kt_chi_hd (chi_id, hd_ma, so_hd, ky_hieu, ngay_hd, ncc, mst, tong, cach, diem, boi)
      values (p_chi, h.ma_ngoai, h.so_hd, h.ky_hieu, h.ngay, h.ncc, h.mst, h.tong, 'tay', null, u.ho_ten) on conflict do nothing;
    update kt_chi set hd_do_nhan = true, co_hd_do = true, ngay_nhan_hd = coalesce(ngay_nhan_hd, h.ngay), sua_boi = u.ho_ten, sua_luc = now() where id = p_chi and not da_xoa;
  end if;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu)
    values (u.ho_ten, 'kt_chi', case when p_bo then 'bo_ghep_hd_vao' else 'ghep_hd_vao_tay' end, jsonb_build_object('chi_id', p_chi, 'hd', p_hd));
end $f$;

-- ô Số hoá đơn: nhiều số cách dấu phẩy / chấm phẩy ("3265, 3284" hoặc "C26TYY 3265; 3284"). Mỗi số tìm HĐ MISA (đã gắn phiếu khác vẫn được —
-- trả nhiều đợt); nhiều HĐ cùng số → HĐ đúng tiền phiếu, không có thì chỉ nhận khi ±60 ngày còn đúng 1 HĐ số đó (gõ thêm ký hiệu để chọn). Số không thấy trên MISA giữ ở so_hd_do (khai tay).
-- HĐ đang gắn mà số không còn trong ô → bỏ gắn.
create or replace function public.kt_dat_so_hd(p_phien text, p_id bigint, p_so text) returns jsonb
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung; c kt_chi; v text := nullif(trim(coalesce(p_so, '')), ''); tk text; so text; chu text; h record; ds text[] := '{}'; sos text[] := '{}'; n_khong int := 0;
begin
  u := kt_chan(p_phien, 'chi', true);
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không thấy phiếu'; end if;
  if v is null then
    update kt_chi set so_hd_do = null, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
    return jsonb_build_object('gan', false);
  end if;
  for tk in select trim(x) from regexp_split_to_table(v, '[,;]+') x where trim(x) <> '' loop
    -- số HĐ = nhóm số CUỐI ("C26TYY 3284" → 3284; phần trước là ký hiệu, so chữ: C26TYY → CTYY)
    so := ltrim(coalesce((regexp_match(tk, '(\d+)\D*$'))[1], ''), '0'); chu := upper(regexp_replace(regexp_replace(tk, '\d+\D*$', ''), '[^A-Za-z]', '', 'g'));
    if so = '' then continue; end if;
    sos := sos || so;
    -- nhiều HĐ cùng số (khác NCC / ký hiệu): lấy HĐ đúng tiền phiếu nếu có; không thì chỉ lấy khi trong ±60 ngày còn đúng 1 HĐ số đó
    with ung as (select t.ma_ngoai, t.so_hd, t.ky_hieu, t.ngay, t.nguoi_mua, t.mst, t.tong, abs(t.tong - c.so_tien) <= 1000 dung_tien,
                        abs(t.ngay - coalesce(c.ngay_tt, c.ngay_de_nghi)) <= 60 gan from kt_thue_hd t
                  where t.nguon like 'misabot:%' and t.ma_ngoai is not null and ltrim(t.so_hd, '0') = so
                    and (chu = '' or upper(regexp_replace(coalesce(t.ky_hieu, ''), '[^A-Za-z]', '', 'g')) like '%' || chu || '%')),   -- so chữ với chữ (ký hiệu C26TYY → CTYY)
         chon as (select * from ung where dung_tien union all select * from ung where gan and not exists (select 1 from ung where dung_tien) and (select count(*) from ung where gan) = 1)
    select ma_ngoai, so_hd, ky_hieu, ngay, nguoi_mua, mst, tong into h from chon order by dung_tien desc limit 1;
    if h.ma_ngoai is null then n_khong := n_khong + 1; continue; end if;
    ds := ds || h.ma_ngoai;
    insert into kt_chi_hd (chi_id, hd_ma, so_hd, ky_hieu, ngay_hd, ncc, mst, tong, cach, boi, ly_do)
      values (p_id, h.ma_ngoai, h.so_hd, h.ky_hieu, h.ngay, h.nguoi_mua, h.mst, h.tong, 'tay', u.ho_ten, 'kế toán khai số HĐ')
      on conflict (chi_id, hd_ma) do update set cach = 'tay', boi = u.ho_ten, ly_do = 'kế toán khai số HĐ', luc = now();
  end loop;
  delete from kt_chi_hd where chi_id = p_id and not (hd_ma = any(ds)) and not (ltrim(so_hd, '0') = any(sos));
  update kt_chi set so_hd_do = v, co_hd_do = true, hd_do_nhan = true,
         ngay_nhan_hd = coalesce(ngay_nhan_hd, (select min(ngay_hd) from kt_chi_hd where chi_id = p_id), current_date), sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu)
    values (u.ho_ten, 'kt_chi', 'khai_so_hd', jsonb_build_object('chi_id', p_id, 'so', v, 'gan_misa', cardinality(ds), 'khong_thay', n_khong, 'hd', ds));
  return jsonb_build_object('gan', cardinality(ds) > 0, 'n', cardinality(ds), 'khong_thay', n_khong);
end $f$;

-- tìm HĐ (cả 2 chiều): hiện cả HĐ đã gắn phiếu khác (trả nhiều đợt) kèm số phiếu đã gắn + tiền đã nối
create or replace function public.kt_tim_hd(p_phien text, p_chieu text, p_q text, p_tien numeric default null) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
declare q text := lower(kt_bo_dau(trim(coalesce(p_q, '')))); qs text := ltrim(regexp_replace(coalesce(p_q, ''), '\D', '', 'g'), '0');
begin
  perform kt_chan(p_phien, case when p_chieu = 'ra' then 'thu' else 'chi' end);
  if length(q) < 2 and qs = '' then return '[]'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(z)), '[]') from (
    select case when p_chieu = 'ra' then t.ky_hieu || '-' || t.so_hd else t.ma_ngoai end hd_ma, t.so_hd, t.ky_hieu, t.ngay, t.nguoi_mua ncc, t.nguoi_mua, t.mst, t.tong,
           case when p_chieu = 'ra' then (select count(*) from kt_thu_hd g where g.hd_ma = t.ky_hieu || '-' || t.so_hd)
                else (select count(*) from kt_chi_hd g where g.hd_ma = t.ma_ngoai) end so_phieu,
           case when p_chieu = 'ra' then (select sum(x.so_tien) from kt_thu_hd g join kt_thu x on x.id = g.thu_id where g.hd_ma = t.ky_hieu || '-' || t.so_hd)
                else (select sum(x.so_tien) from kt_chi_hd g join kt_chi x on x.id = g.chi_id where g.hd_ma = t.ma_ngoai) end da_noi
      from kt_thue_hd t
     where (case when p_chieu = 'ra' then t.nguon like 'meinvoice:%' else t.nguon like 'misabot:%' and t.ma_ngoai is not null end)
       and ((qs <> '' and (ltrim(t.so_hd, '0') = qs or t.mst like qs || '%')) or (length(q) >= 2 and lower(kt_bo_dau(coalesce(t.nguoi_mua, ''))) like '%' || q || '%'))
     order by (case when p_chieu = 'ra' then (select count(*) from kt_thu_hd g where g.hd_ma = t.ky_hieu || '-' || t.so_hd)
                    else (select count(*) from kt_chi_hd g where g.hd_ma = t.ma_ngoai) end) > 0,
              abs(t.tong - coalesce(p_tien, t.tong)), t.ngay desc limit 15) z);
end $f$;
