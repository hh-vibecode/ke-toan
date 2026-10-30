-- 30/10/2026 kế toán: "toàn bộ thông tin NCC (tên, địa chỉ…) update lại ở KiotViet thì app có tự update theo không?"
-- Trước: chỉ theo khi đổi mã / tên, không kéo địa chỉ. Giờ: kéo địa chỉ (Edge Function kt-kiot) + đổi mã / tên / SĐT / địa chỉ đều theo Kiot
-- (trừ NCC kế toán đã sửa tay trên app — sua_tay). — Monsieur Claude
alter table public.kt_kiot_ncc add column if not exists dia_chi text;
create or replace function public.kt_ncc_dong_bo() returns void language plpgsql security definer set search_path = public as $function$
declare v_luc timestamptz; v_moi timestamptz;
begin
  select max(keo_luc) into v_moi from kt_kiot_ncc;
  select nullif(gia_tri, '')::timestamptz into v_luc from kt_cai_dat where khoa = 'kt_ncc_dong_bo_luc';
  if v_luc is not null and v_moi is not null and v_luc >= v_moi
     and not exists (select 1 from kt_kiot_ncc k where not exists (select 1 from kt_ncc n where n.kiot_id = k.id)) then return; end if;
  begin
    insert into kt_ncc (kiot_id, ma, ten, sdt, dia_chi, loai, tao_boi)
    select k.id, k.ma, k.ten, k.sdt, k.dia_chi, case when kt_bo_dau(k.ten) ~ '(^|[^a-z])(tq|trung quoc)([^a-z]|$)' then 'nuoc_ngoai' else 'noi_dia' end, 'Hệ thống'
      from kt_kiot_ncc k where not exists (select 1 from kt_ncc n where n.kiot_id = k.id);
    update kt_ncc n set ma = k.ma, ten = k.ten, sdt = coalesce(k.sdt, n.sdt), dia_chi = coalesce(k.dia_chi, n.dia_chi)
      from kt_kiot_ncc k where k.id = n.kiot_id and not n.sua_tay
       and (n.ma is distinct from k.ma or n.ten is distinct from k.ten or (k.sdt is not null and n.sdt is distinct from k.sdt) or (k.dia_chi is not null and n.dia_chi is distinct from k.dia_chi));
    update kt_cai_dat set gia_tri = coalesce(v_moi, now())::text, sua_luc = now() where khoa = 'kt_ncc_dong_bo_luc';
    if not found then insert into kt_cai_dat (khoa, gia_tri, sua_luc) values ('kt_ncc_dong_bo_luc', coalesce(v_moi, now())::text, now()); end if;
  exception when others then null;   -- phiên chỉ xem / tranh ghi: bỏ qua, lần sau đồng bộ
  end;
end $function$;
