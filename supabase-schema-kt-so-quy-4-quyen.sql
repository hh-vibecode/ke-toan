-- 21/10/2026 (anh): quyền Sổ quỹ tách 4: so_du (Số dư tài khoản) · so_quy (Sổ quỹ theo ngày) · kiem_ket (Kiểm két cuối ngày) · quy_ch (Quỹ tiền mặt cửa hàng).
-- Quyền cũ dong_tien vẫn hiểu = đủ 4 (không ai mất quyền); sửa tài khoản ở trang Phân quyền thì lưu thành 4 quyền mới. Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_co_quyen(u kt_nguoi_dung, p_trang text, p_ghi boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when p_trang = 'chi_gd' then u.vi_tri = 'supreme' or 'chi_gd' = any(u.quyen)
    when p_trang in ('he_thong','phan_quyen','danh_muc','nhat_ky') then u.vi_tri in ('supreme','admin') or '*' = any(u.quyen)
      or 'chi_gd' = any(u.quyen) or 'he_thong' = any(u.quyen)
    else p_trang is null or u.vi_tri in ('supreme','admin') or '*' = any(u.quyen)
      or (p_trang = any(u.quyen) and (not p_ghi or (p_trang || ':ghi') = any(u.quyen)))
      -- 21/10: quyền cũ 'dong_tien' (Sổ quỹ gộp) = đủ 4 quyền mới so_du / so_quy / kiem_ket / quy_ch
      or (p_trang in ('so_du','so_quy','kiem_ket','quy_ch') and 'dong_tien' = any(u.quyen) and (not p_ghi or 'dong_tien:ghi' = any(u.quyen))) end;
$function$;

CREATE OR REPLACE FUNCTION public.kt_so_du_tk(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'so_du');
  return jsonb_build_object(
    'tai_khoan', (with
      bd as (select b.* from kt_v_bien_dong b join kt_tai_khoan tk on tk.id = b.tai_khoan_id where b.ngay >= tk.ngay_ton_dau),
      ton as (
        select tk.id, tk.ten, tk.loai, tk.hoat_dong, tk.thu_tu,
          tk.ton_dau + coalesce(sum(b.vao - b.ra) filter (where b.ngay < p_tu), 0) as dau_ky,
          coalesce(sum(b.vao) filter (where b.ngay between p_tu and p_den and b.kieu in ('thu','vay')), 0) as thu,
          coalesce(sum(b.ra)  filter (where b.ngay between p_tu and p_den and b.kieu in ('chi','vay')), 0) as chi,
          coalesce(sum(b.vao - b.ra) filter (where b.ngay between p_tu and p_den and b.kieu = 'dc'), 0) as dc,
          coalesce(sum(b.vao) filter (where b.ngay between p_tu and p_den and b.kieu = 'vay'), 0) as vay_vao,
          coalesce(sum(b.ra)  filter (where b.ngay between p_tu and p_den and b.kieu = 'vay'), 0) as vay_ra,
          tk.ton_dau + coalesce(sum(b.vao - b.ra) filter (where b.ngay <= p_den), 0) as cuoi_ky
        from kt_tai_khoan tk left join bd b on b.tai_khoan_id = tk.id
        group by tk.id)
      select coalesce(jsonb_agg(to_jsonb(ton) order by thu_tu, id), '[]') from ton
       where hoat_dong or dau_ky <> 0 or cuoi_ky <> 0 or thu <> 0 or chi <> 0 or dc <> 0),
    'thuc_te', (select coalesce(jsonb_agg(jsonb_build_object('tk', tai_khoan_id, 'ngay', ngay, 'so_tien', so_tien)), '[]') from (
       select distinct on (tai_khoan_id) tai_khoan_id, ngay, so_tien from kt_ton_thuc_te where ngay <= p_den
        order by tai_khoan_id, ngay desc) x));
end $function$;

CREATE OR REPLACE FUNCTION public.kt_quy_cua_hang(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'quy_ch');
  return coalesce((select jsonb_agg(jsonb_build_object('ngay', ng, 'cn', chi_nhanh, 'thu', thu, 'chi', chi, 'nop', nop, 'nhan', nhan) order by ng, chi_nhanh) from (
    select (ngay at time zone 'Asia/Ho_Chi_Minh')::date ng, chi_nhanh,
      sum(so_tien) filter (where la_thu and coalesce(nhom,'') <> 'Chuyển rút' and ma !~ '^(TTD_|CTD_)') thu,
      sum(so_tien) filter (where not la_thu and coalesce(nhom,'') <> 'Chuyển rút' and ma !~ '^(TTD_|CTD_)') chi,
      sum(so_tien) filter (where not la_thu and (nhom = 'Chuyển rút' or ma ~ '^CTD_|^CTM|^CNH') and (nhom = 'Chuyển rút')) nop,
      sum(so_tien) filter (where la_thu and nhom = 'Chuyển rút') nhan
    from kt_kiot_so_quy where trang_thai = '0' and phuong_thuc = 'Cash' and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
    group by 1, 2) x), '[]');
end $function$;

CREATE OR REPLACE FUNCTION public.kt_ds_kiem_quy(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'kiem_ket');
  return coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'tk', k.tai_khoan_id, 'ngay', k.ngay, 'so_dem', k.so_dem, 'so_sach', kt_so_du_ngay(k.tai_khoan_id, k.ngay),
      'so_sach_luc_kiem', k.so_sach, 'menh_gia', k.menh_gia, 'ghi_chu', k.ghi_chu, 'nguoi', coalesce(k.sua_boi, k.tao_boi), 'luc', coalesce(k.sua_luc, k.tao_luc),
      'so_anh', (select count(*) from kt_chung_tu c where c.bang = 'kiem_quy' and c.dong_id = k.id and not c.da_xoa)) order by k.ngay desc, k.tai_khoan_id)
    from kt_kiem_quy k where k.ngay between p_tu and p_den), '[]');
