-- 6 BÁO CÁO QUẢN TRỊ CÒN LẠI (15/10/2026, anh: "làm hết đi" — nhóm 3..8 trong mẫu 8 nhóm). Monsieur Claude
-- kt_bc_qt(p_loai): 'don' hiệu suất đơn hàng · 'du_kien' dòng tiền dự kiến · 'ngan_sach' chi phí & ngân sách · 'ton' hàng tồn
--                   · 'vay' vay & chi phí tài chính · 'cs' hiệu quả theo cơ sở / kênh. Quyền: trang P&L (pl). Ngân sách nhập trên app.

create table if not exists public.kt_ngan_sach (
  thang text not null check (thang ~ '^\d{4}-\d{2}$'), loai_id int not null references kt_loai(id), so_tien numeric not null default 0,
  sua_boi text, sua_luc timestamptz not null default now(), primary key (thang, loai_id));
alter table public.kt_ngan_sach enable row level security;
revoke all on public.kt_ngan_sach from anon, authenticated;

create or replace function public.kt_luu_ngan_sach(p_phien text, p_thang text, p_ds jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; n int;
begin
  u := kt_chan(p_phien, 'pl', true);
  if p_thang !~ '^\d{4}-\d{2}$' or jsonb_typeof(p_ds) <> 'array' then raise exception 'Dữ liệu ngân sách không hợp lệ'; end if;
  delete from kt_ngan_sach where thang = p_thang and loai_id not in (select (x->>'loai_id')::int from jsonb_array_elements(p_ds) x where coalesce((x->>'so_tien')::numeric, 0) <> 0);
  insert into kt_ngan_sach (thang, loai_id, so_tien, sua_boi)
  select p_thang, (x->>'loai_id')::int, (x->>'so_tien')::numeric, u.ho_ten from jsonb_array_elements(p_ds) x where coalesce((x->>'so_tien')::numeric, 0) <> 0
  on conflict (thang, loai_id) do update set so_tien = excluded.so_tien, sua_boi = excluded.sua_boi, sua_luc = now();
  get diagnostics n = row_count;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_ngan_sach', null, 'luu', jsonb_build_object('thang', p_thang, 'so_dong', n));
  return n;
end $$;

create or replace function public.kt_bc_qt(p_phien text, p_loai text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; r jsonb;
begin
  perform kt_chan(p_phien, 'pl');
  if p_loai = 'don' then
    -- đơn đặt tạo trong kỳ: chia nhóm như Tổng quan (kt_tq_don) · hoá đơn hoàn thành trong kỳ (có / không qua đơn đặt)
    return jsonb_build_object(
      'don', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select to_char((o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, o.chi_nhanh cn, coalesce(kn.ten, 'Không ghi kênh') kenh,
               case when o.trang_thai = 4 then 'huy' when o.trang_thai = 3 then 'di_hang' when o.da_tra > 0 or coalesce(k.cong_no, 0) < 0 then 'coc' else 'bao_gia' end nhom,
               count(*) so, sum(o.tong) tong,
               sum(case when o.trang_thai not in (3, 4) then least(o.tong, greatest(o.da_tra, case when coalesce(k.cong_no, 0) < 0 then -k.cong_no else 0 end)) else 0 end) coc
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id left join kt_kiot_kenh kn on kn.id = o.kenh_id
         where (o.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2, 3, 4) x),
      'hd', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select to_char((h.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, h.chi_nhanh cn, h.dat_hang_id is not null qua_don, count(*) so, sum(h.tong) tong
          from kt_kiot_hoa_don h where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2, 3) x),
      -- đơn đã cọc chưa đi hàng (mọi thời điểm) — doanh số chờ ghi nhận
      'cho', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select o.chi_nhanh cn, to_char((o.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') thang, count(*) so, sum(o.tong) tong, sum(o.da_tra) da_tra
          from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id
         where o.trang_thai not in (3, 4) and (o.da_tra > 0 or coalesce(k.cong_no, 0) < 0) group by 1, 2) x));
  elsif p_loai = 'du_kien' then
    return jsonb_build_object('nay', v_nay,
      'so_du', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'ten', t.ten, 'loai', t.loai, 'so_du', kt_so_du_ngay(t.id, v_nay))), '[]')
                  from kt_tai_khoan t where t.hoat_dong and t.loai <> 'vay' and t.ngay_ton_dau <= v_nay),
      'chi_cho', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'noi_dung', c.noi_dung, 'so_tien', c.so_tien, 'han', c.han_tt, 'trang_thai', c.trang_thai,
                    'ngay', c.ngay_de_nghi) order by coalesce(c.han_tt, c.ngay_de_nghi)), '[]')
                  from kt_chi c where not c.da_xoa and c.trang_thai in ('cho_duyet', 'cho_gd', 'cho_tt')),
      'vay_tra', (select coalesce(jsonb_agg(jsonb_build_object('ngay', t.ngay, 'goc', t.goc, 'lai', t.lai, 'ten', v.ten) order by t.ngay), '[]')
                  from kt_vay_tra t join kt_vay v on v.id = t.vay_id where not t.da_xoa and not v.da_xoa and not t.da_tra),
      'no_kh', (select coalesce(sum(cong_no), 0) from kt_kiot_khach where cong_no > 0),
      'no_ncc', (select coalesce(sum(cong_no), 0) from kt_kiot_ncc where cong_no <> 0),
      'don_coc', (select coalesce(sum(o.tong - least(o.tong, o.da_tra)), 0) from kt_kiot_dat_hang o left join kt_kiot_khach k on k.id = o.khach_id
                   where o.trang_thai not in (3, 4) and (o.da_tra > 0 or coalesce(k.cong_no, 0) < 0)),
      -- bình quân 8 tuần gần nhất (để ước tính tuần tới)
      'thu_tuan', (select coalesce(sum(so_tien), 0) / 8 from kt_thu where not da_xoa and trang_thai = 'da_duyet' and ngay > v_nay - 56 and ngay <= v_nay),
      'chi_tuan', (select coalesce(sum(so_tien), 0) / 8 from kt_chi where not da_xoa and trang_thai = 'da_tt' and ngay_tt > v_nay - 56 and ngay_tt <= v_nay));
  elsif p_loai = 'ngan_sach' then
    return jsonb_build_object(
      'loai', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ten', ten, 'nhom_bc', nhom_bc) order by ten), '[]') from kt_loai where nhom = 'chi' and hoat_dong),
      'ns', (select coalesce(jsonb_agg(jsonb_build_object('thang', thang, 'loai_id', loai_id, 'so_tien', so_tien)), '[]') from kt_ngan_sach
               where thang between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM')),
      'thuc', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai_id', lid, 'tien', s)), '[]') from (
          select coalesce(pt->>'thang', to_char(c.ngay_tt, 'YYYY-MM')) th, c.loai_id lid, sum(coalesce((pt->>'so_tien')::numeric, c.so_tien)) s
            from kt_chi c left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' then c.phan_bo_thang end) pt on true
           where not c.da_xoa and c.trang_thai = 'da_tt'
             and (case when pt is null then c.ngay_tt between p_tu and p_den else pt->>'thang' between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM') end)
           group by 1, 2) x));
  elsif p_loai = 'ton' then
    with ban as (select d->>'ma' ma, sum((d->>'sl')::numeric) sl, sum((d->>'tien')::numeric) dt from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1),
         ban90 as (select distinct d->>'ma' ma from kt_kiot_hoa_don h cross join lateral jsonb_array_elements(h.chi_tiet) d
                  where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date > v_nay - 90),
         hg as (select p.ma, p.ten, kt_nhom_cha(coalesce(p.nhom, '(không nhóm)')) nhom, greatest(p.tong_ton, 0) ton, greatest(p.gia_tri_ton, 0) gt,
                       (select max((t->>'gia_von')::numeric) from jsonb_array_elements(p.ton) t where (t->>'gia_von')::numeric > 0) gv from kt_kiot_hang p where p.dv_goc_id is null)
    select jsonb_build_object('so_ngay', least(p_den, v_nay) - p_tu + 1,
      'gv_ky', (select coalesce(sum(gia_von), 0) from kt_kiot_hoa_don where trang_thai = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
      'ton_cn', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'sl', sl, 'gt', gt, 'so_ma', n) order by gt desc), '[]') from (
          select t->>'cn' cn, sum((t->>'ton')::numeric) sl, sum((t->>'ton')::numeric * coalesce((t->>'gia_von')::numeric, 0)) gt, count(*) n
            from kt_kiot_hang p cross join lateral jsonb_array_elements(p.ton) t where p.dv_goc_id is null and (t->>'ton')::numeric > 0 group by 1) x),
      'nhom', (select coalesce(jsonb_agg(to_jsonb(x) order by x.gt desc), '[]') from (
          select hg.nhom, sum(hg.gt) gt, sum(hg.ton) ton, count(*) filter (where hg.ton > 0) so_ma, coalesce(sum(b.dt), 0) dt, coalesce(sum(b.sl * coalesce(hg.gv, 0)), 0) gv_ban,
                 sum(hg.gt) filter (where hg.ton > 0 and not exists (select 1 from ban90 z where z.ma = hg.ma)) gt_cham
            from hg left join ban b on b.ma = hg.ma group by 1 having sum(hg.gt) > 0 or coalesce(sum(b.dt), 0) > 0) x),
      'cham', (select coalesce(jsonb_agg(to_jsonb(x) order by x.gt desc), '[]') from (
          select hg.ma, hg.ten, hg.nhom, hg.ton, hg.gt from hg where hg.ton > 0 and not exists (select 1 from ban90 z where z.ma = hg.ma) order by hg.gt desc limit 50) x),
      'cham_tong', (select jsonb_build_object('so_ma', count(*), 'gt', coalesce(sum(gt), 0)) from hg where hg.ton > 0 and not exists (select 1 from ban90 z where z.ma = hg.ma)))
      into r;
    return r;
  elsif p_loai = 'vay' then
    return jsonb_build_object(
      'vay', (select coalesce(jsonb_agg(jsonb_build_object('ten', v.ten, 'ben', v.ben_cho_vay, 'so_tien', v.so_tien, 'lai_suat', v.lai_suat, 'dao_han', v.ngay_dao_han, 'xong', v.da_tat_toan,
                'goc_tra', coalesce((select sum(goc) from kt_vay_tra t where t.vay_id = v.id and not t.da_xoa and t.da_tra), 0))), '[]') from kt_vay v where not v.da_xoa),
      'lai', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'goc', g, 'lai', l)), '[]') from (
          select to_char(ngay, 'YYYY-MM') th, sum(goc) g, sum(lai) l from kt_vay_tra where not da_xoa and da_tra and ngay between p_tu and p_den group by 1) x),
      'chi_tc', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'loai', l, 'tien', s)), '[]') from (
          select to_char(c.ngay_tt, 'YYYY-MM') th, lo.ten l, sum(c.so_tien) s from kt_chi c join kt_loai lo on lo.id = c.loai_id
           where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between p_tu and p_den and (lo.nhom_bc = 'Chi tài chính' or lo.ten ~* '^FINANCE') group by 1, 2) x));
  elsif p_loai = 'cs' then
    return jsonb_build_object(
      'dt', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'dt', dt, 'gv', gv, 'so', so)), '[]') from (
          select to_char((ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, chi_nhanh cn, sum(tong) dt, sum(gia_von) gv, count(*) so from kt_kiot_hoa_don
           where trang_thai = 1 and (ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
      -- giá vốn hàng trả = tiền trả × (giá vốn / tổng) của hoá đơn gốc — như P&L (kt_bc_pl2)
      'tra', (select coalesce(jsonb_agg(jsonb_build_object('thang', th, 'cn', cn, 'tra', s, 'gv', gv)), '[]') from (
          select to_char((t.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM') th, t.chi_nhanh cn, sum(t.tong_tra) s, round(sum(t.tong_tra * coalesce(h.gia_von / nullif(h.tong, 0), 0))) gv
            from kt_kiot_tra_hang t left join kt_kiot_hoa_don h on h.id = t.hoa_don_id
           where coalesce(t.trang_thai, 1) = 1 and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x),
      -- chi phí đã trả, chia theo đơn vị chịu chi phí (phan_bo) — tháng theo phân bổ tháng nếu có
      'cp', (select coalesce(jsonb_agg(jsonb_build_object('dv', dv, 'tien', s, 'nhom_bc', nb)), '[]') from (
          select (pb->>'don_vi_id')::int dv, lo.nhom_bc nb, sum((pb->>'so_tien')::numeric * coalesce((pt->>'so_tien')::numeric / nullif(c.so_tien, 0), 1)) s
            from kt_chi c join kt_loai lo on lo.id = c.loai_id cross join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' then c.phan_bo else '[]' end) pb
            left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' then c.phan_bo_thang end) pt on true
           where not c.da_xoa and c.trang_thai = 'da_tt'
             and (case when pt is null then c.ngay_tt between p_tu and p_den else pt->>'thang' between to_char(p_tu, 'YYYY-MM') and to_char(p_den, 'YYYY-MM') end)
           group by 1, 2) x),
      'cp_khong_pb', (select coalesce(sum(c.so_tien), 0) from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between p_tu and p_den
                       and (jsonb_typeof(c.phan_bo) <> 'array' or jsonb_array_length(c.phan_bo) = 0)),
      'kenh', (select coalesce(jsonb_agg(jsonb_build_object('kenh', ten, 'cn', cn, 'dt', dt, 'so', so)), '[]') from (
          select coalesce(k.ten, 'Không ghi kênh (bán tại quầy)') ten, h.chi_nhanh cn, sum(h.tong) dt, count(*) so
            from kt_kiot_hoa_don h left join kt_kiot_kenh k on k.id = h.kenh_id
           where h.trang_thai = 1 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den group by 1, 2) x));
  end if;
  raise exception 'Loại báo cáo không hợp lệ';
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_bc_qt(text, text, date, date)', 'kt_luu_ngan_sach(text, text, jsonb)'] loop
    execute format('revoke execute on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop; end $$;
