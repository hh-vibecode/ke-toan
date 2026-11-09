-- 09/11/2026 anh: "app có báo có phiếu bị xoá ở Kiot trong T10 — phiếu nào, ai xoá; bấm thông báo hiện ra phiếu lệch luôn được không".
-- (1) kt_canh_bao_kiot: ghi mã phiếu lệch ở mọi nhóm + tình trạng Kiot (Edge kt-kiot v26 hỏi Kiot từng phiếu app thừa: thua_kt = đã xoá / đổi ngày).
-- (2) kt_kiot_phieu_ct: chi tiết phiếu theo mã (ngày, chi nhánh, người bán, khách / NCC, tiền, lần kéo cuối) cho bảng phiếu lệch. — Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_canh_bao_kiot()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ai int[] := kt_ai_co_quyen('nhat_ky', false, null); v_n int := 0; r record; v_tt text; v_nd text;
  v_cuoi kt_nhat_ky; v_ok timestamptz; v_dc timestamptz;
begin
  -- báo 1 lần / 12 tiếng cho cùng tiêu đề
  create temp table if not exists _kt_cb (loai text, tieu_de text, noi_dung text) on commit drop;
  delete from _kt_cb;
  select * into v_cuoi from kt_nhat_ky where hanh_dong in ('keo_kiot', 'keo_kiot_loi', 'doi_chieu_kiot') order by id desc limit 1;
  if v_cuoi.hanh_dong = 'keo_kiot_loi' then
    insert into _kt_cb values ('kiot_loi', 'Kéo Kiot bị lỗi', left(coalesce(v_cuoi.du_lieu->>'loi', ''), 200) || ' · lúc ' || to_char(v_cuoi.luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'));
  end if;
  select max(luc) into v_ok from kt_nhat_ky where hanh_dong = 'keo_kiot';
  if v_ok is null or v_ok < now() - interval '4 hours' then
    insert into _kt_cb values ('kiot_loi', 'Quá 4 tiếng chưa kéo được Kiot',
      'Lần kéo thành công gần nhất: ' || coalesce(to_char(v_ok at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), 'chưa có') || ' — số Kiot trên app đang cũ');
  end if;
  select max(luc) into v_dc from kt_kiot_doi_chieu where loai = 'thang';
  if v_dc is null or v_dc < now() - interval '26 hours' then
    insert into _kt_cb values ('kiot_loi', 'Lịch so khớp doanh thu Kiot không chạy', 'Lần so gần nhất: ' || coalesce(to_char(v_dc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), 'chưa có'));
  end if;
  -- 09/11 anh: thông báo "1 phiếu app có mà Kiot không còn ()" — ngoặc trống vì chỉ đọc hoá đơn, phiếu lệch là ĐƠN ĐẶT (DH002954, Kiot đã xoá).
  -- Nay ghi mã ở mọi nhóm (HĐ, trả hàng, đơn đặt, phiếu nhập, sổ quỹ) + tình trạng Kiot (đã xoá / đổi ngày) lần so ghi được; bấm thông báo mở bảng phiếu lệch.
  for r in select distinct on (thang) * from kt_kiot_doi_chieu where loai = 'thang' and so_lech > so_sua order by thang desc, luc desc limit 2 loop
    select string_agg(nh.ten || ' ' || e.x || coalesce(' (' || case k.tt when 'xoa' then 'Kiot đã xoá' when 'doi' then 'Kiot đổi sang ' || coalesce(k.ngay, 'tháng khác') end || ')', ''), ', ')
      into v_nd
      from (values ('hd', 'HĐ', 1), ('th', 'trả hàng', 2), ('dh', 'đơn đặt', 3), ('nh', 'phiếu nhập', 4), ('sq', 'sổ quỹ', 5)) nh(k, ten, tt)
      cross join lateral (select jsonb_array_elements_text(coalesce(r.ket_qua->nh.k->'thua', '[]')) x) e
      left join lateral (select z->>'tt' tt, z->>'ngay' ngay from jsonb_array_elements(coalesce(r.ket_qua->nh.k->'thua_kt', '[]')) z where z->>'ma' = e.x limit 1) k on true;
    insert into _kt_cb values ('kiot_lech', 'Doanh thu T' || ltrim(substr(r.thang, 6), '0') || '/' || substr(r.thang, 1, 4) || ' lệch Kiot',
      (r.so_lech - r.so_sua) || ' phiếu app có mà Kiot không còn trong tháng: ' || coalesce(left(v_nd, 300), 'xem chi tiết') || ' — bấm xem');
  end loop;
  -- chỉ báo khi lần so tồn mới nhất (trước khi ghi đè) lệch đáng kể
  select luc, ket_qua into r from kt_kiot_doi_chieu where loai = 'ton' order by luc desc limit 1;
  if found then
    select abs(coalesce(sum((v->>'gt')::numeric), 0) - coalesce((select sum((a->>'gt')::numeric) from jsonb_each(r.ket_qua->'app') e(k, a)), 0))
             / nullif(sum((v->>'gt')::numeric), 0) into v_tt from jsonb_each(r.ket_qua->'kiot') e(k, v);
    if coalesce(v_tt::numeric, 0) > 0.01 or coalesce((r.ket_qua->>'dv_phu')::numeric, 0) > 0 then
      insert into _kt_cb values ('kiot_lech', 'Tồn kho app lệch Kiot ' || round(v_tt::numeric * 100, 1) || '%',
        'Lần so ' || to_char(r.luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ': ' || coalesce(r.ket_qua->>'so_dong_lech', '0') || ' dòng lệch (đã ghi đè theo Kiot) — xem nguyên nhân');
    end if;
  end if;
  for r in select * from _kt_cb c where not exists (select 1 from kt_thong_bao t where t.loai = c.loai and t.tieu_de = c.tieu_de and t.tao_luc > now() - interval '12 hours') loop
    perform kt_bao(v_ai, 'Hệ thống', r.loai, r.tieu_de, r.noi_dung, 'kt_kiot', null);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

create or replace function public.kt_kiot_phieu_ct(p_phien text, p_ma text[]) returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'nhat_ky');
  return (select coalesce(jsonb_agg(to_jsonb(z)), '[]') from (
    select 'hd' nhom, ma, ngay, chi_nhanh, nv_ban nguoi, khach_ten doi_tac, tong, trang_thai_ten tt, ma_dat_hang lien_quan, keo_luc, sua_kiot from kt_kiot_hoa_don where ma = any(p_ma[1:50])
    union all select 'dh', ma, ngay, chi_nhanh, nv_ban, khach_ten, tong, trang_thai_ten, (select string_agg(h.ma, ', ') from kt_kiot_hoa_don h where h.dat_hang_id = d.id), keo_luc, sua_kiot from kt_kiot_dat_hang d where ma = any(p_ma[1:50])
    union all select 'th', t.ma, t.ngay, t.chi_nhanh, null, null, t.tong_tra, t.trang_thai_ten, (select h.ma from kt_kiot_hoa_don h where h.id = t.hoa_don_id), t.keo_luc, t.sua_kiot from kt_kiot_tra_hang t where t.ma = any(p_ma[1:50])
    union all select 'nh', ma, ngay, chi_nhanh, null, ncc_ten, tong, trang_thai::text, null, keo_luc, sua_kiot from kt_kiot_nhap_hang where ma = any(p_ma[1:50])
    union all select 'sq', ma, ngay, chi_nhanh, null, doi_tac, so_tien, case when trang_thai = '1' then 'Đã huỷ' else 'Đã thanh toán' end, noi_dung, keo_luc, null from kt_kiot_so_quy where ma = any(p_ma[1:50])) z);
end $f$;
revoke all on function public.kt_kiot_phieu_ct(text, text[]) from public;
grant execute on function public.kt_kiot_phieu_ct(text, text[]) to anon, authenticated;
