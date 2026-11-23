-- LÔ VẬN CHUYỂN: HÌNH THỨC ĐƯỜNG BIỂN / ĐƯỜNG BỘ · CÔNG NỢ FORWARDER GỒM THUẾ NỘP THAY · LẬP PHIẾU CHI TỪ CHI PHÍ LÔ · CHỐT CHI PHÍ — 23/11/2026. Monsieur Claude
-- Kế toán (23/11 11:06) trả lời đề xuất quy trình:
--   (1) đường bộ (hàng lẻ): trả bên vận chuyển TỪNG CHUYẾN, không chuyển tiền hàng hộ;
--   (2) bên dịch vụ hải quan = CHÍNH forwarder; thuế VAT chuyển khoản cho bên dịch vụ nộp thay;
--   (3) chờ đủ bảng kê chi phí rồi mới nhập phiếu Kiot (phải tính giá vốn).
-- Làm:
--   kt_lo_nk.hinh_thuc ('bien' cả cont — có hồ sơ hải quan / kê khai / thuế; 'bo' hàng lẻ — chỉ cước vận chuyển). Lô cũ = 'bien' (3 lô cont).
--   Công nợ đơn vị vận chuyển: phải trả = MỌI khoản chi phí của lô (cước, phí hải quan, thuế NK, VAT NK…) trừ khoản ghi "đơn vị nhận tiền" khác đơn vị
--     → kt_ds_lo_nk trả 'phai_tra_vc'. Phiếu chi nối vào khoản đó tự gắn về đơn vị vận chuyển (kt_ncc_gan) nếu phiếu chưa thuộc NCC nào → đã trả tự trừ.
--   kt_lo_nk_cp_noi_chi: nối 1 phiếu chi vào nhiều khoản chi phí (nút "Lập phiếu chi" trên app, lưu phiếu xong tự nối).
--   Chốt chi phí (kt_lo_nk_chot): khoá số tiền / loại chi phí, hàng / giá trị / tỷ giá đơn, tỷ giá / cách phân bổ lô (vẫn nối phiếu chi, phiếu nhập Kiot được);
--     chuông cho người có quyền trang NCC: "nhập phiếu Kiot theo giá vốn". Mở chốt để sửa.

alter table public.kt_lo_nk add column if not exists hinh_thuc text not null default 'bien';
alter table public.kt_lo_nk drop constraint if exists kt_lo_nk_hinh_thuc_ck;
alter table public.kt_lo_nk add constraint kt_lo_nk_hinh_thuc_ck check (hinh_thuc in ('bien', 'bo'));
alter table public.kt_lo_nk add column if not exists chot_luc timestamptz, add column if not exists chot_boi text;

-- khoản chi phí trả cho đơn vị vận chuyển của lô? (đơn vị nhận tiền để trống hoặc trùng tên đơn vị)
create or replace function public.kt_lo_nk_cp_cua_dv(p_dvn text, p_dv bigint) returns boolean language sql stable set search_path = public as $$
  select p_dv is not null and (nullif(trim(p_dvn), '') is null or lower(trim(p_dvn)) = (select lower(trim(ten)) from kt_ncc where id = p_dv))
$$;

-- ── khoá khi đã chốt chi phí
create or replace function public.kt_lo_nk_chot_cp_tg() returns trigger language plpgsql set search_path = public as $$
declare v_lo bigint := coalesce(new.lo_id, old.lo_id);
begin
  if exists (select 1 from kt_lo_nk where id = v_lo and chot_luc is not null)
     and (tg_op = 'INSERT' or new.lo_id is distinct from old.lo_id or new.loai is distinct from old.loai or new.so_tien is distinct from old.so_tien
          or new.tinh_gv is distinct from old.tinh_gv or new.da_xoa is distinct from old.da_xoa) then
    raise exception 'Lô đã chốt chi phí — bấm "Mở chốt" (tab Phân bổ giá vốn) rồi mới thêm / sửa số tiền / xoá chi phí. Nối phiếu chi vẫn làm được.';
  end if;
  return new;
end $$;
drop trigger if exists kt_lo_nk_cp_chot on public.kt_lo_nk_cp;
create trigger kt_lo_nk_cp_chot before insert or update on public.kt_lo_nk_cp for each row execute function public.kt_lo_nk_chot_cp_tg();

