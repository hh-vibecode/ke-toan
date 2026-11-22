-- HỒ SƠ NCC — TỐI ƯU TỐC ĐỘ (29/10/2026, anh: "thao tác delay và rất lag"). Monsieur Claude
-- Đo trước: dò phiếu theo số TK (view) ~0,5 s / lần · đồng bộ NCC Kiot mỗi lần mở trang / mở phiếu ~0,5 s · gợi ý tab Chờ phân tính từng phiếu ~1,8 s.
-- • kt_v_ncc_phieu: số TK của NCC trải thành bảng (số TK → NCC) rồi ghép 1 lượt (hash join) thay vì so từng phiếu × từng NCC.
-- • kt_ncc_dong_bo: chỉ chạy khi Kiot có lần kéo NCC mới hơn lần đồng bộ trước (mốc lưu kt_cai_dat 'kt_ncc_dong_bo_luc');
--   lỗi ghi (vd phiên "Xem như" chỉ xem) không làm hỏng trang.
-- • kt_ncc_cho / kt_ncc_tim / kt_ds_ncc: tập phiếu đã thuộc NCC tính 1 lần (not in), gợi ý tính 1 lượt cho cả kỳ.
-- • Gắn trigger chỉ-xem kt_tg_chi_xem cho 3 bảng mới (quy ước supabase-schema-kt-xem-nhu.sql — bản đầu bỏ sót).

create or replace view public.kt_v_ncc_phieu as
  with m as (select distinct on (s) s, n.id ncc_id from kt_ncc n, unnest(n.stk) s where not n.da_xoa order by s, n.id)
  select 'chi'::text bang, c.id dong_id, coalesce(g.ncc_id, m.ncc_id) ncc_id, g.ho_so_id, case when g.id is not null then 'gan' else 'stk' end cach
    from kt_chi c left join kt_ncc_gan g on g.bang = 'chi' and g.dong_id = c.id
    left join m on g.id is null and m.s = kt_so_tk(c.thu_huong_stk)
   where not c.da_xoa and coalesce(g.ncc_id, m.ncc_id) is not null
  union all
  select 'thu', t.id, g.ncc_id, g.ho_so_id, 'gan' from kt_thu t join kt_ncc_gan g on g.bang = 'thu' and g.dong_id = t.id where not t.da_xoa and g.ncc_id is not null;
revoke all on public.kt_v_ncc_phieu from public, anon, authenticated;

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
      from kt_kiot_ncc k where k.id = n.kiot_id and (n.ma is distinct from k.ma or n.ten is distinct from k.ten);
    update kt_cai_dat set gia_tri = coalesce(v_moi, now())::text, sua_luc = now() where khoa = 'kt_ncc_dong_bo_luc';
    if not found then insert into kt_cai_dat (khoa, gia_tri, sua_luc) values ('kt_ncc_dong_bo_luc', coalesce(v_moi, now())::text, now()); end if;
  exception when others then null;   -- phiên chỉ xem / tranh ghi: bỏ qua, lần sau đồng bộ
  end;
end $$;
revoke all on function public.kt_ncc_dong_bo() from public, anon, authenticated;

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
    hs as (select ncc_id, count(*) n from kt_ho_so where not da_xoa group by 1)
    select jsonb_build_object('ncc', coalesce((
      select jsonb_agg(jsonb_build_object('id', n.id, 'ma', n.ma, 'ten', n.ten, 'loai', n.loai, 'nguon', case when n.kiot_id is null then 'app' else 'kiot' end,
        'sdt', n.sdt, 'so_tk', cardinality(n.stk), 'cong_no', k.cong_no, 'tong_nhap', k.tong_nhap, 'hoat_dong', coalesce(k.hoat_dong, true),
        'so_phieu', coalesce(so.so_phieu, 0), 'da_tra', coalesce(so.da_tra, 0), 'cho_tra', coalesce(so.cho_tra, 0), 'lan_cuoi', so.lan_cuoi, 'so_hs', coalesce(hs.n, 0))
        order by coalesce(so.so_phieu, 0) desc, coalesce(k.tong_nhap, 0) desc, n.ten)
        from kt_ncc n left join kt_kiot_ncc k on k.id = n.kiot_id left join so on so.ncc_id = n.id left join hs on hs.ncc_id = n.id
       where not n.da_xoa), '[]'),
      'cho', (select count(*) from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and not coalesce(c.ca_nhan, false) and not coalesce(c.la_tam_ung, false)
               and (p_tu is null or c.ngay_tt >= p_tu) and (p_den is null or c.ngay_tt <= p_den)
               and c.id not in (select dong_id from kt_ncc_gan where bang = 'chi') and c.id not in (select dong_id from p where bang = 'chi'))));
end $$;
grant execute on function public.kt_ds_ncc(text, date, date) to anon, authenticated;

