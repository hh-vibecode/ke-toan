-- 18/11/2026 kế toán: "tạo phiếu chi dùng khoản vay công ty, hệ thống có tự tạo khoản vay ở Vay & lãi vay không? Thanh toán trung gian cũng vậy.
-- 1 khoản vay gồm 4 phiếu chi của 4 nơi thì xử lý sao để hệ thống hiểu là cùng 1 khoản vay"
-- → Phiếu chi (đi tiền từ tài khoản loại "vay") và lần thanh toán trung gian gắn được vào 1 khoản vay (kt_chi.vay_id / kt_tt_nn.vay_id);
--   nhiều phiếu chọn cùng 1 khoản = cùng 1 khoản vay. Phiếu ĐÃ CHI tự sinh 1 lần NHẬN TIỀN (giải ngân) của khoản đó (kt_vay_nhan.chi_id / tt_id):
--   • phiếu chi: giải ngân vào chính tài khoản vay (+) rồi phiếu chi đi ra (−) → số dư TK vay không âm nữa, dư nợ hiện ở trang Vay.
--   • thanh toán trung gian KHÔNG gắn phiếu chi: giải ngân không gắn tài khoản (lần chuyển này không trừ số dư TK nào), số tiền = nguyên tệ × tỷ giá.
--     Có gắn phiếu chi thì khoản vay đi theo phiếu chi (không tính 2 lần).
--   Huỷ đã chi / bỏ gắn / đổi sang tài khoản thường / xoá phiếu → lần giải ngân tự ẩn. Xoá khoản vay → bỏ gắn ở phiếu.
-- Monsieur Claude

alter table kt_chi add column if not exists vay_id bigint;
alter table kt_tt_nn add column if not exists vay_id bigint;
alter table kt_vay_nhan add column if not exists chi_id bigint;
alter table kt_vay_nhan add column if not exists tt_id bigint;
create unique index if not exists kt_vay_nhan_chi_uq on kt_vay_nhan (chi_id) where chi_id is not null;
create unique index if not exists kt_vay_nhan_tt_uq on kt_vay_nhan (tt_id) where tt_id is not null;
create index if not exists kt_chi_vay_idx on kt_chi (vay_id) where vay_id is not null;

-- đồng bộ 1 phiếu chi → lần giải ngân
create or replace function kt_vay_dong_bo_chi(p_id bigint) returns void language plpgsql security definer set search_path = public as $$
declare c kt_chi; can boolean;
begin
  select * into c from kt_chi where id = p_id;
  can := found and c.vay_id is not null and not coalesce(c.da_xoa, false) and c.trang_thai = 'da_tt' and c.ngay_tt is not null
    and exists (select 1 from kt_tai_khoan t where t.id = c.tai_khoan_id and t.loai = 'vay')
    and exists (select 1 from kt_vay v where v.id = c.vay_id and not v.da_xoa);
  if can then
    insert into kt_vay_nhan (vay_id, ngay, so_tien, tai_khoan_id, ghi_chu, tao_boi, chi_id)
    values (c.vay_id, c.ngay_tt, c.so_tien, c.tai_khoan_id, 'Từ phiếu chi PC' || lpad(c.id::text, 6, '0'), 'Hệ thống', c.id)
    on conflict (chi_id) where chi_id is not null do update set vay_id = excluded.vay_id, ngay = excluded.ngay, so_tien = excluded.so_tien,
      tai_khoan_id = excluded.tai_khoan_id, ghi_chu = excluded.ghi_chu, da_xoa = false;
  else
    update kt_vay_nhan set da_xoa = true where chi_id = p_id and not da_xoa;
  end if;
end $$;