create or replace function public.kt_lo_nk_chot_don_tg() returns trigger language plpgsql set search_path = public as $$
declare v_lo bigint := coalesce(new.lo_id, old.lo_id);
begin
  if exists (select 1 from kt_lo_nk where id = v_lo and chot_luc is not null)
     and (tg_op = 'INSERT' or new.lo_id is distinct from old.lo_id or new.hang is distinct from old.hang or new.gia_tri is distinct from old.gia_tri
          or new.tien_te is distinct from old.tien_te or new.ty_gia is distinct from old.ty_gia or new.da_xoa is distinct from old.da_xoa) then
    raise exception 'Lô đã chốt chi phí — bấm "Mở chốt" (tab Phân bổ giá vốn) rồi mới thêm / xoá đơn, sửa hàng / giá trị / tỷ giá. Ghép phiếu nhập Kiot vẫn làm được.';
  end if;
  return new;
end $$;
drop trigger if exists kt_lo_nk_don_chot on public.kt_lo_nk_don;
create trigger kt_lo_nk_don_chot before insert or update on public.kt_lo_nk_don for each row execute function public.kt_lo_nk_chot_don_tg();

create or replace function public.kt_lo_nk_chot_lo_tg() returns trigger language plpgsql set search_path = public as $$
begin
  if old.chot_luc is not null and new.chot_luc is not null
     and (new.tien_te is distinct from old.tien_te or new.ty_gia is distinct from old.ty_gia or new.cach_pb is distinct from old.cach_pb) then
    raise exception 'Lô đã chốt chi phí — bấm "Mở chốt" (tab Phân bổ giá vốn) rồi mới đổi tiền tệ / tỷ giá / cách chia chi phí.';
  end if;
  return new;
end $$;
drop trigger if exists kt_lo_nk_chot_lo on public.kt_lo_nk;
create trigger kt_lo_nk_chot_lo before update on public.kt_lo_nk for each row execute function public.kt_lo_nk_chot_lo_tg();

-- ── phiếu chi nối vào chi phí của đơn vị vận chuyển → tự gắn phiếu về đơn vị (nếu phiếu chưa thuộc NCC nào) để công nợ tự trừ
create or replace function public.kt_lo_nk_cp_gan_dv_tg() returns trigger language plpgsql security definer set search_path = public as $$
declare v_dv bigint;
begin
  if new.chi_id is null or new.da_xoa then return new; end if;
  select dv_vc_id into v_dv from kt_lo_nk where id = new.lo_id;
  if kt_lo_nk_cp_cua_dv(new.don_vi_nhan, v_dv) and not exists (select 1 from kt_v_ncc_phieu where bang = 'chi' and dong_id = new.chi_id) then
    insert into kt_ncc_gan (bang, dong_id, ncc_id, tao_boi) values ('chi', new.chi_id, v_dv, coalesce(new.sua_boi, new.tao_boi, 'Hệ thống'))
    on conflict (bang, dong_id) do nothing;
  end if;
  return new;
end $$;
drop trigger if exists kt_lo_nk_cp_gan_dv on public.kt_lo_nk_cp;
create trigger kt_lo_nk_cp_gan_dv after insert or update of chi_id, don_vi_nhan, da_xoa on public.kt_lo_nk_cp for each row execute function public.kt_lo_nk_cp_gan_dv_tg();

-- ── nối 1 phiếu chi vào nhiều khoản chi phí (nút Lập phiếu chi: lưu phiếu xong app gọi hàm này)
create or replace function public.kt_lo_nk_cp_noi_chi(p_phien text, p_ids bigint[], p_chi bigint) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; n int;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if not exists (select 1 from kt_chi where id = p_chi and not da_xoa) then raise exception 'Không thấy phiếu chi'; end if;
  update kt_lo_nk_cp set chi_id = p_chi, sua_boi = u.ho_ten, sua_luc = now() where id = any (p_ids) and not da_xoa and chi_id is null;
  get diagnostics n = row_count;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk_cp', null, 'noi_chi', jsonb_build_object('ids', to_jsonb(p_ids), 'chi_id', p_chi, 'so_dong', n));
  return n;
end $$;
revoke all on function public.kt_lo_nk_cp_noi_chi(text, bigint[], bigint) from public;
grant execute on function public.kt_lo_nk_cp_noi_chi(text, bigint[], bigint) to anon, authenticated;

