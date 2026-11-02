-- 02/11/2026 anh: "kéo thêm sổ quỹ để đối chiếu phần hoa hồng, vừa kéo hoá đơn vừa xem sổ quỹ xem có thiếu không, 2 cái đối chéo cho nhau;
-- nhiều hoá đơn điền tay sai nên về lý thuyết sổ quỹ giá trị mới chuẩn". — Monsieur Claude
-- kt_kiot_hd_thu: bảng chia tiền Kiot của từng hoá đơn (tổng đã thu + các phiếu) — Kiot không báo "hoá đơn có sửa" khi phiếu thu đến sau,
-- nên lịch kt-kiot-thu-hd-1/2/3 kéo lại mỗi đêm. CHỈ để đối chiếu: số hoa hồng vẫn tính như cũ (da_tra + phân bổ phiếu thu cục).
create table if not exists public.kt_kiot_hd_thu (
  id bigint primary key,   -- id hoá đơn Kiot
  ma text, tong_thu numeric not null default 0, ds jsonb not null default '[]', keo_luc timestamptz not null default now());
alter table public.kt_kiot_hd_thu enable row level security;
revoke all on public.kt_kiot_hd_thu from public, anon, authenticated;
drop trigger if exists kt_chi_xem on public.kt_kiot_hd_thu;
create trigger kt_chi_xem before insert or update or delete on public.kt_kiot_hd_thu for each row execute function public.kt_tg_chi_xem();

