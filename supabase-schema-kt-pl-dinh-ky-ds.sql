-- 09/11/2026 anh (đọc phản hồi mục 2 — nút chia nhanh "% doanh số tháng trước"): "chia theo doanh số tháng này chứ, sao lại tháng trước".
-- Khoản định kỳ lặp mỗi tháng → thêm cách chia "% doanh số TỪNG THÁNG": mỗi tháng tự chia Hiền Thủy / Chánh Tâm / BP Sales Sỉ theo doanh thu thuần Kiot
-- (hoá đơn hoàn thành + đang xử lý − trả hàng) của CHÍNH tháng đó (tháng đang chạy = tới hôm nay); tháng chưa có doanh thu → chung. — Monsieur Claude
alter table kt_pl_dinh_ky add column if not exists phan_bo_ds boolean not null default false;

create or replace function public.kt_pl_dinh_ky_luu(p_phien text, p jsonb) returns bigint language plpgsql security definer set search_path = public as $function$
declare u kt_nguoi_dung; v_id bigint := nullif(p->>'id', '')::bigint; v_ds boolean := coalesce((p->>'phan_bo_ds')::boolean, false);
  pb jsonb := case when coalesce((p->>'phan_bo_ds')::boolean, false) then '[]'::jsonb else coalesce(p->'phan_bo', '[]'::jsonb) end;
begin
  u := kt_chan(p_phien, 'pl', true);
  if coalesce((p->>'so_tien')::numeric, 0) <= 0 then raise exception 'Nhập số tiền mỗi tháng'; end if;
  if nullif(p->>'loai_id', '') is null then raise exception 'Chọn loại chi'; end if;
  if coalesce(trim(p->>'ten'), '') = '' then raise exception 'Đặt tên khoản'; end if;
  if nullif(p->>'den_thang', '') is not null and p->>'den_thang' < p->>'tu_thang' then raise exception 'Đến tháng phải sau từ tháng'; end if;
  if jsonb_array_length(pb) > 0 and abs((select sum((x->>'so_tien')::numeric) from jsonb_array_elements(pb) x) - (p->>'so_tien')::numeric) > 1 then
    raise exception 'Tổng phân bổ phải bằng số tiền'; end if;
  if v_id is null then
    insert into kt_pl_dinh_ky (ten, loai_id, loai_con_id, so_tien, phan_bo, phan_bo_ds, tu_thang, den_thang, kieu, ghi_chu, tao_boi)
    values (trim(p->>'ten'), (p->>'loai_id')::int, nullif(p->>'loai_con_id', '')::int, (p->>'so_tien')::numeric, pb, v_ds, p->>'tu_thang', nullif(p->>'den_thang', ''),
            coalesce(nullif(p->>'kieu', ''), 'luon'), nullif(p->>'ghi_chu', ''), u.ho_ten) returning id into v_id;
  else
    update kt_pl_dinh_ky set ten = trim(p->>'ten'), loai_id = (p->>'loai_id')::int, loai_con_id = nullif(p->>'loai_con_id', '')::int, so_tien = (p->>'so_tien')::numeric,
           phan_bo = pb, phan_bo_ds = v_ds, tu_thang = p->>'tu_thang', den_thang = nullif(p->>'den_thang', ''), kieu = coalesce(nullif(p->>'kieu', ''), kieu),
           ghi_chu = nullif(p->>'ghi_chu', ''), sua_boi = u.ho_ten, sua_luc = now() where id = v_id and not da_xoa;
  end if;
  insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values (u.ho_ten, 'kt_pl_dinh_ky', case when p->>'id' is null then 'them' else 'sua' end, p || jsonb_build_object('id', v_id));
  return v_id;
end $function$;

-- tháng: như bản supabase-schema-kt-pl-dinh-ky-ngay.sql (hệ số theo ngày) + nhánh chia % doanh số tháng đó
create or replace function public.kt_pl_dinh_ky_thang(p_phien text, p_tu text, p_den text) returns jsonb
  language plpgsql stable security definer set search_path = public as $function$
