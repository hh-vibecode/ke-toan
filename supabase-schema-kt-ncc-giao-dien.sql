-- 03/11/2026 kế toán (anh chuyển): "nghiên cứu lại giao diện phần NCC, thấy chưa hợp lý" + anh: "xử lý hết, sắp xếp lại cho dễ nhìn, tham khảo các bên khác".
-- • kt_ds_ncc: + qua_han / so_qh (công nợ Kiot quá hạn theo FIFO như kt_cong_no_dt_ct; nợ cũ hơn phiếu nhập đã kéo = quá hạn), nhap_cuoi, them, so_nk (hồ sơ nhập khẩu).
-- • kt_ncc_ct: + sq = sổ quỹ Kiot của NCC (chi trả NCC / thu từ NCC, theo mã NCC Kiot) → sổ chi tiết công nợ khớp công nợ Kiot. — Monsieur Claude
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
    hn as (select ncc_id, sum(greatest(gia_tri - tra, 0)) phai_tra, sum(least(tra, gia_tri)) trong from ht where gia_tri is not null group by 1),
    -- 03/11 giao diện NCC: quá hạn (Kiot, FIFO) · ngày nhập gần nhất · hồ sơ nhập khẩu
    han as (select coalesce((select nullif(gia_tri, '')::int from kt_cai_dat where khoa = 'han_no_ncc_ngay'), 30) d),
    kn as (select h.ncc_id, h.ngay, h.tong, k.cong_no, sum(h.tong) over (partition by h.ncc_id order by h.ngay desc, h.id desc) cum
             from kt_kiot_nhap_hang h join kt_kiot_ncc k on k.id = h.ncc_id where h.trang_thai = 3 and h.tong > 0 and k.cong_no > 0),
    qh as (select ncc_id, sum(least(tong, cong_no - (cum - tong))) filter (where cum - tong < cong_no and (now() at time zone 'Asia/Ho_Chi_Minh')::date - (ngay at time zone 'Asia/Ho_Chi_Minh')::date >= (select d from han)) tien,
                  count(*) filter (where cum - tong < cong_no and (now() at time zone 'Asia/Ho_Chi_Minh')::date - (ngay at time zone 'Asia/Ho_Chi_Minh')::date >= (select d from han)) so,
                  greatest(max(cong_no) - max(cum), 0) cu from kn group by 1),
    nc as (select ncc_id, max(ngay) ngay from kt_kiot_nhap_hang where trang_thai = 3 group by 1),
    nk as (select d.ncc_id, count(distinct d.lo_id) n from kt_lo_nk_don d join kt_lo_nk l on l.id = d.lo_id where not d.da_xoa and not l.da_xoa group by 1)
    select jsonb_build_object('ncc', coalesce((
      select jsonb_agg(jsonb_build_object('id', n.id, 'ma', n.ma, 'ten', n.ten, 'loai', n.loai, 'nguon', case when kt_ncc_kiot(n.loai, n.kiot_id) is null then 'app' else 'kiot' end,
        'sdt', n.sdt, 'so_tk', cardinality(n.stk), 'cong_no', k.cong_no, 'tong_nhap', k.tong_nhap, 'hoat_dong', coalesce(k.hoat_dong, true),
        'so_phieu', coalesce(so.so_phieu, 0), 'da_tra', coalesce(so.da_tra, 0), 'cho_tra', coalesce(so.cho_tra, 0), 'lan_cuoi', so.lan_cuoi, 'so_hs', coalesce(hs.n, 0),
        'email', n.email, 'dia_chi', n.dia_chi, 'so_nhap', coalesce(nh.n, 0),
        'qua_han', case when kt_ncc_kiot(n.loai, n.kiot_id) is not null and k.cong_no > 0 then coalesce(qh.tien, 0) + coalesce(qh.cu, case when qh.ncc_id is null then k.cong_no else 0 end) else 0 end,
        'so_qh', coalesce(qh.so, 0), 'nhap_cuoi', (nc.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'them', n.them, 'so_nk', coalesce(nk.n, 0),
        'phai_tra', case when kt_ncc_kiot(n.loai, n.kiot_id) is not null then greatest(coalesce(k.cong_no, 0), 0) else coalesce(hn.phai_tra, 0) end,
        'phai_thu', case when kt_ncc_kiot(n.loai, n.kiot_id) is not null then greatest(-coalesce(k.cong_no, 0), 0) else greatest(coalesce(so.da_tra, 0) - coalesce(hn.trong, 0), 0) end)
        order by coalesce(so.so_phieu, 0) desc, coalesce(k.tong_nhap, 0) desc, n.ten)
        from kt_ncc n left join kt_kiot_ncc k on k.id = kt_ncc_kiot(n.loai, n.kiot_id) left join so on so.ncc_id = n.id left join hs on hs.ncc_id = n.id left join nh on nh.ncc_id = kt_ncc_kiot(n.loai, n.kiot_id) left join hn on hn.ncc_id = n.id
        left join qh on qh.ncc_id = kt_ncc_kiot(n.loai, n.kiot_id) left join nc on nc.ncc_id = kt_ncc_kiot(n.loai, n.kiot_id) left join nk on nk.ncc_id = n.id
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