end $function$;

CREATE OR REPLACE FUNCTION public.kt_luu_kiem_quy(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_tk int := (p_dong->>'tai_khoan_id')::int; v_ngay date := (p_dong->>'ngay')::date; v_dem numeric := (p_dong->>'so_dem')::numeric; v_id bigint; v_ss numeric;
begin
  u := kt_chan(p_phien, 'kiem_ket', true);
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
end $function$;

CREATE OR REPLACE FUNCTION public.kt_ds_dcf(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'so_du');
  return jsonb_build_object(
    'nap_luc', (select max(nap_luc) from kt_dcf_ngay),
    'dau', (select coalesce(jsonb_agg(jsonb_build_object('tk', tai_khoan_id, 'thang', thang, 'ton', ton_dau)), '[]') from kt_dcf_dau
             where thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM')),
    'ngay', (select coalesce(jsonb_agg(jsonb_build_object('tk', f.tai_khoan_id, 'ngay', f.ngay, 'f_thu', f.thu, 'f_chi', f.chi, 'f_ton', f.ton_ss, 'f_tt', f.ton_tt,
        'a_thu', coalesce(a.thu, 0), 'a_chi', coalesce(a.chi, 0), 'a_ton', kt_so_du_ngay(f.tai_khoan_id, f.ngay),
        'ghi_chu', g.ghi_chu, 'da_xu_ly', coalesce(g.da_xu_ly, false), 'gc_boi', g.sua_boi) order by f.tai_khoan_id, f.ngay), '[]')
        from kt_dcf_ngay f
        left join lateral (select sum(b.vao) thu, sum(b.ra) chi from kt_v_bien_dong b where b.tai_khoan_id = f.tai_khoan_id and b.ngay = f.ngay) a on true
        left join kt_dcf_ghi_chu g on g.tai_khoan_id = f.tai_khoan_id and g.ngay = f.ngay
       where f.ngay between p_tu and p_den));
end $function$;

CREATE OR REPLACE FUNCTION public.kt_luu_dcf_ghi_chu(p_phien text, p_tk integer, p_ngay date, p_ghi_chu text, p_da_xu_ly boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'so_du', true);
  if nullif(btrim(p_ghi_chu), '') is null then delete from kt_dcf_ghi_chu where tai_khoan_id = p_tk and ngay = p_ngay; return; end if;
  insert into kt_dcf_ghi_chu (tai_khoan_id, ngay, ghi_chu, da_xu_ly, sua_boi) values (p_tk, p_ngay, left(btrim(p_ghi_chu), 1000), coalesce(p_da_xu_ly, false), u.ho_ten)
  on conflict (tai_khoan_id, ngay) do update set ghi_chu = excluded.ghi_chu, da_xu_ly = excluded.da_xu_ly, sua_boi = excluded.sua_boi, sua_luc = now();
end $function$;

CREATE OR REPLACE FUNCTION public.kt_luu_ton_thuc_te(p_phien text, p_tai_khoan_id integer, p_ngay date, p_so_tien numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'so_du', true) or kt_co_quyen(u, 'so_quy', true)) then raise exception 'Tài khoản chưa được cấp quyền sửa trang này' using errcode = '42501'; end if;
  if p_so_tien is null then
    delete from kt_ton_thuc_te where tai_khoan_id = p_tai_khoan_id and ngay = p_ngay;
  else
    insert into kt_ton_thuc_te (tai_khoan_id, ngay, so_tien, ghi_boi) values (p_tai_khoan_id, p_ngay, p_so_tien, u.ho_ten)
    on conflict (tai_khoan_id, ngay) do update set so_tien = excluded.so_tien, ghi_boi = excluded.ghi_boi, ghi_luc = now();
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_ton_thuc_te', p_tai_khoan_id, 'ghi',
    jsonb_build_object('ngay', p_ngay, 'so_tien', p_so_tien));
