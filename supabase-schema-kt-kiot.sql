-- =========================================================================
-- APP KẾ TOÁN — chuyển sổ quỹ Kiot thành khoản THU (Monsieur Claude, 05/10/2026)
-- Dữ liệu từ 01/09/2026 (anh chốt 05/10: làm tháng 9 trước). Job kéo Kiot ghi kt_kiot_so_quy rồi gọi kt_dong_bo_kiot().
--
-- Luật (trang Cài đặt > Logic diễn giải đúng luật này):
--   · Chỉ phiếu Kiot "Đã thanh toán" (status 0), số tiền dương, KHÔNG phải nhóm "Chuyển rút" (chuyển quỹ nội bộ Kiot).
--   · Loại thu theo đầu mã phiếu: TTHD / TTHDD (thu tiền hoá đơn) = Thu bán hàng · TTDH (thu tiền đơn đặt hàng) và nhóm
--     "Thu tiền đặt cọc" = Thu đặt cọc · TT (khách trả nợ) = Thu công nợ · còn lại (TNH...) = Thu khác.
--   · Tài khoản nhận: id tài khoản Kiot ghép qua kt_tai_khoan.kiot_ma. Phiếu hình thức TIỀN MẶT (Cash) → luôn vào tài khoản
--     có kiot_ma chứa 'TIEN_MAT_QUAY' (két tiền mặt), KỂ CẢ khi Kiot gắn nhầm tài khoản ngân hàng — giống sheet cũ.
--     (Đối chiếu T9 05/10: 13 phiếu Cash gắn TK HKD HT / CT = đúng 5.832.000 lệch giữa Kiot và sheet.)
--   · Phiếu có nội dung chứa SỐ TÀI KHOẢN của chính công ty (vd "ck từ TECH CN -1913...") = chuyển nội bộ ghi nhầm thành thu
--     → KHÔNG tính thu (đối chiếu T9: TNH000695 30 tr). Kế toán tự ghi điều chuyển nếu cần.
--   · Mã TTD_ / CTD_ (2 chiều lệnh chuyển quỹ Kiot) cũng là chuyển nội bộ, kể cả khi Kiot để trống nhóm.
--   · Cơ sở: chi nhánh Kiot ghép qua kt_don_vi.kiot_chi_nhanh.
--   · Phiếu Kiot bị huỷ sau khi đã chép → khoản thu tương ứng bị ẩn (da_xoa). Phiếu không ghép được tài khoản → bỏ qua, đếm báo.
--   · Phiếu CHI Kiot không chép sang Chi (khoản chi đi qua đề nghị trên app) — giữ trong kt_kiot_so_quy để đối chiếu.
-- =========================================================================

create or replace function public.kt_dong_bo_kiot(p_tu date default date '2026-09-01') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_them int; v_sua int; v_huy int; v_bo int; v_quay int;
  l_ban int; l_coc int; l_no int; l_khac int;
begin
  select id into l_ban  from kt_loai where nhom = 'thu' and ten = 'Thu bán hàng';
  select id into l_coc  from kt_loai where nhom = 'thu' and ten = 'Thu đặt cọc';
  select id into l_no   from kt_loai where nhom = 'thu' and ten = 'Thu công nợ';
  select id into l_khac from kt_loai where nhom = 'thu' and ten = 'Thu khác';
  select id into v_quay from kt_tai_khoan where 'TIEN_MAT_QUAY' = any(kiot_ma) limit 1;

  create temp table _k on commit drop as
  select q.id, q.ma, (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, q.so_tien, q.trang_thai,
    case when q.phuong_thuc = 'Cash' then v_quay
         else coalesce((select t.id from kt_tai_khoan t where q.tai_khoan = any(t.kiot_ma) limit 1),
                       case when q.tai_khoan is null then v_quay end) end tk_id,
    -- mã TTD_ / CTD_ = 2 chiều của lệnh chuyển quỹ trong Kiot, kể cả khi Kiot để trống nhóm "Chuyển rút" (T9: TTD_CTM004014)
    q.ma ~ '^(TTD_|CTD_)' or exists (select 1 from kt_tai_khoan t where length(regexp_replace(t.ten, '[^0-9]', '', 'g')) >= 8
             and coalesce(q.noi_dung, '') like '%' || regexp_replace(t.ten, '[^0-9]', '', 'g') || '%') noi_bo,
    (select d.id from kt_don_vi d where q.chi_nhanh = any(d.kiot_chi_nhanh) limit 1) dv_id,
    case when q.ma ~ '^TTHD' then l_ban
         when q.ma ~ '^TTDH' or q.nhom = 'Thu tiền đặt cọc' then l_coc
         when q.ma ~ '^TT[0-9]' then l_no
         else l_khac end loai_id,
    left(concat_ws(' · ', q.chi_nhanh, nullif(q.doi_tac, ''), q.nhom, nullif(q.noi_dung, '')), 300) noi_dung
  from kt_kiot_so_quy q
  where q.la_thu and q.so_tien > 0 and coalesce(q.nhom, '') <> 'Chuyển rút'
    and (q.ngay at time zone 'Asia/Ho_Chi_Minh')::date >= p_tu;

  select count(*) into v_bo from _k where trang_thai = '0' and tk_id is null and not noi_bo;

  with up as (
    insert into kt_thu (ngay, noi_dung, so_tien, don_vi_id, tai_khoan_id, loai_id, trang_thai, nguon, ma_nguon, tao_boi)
    select ngay, 'Kiot ' || ma || ' · ' || noi_dung, so_tien, dv_id, tk_id, loai_id, 'da_duyet', 'kiot', 'kiot:' || id, 'Kiot (tự kéo)'
      from _k where trang_thai = '0' and tk_id is not null and not noi_bo
    on conflict (ma_nguon) do update set ngay = excluded.ngay, noi_dung = excluded.noi_dung, so_tien = excluded.so_tien,
      don_vi_id = excluded.don_vi_id, tai_khoan_id = excluded.tai_khoan_id, loai_id = excluded.loai_id, da_xoa = false,
      sua_luc = now(), sua_boi = 'Kiot (tự kéo)'
      where (kt_thu.ngay, kt_thu.so_tien, kt_thu.don_vi_id, kt_thu.tai_khoan_id, kt_thu.loai_id, kt_thu.da_xoa)
        is distinct from (excluded.ngay, excluded.so_tien, excluded.don_vi_id, excluded.tai_khoan_id, excluded.loai_id, false)
    returning (xmax = 0) moi)
  select count(*) filter (where moi), count(*) filter (where not moi) into v_them, v_sua from up;

  update kt_thu t set da_xoa = true, sua_luc = now(), sua_boi = case when _k.noi_bo then 'Kiot (chuyển nội bộ, không tính thu)' else 'Kiot (phiếu đã huỷ)' end
    from _k where t.ma_nguon = 'kiot:' || _k.id and (_k.trang_thai <> '0' or _k.noi_bo) and not t.da_xoa;
  get diagnostics v_huy = row_count;

  return jsonb_build_object('them', v_them, 'sua', v_sua, 'huy', v_huy, 'bo_qua_khong_ghep_tk', v_bo);
end $$;
revoke execute on function public.kt_dong_bo_kiot(date) from public, anon, authenticated;