-- Đối chéo 2 chiều, sổ quỹ là chuẩn:
--  sổ quỹ → hoá đơn: phiếu thu khách trong kỳ, phần chưa vào hoá đơn 2026 nào (chua_hd); cọc đơn huỷ / không thấy đơn; tiền về cho hoá đơn kỳ trước (truoc).
--  hoá đơn → sổ quỹ: hoá đơn trong kỳ, thực thu app (đã trả + phân bổ phiếu cục) so với tiền có trong sổ quỹ (phiếu chia vào hoá đơn + cọc của đơn); điểm thưởng tách riêng.
create or replace function public.kt_hh_doi_chieu(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql stable security definer set search_path = public as $f$
declare v_cuc jsonb; v_kq jsonb;
begin
  perform kt_chan(p_phien, 'pl');
  select coalesce(jsonb_object_agg(hoa_don_id::text, thu), '{}') into v_cuc from kt_hd_thu_cuc();
  with
    sq as materialized (select q.ma, q.chi_nhanh cn, q.so_tien, q.doi_tac, (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay,
                   case when q.ma ~ '^TTHD' then 'hd' when q.ma ~ '^TTDH' then 'coc' else 'cuc' end kieu
              from kt_kiot_so_quy q where q.la_thu and q.trang_thai = '0' and q.nhom = 'Tiền khách trả'),
    q as (select * from sq where ngay between p_tu and p_den),
    -- mọi khoản Kiot chia vào hoá đơn 2026 còn hiệu lực
    d as materialized (select h.id, h.ma, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay_hd, h.chi_nhanh cn, coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)') nv, h.khach_ten khach,
                   x->>'ma' phieu, (x->>'ngay')::date ngay, (x->>'tien')::numeric tien, x->>'pt' pt, s.ma is not null co_quy
              from kt_kiot_hd_thu t join kt_kiot_hoa_don h on h.id = t.id and h.trang_thai in (1, 3) cross join lateral jsonb_array_elements(t.ds) x left join sq s on s.ma = x->>'ma'),
    k as (select id, sum(tien) filter (where co_quy) quy, sum(tien) filter (where pt = 'Point') diem, string_agg(phieu, ' · ') phieu from d group by 1),
    dg as (select phieu, sum(tien) tien from d group by 1),
    cd as (select regexp_replace(substr(ma, 3), '-[0-9]+$', '') dh, sum(so_tien) tien from sq where kieu = 'coc' group by 1),
    -- phiếu thu cục khách chưa đánh vào hoá đơn trên Kiot (mọi ngày): app đang phân bổ theo khách
    cl as (select sq.doi_tac khach, sum(sq.so_tien - coalesce(dg.tien, 0)) con from sq left join dg on dg.phieu = sq.ma where sq.kieu <> 'coc' and sq.so_tien - coalesce(dg.tien, 0) > 1 group by 1),
    h as (select h.id, h.ma, (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, h.chi_nhanh cn, coalesce(nullif(trim(h.nv_ban), ''), '(không ghi)') nv, h.khach_ten khach, h.tong,
                 least(greatest(coalesce(h.da_tra, 0), 0) + coalesce((v_cuc->>h.id::text)::numeric, 0), h.tong) app,
                 coalesce(k.quy, 0) + coalesce(cd.tien, 0) quy, coalesce(k.diem, 0) diem, t.id is null thieu, k.phieu, dn.ma don
            from kt_kiot_hoa_don h left join kt_kiot_hd_thu t on t.id = h.id
            left join lateral (select o.ma from kt_kiot_dat_hang o where o.id = h.dat_hang_id or (h.dat_hang_id is null and o.ma = nullif(h.ma_dat_hang, '')) limit 1) dn on true
            left join cd on cd.dh = dn.ma
            left join k on k.id = h.id
           where h.trang_thai in (1, 3) and h.tong > 0 and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den),
    hl as (select h.*, app - diem - quy lech, sum(app - diem - quy) over (partition by h.khach) lech_kh, coalesce(cl.con, 0) con_kh from h left join cl on cl.khach = h.khach where not thieu and abs(app - diem - quy) > 1)
  select jsonb_build_object(
      'quy', (select coalesce(jsonb_agg(jsonb_build_object('cn', cn, 'hd', hd, 'cuc', cuc, 'coc', coc) order by cn), '[]') from (
          select cn, coalesce(sum(so_tien) filter (where kieu = 'hd'), 0) hd, coalesce(sum(so_tien) filter (where kieu = 'cuc'), 0) cuc, coalesce(sum(so_tien) filter (where kieu = 'coc'), 0) coc from q group by 1) x),
      -- sổ quỹ có tiền, chưa vào hoá đơn 2026 (hoá đơn trước 2026, hoặc chưa gắn hoá đơn)
      'chua_hd', (select coalesce(jsonb_agg(jsonb_build_object('ma', q.ma, 'ngay', q.ngay, 'cn', q.cn, 'khach', q.doi_tac, 'tien', q.so_tien, 'vao', coalesce(dg.tien, 0), 'con', q.so_tien - coalesce(dg.tien, 0), 'ghep', exists (select 1 from hl where hl.khach = q.doi_tac and hl.lech_kh > 1 and hl.con_kh >= hl.lech_kh - 1)) order by q.ngay desc, q.ma), '[]')
                    from q left join dg on dg.phieu = q.ma where q.kieu <> 'coc' and q.so_tien - coalesce(dg.tien, 0) > 1),
      -- cọc đơn đã huỷ / không thấy đơn: không tính hoa hồng
      'coc_le', (select coalesce(jsonb_agg(jsonb_build_object('ma', q.ma, 'ngay', q.ngay, 'cn', q.cn, 'khach', q.doi_tac, 'tien', q.so_tien, 'huy', o.ma is not null) order by q.ngay desc), '[]')
                   from q left join kt_kiot_dat_hang o on o.ma = regexp_replace(substr(q.ma, 3), '-[0-9]+$', '') where q.kieu = 'coc' and (o.ma is null or o.trang_thai = 4)),
      -- tiền về trong kỳ cho hoá đơn tháng trước: hoa hồng đang tính ở tháng hoá đơn
      'truoc', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay_hd', ngay_hd, 'cn', cn, 'nv', nv, 'khach', khach, 'phieu', phieu, 'ngay', ngay, 'tien', tien) order by ngay desc, ma), '[]')
                  from d where ngay between p_tu and p_den and ngay_hd < p_tu and coalesce(pt, '') <> 'Point'),
      'hd', (select jsonb_build_object('so', count(*), 'tong', coalesce(sum(tong), 0), 'app', coalesce(sum(app), 0), 'quy', coalesce(sum(quy), 0), 'diem', coalesce(sum(diem), 0),
                    'so_diem', count(*) filter (where diem > 0), 'thieu', count(*) filter (where thieu)) from h),
      -- thực thu app khác tiền sổ quỹ (điểm thưởng tách riêng, không tính là lệch)
      'lech', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', ngay, 'cn', cn, 'nv', nv, 'khach', khach, 'tong', tong, 'app', app, 'quy', quy, 'diem', diem, 'lech', lech, 'phieu', phieu, 'don', don,
                 'ghep', lech_kh > 1 and con_kh >= lech_kh - 1) order by abs(lech) desc), '[]') from hl),
      'diem_ds', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', ngay, 'khach', khach, 'nv', nv, 'tong', tong, 'diem', diem) order by ngay desc), '[]') from h where diem > 0),
      'luc', (select max(keo_luc) from kt_kiot_hd_thu)) into v_kq;
  return v_kq;
end $f$;
revoke all on function public.kt_hh_doi_chieu(text, date, date) from public;
grant execute on function public.kt_hh_doi_chieu(text, date, date) to anon, authenticated;


-- lịch mỗi đêm kéo lại bảng chia thu (chia 3 lượt để mỗi lần gọi dưới 150 giây)
select cron.unschedule(jobname) from cron.job where jobname in ('kt-kiot-thu-hd-1', 'kt-kiot-thu-hd-2', 'kt-kiot-thu-hd-3');
select cron.schedule('kt-kiot-thu-hd-1', '45 17 * * *', replace(replace(command, '{"day_du":["hang"]}', '{"thu_hd":{"lui":[0,1,2,3]}}'), '150000', '200000')) from cron.job where jobname = 'kt-kiot-hang-dem';
select cron.schedule('kt-kiot-thu-hd-2', '50 17 * * *', replace(replace(command, '{"day_du":["hang"]}', '{"thu_hd":{"lui":[4,5,6,7]}}'), '150000', '200000')) from cron.job where jobname = 'kt-kiot-hang-dem';
select cron.schedule('kt-kiot-thu-hd-3', '55 17 * * *', replace(replace(command, '{"day_du":["hang"]}', '{"thu_hd":{"lui":[8,9,10,11]}}'), '150000', '200000')) from cron.job where jobname = 'kt-kiot-hang-dem';