end $function$;

CREATE OR REPLACE FUNCTION public.kt_dong_tien(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'tong_quan') or kt_co_quyen(u, 'so_du') or kt_co_quyen(u, 'so_quy')) then
    raise exception 'Tài khoản chưa được cấp quyền xem dòng tiền' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'dau_ky', (select coalesce(jsonb_object_agg(tk.id, tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b
                 where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau and b.ngay < p_tu), 0)), '{}') from kt_tai_khoan tk),
    'phat_sinh', (select coalesce(jsonb_agg(jsonb_build_object('tk', b.tai_khoan_id, 'ngay', b.ngay, 'kieu', b.kieu,
                   'vao', b.vao, 'ra', b.ra)), '[]')
                  from (select b.tai_khoan_id, b.ngay, b.kieu, sum(b.vao) vao, sum(b.ra) ra from kt_v_bien_dong b
                          join kt_tai_khoan tk on tk.id = b.tai_khoan_id
                         where b.ngay between p_tu and p_den and b.ngay >= tk.ngay_ton_dau
                         group by 1, 2, 3) b),
    -- tổng thu / chi theo ngày cho biểu đồ Tổng quan — KHÔNG lọc theo mốc số dư (09/10/2026: có dữ liệu tháng 5–8 trước mốc số dư 01/09)
    'theo_ngay', (select coalesce(jsonb_agg(jsonb_build_object('ngay', ngay, 'thu', thu, 'chi', chi) order by ngay), '[]') from (
                   select ngay, coalesce(sum(vao) filter (where kieu = 'thu'), 0) thu, coalesce(sum(ra) filter (where kieu = 'chi'), 0) chi
                     from kt_v_bien_dong where ngay between p_tu and p_den group by ngay) x),
    'thuc_te', (select coalesce(jsonb_agg(jsonb_build_object('tk', tai_khoan_id, 'ngay', ngay, 'so_tien', so_tien)), '[]')
                 from kt_ton_thuc_te where ngay between p_tu and p_den));
end $function$;

CREATE OR REPLACE FUNCTION public.kt_so_quy_ngay(p_phien text, p_tk integer, p_ngay date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'tong_quan') or kt_co_quyen(u, 'so_du') or kt_co_quyen(u, 'so_quy')) then raise exception 'Tài khoản chưa được cấp quyền xem dòng tiền' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'kieu', (x->>'id')::bigint) from (
    select jsonb_build_object('kieu', 'thu', 'id', t.id, 'nd', t.noi_dung, 'vao', t.so_tien, 'ra', 0, 'ca_nhan', t.khong_hach_toan) x
      from kt_thu t where not t.da_xoa and t.trang_thai = 'da_duyet' and t.tai_khoan_id = p_tk and t.ngay = p_ngay and not kt_an_thu(u, t.noi_dung)
    union all select jsonb_build_object('kieu', 'chi', 'id', c.id, 'nd', c.noi_dung, 'vao', 0, 'ra', c.so_tien, 'ca_nhan', c.khong_hach_toan, 'doi', c.thu_huong_ten)
      from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.tai_khoan_id = p_tk and c.ngay_tt = p_ngay and not kt_an_thu(u, c.noi_dung)
    union all select jsonb_build_object('kieu', 'dc', 'id', d.id, 'nd', d.noi_dung, 'vao', 0, 'ra', d.so_tien, 'ca_nhan', d.khong_hach_toan, 'doi', 'sang ' || (select ten from kt_tai_khoan where id = d.tk_nhan_id))
      from kt_dieu_chuyen d where not d.da_xoa and d.tk_di_id = p_tk and d.ngay = p_ngay and not kt_an_thu(u, d.noi_dung)
    union all select jsonb_build_object('kieu', 'dc', 'id', d.id, 'nd', d.noi_dung, 'vao', d.so_tien, 'ra', 0, 'ca_nhan', d.khong_hach_toan, 'doi', 'từ ' || (select ten from kt_tai_khoan where id = d.tk_di_id))
      from kt_dieu_chuyen d where not d.da_xoa and d.tk_nhan_id = p_tk and d.ngay = p_ngay and not kt_an_thu(u, d.noi_dung)
    union all select jsonb_build_object('kieu', 'vay', 'id', n.id, 'nd', 'Nhận tiền vay · ' || v.ten, 'vao', n.so_tien, 'ra', 0)
      from kt_vay_nhan n join kt_vay v on v.id = n.vay_id where not n.da_xoa and n.tai_khoan_id = p_tk and n.ngay = p_ngay
    union all select jsonb_build_object('kieu', 'vay', 'id', r.id, 'nd', 'Trả nợ vay · ' || v.ten, 'vao', 0, 'ra', r.goc + r.lai)
      from kt_vay_tra r join kt_vay v on v.id = r.vay_id where not r.da_xoa and r.da_tra and r.tai_khoan_id = p_tk and r.ngay = p_ngay) s), '[]');
