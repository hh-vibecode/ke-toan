-- 31/10/2026 kế toán (anh chuyển chat kèm sơ đồ luồng NCC nước ngoài): "luồng NCC nước ngoài không lấy từ Kiot về đâu, xoá kết nối;
-- chỉ lấy luồng trên Kiot về với NCC trong nước". NCC nước ngoài đi theo luồng trên app (đơn đặt hàng / thanh toán / hồ sơ nhập khẩu).
-- • kt_ncc_kiot(loai, kiot_id): mã Kiot chỉ dùng cho NCC nội địa / dịch vụ; nước ngoài / trung gian → null (coi như NCC tạo trên app).
-- • kt_ds_ncc / kt_ncc_ct: NCC nước ngoài không còn công nợ Kiot, phiếu nhập Kiot, số phiếu nhập; phải trả / ứng trước tính theo hồ sơ như NCC app.
-- • kt_ncc_dong_bo: NCC mới kéo từ Kiot luôn vào nội địa (bỏ tự xếp "TQ / Trung Quốc" → nước ngoài); không đồng bộ tên / SĐT / địa chỉ cho NCC nước ngoài.
-- • kt_ncc_tu_gan / kt_ncc_phan_bo_luu: không chia phiếu chi vào phiếu nhập Kiot cho NCC nước ngoài; gỡ 2 dòng đã tự chia (NCC TQ Đài Niệm Phật, NCC TQ TƯỢNG MR CHEN).
-- Giữ nguyên: 45 NCC nước ngoài (giữ kiot_id để lần kéo Kiot sau không tạo trùng), phiếu chi đã gắn, hồ sơ. Đổi loại về nội địa → số Kiot hiện lại. — Monsieur Claude
create or replace function public.kt_ncc_kiot(p_loai text, p_kiot bigint) returns bigint language sql immutable set search_path = public as $$
  select case when p_loai in ('noi_dia', 'dich_vu') then p_kiot end
$$;
revoke all on function public.kt_ncc_kiot(text, bigint) from public, anon, authenticated;

create or replace function public.kt_ds_ncc(p_phien text, p_tu date DEFAULT NULL::date, p_den date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      select jsonb_agg(jsonb_build_object('id', n.id, 'ma', n.ma, 'ten', n.ten, 'loai', n.loai, 'nguon', case when kt_ncc_kiot(n.loai, n.kiot_id) is null then 'app' else 'kiot' end,
        'sdt', n.sdt, 'so_tk', cardinality(n.stk), 'cong_no', k.cong_no, 'tong_nhap', k.tong_nhap, 'hoat_dong', coalesce(k.hoat_dong, true),
        'so_phieu', coalesce(so.so_phieu, 0), 'da_tra', coalesce(so.da_tra, 0), 'cho_tra', coalesce(so.cho_tra, 0), 'lan_cuoi', so.lan_cuoi, 'so_hs', coalesce(hs.n, 0),
        'email', n.email, 'dia_chi', n.dia_chi, 'so_nhap', coalesce(nh.n, 0),
        'phai_tra', case when kt_ncc_kiot(n.loai, n.kiot_id) is not null then greatest(coalesce(k.cong_no, 0), 0) else coalesce(hn.phai_tra, 0) end,
        'phai_thu', case when kt_ncc_kiot(n.loai, n.kiot_id) is not null then greatest(-coalesce(k.cong_no, 0), 0) else greatest(coalesce(so.da_tra, 0) - coalesce(hn.trong, 0), 0) end)
        order by coalesce(so.so_phieu, 0) desc, coalesce(k.tong_nhap, 0) desc, n.ten)
        from kt_ncc n left join kt_kiot_ncc k on k.id = kt_ncc_kiot(n.loai, n.kiot_id) left join so on so.ncc_id = n.id left join hs on hs.ncc_id = n.id left join nh on nh.ncc_id = kt_ncc_kiot(n.loai, n.kiot_id) left join hn on hn.ncc_id = n.id
       where not n.da_xoa), '[]'),
      'cho', (select count(*) from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and not coalesce(c.ca_nhan, false) and not coalesce(c.la_tam_ung, false)
               and (p_tu is null or c.ngay_tt >= p_tu) and (p_den is null or c.ngay_tt <= p_den)
               and c.id not in (select dong_id from kt_ncc_gan where bang = 'chi') and c.id not in (select dong_id from p where bang = 'chi'))));
