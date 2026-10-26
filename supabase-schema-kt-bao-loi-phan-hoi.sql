-- 26/10/2026 (anh): "lỗi xử lý xong thì báo lại thông báo của người đã làm, click vào ra lỗi đã báo với cách xử lý, cho người ta chọn hoàn thành hoặc feedback lại tiếp".
--  · kt_bao_loi thêm: xac_nhan (null / 'cho' chờ người báo xem / 'hoan_thanh' / 'phan_hoi'), lich_su (jsonb: xử lý, phản hồi, hoàn thành — ai, lúc, nội dung)
--  · đánh dấu Đã xử lý (trang Log hoặc Claude xử lý bằng SQL qua kt_bao_loi_bao_kq) → chuông của NGƯỜI BÁO (khớp họ tên tài khoản): "Lỗi đã báo · … đã xử lý"
--  · người báo bấm chuông → cửa sổ: lỗi đã báo + cách xử lý + lịch sử → "✓ Hoàn thành" hoặc "Phản hồi tiếp" (ghi nội dung → mở lại lỗi, chuông Supreme)
-- — Monsieur Claude
alter table kt_bao_loi add column if not exists xac_nhan text check (xac_nhan in ('cho', 'hoan_thanh', 'phan_hoi'));
alter table kt_bao_loi add column if not exists lich_su jsonb not null default '[]';

-- báo kết quả cho người báo (nội bộ: hàm xử lý + Claude xử lý bằng SQL gọi)
create or replace function public.kt_bao_loi_bao_kq(p_id bigint, p_ai text) returns void
  language plpgsql security definer set search_path = public as $f$
declare b kt_bao_loi;
begin
  select * into b from kt_bao_loi where id = p_id;
  if b.id is null or not b.da_xu_ly then return; end if;
  update kt_bao_loi set xac_nhan = 'cho',
         lich_su = lich_su || jsonb_build_array(jsonb_build_object('loai', 'xu_ly', 'ai', p_ai, 'luc', now(), 'noi_dung', coalesce(b.xu_ly_ghi, 'Đã xử lý')))
   where id = p_id;
  insert into kt_thong_bao (nguoi_dung_id, tu, loai, tieu_de, noi_dung, bang, dong_id)
  select n.id, p_ai, 'bao_loi_kq', 'Lỗi đã báo' || coalesce(' · ' || nullif(b.so_phieu, ''), '') || ': đã xử lý — bấm xem',
         left(coalesce(b.xu_ly_ghi, 'Đã xử lý'), 300), 'bao_loi_kq', b.id
    from kt_nguoi_dung n where n.ho_ten = b.nguoi and n.hoat_dong;
end $f$;
revoke all on function public.kt_bao_loi_bao_kq(bigint, text) from anon, authenticated, public;

-- trang Log: đánh dấu xử lý → báo người báo
create or replace function public.kt_bao_loi_xu_ly(p_phien text, p_id bigint, p_xong boolean, p_ghi text) returns void
 language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'nhat_ky');
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  update kt_bao_loi set da_xu_ly = p_xong, xu_ly_boi = case when p_xong then u.ho_ten end, xu_ly_luc = case when p_xong then now() end,
    xu_ly_ghi = nullif(trim(coalesce(p_ghi, '')), ''), xac_nhan = case when p_xong then xac_nhan end where id = p_id;
  if p_xong then perform kt_bao_loi_bao_kq(p_id, u.ho_ten); end if;
end $f$;

-- người báo (hoặc người có quyền Log) xem 1 lỗi đã báo
create or replace function public.kt_bao_loi_xem(p_phien text, p_id bigint) returns jsonb
  language plpgsql stable security definer set search_path = public as $f$
declare u kt_nguoi_dung; b kt_bao_loi;
begin
  u := kt_chan(p_phien);
  select * into b from kt_bao_loi where id = p_id;
  if b.id is null then raise exception 'Không thấy báo lỗi'; end if;
  if b.nguoi <> u.ho_ten and not kt_co_quyen(u, 'nhat_ky') then raise exception 'Chỉ người báo lỗi xem được'; end if;
  return to_jsonb(b) || jsonb_build_object('la_nguoi_bao', b.nguoi = u.ho_ten,
    'anh', (select count(*) from kt_chung_tu k where k.bang = 'bao_loi' and k.dong_id = b.id and not k.da_xoa));
end $f$;

-- người báo xác nhận: hoàn thành, hoặc phản hồi tiếp (mở lại lỗi, báo chuông Supreme)
create or replace function public.kt_bao_loi_xac_nhan(p_phien text, p_id bigint, p_hoan_thanh boolean, p_noi_dung text) returns void
  language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung; b kt_bao_loi;
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  select * into b from kt_bao_loi where id = p_id;
  if b.id is null then raise exception 'Không thấy báo lỗi'; end if;
  if b.nguoi <> u.ho_ten then raise exception 'Chỉ người báo lỗi xác nhận được'; end if;
  if p_hoan_thanh then
    update kt_bao_loi set xac_nhan = 'hoan_thanh',
           lich_su = lich_su || jsonb_build_array(jsonb_build_object('loai', 'hoan_thanh', 'ai', u.ho_ten, 'luc', now(), 'noi_dung', nullif(trim(coalesce(p_noi_dung, '')), '')))
     where id = p_id;
  else
    if coalesce(trim(p_noi_dung), '') = '' then raise exception 'Ghi phản hồi'; end if;
    update kt_bao_loi set xac_nhan = 'phan_hoi', da_xu_ly = false, xu_ly_boi = null, xu_ly_luc = null,
           lich_su = lich_su || jsonb_build_array(jsonb_build_object('loai', 'phan_hoi', 'ai', u.ho_ten, 'luc', now(), 'noi_dung', left(trim(p_noi_dung), 2000)))
     where id = p_id;
    insert into kt_thong_bao (nguoi_dung_id, tu, loai, tieu_de, noi_dung, bang, dong_id)
    select n.id, u.ho_ten, 'bao_loi', 'Phản hồi lỗi' || coalesce(' · ' || nullif(b.so_phieu, ''), '') || ' — chưa xong', left(trim(p_noi_dung), 300), 'bao_loi', b.id
      from kt_nguoi_dung n where n.vi_tri = 'supreme' and n.hoat_dong;
  end if;
end $f$;
revoke all on function public.kt_bao_loi_xem(text, bigint), public.kt_bao_loi_xac_nhan(text, bigint, boolean, text) from public;
grant execute on function public.kt_bao_loi_xem(text, bigint), public.kt_bao_loi_xac_nhan(text, bigint, boolean, text) to anon;

-- 4 lỗi Claude xử lý 26/10 bằng SQL (VIEC 133) → báo người báo
select kt_bao_loi_bao_kq(id, 'Hệ thống') from kt_bao_loi where id in (9, 10, 11, 14) and da_xu_ly and xac_nhan is null;
