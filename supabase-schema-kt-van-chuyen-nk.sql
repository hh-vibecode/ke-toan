-- VẬN CHUYỂN NHẬP KHẨU + PO NỐI TIẾP SAU "ĐANG VẬN CHUYỂN" — 21/11/2026. Monsieur Claude
-- Kế toán trả lời câu hỏi hệ thống (21/11 15:57): (1) 1 PO đi 1 đơn vị vận chuyển, hoặc 1 lô gồm nhiều PO — không cố định; (2) ghi đơn vị, mã vận đơn,
-- ngày đi / dự kiến / về thực tế, phí, hoá đơn vận chuyển (thiếu bổ sung sau); (3) trạng thái PO tự đổi, nhưng phải có chỗ khai ngày hàng về;
-- (4) hàng về kho → kiểm → KT kho nhập phiếu Kiot; (5) phí vận chuyển = phiếu riêng của nhóm đơn vị vận chuyển để theo dõi công nợ với đơn vị đó.
-- + chứng từ: ảnh thanh toán gắn ở phần thanh toán, PO tự hiện; hoá đơn NCC gắn ở PO, 1 ô; giao dịch nào liên quan PO thì hiện ở PO.
-- Làm (dựng trên Hồ sơ nhập khẩu = lô vận chuyển, không tạo luồng song song):
--   kt_ncc.loai thêm 'van_chuyen' (Đơn vị vận chuyển, nằm trong NCC nước ngoài → công nợ / phiếu chi gắn NCC / phân bổ thanh toán trung gian dùng sẵn).
--   kt_lo_nk thêm dv_vc_id (đơn vị vận chuyển) + ma_van_don. 1 PO đi riêng = 1 lô chỉ có PO đó.
--   Trạng thái tự đổi: khai ngày đi (≤ hôm nay) → lô "Đang vận chuyển"; khai ngày về thực tế → lô "Đã về kho";
--   lô Đang vận chuyển / thông quan → PO "Đang vận chuyển"; lô Đã về kho / Hoàn tất → PO "Hàng đã về kho" (PO đi nhiều lô: lô cuối về mới đổi). Không lùi trạng thái, không đụng PO đã giao khách / huỷ.
--   kt_po_ds trả lô của từng PO (+ phí vận chuyển, phiếu chi của phí); kt_ds_lo_nk trả tên đơn vị VC, phí VC, PO; kt_tt_nn_ds trả loại NCC từng dòng phân bổ.
alter table public.kt_ncc drop constraint if exists kt_ncc_loai_check;
alter table public.kt_ncc add constraint kt_ncc_loai_check check (loai = any (array['noi_dia', 'nuoc_ngoai', 'trung_gian', 'dich_vu', 'van_chuyen']));
alter table public.kt_lo_nk add column if not exists dv_vc_id bigint, add column if not exists ma_van_don text;

create or replace function public.kt_lo_nk_tu_tt() returns trigger language plpgsql set search_path = public as $$
begin
  if new.ngay_ve is not null and (tg_op = 'INSERT' or old.ngay_ve is distinct from new.ngay_ve) and new.trang_thai in ('dat_hang', 'san_xuat', 'van_chuyen', 'thong_quan') then
    new.trang_thai := 've_kho';
  elsif new.ngay_kh is not null and new.ngay_kh <= (now() at time zone 'Asia/Ho_Chi_Minh')::date and (tg_op = 'INSERT' or old.ngay_kh is distinct from new.ngay_kh) and new.trang_thai in ('dat_hang', 'san_xuat') then
    new.trang_thai := 'van_chuyen';
  end if;
  return new;
end $$;
drop trigger if exists kt_lo_nk_tu_tt on public.kt_lo_nk;
create trigger kt_lo_nk_tu_tt before insert or update of ngay_ve, ngay_kh on public.kt_lo_nk for each row execute function public.kt_lo_nk_tu_tt();

