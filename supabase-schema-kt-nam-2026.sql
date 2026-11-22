-- =========================================================================
-- APP KẾ TOÁN — MỞ RỘNG DỮ LIỆU NĂM 2026 (09/10/2026) — Monsieur Claude
-- Anh: "xử lý hết số liệu của 2026". Kiot (sổ quỹ, hoá đơn, trả hàng, nhập hàng) từ 01/01 (scripts/keo-kiot-cu.js);
-- thu Kiot + chi + điều chuyển từ 01/05 (scripts/nhap-sheet-khoang.js); SỐ DƯ tài khoản vẫn tính từ mốc 01/09
-- (tính ngược ra 7 tài khoản âm vô lý — tháng 5–8 thiếu sổ chi của chúng + thu ngoài Kiot).
-- File này ĐỊNH NGHĨA LẠI kt_dong_tien (thêm theo_ngay). Chạy SAU supabase-schema-kt.sql.
-- =========================================================================
create or replace function public.kt_dong_tien(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'tong_quan') or kt_co_quyen(u, 'dong_tien')) then
    raise exception 'Tài khoản chưa được cấp quyền xem dòng tiền' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'dau_ky', (select coalesce(jsonb_object_agg(tk.id, tk.ton_dau + coalesce((select sum(b.vao - b.ra) from kt_v_bien_dong b
                 where b.tai_khoan_id = tk.id and b.ngay >= tk.ngay_ton_dau and b.ngay < p_tu), 0)), '{}') from kt_tai_khoan tk),
    'phat_sinh', (select coalesce(jsonb_agg(jsonb_build_object('tk', b.tai_khoan_id, 'ngay', b.ngay, 'kieu', b.kieu,
                   'vao', b.vao, 'ra', b.ra)), '[]')
                  from (select b.tai_khoan_id, b.ngay, b.kieu, sum(b.vao) vao, sum(b.ra) ra from kt_v_bien_dong b
                          join kt_tai_khoan tk on tk.id = b.tai_khoan_id
                         where b.ngay between p_tu and p_den and b.ngay >= tk.ngay_ton_dau
                         group by 1, 2, 3) b),
    -- tổng thu / chi theo ngày cho biểu đồ Tổng quan — KHÔNG lọc theo mốc số dư (09/10/2026: có dữ liệu tháng 5–8 trước mốc số dư 01/09)
    'theo_ngay', (select coalesce(jsonb_agg(jsonb_build_object('ngay', ngay, 'thu', thu, 'chi', chi) order by ngay), '[]') from (
                   select ngay, coalesce(sum(vao) filter (where kieu = 'thu'), 0) thu, coalesce(sum(ra) filter (where kieu = 'chi'), 0) chi
                     from kt_v_bien_dong where ngay between p_tu and p_den group by ngay) x),
    'thuc_te', (select coalesce(jsonb_agg(jsonb_build_object('tk', tai_khoan_id, 'ngay', ngay, 'so_tien', so_tien)), '[]')
                 from kt_ton_thuc_te where ngay between p_tu and p_den));
end $$;