end $function$;

create or replace function public.kt_ncc_ct(p_phien text, p_id bigint)
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
    'nhap', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'ngay', h.ngay, 'chi_nhanh', h.chi_nhanh, 'tong', h.tong, 'da_tra', h.da_tra, 'trang_thai', h.trang_thai, 'mo_ta', h.mo_ta,
          'ho_so_id', (select g.ho_so_id from kt_ncc_gan g where g.bang = 'nhap' and g.dong_id = h.id), 'giam_gia', h.giam_gia, 'chi_tiet', h.chi_tiet)
        order by h.ngay desc) from kt_kiot_nhap_hang h where v_kiot is not null and h.ncc_id = v_kiot), '[]'),
    'ct', coalesce((select jsonb_agg(jsonb_build_object('id', ct.id, 'bang', ct.bang, 'dong_id', ct.dong_id, 'ten', ct.ten_file, 'mime', ct.mime, 'tao_boi', ct.tao_boi, 'tao_luc', ct.tao_luc) order by ct.tao_luc desc)
        from kt_chung_tu ct where not ct.da_xoa and ((ct.bang = 'chi' and ct.dong_id = any (v_chi)) or (ct.bang = 'ho_so' and ct.dong_id = any (v_hs)) or (ct.bang = 'ncc' and ct.dong_id = p_id)
          or (ct.bang = 'thu' and ct.dong_id in (select dong_id from kt_v_ncc_phieu where ncc_id = p_id and bang = 'thu')))), '[]'));
end $function$;

create or replace function public.kt_ncc_dong_bo()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_luc timestamptz; v_moi timestamptz;
begin
  select max(keo_luc) into v_moi from kt_kiot_ncc;
  select nullif(gia_tri, '')::timestamptz into v_luc from kt_cai_dat where khoa = 'kt_ncc_dong_bo_luc';
  if v_luc is not null and v_moi is not null and v_luc >= v_moi
     and not exists (select 1 from kt_kiot_ncc k where not exists (select 1 from kt_ncc n where n.kiot_id = k.id)) then return; end if;
  begin
    insert into kt_ncc (kiot_id, ma, ten, sdt, dia_chi, loai, tao_boi)
    select k.id, k.ma, k.ten, k.sdt, k.dia_chi, 'noi_dia', 'Hệ thống'
      from kt_kiot_ncc k where not exists (select 1 from kt_ncc n where n.kiot_id = k.id);
    update kt_ncc n set ma = k.ma, ten = k.ten, sdt = coalesce(k.sdt, n.sdt), dia_chi = coalesce(k.dia_chi, n.dia_chi)
      from kt_kiot_ncc k where k.id = kt_ncc_kiot(n.loai, n.kiot_id) and not n.sua_tay
       and (n.ma is distinct from k.ma or n.ten is distinct from k.ten or (k.sdt is not null and n.sdt is distinct from k.sdt) or (k.dia_chi is not null and n.dia_chi is distinct from k.dia_chi));
    update kt_cai_dat set gia_tri = coalesce(v_moi, now())::text, sua_luc = now() where khoa = 'kt_ncc_dong_bo_luc';
    if not found then insert into kt_cai_dat (khoa, gia_tri, sua_luc) values ('kt_ncc_dong_bo_luc', coalesce(v_moi, now())::text, now()); end if;
  exception when others then null;   -- phiên chỉ xem / tranh ghi: bỏ qua, lần sau đồng bộ
  end;
end $function$;

