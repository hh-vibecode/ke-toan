-- 13/11/2026 — NÚT "CHIA LƯƠNG / BHXH" trên phiếu chi (Phương án A anh chọn + anh: "khoản bảo hiểm xã hội cũng cần chia tương tự").
-- Kế toán mở phiếu tổng lương (hoặc BHXH) → điền số tiền từng nhóm theo bảng lương → app tự tách mỗi nhóm 1 phiếu (kt_tach_chi: cùng trạng thái /
-- tài khoản / ngày → số dư không đổi, chứng từ ở phiếu gốc), gắn sẵn loại chi + tháng hạch toán (lương T10 trả đầu T11 vẫn vào T10) + phân bổ:
--   • nhóm "theo % doanh số tháng" → phân bổ Hiền Thủy / Chánh Tâm / BP Sales Sỉ theo doanh thu thuần Kiot CHÍNH tháng đó (như khoản định kỳ phan_bo_ds;
--     tháng đang chạy = tới hôm nay; chưa có doanh thu → tạm Toàn công ty), đánh dấu 'ds' trong phan_bo như nút "Theo % doanh số" có sẵn →
--     lịch kt-pb-ds (kt_pb_ds_tinh_lai, mỗi đêm) tự chia lại theo doanh số mới tới hết tháng sau; sửa tay phân bổ trên form → thôi tự chia (như cũ);
--   • nhóm vào thẳng 1 đơn vị (trực tiếp HT / CT / Sales Sỉ, Toàn công ty…).
-- Bản chạy đầu (cùng ngày) thêm cột kt_chi.pb_ds + trigger + lịch kt-chia-ds riêng → gỡ, dùng chung cơ chế 'ds' có sẵn (không 2 cơ chế song song). — Monsieur Claude
select cron.unschedule('kt-chia-ds') where exists (select 1 from cron.job where jobname = 'kt-chia-ds');
drop function if exists public.kt_chia_ds_lai();
drop trigger if exists kt_chi_pb_ds on public.kt_chi;
drop function if exists public.kt_chi_pb_ds_tg();
alter table public.kt_chi drop column if exists pb_ds;

-- doanh thu thuần Kiot từng cơ sở (HT / CT / BP Sales Sỉ) của 1 tháng — cùng cách tính kt_pl_dinh_ky_thang
create or replace function public.kt_ds_co_so_thang(p_thang text) returns jsonb
language sql stable security definer set search_path = public as $$
  with th as (select (p_thang || '-01')::date d1, ((p_thang || '-01')::date + interval '1 month - 1 day')::date d2,
                     (now() at time zone 'Asia/Ho_Chi_Minh')::date nay),
  cs as (select id dv, kiot_chi_nhanh cn from kt_don_vi where id in (2, 3, 4)),
  dsm as (select cs.dv,
                 greatest(coalesce((select sum(h.tong) from kt_kiot_hoa_don h where h.trang_thai in (1, 3) and h.chi_nhanh = any(cs.cn)
                                     and (h.ngay at time zone 'Asia/Ho_Chi_Minh')::date between th.d1 and least(th.d2, th.nay)), 0)
                       - coalesce((select sum(t.tong_tra) from kt_kiot_tra_hang t where coalesce(t.trang_thai, 1) = 1 and t.chi_nhanh = any(cs.cn)
                                     and (t.ngay at time zone 'Asia/Ho_Chi_Minh')::date between th.d1 and least(th.d2, th.nay)), 0), 0) dt
            from cs cross join th)
  select coalesce(jsonb_agg(jsonb_build_object('don_vi_id', dv, 'dt', dt) order by dv) filter (where dt > 0), '[]'::jsonb) from dsm
$$;

