-- 19/11/2026 kế toán: "bên trên giải ngân bằng tiền đô, bên dưới lại bắt khai báo theo NCC bằng tiền tệ — Yongkang nhận tiền, quy đổi đô sang tệ, lại 1 lần tỷ giá nữa
-- mới phân bổ được cho từng NCC" → kt_tt_nn.pb_tien_te (tiền tệ phân bổ, null = như tiền chuyển) + pb_ty_gia (1 đơn vị tiền chuyển = ? tiền phân bổ). — Monsieur Claude
alter table kt_tt_nn add column if not exists pb_tien_te text, add column if not exists pb_ty_gia numeric;

CREATE OR REPLACE FUNCTION public.kt_tt_nn_luu(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v bigint := nullif(p_dong->>'id', '')::bigint; pb jsonb; tong numeric := coalesce(nullif(p_dong->>'so_tien_nt', '')::numeric, 0);
  v_te text := coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'); v_pte text := nullif(p_dong->>'pb_tien_te', ''); v_pty numeric := nullif(p_dong->>'pb_ty_gia', '')::numeric;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if tong <= 0 then raise exception 'Nhập số tiền nguyên tệ'; end if;
  if nullif(p_dong->>'ty_gia', '') is not null and (p_dong->>'ty_gia')::numeric <= 0 then raise exception 'Tỷ giá phải lớn hơn 0'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('ncc_id', nullif(e->>'ncc_id', '')::bigint, 'ncc_ten', e->>'ncc_ten', 'po_id', nullif(e->>'po_id', '')::bigint,
           'so_tien_nt', (e->>'so_tien_nt')::numeric, 'ghi_chu', nullif(btrim(e->>'ghi_chu'), ''))), '[]') into pb
    from jsonb_array_elements(coalesce(p_dong->'phan_bo', '[]')) e where coalesce(nullif(e->>'so_tien_nt', '')::numeric, 0) > 0;
  if exists (select 1 from jsonb_array_elements(pb) e where e->>'ncc_id' is null) then raise exception 'Mỗi dòng phân bổ chọn nhà cung cấp'; end if;
  -- 19/11 kế toán: "giải ngân bằng tiền đô, bên Yongkang nhận rồi quy đổi đô sang tệ 1 lần nữa mới phân bổ cho từng NCC" → phân bổ theo tiền tệ riêng + tỷ giá đổi (1 tiền chuyển = pb_ty_gia tiền phân bổ)
  if v_pte is null or v_pte = v_te then v_pte := null; v_pty := null;
  elsif coalesce(v_pty, 0) <= 0 then raise exception 'Nhập tỷ giá đổi % sang % để phân bổ', v_te, v_pte; end if;
  if (select coalesce(sum((e->>'so_tien_nt')::numeric), 0) from jsonb_array_elements(pb) e) > round(tong * coalesce(v_pty, 1), 2) + 0.01 then raise exception 'Tổng phân bổ lớn hơn số tiền chuyển%', case when v_pty is not null then ' (đã quy đổi sang ' || v_pte || ')' else '' end; end if;
  if v is null then
    insert into kt_tt_nn (ngay, tk_id, chi_id, ben_nhan, tien_te, so_tien_nt, ty_gia, phi, phan_bo, ghi_chu, tao_boi, pb_tien_te, pb_ty_gia)
    values (coalesce(nullif(p_dong->>'ngay', '')::date, current_date), nullif(p_dong->>'tk_id', '')::bigint, nullif(p_dong->>'chi_id', '')::bigint, nullif(btrim(p_dong->>'ben_nhan'), ''),
      coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'), tong, nullif(p_dong->>'ty_gia', '')::numeric, nullif(p_dong->>'phi', '')::numeric, pb, nullif(btrim(p_dong->>'ghi_chu'), ''), u.ho_ten, v_pte, v_pty)
    returning id into v;
  else
    update kt_tt_nn set ngay = coalesce(nullif(p_dong->>'ngay', '')::date, ngay), tk_id = nullif(p_dong->>'tk_id', '')::bigint, chi_id = nullif(p_dong->>'chi_id', '')::bigint,
      ben_nhan = nullif(btrim(p_dong->>'ben_nhan'), ''), tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te), so_tien_nt = tong, ty_gia = nullif(p_dong->>'ty_gia', '')::numeric,
      phi = nullif(p_dong->>'phi', '')::numeric, phan_bo = pb, pb_tien_te = v_pte, pb_ty_gia = v_pty, ghi_chu = nullif(btrim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v and not da_xoa;
    if not found then raise exception 'Không thấy lần thanh toán'; end if;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_tt_nn', v, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v;
end $function$
;

CREATE OR REPLACE FUNCTION public.kt_lo_nk_phi_tt(p_lo bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with lp as (select distinct d.po_id from kt_lo_nk_don d where d.lo_id = p_lo and not d.da_xoa and d.po_id is not null),
  nlo as (select d.po_id, count(distinct d.lo_id) n from kt_lo_nk_don d join kt_lo_nk l on l.id = d.lo_id and not l.da_xoa
           where not d.da_xoa and d.po_id in (select po_id from lp) group by 1),
  pb as (select t.id, t.ngay, t.ben_nhan, t.phi, t.so_tien_nt * coalesce(t.pb_ty_gia, 1) so_tien_nt, (x->>'po_id')::bigint po_id, (x->>'so_tien_nt')::numeric nt
           from kt_tt_nn t cross join lateral jsonb_array_elements(t.phan_bo) x
          where not t.da_xoa and coalesce(t.phi, 0) > 0 and t.so_tien_nt > 0 and nullif(x->>'po_id', '') is not null),
  z as (select pb.id, pb.ngay, pb.ben_nhan, sum(pb.phi * pb.nt / pb.so_tien_nt / nlo.n) s from pb join nlo on nlo.po_id = pb.po_id group by 1, 2, 3)
  select coalesce(jsonb_agg(jsonb_build_object('id', null, 'ao', true, 'tt_id', z.id, 'loai', 'khac', 'ngay', z.ngay, 'tinh_gv', true, 'so_tien', round(z.s),
           'noi_dung', 'Phí chuyển tiền thanh toán trung gian' || coalesce(' · ' || z.ben_nhan, '')) order by z.ngay, z.id) filter (where round(z.s) > 0), '[]'::jsonb)
    from z
$function$
;