-- ── chốt / mở chốt chi phí
create or replace function public.kt_lo_nk_chot(p_phien text, p_id bigint, p_chot boolean) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; l kt_lo_nk;
begin
  u := kt_chan(p_phien, 'ncc', true);
  select * into l from kt_lo_nk where id = p_id and not da_xoa;
  if l.id is null then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  if p_chot then
    if l.chot_luc is not null then raise exception 'Lô đã chốt chi phí'; end if;
    if not exists (select 1 from kt_lo_nk_don where lo_id = p_id and not da_xoa) then raise exception 'Lô chưa có đơn hàng nào'; end if;
    if exists (select 1 from kt_lo_nk_don d where d.lo_id = p_id and not d.da_xoa and coalesce(d.tien_te, l.tien_te) <> 'VND' and d.ty_gia is null and l.ty_gia is null) then
      raise exception 'Còn đơn hàng thiếu tỷ giá — nhập tỷ giá ở đơn hoặc ở lô trước khi chốt'; end if;
    update kt_lo_nk set chot_luc = now(), chot_boi = u.ho_ten where id = p_id;
    insert into kt_thong_bao (nguoi_dung_id, tu, loai, tieu_de, noi_dung, bang, dong_id)
    select nd.id, u.ho_ten, 'lo_nk_chot', 'Lô ' || l.ma || ' đã chốt chi phí — nhập phiếu Kiot theo giá vốn',
           l.ten || ' · bấm để xem giá vốn / sản phẩm (tab Phân bổ giá vốn, có Xuất Excel)', 'lo_nk', p_id
      from kt_nguoi_dung nd where nd.hoat_dong and nd.id <> u.id and kt_co_quyen(nd, 'ncc');
  else
    if l.chot_luc is null then raise exception 'Lô chưa chốt chi phí'; end if;
    update kt_lo_nk set chot_luc = null, chot_boi = null where id = p_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk', p_id, case when p_chot then 'chot_cp' else 'mo_chot_cp' end, null);
end $$;
revoke all on function public.kt_lo_nk_chot(text, bigint, boolean) from public;
grant execute on function public.kt_lo_nk_chot(text, bigint, boolean) to anon, authenticated;

-- ── lưu lô: thêm hình thức
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
  if nullif(p_dong->>'hinh_thuc', '') is not null and p_dong->>'hinh_thuc' not in ('bien', 'bo') then raise exception 'Hình thức vận chuyển không hợp lệ'; end if;
  if v_id is null then
    v_nam := to_char(coalesce(nullif(p_dong->>'ngay_kh', '')::date, current_date), 'YYYY');
    select coalesce(max(nullif(regexp_replace(ma, '^NK-' || v_nam || '-', ''), ma)::int), 0) + 1 into v_n from kt_lo_nk where ma ~ ('^NK-' || v_nam || '-[0-9]+$');
    v_ma := coalesce(nullif(trim(p_dong->>'ma'), ''), 'NK-' || v_nam || '-' || lpad(v_n::text, 2, '0'));
    if exists (select 1 from kt_lo_nk where ma = v_ma) then raise exception 'Mã hồ sơ % đã có', v_ma; end if;
    insert into kt_lo_nk (ma, ten, trang_thai, so_cont, forwarder, ngay_kh, ngay_du_kien, ngay_ve, tien_te, ty_gia, cach_pb, ghi_chu, tao_boi, hinh_thuc)
    values (v_ma, trim(p_dong->>'ten'), coalesce(nullif(p_dong->>'trang_thai', ''), 'dat_hang'), nullif(trim(p_dong->>'so_cont'), ''), nullif(trim(p_dong->>'forwarder'), ''),
      nullif(p_dong->>'ngay_kh', '')::date, nullif(p_dong->>'ngay_du_kien', '')::date, nullif(p_dong->>'ngay_ve', '')::date,
      coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'), nullif(p_dong->>'ty_gia', '')::numeric, coalesce(nullif(p_dong->>'cach_pb', ''), 'gia_tri'), nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten,
      coalesce(nullif(p_dong->>'hinh_thuc', ''), 'bien'))
    returning id into v_id;
  else
    if nullif(trim(p_dong->>'ma'), '') is not null and exists (select 1 from kt_lo_nk where ma = trim(p_dong->>'ma') and id <> v_id) then raise exception 'Mã hồ sơ % đã có', trim(p_dong->>'ma'); end if;
    update kt_lo_nk set ma = coalesce(nullif(trim(p_dong->>'ma'), ''), ma), ten = trim(p_dong->>'ten'), trang_thai = coalesce(nullif(p_dong->>'trang_thai', ''), trang_thai),
      so_cont = nullif(trim(p_dong->>'so_cont'), ''), forwarder = nullif(trim(p_dong->>'forwarder'), ''),
      ngay_kh = nullif(p_dong->>'ngay_kh', '')::date, ngay_du_kien = nullif(p_dong->>'ngay_du_kien', '')::date, ngay_ve = nullif(p_dong->>'ngay_ve', '')::date,
      tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te), ty_gia = nullif(p_dong->>'ty_gia', '')::numeric, cach_pb = coalesce(nullif(p_dong->>'cach_pb', ''), cach_pb),
      ghi_chu = nullif(trim(p_dong->>'ghi_chu'), ''), hinh_thuc = coalesce(nullif(p_dong->>'hinh_thuc', ''), hinh_thuc), sua_boi = u.ho_ten, sua_luc = now()
     where id = v_id and not da_xoa;
    if not found then raise exception 'Không thấy hồ sơ nhập khẩu'; end if;
  end if;
  update kt_lo_nk set cang_di = nullif(trim(p_dong->>'cang_di'), ''), cang_den = nullif(trim(p_dong->>'cang_den'), ''), dv_xuat_khau = nullif(trim(p_dong->>'dv_xuat_khau'), ''),
    dv_nhan_tien = nullif(trim(p_dong->>'dv_nhan_tien'), ''), dv_mo_tk = nullif(trim(p_dong->>'dv_mo_tk'), ''),
    dv_vc_id = nullif(p_dong->>'dv_vc_id', '')::bigint, ma_van_don = nullif(trim(p_dong->>'ma_van_don'), '') where id = v_id;   -- 21/11 đơn vị vận chuyển + mã vận đơn
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_lo_nk', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $function$;

