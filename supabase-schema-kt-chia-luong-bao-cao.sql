-- 16/11/2026: phiếu chi "chia lương / BHXH ngầm" (kt_chi.chia_cp, tổng nhóm = số tiền phiếu) → tách thành dòng ảo mỗi nhóm (cùng id phiếu;
-- so_tien / loai_id cha / loai_con_id / phan_bo theo nhóm) cho báo cáo đọc thẳng kt_chi theo loại (Tổng quan, Lưu chuyển tiền tệ). — Monsieur Claude
create or replace function public.kt_chi_tach_chia() returns setof public.kt_chi
language sql stable security definer set search_path = public as $f$
  select c.* from kt_chi c
   where not (c.chia_cp is not null and (select coalesce(sum((g->>'so_tien')::numeric), 0) from jsonb_array_elements(c.chia_cp->'nhom') g) = c.so_tien)
  union all
  select (jsonb_populate_record(c, jsonb_build_object('so_tien', (g->>'so_tien')::numeric, 'loai_id', coalesce(lg.cha_id, lg.id),
          'loai_con_id', case when lg.cha_id is not null then lg.id end, 'phan_bo', g->'phan_bo'))).*
    from kt_chi c cross join lateral jsonb_array_elements(c.chia_cp->'nhom') g join kt_loai lg on lg.id = (g->>'loai_id')::int
   where c.chia_cp is not null and (select coalesce(sum((g2->>'so_tien')::numeric), 0) from jsonb_array_elements(c.chia_cp->'nhom') g2) = c.so_tien
