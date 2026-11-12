-- ĐỐI SOÁT GIAO DỊCH (Sổ quỹ & số dư tài khoản → tab "Đối soát giao dịch") — 11/11/2026, bản đầu theo spec "Đối soát giao dịch KiotViet ↔ App ↔ Sao kê".
-- Dùng lại kết quả ghép sao kê đã có (kt_sao_ke_ky.ket_qua.rows — trang Đối chiếu sao kê / Edge kt-sao-ke tính sẵn), KHÔNG ghép lại:
--   (1) dòng sao kê chưa có phiếu trên app ("Thiếu phiếu");
--   (2) phiếu app của tài khoản ngân hàng trong khoảng ngày đã có sao kê nhưng không dòng sao kê nào nhận ("App có, sao kê không");
--   (3) phiếu điều chuyển: mỗi đầu là ngân hàng phải thấy trên sao kê của đầu đó ("Điều chuyển chờ xác minh 2 đầu"; đầu két tiền mặt = kiểm két, bỏ qua);
--   (4) tài khoản ngân hàng đang dùng mà kỳ đang xem chưa có sao kê phủ hết ("Thiếu sao kê").
-- Chỉ đọc. Quyền theo trang Số dư tài khoản. — Monsieur Claude
-- 12/11 kế toán duyệt cách hiểu ("ok đúng ý rồi, triển khai giao diện dễ nhìn, đừng lằng nhằng"): thêm phiếu Kiot (thu / chi chuyển khoản trên TK ngân hàng
-- của cửa hàng) để trang ghép với dòng sao kê; trả toàn bộ dòng sao kê trong kỳ; bảng kt_dsgd_xu_ly lưu ghi chú / đánh dấu đã xử lý / ghép tay. — Monsieur Claude
create table if not exists public.kt_dsgd_xu_ly (
  khoa text primary key,            -- sk:<id dòng sao kê> · kv:<id phiếu Kiot> · app:<loại>:<id>:<tk> · dc:<id> · dck:<id dòng sao kê>
  ghi_chu text, ghep text,          -- ghep: khoá bên kia khi ghép tay (vd sk:123 ↔ kv:456)
  nguoi text, luc timestamptz not null default now());
alter table public.kt_dsgd_xu_ly enable row level security;
revoke all on public.kt_dsgd_xu_ly from anon, authenticated;
create or replace function public.kt_dsgd_luu(p_phien text, p_khoa text, p_ghi_chu text, p_ghep text, p_bo boolean) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien, 'so_du', true);
  if p_khoa !~ '^(sk|kv|app|dc|dck):' then raise exception 'Khoá không hợp lệ'; end if;
  if p_bo then
    delete from kt_dsgd_xu_ly where khoa = p_khoa or (p_ghep is not null and khoa = p_ghep);
  else
    if coalesce(btrim(p_ghi_chu), '') = '' and p_ghep is null then raise exception 'Ghi chú cách đã xử lý'; end if;
    insert into kt_dsgd_xu_ly (khoa, ghi_chu, ghep, nguoi) values (p_khoa, left(btrim(p_ghi_chu), 500), p_ghep, coalesce(u.ho_ten, u.ten_dang_nhap))
      on conflict (khoa) do update set ghi_chu = excluded.ghi_chu, ghep = excluded.ghep, nguoi = excluded.nguoi, luc = now();
    if p_ghep is not null then
      insert into kt_dsgd_xu_ly (khoa, ghi_chu, ghep, nguoi) values (p_ghep, left(btrim(p_ghi_chu), 500), p_khoa, coalesce(u.ho_ten, u.ten_dang_nhap))
        on conflict (khoa) do update set ghi_chu = excluded.ghi_chu, ghep = excluded.ghep, nguoi = excluded.nguoi, luc = now();
    end if;
  end if;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_dsgd_xu_ly', null, case when p_bo then 'mo_lai' else 'xu_ly' end,
    jsonb_build_object('khoa', p_khoa, 'ghep', p_ghep, 'ghi_chu', p_ghi_chu));