create or replace function public.kt_lo_nk_po_tt(p_lo bigint) returns int language plpgsql security definer set search_path = public as $$
declare v_n int; v_ds jsonb;
begin
  with doi as (
    update kt_po p set trang_thai = case when l.trang_thai in ('ve_kho', 'hoan_tat') then 'da_nhan' else 'dang_giao' end, sua_boi = 'Hệ thống', sua_luc = now()
      from kt_lo_nk l join kt_lo_nk_don d on d.lo_id = l.id and not d.da_xoa
     where l.id = p_lo and not l.da_xoa and d.po_id = p.id and not p.da_xoa
       and ((l.trang_thai in ('van_chuyen', 'thong_quan') and p.trang_thai in ('nhap', 'da_gui', 'dang_sx'))
         or (l.trang_thai in ('ve_kho', 'hoan_tat') and p.trang_thai in ('nhap', 'da_gui', 'dang_sx', 'dang_giao')
             and not exists (select 1 from kt_lo_nk_don d2 join kt_lo_nk l2 on l2.id = d2.lo_id and not l2.da_xoa
                              where d2.po_id = p.id and not d2.da_xoa and l2.id <> l.id and l2.trang_thai not in ('ve_kho', 'hoan_tat'))))
    returning p.id, p.so, p.trang_thai)
  select count(*), jsonb_agg(jsonb_build_object('id', id, 'so', so, 'tt', trang_thai)) into v_n, v_ds from doi;
  if v_n > 0 then perform kt_ghi_nhat_ky('Hệ thống', 'kt_po', null, 'po_theo_lo', jsonb_build_object('lo_id', p_lo, 'po', v_ds)); end if;
  return v_n;
end $$;
revoke all on function public.kt_lo_nk_po_tt(bigint) from public, anon, authenticated;
-- (PL/pgSQL đọc new.lo_id cả khi bảng là kt_lo_nk → lỗi; tách 2 hàm — phát hiện khi thử, sửa 21/11)
create or replace function public.kt_lo_nk_po_tt_tg() returns trigger language plpgsql security definer set search_path = public as $
begin perform kt_lo_nk_po_tt(new.id); return null; end $;
create or replace function public.kt_lo_nk_don_po_tt_tg() returns trigger language plpgsql security definer set search_path = public as $
begin perform kt_lo_nk_po_tt(new.lo_id); return null; end $;
drop trigger if exists kt_lo_nk_po_tt on public.kt_lo_nk;
create trigger kt_lo_nk_po_tt after insert on public.kt_lo_nk for each row execute function public.kt_lo_nk_po_tt_tg();
-- (update of trang_thai không chạy khi trạng thái do trigger trước đổi theo ngày → xét theo giá trị cũ / mới)
drop trigger if exists kt_lo_nk_po_tt_sua on public.kt_lo_nk;
create trigger kt_lo_nk_po_tt_sua after update on public.kt_lo_nk for each row when (old.trang_thai is distinct from new.trang_thai) execute function public.kt_lo_nk_po_tt_tg();
drop trigger if exists kt_lo_nk_don_po_tt on public.kt_lo_nk_don;
create trigger kt_lo_nk_don_po_tt after insert or update of po_id, lo_id, da_xoa on public.kt_lo_nk_don for each row execute function public.kt_lo_nk_don_po_tt_tg();

