-- PHIẾU NHẬP KIOT GẮN VÀO HỒ SƠ (29/10/2026, anh gửi ảnh mẫu popup NCC: cột "Hợp đồng" cho cả phiếu nhập). Monsieur Claude
-- kt_ncc_gan nhận bang 'nhap' (dong_id = kt_kiot_nhap_hang.id); kt_ncc_ct trả id + ho_so_id của phiếu nhập. Phiếu nhập không tính vào số phiếu / đã trả (chỉ phiếu chi / thu).
alter table public.kt_ncc_gan drop constraint if exists kt_ncc_gan_bang_check;
alter table public.kt_ncc_gan add constraint kt_ncc_gan_bang_check check (bang in ('chi','thu','nhap'));

CREATE OR REPLACE FUNCTION public.kt_ncc_gan_phieu(p_phien text, p_bang text, p_ids bigint[], p_kieu text, p_ncc bigint, p_ho_so bigint, p_nho_stk boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_ncc bigint := p_ncc; v_n int := 0; i bigint;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'ncc', true) or (p_bang = 'chi' and kt_co_quyen(u, 'chi_duyet')) or (p_bang = 'thu' and kt_co_quyen(u, 'thu', true))) then
    raise exception 'Tài khoản chưa được cấp quyền gán hồ sơ NCC' using errcode = '42501'; end if;
  if p_bang not in ('chi','thu','nhap') or p_kieu not in ('gan','khong','bo') then raise exception 'Tham số không hợp lệ'; end if;
  if p_ho_so is not null then select ncc_id into v_ncc from kt_ho_so where id = p_ho_so and not da_xoa;
    if v_ncc is null then raise exception 'Không thấy hồ sơ'; end if;
    if p_ncc is not null and p_ncc <> v_ncc then raise exception 'Hồ sơ không thuộc NCC đã chọn'; end if; end if;
  if p_kieu = 'gan' and v_ncc is null then raise exception 'Chọn nhà cung cấp'; end if;
  foreach i in array p_ids loop
    if p_kieu = 'bo' then delete from kt_ncc_gan where bang = p_bang and dong_id = i;
    else
      insert into kt_ncc_gan (bang, dong_id, ncc_id, ho_so_id, tao_boi) values (p_bang, i, case when p_kieu = 'gan' then v_ncc end, case when p_kieu = 'gan' then p_ho_so end, u.ho_ten)
      on conflict (bang, dong_id) do update set ncc_id = excluded.ncc_id, ho_so_id = excluded.ho_so_id, tao_boi = excluded.tao_boi, tao_luc = now();
    end if;
    perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, i, 'ho_so_ncc', jsonb_build_object('kieu', p_kieu, 'ncc_id', v_ncc, 'ho_so_id', p_ho_so));
    v_n := v_n + 1;
  end loop;
  if p_kieu = 'gan' and p_nho_stk and p_bang = 'chi' then
    update kt_ncc n set stk = (select array_agg(distinct s) from unnest(n.stk || array(select kt_so_tk(c.thu_huong_stk) from kt_chi c where c.id = any (p_ids) and kt_so_tk(c.thu_huong_stk) is not null)) s),
           sua_boi = u.ho_ten, sua_luc = now() where n.id = v_ncc;
  end if;
  return v_n;
end $function$;

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
          'ho_so_id', p.ho_so_id, 'cach', p.cach, 'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'chi' and ct.dong_id = c.id and not ct.da_xoa)) x
          from kt_v_ncc_phieu p join kt_chi c on c.id = p.dong_id where p.bang = 'chi' and p.ncc_id = p_id
        union all
        select jsonb_build_object('bang', 'thu', 'id', t.id, 'ngay', t.ngay, 'noi_dung', t.noi_dung, 'so_tien', t.so_tien, 'trang_thai', t.trang_thai,
          'tai_khoan_id', t.tai_khoan_id, 'loai_id', t.loai_id, 'ho_so_id', p.ho_so_id, 'cach', p.cach,
          'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'thu' and ct.dong_id = t.id and not ct.da_xoa))
          from kt_v_ncc_phieu p join kt_thu t on t.id = p.dong_id where p.bang = 'thu' and p.ncc_id = p_id) z), '[]'),
    'han', coalesce((select nullif(gia_tri, '')::int from kt_cai_dat where khoa = 'han_no_ncc_ngay'), 30),
    'no', case when n.kiot_id is not null then kt_cong_no_dt_ct(p_phien, 'ncc', n.kiot_id) end,
    'nhap', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'ma', h.ma, 'ngay', h.ngay, 'chi_nhanh', h.chi_nhanh, 'tong', h.tong, 'da_tra', h.da_tra, 'trang_thai', h.trang_thai, 'mo_ta', h.mo_ta,
          'ho_so_id', (select g.ho_so_id from kt_ncc_gan g where g.bang = 'nhap' and g.dong_id = h.id))
        order by h.ngay desc) from kt_kiot_nhap_hang h where n.kiot_id is not null and h.ncc_id = n.kiot_id), '[]'),
    'ct', coalesce((select jsonb_agg(jsonb_build_object('id', ct.id, 'bang', ct.bang, 'dong_id', ct.dong_id, 'ten', ct.ten_file, 'mime', ct.mime, 'tao_boi', ct.tao_boi, 'tao_luc', ct.tao_luc) order by ct.tao_luc desc)
        from kt_chung_tu ct where not ct.da_xoa and ((ct.bang = 'chi' and ct.dong_id = any (v_chi)) or (ct.bang = 'ho_so' and ct.dong_id = any (v_hs)) or (ct.bang = 'ncc' and ct.dong_id = p_id)
          or (ct.bang = 'thu' and ct.dong_id in (select dong_id from kt_v_ncc_phieu where ncc_id = p_id and bang = 'thu')))), '[]'));
end $function$;
