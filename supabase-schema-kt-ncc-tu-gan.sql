-- 30/10/2026 kế toán (anh chuyển): "cho app tự kết nối thanh toán, làm đến đâu nếu sai chị sẽ sửa sau". — Monsieur Claude
-- kt_ncc_tu_gan(p_ghi): (A) phiếu chi đã chi (loại tiền hàng / đặt cọc) chưa vào NCC, gợi ý có đúng 1 NCC điểm cao nhất → gắn NCC đó;
--   (B) phiếu chi của NCC Kiot chưa phân bổ hết → chia cho phiếu nhập (cũ trước), mỗi phiếu nhập tối đa phần ĐÃ TRẢ theo công nợ Kiot
--       (nợ còn lại tính vào phiếu nhập mới nhất — cùng cách màn NCC), chỉ phiếu nhập có ngày ≤ ngày chi (phiếu cọc / ứng trước: mọi ngày).
-- Đánh dấu tao_boi = 'Hệ thống (tự gắn)'. Phiếu / phiếu nhập người dùng đã gắn hoặc bỏ gắn tay (có nhật ký) → không đụng lại.
-- p_ghi = false: chạy thử, trả số, không ghi.
create or replace function public.kt_ncc_tu_gan(p_ghi boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $f$
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
    for r in select n.id ncc_id, n.kiot_id, k.cong_no from kt_ncc n join kt_kiot_ncc k on k.id = n.kiot_id where not n.da_xoa
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
end $f$;
revoke all on function public.kt_ncc_tu_gan(boolean) from public, anon, authenticated;

-- lịch: mỗi giờ phút 25 (sau lần kéo Kiot phút 17)
select cron.unschedule(jobid) from cron.job where jobname = 'kt-ncc-tu-gan';
select cron.schedule('kt-ncc-tu-gan', '25 * * * *', 'select public.kt_ncc_tu_gan(true)');

-- kt_ncc_ct: phiếu chi thêm cờ tu_gan (NCC do hệ thống tự gắn) để màn NCC hiện nhãn "Tự gắn"
CREATE OR REPLACE FUNCTION public.kt_ncc_ct(p_phien text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; n kt_ncc; v_chi bigint[]; v_hs bigint[];
begin
  u := kt_chan(p_phien, 'ncc');
  select * into n from kt_ncc where id = p_id and not da_xoa;
  if n.id is null then raise exception 'Không thấy nhà cung cấp'; end if;
  select coalesce(array_agg(dong_id), '{}') into v_chi from kt_v_ncc_phieu where ncc_id = p_id and bang = 'chi';
  select coalesce(array_agg(id), '{}') into v_hs from kt_ho_so where ncc_id = p_id and not da_xoa;
  return jsonb_build_object(
    'ncc', to_jsonb(n) || jsonb_build_object('nguon', case when n.kiot_id is null then 'app' else 'kiot' end)
           || coalesce((select jsonb_build_object('cong_no', k.cong_no, 'tong_nhap', k.tong_nhap, 'tong_nhap_tru_tra', k.tong_nhap_tru_tra) from kt_kiot_ncc k where k.id = n.kiot_id), '{}'),
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
    'no', case when n.kiot_id is not null then kt_cong_no_dt_ct(p_phien, 'ncc', n.kiot_id) end,
    'nhap', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'ngay', h.ngay, 'chi_nhanh', h.chi_nhanh, 'tong', h.tong, 'da_tra', h.da_tra, 'trang_thai', h.trang_thai, 'mo_ta', h.mo_ta,
          'ho_so_id', (select g.ho_so_id from kt_ncc_gan g where g.bang = 'nhap' and g.dong_id = h.id), 'giam_gia', h.giam_gia, 'chi_tiet', h.chi_tiet)
        order by h.ngay desc) from kt_kiot_nhap_hang h where n.kiot_id is not null and h.ncc_id = n.kiot_id), '[]'),
    'ct', coalesce((select jsonb_agg(jsonb_build_object('id', ct.id, 'bang', ct.bang, 'dong_id', ct.dong_id, 'ten', ct.ten_file, 'mime', ct.mime, 'tao_boi', ct.tao_boi, 'tao_luc', ct.tao_luc) order by ct.tao_luc desc)
        from kt_chung_tu ct where not ct.da_xoa and ((ct.bang = 'chi' and ct.dong_id = any (v_chi)) or (ct.bang = 'ho_so' and ct.dong_id = any (v_hs)) or (ct.bang = 'ncc' and ct.dong_id = p_id)
          or (ct.bang = 'thu' and ct.dong_id in (select dong_id from kt_v_ncc_phieu where ncc_id = p_id and bang = 'thu')))), '[]'));
end $function$;