-- phân bổ p_tien theo % doanh số tháng (mỗi dòng mang 'ds' = tháng → kt_pb_ds_tinh_lai chia lại mỗi đêm): làm tròn từng phần, phần lẻ dồn dòng cuối
create or replace function public.kt_pb_theo_ds(p_thang text, p_tien numeric) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d jsonb := kt_ds_co_so_thang(p_thang); tong numeric; r jsonb := '[]'::jsonb; e jsonb; da numeric := 0; i int := 0; n int; v numeric;
begin
  n := jsonb_array_length(d);
  if n = 0 then return jsonb_build_array(jsonb_build_object('don_vi_id', 1, 'so_tien', p_tien, 'ds', p_thang)); end if;   -- chưa có doanh số: tạm Tổng công ty
  select sum((x->>'dt')::numeric) into tong from jsonb_array_elements(d) x;
  for e in select x from jsonb_array_elements(d) x loop
    i := i + 1;
    v := case when i = n then p_tien - da else round(p_tien * (e->>'dt')::numeric / tong) end;
    da := da + v;
    r := r || jsonb_build_array(jsonb_build_object('don_vi_id', (e->>'don_vi_id')::int, 'so_tien', v, 'ds', p_thang));
  end loop;
  return r;
end $$;
revoke all on function public.kt_ds_co_so_thang(text) from public, anon, authenticated;
revoke all on function public.kt_pb_theo_ds(text, numeric) from public, anon, authenticated;