create or replace function public.kt_ncc_tu_gan(p_ghi boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare T constant text := 'Hệ thống (tự gắn)'; v_a int := 0; v_b int := 0; v_tien numeric := 0; v_ids bigint[]; r record; c record; h record; v_con numeric; v_lay numeric; v_kq jsonb;
begin
  begin
    -- (A) gắn NCC
    select coalesce(array_agg(x.id), '{}') into v_ids from kt_chi x
     where not x.da_xoa and x.trang_thai = 'da_tt' and not coalesce(x.ca_nhan, false) and not coalesce(x.la_tam_ung, false)
       and x.id not in (select dong_id from kt_ncc_gan where bang = 'chi') and x.id not in (select dong_id from kt_v_ncc_phieu where bang = 'chi')
       and not exists (select 1 from kt_nhat_ky k where k.bang = 'kt_chi' and k.dong_id = x.id and k.hanh_dong = 'ho_so_ncc')
       -- chỉ phiếu loại tiền hàng / đặt cọc (kể cả mục con) — phiếu chi phí khác trả cho người trùng tên NCC (vd nhân viên) không tự gắn
       and exists (select 1 from kt_loai l where l.id = x.loai_id and (kt_bo_dau(l.ten) ~ '(tien hang|dat coc)' or l.cha_id in (select id from kt_loai where nhom = 'chi' and kt_bo_dau(ten) ~ '(tien hang|dat coc)')));
    for r in select g.chi_id, (array_agg(g.ncc_id order by g.diem desc))[1] ncc_id from kt_ncc_goi_y_chi(v_ids) g
              group by g.chi_id having count(*) filter (where g.diem = (select max(g2.diem) from kt_ncc_goi_y_chi(array[g.chi_id]) g2)) = 1 loop
      insert into kt_ncc_gan (bang, dong_id, ncc_id, tao_boi) values ('chi', r.chi_id, r.ncc_id, T) on conflict (bang, dong_id) do nothing;
      perform kt_ghi_nhat_ky('Hệ thống', 'kt_chi', r.chi_id, 'tu_gan_ncc', jsonb_build_object('ncc_id', r.ncc_id));
      v_a := v_a + 1;
    end loop;
    -- (B) phân bổ phiếu chi → phiếu nhập
    -- phần tự chia của phiếu chi đã bị bỏ khỏi NCC / đã xoá → gỡ
    delete from kt_ncc_phan_bo b where b.tao_boi = T and not exists (select 1 from kt_v_ncc_phieu p join kt_chi x on x.id = p.dong_id
      where p.bang = 'chi' and p.dong_id = b.chi_id and p.ncc_id = b.ncc_id and x.trang_thai = 'da_tt');
    for r in select n.id ncc_id, n.kiot_id, k.cong_no from kt_ncc n join kt_kiot_ncc k on k.id = kt_ncc_kiot(n.loai, n.kiot_id) where not n.da_xoa
               and exists (select 1 from kt_v_ncc_phieu p where p.bang = 'chi' and p.ncc_id = n.id) loop
      create temp table if not exists _nh (id bigint, ngay date, con numeric) on commit drop; truncate _nh;
      insert into _nh select l.id, l.ngay, l.tra - coalesce((select sum(b.so_tien) from kt_ncc_phan_bo b where b.nhap_id = l.id), 0) from (
          select h2.id, (h2.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay,
                 h2.tong - greatest(least(h2.tong, coalesce(r.cong_no, 0) - (sum(h2.tong) over (order by h2.ngay desc, h2.id desc) - h2.tong)), 0) tra
            from kt_kiot_nhap_hang h2 where h2.ncc_id = r.kiot_id and h2.trang_thai = 3 and h2.tong > 0) l
        where not exists (select 1 from kt_nhat_ky k where k.bang = 'kt_ncc_phan_bo' and k.dong_id = l.id and k.hanh_dong = 'gan_nhap' and k.nguoi <> 'Hệ thống');
      delete from _nh where con <= 1;
      for c in select x.id, x.ngay_tt, x.so_tien - coalesce((select sum(b.so_tien) from kt_ncc_phan_bo b where b.chi_id = x.id), 0) con,
                      coalesce(kt_bo_dau(l.ten), '') ~ '(coc|ung truoc)' coc
                 from kt_v_ncc_phieu p join kt_chi x on x.id = p.dong_id left join kt_loai l on l.id = x.loai_id
                where p.bang = 'chi' and p.ncc_id = r.ncc_id and x.trang_thai = 'da_tt' and not coalesce(x.la_tam_ung, false)
                  and not exists (select 1 from kt_nhat_ky k where k.bang = 'kt_ncc_phan_bo' and k.dong_id = x.id and k.hanh_dong = 'gan_chi' and k.nguoi <> 'Hệ thống')
                order by x.ngay_tt, x.id loop
        v_con := c.con;
        for h in select * from _nh where con > 1 and (c.coc or ngay <= c.ngay_tt) order by ngay, id loop
          exit when v_con <= 1;
          v_lay := least(v_con, h.con);
          insert into kt_ncc_phan_bo (ncc_id, chi_id, nhap_id, so_tien, tao_boi) values (r.ncc_id, c.id, h.id, v_lay, T);
          update _nh set con = con - v_lay where id = h.id;
          v_con := v_con - v_lay; v_b := v_b + 1; v_tien := v_tien + v_lay;
        end loop;
      end loop;
    end loop;
    v_kq := jsonb_build_object('gan_ncc', v_a, 'phan_bo', v_b, 'tien', v_tien);
    if not p_ghi then raise exception 'KT_THU'; end if;
  exception when raise_exception then
    if sqlerrm <> 'KT_THU' then raise; end if;
    return v_kq || jsonb_build_object('thu', true);
  end;
  if v_b > 0 then perform kt_ghi_nhat_ky('Hệ thống', 'kt_ncc_phan_bo', null, 'tu_phan_bo', v_kq); end if;
  return v_kq;
end $function$;

create or replace function public.kt_ncc_phan_bo_luu(p_phien text, p_ncc bigint, p_loai text, p_id bigint, p_ds jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; n kt_ncc; v_n int := 0; r record;
begin
  u := kt_chan(p_phien, 'ncc', true);
  select * into n from kt_ncc where id = p_ncc and not da_xoa;
  if n.id is null then raise exception 'Không thấy nhà cung cấp'; end if;
  if p_loai not in ('nhap','chi') then raise exception 'Tham số không hợp lệ'; end if;
  if p_loai = 'nhap' then delete from kt_ncc_phan_bo where ncc_id = p_ncc and nhap_id = p_id; else delete from kt_ncc_phan_bo where ncc_id = p_ncc and chi_id = p_id; end if;
  for r in select case when p_loai = 'nhap' then (d->>'chi_id')::bigint else p_id end chi_id, case when p_loai = 'nhap' then p_id else (d->>'nhap_id')::bigint end nhap_id,
                  (d->>'so_tien')::numeric so_tien from jsonb_array_elements(coalesce(p_ds, '[]')) d loop
    if not (r.so_tien > 0) then continue; end if;
    if not exists (select 1 from kt_v_ncc_phieu v where v.bang = 'chi' and v.dong_id = r.chi_id and v.ncc_id = p_ncc) then raise exception 'Phiếu chi PC% không thuộc NCC này', lpad(r.chi_id::text, 6, '0'); end if;
    if kt_ncc_kiot(n.loai, n.kiot_id) is null or not exists (select 1 from kt_kiot_nhap_hang h where h.id = r.nhap_id and h.ncc_id = n.kiot_id) then raise exception 'Phiếu nhập không thuộc NCC này'; end if;
    insert into kt_ncc_phan_bo (ncc_id, chi_id, nhap_id, so_tien, tao_boi) values (p_ncc, r.chi_id, r.nhap_id, r.so_tien, u.ho_ten);
    v_n := v_n + 1;
  end loop;
  -- không gắn quá số tiền phiếu chi / phiếu nhập
  if exists (select 1 from kt_ncc_phan_bo b join kt_chi c on c.id = b.chi_id where b.ncc_id = p_ncc group by b.chi_id, c.so_tien having sum(b.so_tien) > max(c.so_tien) + 1) then
    raise exception 'Số tiền gắn vượt số tiền của phiếu chi'; end if;
  if exists (select 1 from kt_ncc_phan_bo b join kt_kiot_nhap_hang h on h.id = b.nhap_id where b.ncc_id = p_ncc group by b.nhap_id, h.tong having sum(b.so_tien) > max(h.tong) + 1) then
    raise exception 'Số tiền gắn vượt giá trị phiếu nhập'; end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_ncc_phan_bo', p_id, 'gan_' || p_loai, jsonb_build_object('ncc_id', p_ncc, 'ds', p_ds));
  return v_n;
end $function$;

delete from public.kt_ncc_phan_bo b using public.kt_ncc n where n.id = b.ncc_id and public.kt_ncc_kiot(n.loai, n.kiot_id) is null;