end $$;
revoke execute on function public.kt_dsgd_luu(text, text, text, text, boolean) from public;
grant execute on function public.kt_dsgd_luu(text, text, text, text, boolean) to anon, authenticated;

create or replace function public.kt_doi_soat_gd(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'so_du');
  return (with
  tk as (select id, ten, thu_tu, loai from kt_tai_khoan where hoat_dong),
  nh as (select * from tk where loai = 'ngan_hang'),
  ky as (select k.id, k.tk_id, k.tu, k.den, k.ket_qua from kt_sao_ke_ky k where k.tk_id in (select id from nh) and k.ket_qua is not null),
  dong as (select ky.tk_id, ky.id ky_id, r from ky, jsonb_array_elements(coalesce(ky.ket_qua->'rows', '[]')) r),
  ghep as (select distinct d.tk_id, p->>'k' k, (p->>'id')::bigint id from dong d, jsonb_array_elements(coalesce(d.r->'phieu', '[]')) p),
  app as (
    select 'thu' k, t.id, t.tai_khoan_id tk_id, t.ngay, t.so_tien vao, 0::numeric ra, t.noi_dung nd from kt_thu t
      where not t.da_xoa and t.trang_thai = 'da_duyet' and t.ngay between p_tu and p_den and t.tai_khoan_id in (select id from nh)
    union all
    select 'chi', c.id, c.tai_khoan_id, c.ngay_tt, 0, c.so_tien, c.noi_dung from kt_chi c
      where not c.da_xoa and c.trang_thai = 'da_tt' and c.ngay_tt between p_tu and p_den and c.tai_khoan_id in (select id from nh)
    union all
    select 'dc', d.id, d.tk_di_id, d.ngay, 0, d.so_tien, d.noi_dung from kt_dieu_chuyen d
      where not d.da_xoa and not coalesce(d.khong_hach_toan, false) and d.ngay between p_tu and p_den and d.tk_di_id in (select id from nh)
    union all
    select 'dc', d.id, d.tk_nhan_id, d.ngay, d.so_tien, 0, d.noi_dung from kt_dieu_chuyen d
      where not d.da_xoa and not coalesce(d.khong_hach_toan, false) and d.ngay between p_tu and p_den and d.tk_nhan_id in (select id from nh)
    union all
    select 'vay', n.id, n.tai_khoan_id, n.ngay, n.so_tien, 0, 'Nhận tiền vay · ' || v.ten from kt_vay_nhan n join kt_vay v on v.id = n.vay_id
      where not n.da_xoa and n.ngay between p_tu and p_den and n.tai_khoan_id in (select id from nh)
    union all
    select 'vay', -r.id, r.tai_khoan_id, r.ngay, 0, r.goc + r.lai, 'Trả nợ vay · ' || v.ten from kt_vay_tra r join kt_vay v on v.id = r.vay_id
      where not r.da_xoa and r.da_tra and r.ngay between p_tu and p_den and r.tai_khoan_id in (select id from nh)),
  app2 as (select a.*, exists (select 1 from ky where ky.tk_id = a.tk_id and a.ngay between ky.tu and ky.den) phu,
                  exists (select 1 from ghep g where g.tk_id = a.tk_id and g.k = a.k and g.id = a.id) thay from app a),
  dc as (select d.id, d.ngay, d.so_tien, d.noi_dung, d.da_xac_nhan, d.tk_di_id, d.tk_nhan_id,
           (select loai from kt_tai_khoan where id = d.tk_di_id) l_di, (select loai from kt_tai_khoan where id = d.tk_nhan_id) l_nhan,
           exists (select 1 from ky where ky.tk_id = d.tk_di_id and d.ngay between ky.tu and ky.den) phu_di,
           exists (select 1 from ky where ky.tk_id = d.tk_nhan_id and d.ngay between ky.tu and ky.den) phu_nhan,
           exists (select 1 from ghep g where g.tk_id = d.tk_di_id and g.k = 'dc' and g.id = d.id) thay_di,
           exists (select 1 from ghep g where g.tk_id = d.tk_nhan_id and g.k = 'dc' and g.id = d.id) thay_nhan
         from kt_dieu_chuyen d
         where not d.da_xoa and not coalesce(d.khong_hach_toan, false) and d.ngay between p_tu and p_den
           and (d.tk_di_id in (select id from nh) or d.tk_nhan_id in (select id from nh))),
  dc2 as (select dc.*,
           case when (l_di = 'ngan_hang' and phu_di and not thay_di) or (l_nhan = 'ngan_hang' and phu_nhan and not thay_nhan) then 'lech'
                when (l_di = 'ngan_hang' and not phu_di) or (l_nhan = 'ngan_hang' and not phu_nhan) then 'cho'
                else 'du' end tt from dc)
  select jsonb_build_object(
    'tk', coalesce((select jsonb_agg(jsonb_build_object('id', nh.id, 'ten', nh.ten,
            'ky', coalesce((select jsonb_agg(jsonb_build_object('tu', ky.tu, 'den', ky.den) order by ky.tu) from ky where ky.tk_id = nh.id and ky.tu <= p_den and ky.den >= p_tu), '[]'),
            'so_dong', (select count(*) from dong where dong.tk_id = nh.id and (r->>'ngay')::date between p_tu and p_den),
            'da_ghep', (select count(*) from dong where dong.tk_id = nh.id and (r->>'ngay')::date between p_tu and p_den and jsonb_array_length(coalesce(r->'phieu', '[]')) > 0),
            'so_phieu', (select count(*) from app where app.tk_id = nh.id),
            'kiot', coalesce(array_length((select kiot_ma from kt_tai_khoan where id = nh.id), 1), 0) > 0) order by nh.thu_tu, nh.id) from nh), '[]'),
    'dong', coalesce((select jsonb_agg(jsonb_build_object('id', (r->>'id')::bigint, 'tk_id', tk_id, 'ngay', r->>'ngay', 'so_ct', r->>'so_ct', 'no', (r->>'no')::numeric,
            'co', (r->>'co')::numeric, 'nd', r->>'nd', 'phieu', coalesce(r->'phieu', '[]')) order by r->>'ngay', (r->>'stt')::int)
          from dong where (r->>'ngay')::date between p_tu and p_den), '[]'),
    'kv', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'ma', q.ma, 'ngay', (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'la_thu', q.la_thu, 'so_tien', q.so_tien,
            'tk_id', t.id, 'nhom', q.nhom, 'doi_tac', q.doi_tac, 'nd', q.noi_dung, 'cn', q.chi_nhanh) order by q.ngay)
          from kt_kiot_so_quy q join kt_tai_khoan t on t.id in (select id from nh) and q.tai_khoan = any(t.kiot_ma)
          where coalesce(q.phuong_thuc, '') <> 'Cash' and q.trang_thai = '0'
            and (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date between p_tu - 3 and p_den + 3), '[]'),
    'xl', coalesce((select jsonb_agg(jsonb_build_object('khoa', khoa, 'ghi_chu', ghi_chu, 'ghep', ghep, 'nguoi', nguoi, 'luc', luc)) from kt_dsgd_xu_ly), '[]'),
    'app_thieu', coalesce((select jsonb_agg(jsonb_build_object('k', k, 'id', id, 'tk_id', tk_id, 'ngay', ngay, 'vao', vao, 'ra', ra, 'nd', nd) order by ngay, k, id)
          from app2 where phu and not thay and k <> 'dc'), '[]'),
    'dc', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'ngay', ngay, 'so_tien', so_tien, 'nd', noi_dung, 'xn', da_xac_nhan, 'di', tk_di_id, 'nhan', tk_nhan_id,
            'l_di', l_di, 'l_nhan', l_nhan, 'phu_di', phu_di, 'phu_nhan', phu_nhan, 'thay_di', thay_di, 'thay_nhan', thay_nhan, 'tt', tt) order by ngay, id)
          from dc2 where tt <> 'du'), '[]'),
    'dc_du', (select count(*) from dc2 where tt = 'du')));
end $$;
revoke execute on function public.kt_doi_soat_gd(text, date, date) from public;
grant execute on function public.kt_doi_soat_gd(text, date, date) to anon, authenticated;