create or replace function public.kt_ncc_cho(p_phien text, p_tu date, p_den date) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_ids bigint[];
begin
  u := kt_chan(p_phien, 'ncc');
  select coalesce(array_agg(c.id), '{}') into v_ids from kt_chi c
   where not c.da_xoa and c.trang_thai = 'da_tt' and not coalesce(c.ca_nhan, false) and not coalesce(c.la_tam_ung, false)
     and (p_tu is null or c.ngay_tt >= p_tu) and (p_den is null or c.ngay_tt <= p_den)
     and c.id not in (select dong_id from kt_ncc_gan where bang = 'chi') and c.id not in (select dong_id from kt_v_ncc_phieu where bang = 'chi');
  return coalesce((with g as (select g.chi_id, jsonb_agg(jsonb_build_object('ncc_id', g.ncc_id, 'ten', n.ten, 'ly_do', g.ly_do) order by g.diem desc, n.ten) gy
                                from kt_ncc_goi_y_chi(v_ids) g join kt_ncc n on n.id = g.ncc_id group by g.chi_id)
    select jsonb_agg(jsonb_build_object('id', c.id, 'ngay', c.ngay_tt, 'noi_dung', c.noi_dung, 'so_tien', c.so_tien, 'nguoi_nhan', c.thu_huong_ten,
      'stk', c.thu_huong_stk, 'loai_id', c.loai_id, 'tai_khoan_id', c.tai_khoan_id, 'goi_y', g.gy) order by c.ngay_tt desc, c.id desc)
      from kt_chi c left join g on g.chi_id = c.id where c.id = any (v_ids)), '[]');
end $$;

-- gợi ý cho 1 NCC (tab "+ Gán thêm phiếu"): tập chưa thuộc NCC tính 1 lần
create or replace function public.kt_ncc_tim(p_phien text, p_ncc bigint, p_q text) returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_ids bigint[]; q text := kt_bo_dau(trim(coalesce(p_q, ''))); v_so numeric := nullif(regexp_replace(coalesce(p_q, ''), '\D', '', 'g'), '')::numeric;
begin
  u := kt_chan(p_phien, 'ncc');
  if q = '' then
    select coalesce(array_agg(c.id), '{}') into v_ids from kt_chi c
     where not c.da_xoa and c.trang_thai not in ('tu_choi','tu_choi_tt') and not coalesce(c.ca_nhan, false) and not coalesce(c.la_tam_ung, false)
       and c.id not in (select dong_id from kt_ncc_gan where bang = 'chi') and c.id not in (select dong_id from kt_v_ncc_phieu where bang = 'chi');
    return coalesce((select jsonb_agg(jsonb_build_object('bang', 'chi', 'id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'noi_dung', c.noi_dung, 'so_tien', c.so_tien,
        'trang_thai', c.trang_thai, 'nguoi_nhan', c.thu_huong_ten, 'stk', c.thu_huong_stk, 'ly_do', g.ly_do) order by coalesce(c.ngay_tt, c.ngay_de_nghi) desc, c.id desc)
      from kt_ncc_goi_y_chi(v_ids) g join kt_chi c on c.id = g.chi_id where g.ncc_id = p_ncc), '[]');
  end if;
  return coalesce((with p as materialized (select v.bang, v.dong_id, n.ten from kt_v_ncc_phieu v join kt_ncc n on n.id = v.ncc_id)
    select jsonb_agg(x order by x->>'ngay' desc nulls last) from (
      (select jsonb_build_object('bang', 'chi', 'id', c.id, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'noi_dung', c.noi_dung, 'so_tien', c.so_tien, 'trang_thai', c.trang_thai,
        'nguoi_nhan', c.thu_huong_ten, 'stk', c.thu_huong_stk, 'ncc_ten', p.ten) x
        from kt_chi c left join p on p.bang = 'chi' and p.dong_id = c.id where not c.da_xoa and c.trang_thai not in ('tu_choi','tu_choi_tt')
         and (kt_bo_dau(coalesce(c.noi_dung, '') || ' ' || coalesce(c.thu_huong_ten, '') || ' ' || coalesce(c.noi_dung_ck, '')) like '%' || q || '%'
              or 'pc' || lpad(c.id::text, 6, '0') = q or (v_so >= 1000 and c.so_tien = v_so) or kt_so_tk(c.thu_huong_stk) = kt_so_tk(p_q))
        order by coalesce(c.ngay_tt, c.ngay_de_nghi) desc limit 50)
      union all
      (select jsonb_build_object('bang', 'thu', 'id', t.id, 'ngay', t.ngay, 'noi_dung', t.noi_dung, 'so_tien', t.so_tien, 'trang_thai', t.trang_thai, 'ncc_ten', p.ten)
        from kt_thu t left join p on p.bang = 'thu' and p.dong_id = t.id where not t.da_xoa and coalesce(t.nguon, '') <> 'kiot'
         and (kt_bo_dau(coalesce(t.noi_dung, '')) like '%' || q || '%' or 'pt' || lpad(t.id::text, 6, '0') = q or (v_so >= 1000 and t.so_tien = v_so))
        order by t.ngay desc limit 20)) z), '[]');
end $$;

-- trigger chỉ-xem cho 3 bảng mới (phiên "Xem như" không ghi được)
do $$ declare t text;
begin
  foreach t in array array['kt_ncc','kt_ho_so','kt_ncc_gan'] loop
    execute format('drop trigger if exists kt_chi_xem on public.%I', t);
    execute format('create trigger kt_chi_xem before insert or update or delete on public.%I for each row execute function public.kt_tg_chi_xem()', t);
  end loop;
end $$;