CREATE OR REPLACE FUNCTION public.kt_luu_lo_nk(p_phien text, p_dong jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint; v_nam text; v_ma text; v_n int;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if nullif(trim(p_dong->>'ten'), '') is null then raise exception 'Nhập tên lô hàng'; end if;
  if nullif(p_dong->>'ty_gia', '') is not null and (p_dong->>'ty_gia')::numeric <= 0 then raise exception 'Tỷ giá phải lớn hơn 0'; end if;
  if nullif(p_dong->>'dv_vc_id', '') is not null and not exists (select 1 from kt_ncc where id = (p_dong->>'dv_vc_id')::bigint and not da_xoa) then raise exception 'Không thấy đơn vị vận chuyển'; end if;
  if v_id is null then
    v_nam := to_char(coalesce(nullif(p_dong->>'ngay_kh', '')::date, current_date), 'YYYY');
    select coalesce(max(nullif(regexp_replace(ma, '^NK-' || v_nam || '-', ''), ma)::int), 0) + 1 into v_n from kt_lo_nk where ma ~ ('^NK-' || v_nam || '-[0-9]+$');
    v_ma := coalesce(nullif(trim(p_dong->>'ma'), ''), 'NK-' || v_nam || '-' || lpad(v_n::text, 2, '0'));
    if exists (select 1 from kt_lo_nk where ma = v_ma) then raise exception 'Mã hồ sơ % đã có', v_ma; end if;
    insert into kt_lo_nk (ma, ten, trang_thai, so_cont, forwarder, ngay_kh, ngay_du_kien, ngay_ve, tien_te, ty_gia, cach_pb, ghi_chu, tao_boi)
    values (v_ma, trim(p_dong->>'ten'), coalesce(nullif(p_dong->>'trang_thai', ''), 'dat_hang'), nullif(trim(p_dong->>'so_cont'), ''), nullif(trim(p_dong->>'forwarder'), ''),
      nullif(p_dong->>'ngay_kh', '')::date, nullif(p_dong->>'ngay_du_kien', '')::date, nullif(p_dong->>'ngay_ve', '')::date,
      coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'), nullif(p_dong->>'ty_gia', '')::numeric, coalesce(nullif(p_dong->>'cach_pb', ''), 'gia_tri'), nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten)
    returning id into v_id;
  else
    if nullif(trim(p_dong->>'ma'), '') is not null and exists (select 1 from kt_lo_nk where ma = trim(p_dong->>'ma') and id <> v_id) then raise exception 'Mã hồ sơ % đã có', trim(p_dong->>'ma'); end if;
    update kt_lo_nk set ma = coalesce(nullif(trim(p_dong->>'ma'), ''), ma), ten = trim(p_dong->>'ten'), trang_thai = coalesce(nullif(p_dong->>'trang_thai', ''), trang_thai),
      so_cont = nullif(trim(p_dong->>'so_cont'), ''), forwarder = nullif(trim(p_dong->>'forwarder'), ''),
      ngay_kh = nullif(p_dong->>'ngay_kh', '')::date, ngay_du_kien = nullif(p_dong->>'ngay_du_kien', '')::date, ngay_ve = nullif(p_dong->>'ngay_ve', '')::date,
      tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te), ty_gia = nullif(p_dong->>'ty_gia', '')::numeric, cach_pb = coalesce(nullif(p_dong->>'cach_pb', ''), cach_pb),
      ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
    if not found then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  end if;
  update kt_lo_nk set cang_di = nullif(trim(p_dong->>'cang_di'), ''), cang_den = nullif(trim(p_dong->>'cang_den'), ''), dv_xuat_khau = nullif(trim(p_dong->>'dv_xuat_khau'), ''),
    dv_nhan_tien = nullif(trim(p_dong->>'dv_nhan_tien'), ''), dv_mo_tk = nullif(trim(p_dong->>'dv_mo_tk'), ''),
    dv_vc_id = nullif(p_dong->>'dv_vc_id', '')::bigint, ma_van_don = nullif(trim(p_dong->>'ma_van_don'), '') where id = v_id;   -- 21/11 đơn vị vận chuyển + mã vận đơn
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.kt_ds_lo_nk(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(to_jsonb(l) || jsonb_build_object(
      'so_don', (select count(*) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa),
      'ncc', (select coalesce(jsonb_agg(distinct n.ten), '[]') from kt_lo_nk_don d join kt_ncc n on n.id = d.ncc_id where d.lo_id = l.id and not d.da_xoa),
      'gia_tri', (select coalesce(sum(kt_lo_nk_don_vnd(d, l)), 0) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa),
      'gia_tri_te', (select sum(d.gia_tri) from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa and coalesce(d.tien_te, l.tien_te) = l.tien_te),
      'chi_phi', (select coalesce(sum(c.so_tien), 0) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and c.tinh_gv)
                   + coalesce((select sum((x->>'so_tien')::numeric) from jsonb_array_elements(kt_lo_nk_phi_tt(l.id)) x), 0),
      'chi_phi_khac', (select coalesce(sum(c.so_tien), 0) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and not c.tinh_gv),
      'so_ct', (select count(*) from kt_chung_tu ct where ct.bang = 'lo_nk' and ct.dong_id = l.id and not ct.da_xoa),
      'dv_vc_ten', (select ten from kt_ncc where id = l.dv_vc_id),
      'phi_vc', (select coalesce(sum(c.so_tien), 0) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and c.loai in ('van_chuyen_qt', 'van_chuyen_nd')),
      'po_ids', (select coalesce(jsonb_agg(distinct d.po_id), '[]') from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa and d.po_id is not null),
      'kk', kt_lo_nk_kk_tong(l))
    order by coalesce(l.ngay_kh, l.tao_luc::date) desc, l.id desc) from kt_lo_nk l where not l.da_xoa), '[]');
end $function$;