declare v_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  perform kt_chan(p_phien, 'pl');
  return (select coalesce(jsonb_agg(z), '[]') from (
    with th as (select to_char(g, 'YYYY-MM') thang, g::date d1, (g + interval '1 month - 1 day')::date d2,
                       case when g::date + interval '1 month' <= date_trunc('month', v_nay) then 1.0
                            when g::date = date_trunc('month', v_nay)::date then extract(day from v_nay) / extract(day from (g + interval '1 month - 1 day'))
                            else 0 end hs
                  from generate_series((greatest(p_tu, '2026-09') || '-01')::date, (p_den || '-01')::date, interval '1 month') g),
    cs as (select id dv, kiot_chi_nhanh cn from kt_don_vi where id in (2, 3, 4)),
    dsm as (select th.thang, cs.dv,
                   greatest(coalesce((select sum(h.tong) from kt_kiot_hoa_don h where h.trang_thai in (1, 3) and h.chi_nhanh = any(cs.cn)
                                       and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between th.d1 and least(th.d2, v_nay)), 0)
                         - coalesce((select sum(t.tong_tra) from kt_kiot_tra_hang t where coalesce(t.trang_thai, 1) = 1 and t.chi_nhanh = any(cs.cn)
                                       and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between th.d1 and least(th.d2, v_nay)), 0), 0) dt
              from th cross join cs),
    dsw as (select thang, dv, dt / nullif(sum(dt) over (partition by thang), 0) w from dsm),
    k as (select d.*, th.thang, th.hs, coalesce(d.loai_con_id, d.loai_id) muc,
                 exists (select 1 from kt_pl_dinh_ky_chot c where c.dinh_ky_id = d.id and c.thang = th.thang) chot
            from kt_pl_dinh_ky d join th on th.thang >= d.tu_thang and (d.den_thang is null or th.thang <= d.den_thang) where not d.da_xoa),
    t as (select k.*, k.so_tien * k.hs so_tien_ky, case when k.kieu = 'uoc_tinh' then coalesce((select sum(h.tien) from kt_v_chi_ht h
                   where h.thang = k.thang and h.loai_id in (select kt_loai_cay(k.muc))), 0) end thuc from k),
    s as (select t.*, case when kieu = 'luon' then so_tien_ky when chot then 0 else greatest(so_tien_ky - thuc, 0) end them from t),
    -- chia cố định (phan_bo) / không chia
    r as (select s.id, s.ten, s.kieu, s.thang, s.muc loai, s.so_tien, s.so_tien_ky, s.hs, s.thuc, s.chot, s.them,
                 (pb->>'don_vi_id')::int dv, case when pb is null then s.them else s.them * (pb->>'so_tien')::numeric / s.so_tien end raw, false theo_ds
            from s left join lateral jsonb_array_elements(case when jsonb_array_length(s.phan_bo) > 0 then s.phan_bo end) pb on true
           where not s.phan_bo_ds or not exists (select 1 from dsw where dsw.thang = s.thang and dsw.w > 0)
          union all
          -- chia % doanh số tháng đó
          select s.id, s.ten, s.kieu, s.thang, s.muc, s.so_tien, s.so_tien_ky, s.hs, s.thuc, s.chot, s.them, w.dv, s.them * w.w, true
            from s join dsw w on w.thang = s.thang and w.w > 0 where s.phan_bo_ds),
    -- làm tròn từng phần, phần lẻ dồn vào dòng cuối → tổng các phần = đúng số khoản (09/11 anh: số và chi tiết phải khớp tuyệt đối)
    rr as (select r.*, row_number() over (partition by id, thang order by dv nulls first) rn, count(*) over (partition by id, thang) cnt,
                  sum(round(raw)) over (partition by id, thang) tong_tron from r)
    select id, ten, kieu, thang, loai, so_tien, round(so_tien_ky) so_tien_ky, round(hs, 4) he_so, round(thuc) thuc, chot, round(them) them, dv,
           case when rn = cnt then round(raw) + round(them) - tong_tron else round(raw) end tien, theo_ds
      from rr) z);
end $function$;