-- % doanh số tháng cho cửa sổ Chia lương (kế toán)
create or replace function public.kt_chia_luong_ty_le(p_phien text, p_thang text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u kt_nguoi_dung; d jsonb; tong numeric;
begin
  u := kt_chan(p_phien, 'chi');
  if not kt_co_quyen(u, 'chi_duyet') then raise exception 'Chỉ kế toán' using errcode = '42501'; end if;
  if p_thang !~ '^\d{4}-\d{2}$' then raise exception 'Tháng không hợp lệ'; end if;
  d := kt_ds_co_so_thang(p_thang);
  select sum((x->>'dt')::numeric) into tong from jsonb_array_elements(d) x;
  return (select coalesce(jsonb_agg(jsonb_build_object('don_vi_id', (x->>'don_vi_id')::int, 'pt', round(100 * (x->>'dt')::numeric / tong, 1))), '[]'::jsonb)
            from jsonb_array_elements(d) x);
end $$;
revoke all on function public.kt_chia_luong_ty_le(text, text) from public;
grant execute on function public.kt_chia_luong_ty_le(text, text) to anon, authenticated;

-- chia 1 phiếu thành các nhóm. p_ds = [{nhom, loai_id, chia: 'ds' | '<don_vi_id>', so_tien}], dòng 1 = phiếu gốc
create or replace function public.kt_chia_luong(p_phien text, p_id bigint, p_thang text, p_nhan text, p_ds jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; r jsonb; v bigint; tien numeric; tong numeric; moi bigint[] := '{}'; nd text; pb jsonb; ch text;
begin
  u := kt_chan(p_phien, 'chi', true);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  if not kt_co_quyen(u, 'chi_duyet') then raise exception 'Chỉ kế toán (quyền xác nhận) chia lương' using errcode = '42501'; end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi'; end if;
  if c.trang_thai in ('tu_choi', 'tu_choi_tt') then raise exception 'Phiếu đã từ chối — không chia'; end if;
  if c.la_tam_ung or c.loai_dn = 'hoan_ung' then raise exception 'Không chia phiếu tạm ứng / hoàn ứng'; end if;
  if coalesce(p_thang, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Chọn tháng hạch toán'; end if;
  if exists (select 1 from kt_khoa_ky where thang = p_thang) then raise exception 'Tháng % đã khoá sổ', p_thang; end if;
  if jsonb_typeof(p_ds) <> 'array' or jsonb_array_length(p_ds) < 1 then raise exception 'Điền ít nhất 1 nhóm'; end if;
  select sum((e->>'so_tien')::numeric) into tong from jsonb_array_elements(p_ds) e;
  if tong is distinct from c.so_tien then raise exception 'Tổng các nhóm (%) phải bằng số tiền phiếu (%)', tong, c.so_tien; end if;
  for r in select e from jsonb_array_elements(p_ds) e loop
    tien := (r->>'so_tien')::numeric; ch := r->>'chia';
    if tien is null or tien <= 0 or tien <> round(tien) then raise exception 'Số tiền từng nhóm phải là số nguyên > 0'; end if;
    if coalesce(trim(r->>'nhom'), '') = '' then raise exception 'Đặt tên từng nhóm'; end if;
    if not exists (select 1 from kt_loai where id = (r->>'loai_id')::int and nhom = 'chi') then raise exception 'Nhóm "%": chọn loại chi', r->>'nhom'; end if;
    if ch is distinct from 'ds' and not exists (select 1 from kt_don_vi where id = nullif(ch, '')::int) then raise exception 'Nhóm "%": chọn cách chia', r->>'nhom'; end if;
  end loop;
  -- dòng 2..n: tách sang phiếu mới
  for r in select e from jsonb_array_elements(p_ds) with ordinality x(e, n) where n > 1 order by n loop
    tien := (r->>'so_tien')::numeric; ch := r->>'chia';
    nd := left(trim(p_nhan) || ' T' || right(p_thang, 2) || '/' || left(p_thang, 4) || ' · ' || trim(r->>'nhom'), 300);
    v := kt_tach_chi(p_phien, p_id, tien, nd, (r->>'loai_id')::int);
    pb := case when ch = 'ds' then kt_pb_theo_ds(p_thang, tien) else jsonb_build_array(jsonb_build_object('don_vi_id', ch::int, 'so_tien', tien)) end;
    update kt_chi set phan_bo = pb, thang_ht = p_thang, phan_bo_thang = null,
           ghi_chu = left(concat_ws(' · ', 'Tách từ PC' || lpad(p_id::text, 6, '0') || ' (chia ' || case when upper(trim(p_nhan)) = 'BHXH' then 'BHXH' else lower(trim(p_nhan)) end || ')', c.ghi_chu), 1000) where id = v;
    moi := moi || v;
  end loop;
  -- dòng 1: phiếu gốc (còn đúng số tiền dòng 1)
  r := p_ds->0; tien := (r->>'so_tien')::numeric; ch := r->>'chia';
  nd := left(trim(p_nhan) || ' T' || right(p_thang, 2) || '/' || left(p_thang, 4) || ' · ' || trim(r->>'nhom'), 300);
  pb := case when ch = 'ds' then kt_pb_theo_ds(p_thang, tien) else jsonb_build_array(jsonb_build_object('don_vi_id', ch::int, 'so_tien', tien)) end;
  update kt_chi set loai_id = (r->>'loai_id')::int, noi_dung = nd, phan_bo = pb,
         thang_ht = p_thang, phan_bo_thang = null,
         -- ghi chú gốc gọn 1 dòng (thay các dòng "Đã tách … sang …" kt_tach_chi ghi từng lần)
         ghi_chu = left(concat_ws(' · ', 'Nội dung đề nghị: ' || c.noi_dung || ' (' || replace(to_char(c.so_tien, 'FM999G999G999G999'), ',', '.') || ')'
                                   || case when cardinality(moi) > 0 then ' — chia ' || case when upper(trim(p_nhan)) = 'BHXH' then 'BHXH' else lower(trim(p_nhan)) end || ' sang PC'
                                        || (select string_agg(lpad(m::text, 6, '0'), ', PC' order by m) from unnest(moi) m) else '' end, c.ghi_chu), 1000),
         sua_boi = u.ho_ten, sua_luc = now()
   where id = p_id;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_chi', p_id, 'chia_luong',
          jsonb_build_object('thang', p_thang, 'khoan', p_nhan, 'nhom', p_ds, 'phieu_moi', to_jsonb(moi), 'noi_dung_cu', c.noi_dung));
  return jsonb_build_object('goc', p_id, 'moi', to_jsonb(moi));
end $$;
revoke all on function public.kt_chia_luong(text, bigint, text, text, jsonb) from public;
grant execute on function public.kt_chia_luong(text, bigint, text, text, jsonb) to anon, authenticated;