CREATE OR REPLACE FUNCTION public.kt_tt_nn_ds(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(to_jsonb(t) - 'da_xoa' || jsonb_build_object('phan_bo', (select coalesce(jsonb_agg(x || jsonb_build_object('ncc_loai', (select loai from kt_ncc where id = nullif(x->>'ncc_id', '')::bigint))), '[]') from jsonb_array_elements(coalesce(t.phan_bo, '[]')) x)) || jsonb_build_object('tk', (select ten from kt_tai_khoan where id = t.tk_id), 'tk_loai', (select loai from kt_tai_khoan where id = t.tk_id), 'vay_ten', (select ten from kt_vay where id = t.vay_id and not da_xoa),
      'ra', kt_tt_nn_ra(t),
      'chi', (select jsonb_build_object('id', c.id, 'so_tien', c.so_tien, 'tt', c.trang_thai, 'ngay', c.ngay_tt) from kt_chi c where c.id = t.chi_id and not c.da_xoa),
      'nghi_trung', case when t.chi_id is null and t.tk_id is not null and kt_tt_nn_ra(t) > 0 then (select jsonb_agg(jsonb_build_object('id', c.id, 'ngay', c.ngay_tt, 'nd', left(c.noi_dung, 80)) order by abs(c.ngay_tt - t.ngay))
          from kt_chi c where not c.da_xoa and c.trang_thai = 'da_tt' and c.tai_khoan_id = t.tk_id and c.ngay_tt between t.ngay - 10 and t.ngay + 10
           and abs(c.so_tien - kt_tt_nn_ra(t)) < 1 and not exists (select 1 from kt_tt_nn o where o.chi_id = c.id and not o.da_xoa)) end) order by t.ngay desc, t.id desc)
    from kt_tt_nn t where not t.da_xoa), '[]');
end $function$;

CREATE OR REPLACE FUNCTION public.kt_po_ds(p_phien text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform kt_chan(p_phien, 'ncc');
  return jsonb_build_object(
    'po', coalesce((select jsonb_agg(to_jsonb(p) - 'da_xoa' order by p.ngay desc, p.id desc) from kt_po p where not p.da_xoa), '[]'),
    'ben_mua', (select gia_tri from kt_cai_dat where khoa = 'po_ben_mua'),
    -- phiếu chi đã gắn vào PO (số tiền VND, trạng thái thật trên Thu chi)
    'chi', coalesce((select jsonb_object_agg(c.id, jsonb_build_object('ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'so_tien', c.so_tien, 'tt', c.trang_thai, 'nd', c.noi_dung, 'th', c.thu_huong_ten))
      from kt_chi c where not c.da_xoa and c.id in (select (e)::bigint from kt_po p, jsonb_array_elements_text(p.chi_ids) e where not p.da_xoa)), '{}'),
    -- 21/11 kế toán: PO hiện lô vận chuyển chứa nó (đơn vị, mã vận đơn, các mốc ngày, phí vận chuyển + phiếu chi của phí)
    'lo', coalesce((select jsonb_object_agg(x.po_id, x.ds) from (select d.po_id, jsonb_agg(distinct jsonb_build_object('id', l.id, 'ma', l.ma, 'ten', l.ten, 'trang_thai', l.trang_thai,
        'dv_vc_id', l.dv_vc_id, 'dv_vc_ten', (select ten from kt_ncc where id = l.dv_vc_id), 'forwarder', l.forwarder, 'ma_van_don', l.ma_van_don, 'so_cont', l.so_cont,
        'ngay_kh', l.ngay_kh, 'ngay_du_kien', l.ngay_du_kien, 'ngay_ve', l.ngay_ve, 'so_po', (select count(distinct d2.po_id) from kt_lo_nk_don d2 where d2.lo_id = l.id and not d2.da_xoa and d2.po_id is not null),
        'cp', (select coalesce(jsonb_agg(jsonb_build_object('loai', c.loai, 'nd', c.noi_dung, 'so_tien', c.so_tien, 'chi_id', c.chi_id, 'ngay', c.ngay, 'dvn', c.don_vi_nhan) order by c.ngay nulls last, c.id), '[]')
                 from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa))) ds
      from kt_lo_nk_don d join kt_lo_nk l on l.id = d.lo_id and not l.da_xoa where not d.da_xoa and d.po_id is not null group by d.po_id) x), '{}'));
end $function$;

-- chạy bù cho lô đang có
select kt_lo_nk_po_tt(id) from kt_lo_nk where not da_xoa;

-- forwarder gõ tay ở lô → đơn vị vận chuyển thật (NCC loại Vận chuyển), gắn lại lô (21/11: 3 lô "Donny Forwarder")
do $$ declare r record; v bigint;
begin
  for r in select distinct btrim(forwarder) ten from kt_lo_nk where not da_xoa and dv_vc_id is null and nullif(btrim(forwarder), '') is not null loop
    select id into v from kt_ncc where not da_xoa and lower(btrim(ten)) = lower(r.ten) order by (loai = 'van_chuyen') desc, id limit 1;
    if v is null then
      insert into kt_ncc (ten, loai, tao_boi) values (r.ten, 'van_chuyen', 'Hệ thống') returning id into v;
      update kt_ncc set ma = 'NCCA' || lpad(v::text, 4, '0') where id = v;
    end if;
    update kt_lo_nk set dv_vc_id = v where not da_xoa and dv_vc_id is null and lower(btrim(forwarder)) = lower(r.ten);
  end loop;
end $$;