-- đồng bộ 1 lần thanh toán trung gian → lần giải ngân (chỉ khi KHÔNG gắn phiếu chi)
create or replace function kt_vay_dong_bo_tt(p_id bigint) returns void language plpgsql security definer set search_path = public as $$
declare t kt_tt_nn; tien numeric;
begin
  select * into t from kt_tt_nn where id = p_id;
  if found and t.chi_id is not null and t.vay_id is not null and not coalesce(t.da_xoa, false) then
    update kt_chi set vay_id = t.vay_id where id = t.chi_id and vay_id is distinct from t.vay_id;   -- khoản vay đi theo phiếu chi
  end if;
  tien := case when t.tien_te = 'VND' then t.so_tien_nt when t.ty_gia > 0 then round(t.so_tien_nt * t.ty_gia) end;
  if found and t.vay_id is not null and t.chi_id is null and not coalesce(t.da_xoa, false) and tien > 0
     and exists (select 1 from kt_vay v where v.id = t.vay_id and not v.da_xoa) then
    insert into kt_vay_nhan (vay_id, ngay, so_tien, tai_khoan_id, ghi_chu, tao_boi, tt_id)
    values (t.vay_id, t.ngay, tien, null, 'Từ thanh toán trung gian ' || coalesce(t.ben_nhan, '') || ' · ' || t.so_tien_nt || ' ' || t.tien_te, 'Hệ thống', t.id)
    on conflict (tt_id) where tt_id is not null do update set vay_id = excluded.vay_id, ngay = excluded.ngay, so_tien = excluded.so_tien, ghi_chu = excluded.ghi_chu, da_xoa = false;
  else
    update kt_vay_nhan set da_xoa = true where tt_id = p_id and not da_xoa;
  end if;
end $$;

create or replace function kt_vay_tg_chi() returns trigger language plpgsql security definer set search_path = public as $$
begin perform kt_vay_dong_bo_chi(new.id); return null; end $$;
create or replace function kt_vay_tg_tt() returns trigger language plpgsql security definer set search_path = public as $$
begin perform kt_vay_dong_bo_tt(new.id); return null; end $$;
create or replace function kt_vay_tg_xoa() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.da_xoa and not old.da_xoa then
    update kt_chi set vay_id = null where vay_id = new.id;
    update kt_tt_nn set vay_id = null where vay_id = new.id;
  end if;
  return null;
end $$;

drop trigger if exists kt_vay_tg_chi on kt_chi;
drop trigger if exists kt_vay_tg_chi_moi on kt_chi;
create trigger kt_vay_tg_chi_moi after insert on kt_chi for each row when (new.vay_id is not null) execute function kt_vay_tg_chi();
create trigger kt_vay_tg_chi after update of vay_id, trang_thai, so_tien, ngay_tt, tai_khoan_id, da_xoa on kt_chi
  for each row when (new.vay_id is not null or old.vay_id is not null) execute function kt_vay_tg_chi();
drop trigger if exists kt_vay_tg_tt on kt_tt_nn;
drop trigger if exists kt_vay_tg_tt_moi on kt_tt_nn;
create trigger kt_vay_tg_tt_moi after insert on kt_tt_nn for each row when (new.vay_id is not null) execute function kt_vay_tg_tt();
create trigger kt_vay_tg_tt after update of vay_id, chi_id, ngay, so_tien_nt, tien_te, ty_gia, ben_nhan, da_xoa on kt_tt_nn
  for each row when (new.vay_id is not null or old.vay_id is not null) execute function kt_vay_tg_tt();
drop trigger if exists kt_vay_tg_xoa on kt_vay;
create trigger kt_vay_tg_xoa after update of da_xoa on kt_vay for each row execute function kt_vay_tg_xoa();

