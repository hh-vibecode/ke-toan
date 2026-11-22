-- 02/11/2026 anh: "bảo gỡ rồi mà sao vẫn có khoản phí ở 2 NCC đầu" — NCC nước ngoài / trung gian không tự gắn phiếu chi nữa, gỡ 2 phiếu đã tự gắn 30/10. — Monsieur Claude
delete from kt_ncc_gan g using kt_ncc n where g.ncc_id = n.id and g.bang = 'chi' and g.tao_boi = 'Hệ thống (tự gắn)' and n.loai not in ('noi_dia', 'dich_vu');

CREATE OR REPLACE FUNCTION public.kt_ncc_tu_gan(p_ghi boolean DEFAULT true)
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
      -- 02/11 anh: NCC nước ngoài / trung gian đi luồng trên app, không tự gắn phiếu chi
      if not exists (select 1 from kt_ncc n where n.id = r.ncc_id and n.loai in ('noi_dia', 'dich_vu')) then continue; end if;
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
