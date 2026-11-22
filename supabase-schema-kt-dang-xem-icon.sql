-- 02/11/2026 anh: không để trùng icon người online. — Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_bao_danh(p_phien text, p_ma text, p_trang text DEFAULT NULL::text, p_con integer DEFAULT NULL::integer, p_roi boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if coalesce(trim(p_ma), '') = '' or length(p_ma) > 64 then raise exception 'Mã trình duyệt không hợp lệ'; end if;
  if p_roi then delete from kt_dang_xem where ma = p_ma; return '[]'::jsonb; end if;
  -- lúc Xem như: không báo danh (không hiện admin thành người khác), chỉ xem danh sách
  if coalesce(current_setting('kt.chi_xem', true), '') <> '1' and u.ten_dang_nhap not like 'tam-%' then
    insert into kt_dang_xem (ma, nguoi_dung_id, ten, trang, con, last_seen)
    values (p_ma, u.id, u.ho_ten, left(p_trang, 60), p_con, now())
    on conflict (ma) do update set nguoi_dung_id = excluded.nguoi_dung_id, ten = excluded.ten, trang = excluded.trang,
      con = coalesce(excluded.con, kt_dang_xem.con), last_seen = now();
  end if;
  delete from kt_dang_xem where last_seen < now() - interval '1 day';   -- dọn tab đóng đột ngột
  -- 02/11 anh: "không để trùng icon người online" — mỗi tài khoản 1 con vật cố định theo thứ tự tài khoản (không random mỗi lần mở app); 1 người nhiều máy / tab chỉ hiện 1 dòng
  return coalesce((select jsonb_agg(jsonb_build_object('ma', ma, 'ten', ten, 'trang', trang, 'toi', nguoi_dung_id = u.id,
      'con', (array[12,7,9,3,20,25,27,10,21,24,19,23,30,15,18,5,17,28,2,29,6,26,8,13,16,22,1,4,11,14])[(((select count(*) from kt_nguoi_dung n where n.ten_dang_nhap not like 'tam-%' and n.id <= x.nguoi_dung_id) - 1) % 30 + 1)::int]) order by last_seen desc)
    from (select distinct on (nguoi_dung_id) * from kt_dang_xem where last_seen > now() - interval '90 seconds' order by nguoi_dung_id, last_seen desc limit 50) x), '[]');
end $function$;
