-- Chi TIỀN MẶT từ két: thủ quỹ ghi NGƯỜI ĐẾN NHẬN TIỀN (16/10/2026, anh Hải: "liên quan két tiền mặt thì thủ quỹ có thêm mục ghi ai là người đã đến nhận, vì không phải chuyển khoản") — Monsieur Claude
-- Bắt buộc khi chuyển Đã thanh toán mà tài khoản đi tiền là tiền mặt. Vá trên định nghĩa đang chạy.
alter table public.kt_chi add column if not exists nguoi_nhan_tien text;

do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_luu_chi'::regproc);
  n := length(d);
  d := replace(d, $a$    unc          = case when v_duyet or v_gd or v_tq then$a$,
                  $a$    nguoi_nhan_tien = case when v_duyet or v_gd or v_tq then coalesce(nullif(trim(p_dong->>'nguoi_nhan_tien'), ''), nguoi_nhan_tien) else nguoi_nhan_tien end,
    unc          = case when v_duyet or v_gd or v_tq then$a$);
  if length(d) = n then raise exception 'kt_luu_chi: khong thay cot unc'; end if;
  n := length(d);
  d := replace(d, $a$      raise exception 'Up ảnh giao dịch (uỷ nhiệm chi / phiếu chi tiền mặt) trước khi bấm Đã chi tiền';
    end if;$a$,
                  $a$      raise exception 'Up ảnh giao dịch (uỷ nhiệm chi / phiếu chi tiền mặt) trước khi bấm Đã chi tiền';
    end if;
    if (select loai from kt_tai_khoan where id = v_tk) = 'tien_mat'
       and coalesce(nullif(trim(p_dong->>'nguoi_nhan_tien'), ''), v_cu.nguoi_nhan_tien) is null then
      raise exception 'Chi tiền mặt: ghi tên người đến nhận tiền';
    end if;$a$);
  if length(d) = n then raise exception 'kt_luu_chi: khong thay cho kiem anh'; end if;
  execute d;
end $$;