end $function$;

CREATE OR REPLACE FUNCTION public.kt_bc_lctt(p_phien text, p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_moc date;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'so_du') or kt_co_quyen(u, 'pl')) then raise exception 'Tài khoản chưa được cấp quyền xem dòng tiền' using errcode = '42501'; end if;
  select max(ngay_ton_dau) into v_moc from kt_tai_khoan where hoat_dong;
  return jsonb_build_object(
    'moc', v_moc,
    -- số dư (tổng các tài khoản — điều chuyển nội bộ tự triệt tiêu) tại ngày dau_ngay = max(p_tu, mốc tồn đầu); trước mốc không có số dư
    'dau_ngay', greatest(p_tu, v_moc),
    'dau', case when greatest(p_tu, v_moc) <= p_den then (select sum(tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b
                 where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau and b.ngay < greatest(p_tu, v_moc)), 0)) from kt_tai_khoan tk) end,
    'thu', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai_id, 'dv', don_vi_id, 'tien', s)), '[]') from (
        select to_char(ngay, 'YYYY-MM') th, case when khong_hach_toan then -1 else loai_id end loai_id, don_vi_id, sum(so_tien) s from kt_thu
         where not da_xoa and trang_thai = 'da_duyet' and ngay between p_tu and p_den group by 1, 2, 3) x),
    'chi', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', loai_id, 'dv', dv, 'tien', s)), '[]') from (
        select to_char(c.ngay_tt, 'YYYY-MM') th, case when c.khong_hach_toan then -1 else c.loai_id end loai_id, (pb->>'don_vi_id')::int dv,
               round(sum(c.so_tien * coalesce((pb->>'so_tien')::numeric / nullif(c.so_tien, 0), 1))) s
          from kt_chi c left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' and jsonb_array_length(c.phan_bo) > 0 then c.phan_bo end) pb on true
         where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between p_tu and p_den group by 1, 2, 3) x),
    -- biến động ròng theo tháng (để ra số dư cuối từng tháng, chỉ phần từ mốc)
    'rong', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'rong', s)), '[]') from (
        select to_char(b.ngay, 'YYYY-MM') th, sum(b.vao - b.ra) s from kt_v_bien_dong b join kt_tai_khoan tk on tk.id = b.tai_khoan_id
         where b.ngay between p_tu and p_den and b.ngay >= tk.ngay_ton_dau group by 1) x),
    -- 15/10/2026: nhận tiền vay / trả nợ vay (trang Vay) — hoạt động tài chính
    'vay', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'nhan', n, 'tra', t)), '[]') from (
        select th, sum(n) n, sum(t) t from (select to_char(ngay, 'YYYY-MM') th, so_tien n, 0 t from kt_vay_nhan where not da_xoa and tai_khoan_id is not null and ngay between p_tu and p_den
          union all select to_char(ngay, 'YYYY-MM'), 0, goc + lai from kt_vay_tra where not da_xoa and da_tra and tai_khoan_id is not null and ngay between p_tu and p_den) z group by 1) x),
    'loai', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'nhom', nhom, 'nhom_bc', nhom_bc, 'thu_tu', thu_tu) order by thu_tu, id), '[]') from kt_loai));
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
end $function$;