-- ── danh sách lô: + phai_tra_vc (mọi khoản chi phí trả cho đơn vị vận chuyển, gồm thuế nộp thay)
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
      'phai_tra_vc', (select coalesce(sum(c.so_tien), 0) from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa and kt_lo_nk_cp_cua_dv(c.don_vi_nhan, l.dv_vc_id)),
      'po_ids', (select coalesce(jsonb_agg(distinct d.po_id), '[]') from kt_lo_nk_don d where d.lo_id = l.id and not d.da_xoa and d.po_id is not null),
      'kk', kt_lo_nk_kk_tong(l))
    order by coalesce(l.ngay_kh, l.tao_luc::date) desc, l.id desc) from kt_lo_nk l where not l.da_xoa), '[]');
end $function$;

-- ── PO: lô kèm hình thức + đã chốt
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
    -- 21/11 kế toán: PO hiện lô vận chuyển chứa nó (đơn vị, mã vận đơn, các mốc ngày, phí vận chuyển + phiếu chi của phí); 23/11 + hình thức, đã chốt chi phí
    'lo', coalesce((select jsonb_object_agg(x.po_id, x.ds) from (select d.po_id, jsonb_agg(distinct jsonb_build_object('id', l.id, 'ma', l.ma, 'ten', l.ten, 'trang_thai', l.trang_thai,
        'hinh_thuc', l.hinh_thuc, 'chot_luc', l.chot_luc,
        'dv_vc_id', l.dv_vc_id, 'dv_vc_ten', (select ten from kt_ncc where id = l.dv_vc_id), 'forwarder', l.forwarder, 'ma_van_don', l.ma_van_don, 'so_cont', l.so_cont,
        'ngay_kh', l.ngay_kh, 'ngay_du_kien', l.ngay_du_kien, 'ngay_ve', l.ngay_ve, 'so_po', (select count(distinct d2.po_id) from kt_lo_nk_don d2 where d2.lo_id = l.id and not d2.da_xoa and d2.po_id is not null),
        'cp', (select coalesce(jsonb_agg(jsonb_build_object('loai', c.loai, 'nd', c.noi_dung, 'so_tien', c.so_tien, 'chi_id', c.chi_id, 'ngay', c.ngay, 'dvn', c.don_vi_nhan) order by c.ngay nulls last, c.id), '[]')
                 from kt_lo_nk_cp c where c.lo_id = l.id and not c.da_xoa))) ds
      from kt_lo_nk_don d join kt_lo_nk l on l.id = d.lo_id and not l.da_xoa where not d.da_xoa and d.po_id is not null group by d.po_id) x), '{}'));
end $function$;

-- hàm phụ / trigger: không cho gọi thẳng từ trình duyệt
revoke all on function public.kt_lo_nk_cp_cua_dv(text, bigint) from public, anon, authenticated;
revoke all on function public.kt_lo_nk_cp_gan_dv_tg() from public, anon, authenticated;