-- gắn / bỏ gắn khoản vay cho phiếu chi ('chi') hoặc lần thanh toán trung gian ('tt'); p_moi = tạo khoản vay mới rồi gắn
create or replace function kt_gan_vay(p_phien text, p_loai text, p_id bigint, p_vay bigint, p_moi jsonb default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v bigint := p_vay; tk int; tien numeric; ngay date;
begin
  u := kt_chan(p_phien, 'vay', true);
  if p_loai not in ('chi', 'tt') then raise exception 'Loại không hợp lệ'; end if;
  if p_moi is not null then
    if nullif(btrim(p_moi->>'ten'), '') is null then raise exception 'Cần tên khoản vay'; end if;
    tk := case when p_loai = 'chi' then (select tai_khoan_id from kt_chi where id = p_id) else (select tk_id from kt_tt_nn where id = p_id) end;
    -- số tiền vay / ngày vay để trống = lấy theo phiếu đang gắn (sửa lại ở trang Vay khi biết hạn mức / khế ước)
    if p_loai = 'chi' then select so_tien, coalesce(ngay_tt, ngay_de_nghi) into tien, ngay from kt_chi where id = p_id;
    else select case when tien_te = 'VND' then so_tien_nt when ty_gia > 0 then round(so_tien_nt * ty_gia) end, ngay into tien, ngay from kt_tt_nn where id = p_id; end if;
    insert into kt_vay (ten, ben_cho_vay, so_tien, ngay_vay, ngay_dao_han, lai_suat, hinh_thuc, tai_khoan_id, chu_vay, ghi_chu, tao_boi)
    values (btrim(p_moi->>'ten'), nullif(btrim(p_moi->>'ben_cho_vay'), ''), coalesce(nullif(p_moi->>'so_tien', '')::numeric, tien, 0),
      coalesce(nullif(p_moi->>'ngay_vay', '')::date, ngay, current_date), nullif(p_moi->>'ngay_dao_han', '')::date, nullif(p_moi->>'lai_suat', '')::numeric,
      coalesce(nullif(p_moi->>'hinh_thuc', ''), 'goc_cuoi_ky'), tk, 'cong_ty', nullif(btrim(p_moi->>'ghi_chu'), ''), u.ho_ten)
    returning id into v;
    perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vay', v, 'them', p_moi || jsonb_build_object('tu', p_loai, 'tu_id', p_id));
  elsif v is not null and not exists (select 1 from kt_vay where id = v and not da_xoa) then
    raise exception 'Không thấy khoản vay';
  end if;
  if p_loai = 'chi' then
    update kt_chi set vay_id = v where id = p_id and not da_xoa;
  else
    update kt_tt_nn set vay_id = v where id = p_id and not da_xoa;
  end if;
  if not found then raise exception 'Không thấy phiếu'; end if;
  perform kt_ghi_nhat_ky(u.ho_ten, case when p_loai = 'chi' then 'kt_chi' else 'kt_tt_nn' end, p_id, 'sua', jsonb_build_object('vay_id', v));
  return v;
end $$;

-- lần nhận tiền sinh từ phiếu: không sửa / xoá tay ở trang Vay (sửa ở phiếu)
create or replace function kt_luu_vay_nhan(p_phien text, p_dong jsonb)
 RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare u kt_nguoi_dung; v_id bigint := (p_dong->>'id')::bigint;
begin
  u := kt_chan(p_phien, 'vay', true);
  if (p_dong->>'ngay') is null or coalesce((p_dong->>'so_tien')::numeric, 0) <= 0 or (p_dong->>'tai_khoan_id') is null then
    raise exception 'Cần ngày, số tiền nhận, tài khoản nhận'; end if;
  if v_id is null then
    insert into kt_vay_nhan (vay_id, ngay, so_tien, tai_khoan_id, ghi_chu, tao_boi)
    values ((p_dong->>'vay_id')::bigint, (p_dong->>'ngay')::date, (p_dong->>'so_tien')::numeric, (p_dong->>'tai_khoan_id')::int, nullif(trim(p_dong->>'ghi_chu'), ''), u.ho_ten)
    returning id into v_id;
  else
    if exists (select 1 from kt_vay_nhan where id = v_id and (chi_id is not null or tt_id is not null)) then
      raise exception 'Lần nhận này lấy từ phiếu chi / thanh toán trung gian — sửa ở phiếu đó'; end if;
    update kt_vay_nhan set ngay = (p_dong->>'ngay')::date, so_tien = (p_dong->>'so_tien')::numeric, tai_khoan_id = (p_dong->>'tai_khoan_id')::int,
      ghi_chu = nullif(trim(p_dong->>'ghi_chu'), '') where id = v_id and not da_xoa;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vay_nhan', v_id, case when (p_dong->>'id') is null then 'them' else 'sua' end, p_dong);
  return v_id;
end $function$;