$f$;
revoke all on function public.kt_chi_tach_chia() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.kt_bao_cao(p_phien text, p_tu date, p_den date, p_chi_theo text DEFAULT 'ngay_tt'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform kt_chan(p_phien, 'tong_quan');
  with
  bd as (select b.*, tk.ngay_ton_dau from kt_v_bien_dong b join kt_tai_khoan tk on tk.id = b.tai_khoan_id
          where b.ngay >= tk.ngay_ton_dau),
  ton as (
    select tk.id, tk.ten, tk.loai, tk.hoat_dong, tk.thu_tu,
      tk.ton_dau + coalesce(sum(b.vao - b.ra) filter (where b.ngay < p_tu), 0) as dau_ky,
      coalesce(sum(b.vao) filter (where b.ngay between p_tu and p_den and b.kieu = 'thu'), 0) as thu,
      coalesce(sum(b.ra)  filter (where b.ngay between p_tu and p_den and b.kieu = 'chi'), 0) as chi,
      coalesce(sum(b.vao - b.ra) filter (where b.ngay between p_tu and p_den and b.kieu = 'dc'), 0) as dc,
      tk.ton_dau + coalesce(sum(b.vao - b.ra) filter (where b.ngay <= p_den), 0) as cuoi_ky
    from kt_tai_khoan tk left join bd b on b.tai_khoan_id = tk.id
    group by tk.id),
  thu_ky as (select t.*, l.ten loai_ten from kt_thu t join kt_loai l on l.id = t.loai_id
              where not t.da_xoa and t.trang_thai = 'da_duyet' and t.ngay between p_tu and p_den),
  chi_ky as (select c.*, l.ten loai_ten, l.nhom_bc, l.cach_chia from kt_chi_tach_chia() c join kt_loai l on l.id = c.loai_id
              where not c.da_xoa and c.trang_thai = 'da_tt'
                and (case when p_chi_theo = 'ngay_su_dung' then coalesce(c.ngay_su_dung, c.ngay_tt) else c.ngay_tt end) between p_tu and p_den),
  -- Tỉ lệ chia chi phí chung = thu (đã duyệt) của từng cơ sở / tổng thu trong kỳ
  thu_dv as (select don_vi_id, sum(so_tien) thu from thu_ky where don_vi_id is not null group by don_vi_id),
  tong_thu as (select nullif(sum(thu), 0) tong from thu_dv),
  chi_rieng as (   -- chi phí riêng: theo phân bổ của phiếu; phiếu không phân bổ → "Chưa phân bổ" (don_vi_id null)
    select (x->>'don_vi_id')::int don_vi_id, c.loai_id, c.loai_ten, (x->>'so_tien')::numeric so_tien
      from chi_ky c cross join lateral jsonb_array_elements(c.phan_bo) x where c.cach_chia = 'rieng'
    union all
    select null, c.loai_id, c.loai_ten, c.so_tien from chi_ky c
     where c.cach_chia = 'rieng' and jsonb_array_length(c.phan_bo) = 0),
  chi_chung as (   -- chi phí chung: chia theo tỉ lệ thu; kỳ không có thu → "Chưa phân bổ"
    select d.don_vi_id, c.loai_id, c.loai_ten, round(c.so_tien * d.thu / tt.tong) so_tien
      from chi_ky c cross join thu_dv d cross join tong_thu tt where c.cach_chia = 'ty_le_thu' and tt.tong is not null
    union all
    select null, c.loai_id, c.loai_ten, c.so_tien from chi_ky c, tong_thu tt where c.cach_chia = 'ty_le_thu' and tt.tong is null),
  chi_dv as (select * from chi_rieng union all select * from chi_chung),
  cno as (select n.*, n.so_tien - n.tra_hang - coalesce((select sum(so_tien) from kt_cong_no_thu
           where cong_no_id = n.id and not da_xoa and ngay <= p_den), 0) con_no
         from kt_cong_no n where not n.da_xoa and n.ngay <= p_den)
  select jsonb_build_object(
    'tu', p_tu, 'den', p_den,
    'tien_vao', (select coalesce(sum(so_tien), 0) from thu_ky),
    'tien_ra',  (select coalesce(sum(so_tien), 0) from chi_ky),
    'dieu_chuyen', (select coalesce(sum(so_tien), 0) from kt_dieu_chuyen where not da_xoa and ngay between p_tu and p_den),
    'ton_dau_ky', (select coalesce(sum(dau_ky), 0) from ton),
    'ton_cuoi_ky', (select coalesce(sum(cuoi_ky), 0) from ton),
    'tai_khoan', (select coalesce(jsonb_agg(to_jsonb(ton) order by thu_tu, id), '[]') from ton
                   where hoat_dong or dau_ky <> 0 or cuoi_ky <> 0 or thu <> 0 or chi <> 0 or dc <> 0),
    'thu_theo_loai', (select coalesce(jsonb_agg(jsonb_build_object('loai', loai_ten, 'so_tien', s) order by s desc), '[]')
                       from (select loai_ten, sum(so_tien) s from thu_ky group by loai_ten) x),
    'chi_theo_loai', (select coalesce(jsonb_agg(jsonb_build_object('loai', loai_ten, 'nhom_bc', nhom_bc, 'cach_chia', cach_chia,
                        'so_tien', s, 'so_phieu', n) order by s desc), '[]')
                       from (select loai_ten, nhom_bc, cach_chia, sum(so_tien) s, count(*) n from chi_ky
                             group by loai_ten, nhom_bc, cach_chia) x),
    'thu_theo_dv', (select coalesce(jsonb_agg(jsonb_build_object('don_vi_id', don_vi_id, 'loai', loai_ten, 'so_tien', s)), '[]')
                     from (select don_vi_id, loai_ten, sum(so_tien) s from thu_ky group by 1, 2) x),
    'chi_theo_dv', (select coalesce(jsonb_agg(jsonb_build_object('don_vi_id', don_vi_id, 'loai', loai_ten, 'so_tien', s)), '[]')
                     from (select don_vi_id, loai_ten, sum(so_tien) s from chi_dv group by 1, 2) x),
    -- Công nợ khách = SỐ KIOT (anh chốt 08/10: "kiot là đủ") — bỏ trang nhập tay khỏi báo cáo. Số Kiot là số HIỆN TẠI.
    'cong_no', (select jsonb_build_object('phai_thu', coalesce(sum(cong_no) filter (where cong_no > 0), 0), 'so_khach_no', count(*) filter (where cong_no > 0),
                  'tra_truoc', coalesce(-sum(cong_no) filter (where cong_no < 0), 0), 'so_tra_truoc', count(*) filter (where cong_no < 0)) from kt_kiot_khach),
    'top_no', (select coalesce(jsonb_agg(jsonb_build_object('khach', ten, 'ma', ma, 'con_no', cong_no) order by cong_no desc), '[]')
                from (select ten, ma, cong_no from kt_kiot_khach where cong_no > 0 order by cong_no desc limit 8) x),
    'dem', jsonb_build_object(
       'cho_duyet', (select count(*) from kt_chi where not da_xoa and trang_thai = 'cho_duyet'),
       'cho_gd',    (select count(*) from kt_chi where not da_xoa and trang_thai = 'cho_gd'),
       'nghi_trung', (select count(*) from kt_chi where not da_xoa and nghi_trung is not null and trang_thai <> 'tu_choi'),
       'nghi_loai', (select count(*) from kt_chi c where not c.da_xoa and kt_nghi_loai(c) is not null),   -- 09/10: loại chi khác luật từ ngày áp dụng app
       'cho_tt',    (select count(*) from kt_chi where not da_xoa and trang_thai = 'cho_tt'),
       'hd_do_chua_nhan', (select count(*) from kt_chi where not da_xoa and trang_thai = 'da_tt' and co_hd_do and not hd_do_nhan and ngay_tt >= date '2026-09-01'),   -- trước T9 không theo dõi nhận HĐ (anh 09/10: trước T9 phiên phiến)
       'chi_thieu_unc', (select count(*) from kt_chi c where c.trang_thai = 'da_tt' and kt_thieu_unc(c)),
       'dc_chua_xac_nhan', (select count(*) from kt_dieu_chuyen where not da_xoa and not da_xac_nhan),
       'thu_cho_duyet', (select count(*) from kt_thu where not da_xoa and trang_thai = 'cho_duyet'),
       'tk_am', (select count(*) from ton where cuoi_ky < 0)),
    'sap_tra', (select coalesce(jsonb_agg(to_jsonb(s) order by s.han nulls last), '[]') from kt_sap_tra s
                 where not s.da_xoa and not s.da_tra),
    'kiot_keo_luc', (select max(keo_luc) from kt_kiot_so_quy)
  ) into r;
  -- Ô kiểu Xero (anh chốt 05/10): số dư sao kê mới nhất / khoản phải trả / tuổi nợ phải thu
  r := r || jsonb_build_object(
    'thuc_te', (select coalesce(jsonb_agg(jsonb_build_object('tk', tai_khoan_id, 'ngay', ngay, 'so_tien', so_tien)), '[]') from (
       select distinct on (tai_khoan_id) tai_khoan_id, ngay, so_tien from kt_ton_thuc_te where ngay <= p_den
        order by tai_khoan_id, ngay desc) x),
    'phai_tra', (select jsonb_build_object(
       'cho_duyet_tien', coalesce(sum(so_tien) filter (where trang_thai = 'cho_duyet'), 0),
       'cho_gd_tien', coalesce(sum(so_tien) filter (where trang_thai = 'cho_gd'), 0),
       'cho_tt_tien', coalesce(sum(so_tien) filter (where trang_thai = 'cho_tt'), 0),
       'qua_han', count(*) filter (where han_tt < (now() at time zone 'Asia/Ho_Chi_Minh')::date),
       'qua_han_tien', coalesce(sum(so_tien) filter (where han_tt < (now() at time zone 'Asia/Ho_Chi_Minh')::date), 0))
       from kt_chi where not da_xoa and trang_thai in ('cho_duyet','cho_gd','cho_tt')),
    -- (tuổi nợ theo trang nhập tay — KHÔNG còn hiện từ 08/10 vì công nợ dùng số Kiot; giữ để tra lại số sheet cũ)
    'no_tuoi', (select coalesce(jsonb_agg(jsonb_build_object('nhom', nhom, 'so_khoan', n, 'con_no', s) order by thu_tu), '[]') from (
       select case when p_den - ngay <= 30 then 'Dưới 30 ngày' when p_den - ngay <= 60 then '31–60 ngày'
                   when p_den - ngay <= 90 then '61–90 ngày' else 'Trên 90 ngày' end nhom,
              min(case when p_den - ngay <= 30 then 1 when p_den - ngay <= 60 then 2 when p_den - ngay <= 90 then 3 else 4 end) thu_tu,
              count(*) n, sum(con_no) s
         from (select n.ngay, n.so_tien - n.tra_hang - coalesce((select sum(t.so_tien) from kt_cong_no_thu t
                 where t.cong_no_id = n.id and not t.da_xoa and t.ngay <= p_den), 0) con_no
               from kt_cong_no n where not n.da_xoa and n.ngay <= p_den) c
        where con_no > 0 group by 1) x));
  return r;
end $function$
;

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
        select to_char(c.ngay_tt, 'YYYY-MM') th, case when c.ca_nhan then -1 else c.loai_id end loai_id, (pb->>'don_vi_id')::int dv,
               round(sum(c.so_tien * coalesce((pb->>'so_tien')::numeric / nullif(c.so_tien, 0), 1))) s
          from kt_chi_tach_chia() c left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' and jsonb_array_length(c.phan_bo) > 0 then c.phan_bo end) pb on true
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
end $function$
;
