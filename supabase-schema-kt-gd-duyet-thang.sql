-- Giám đốc / Supreme duyệt 1 lần qua luôn 2 bước (16/10/2026, anh Hải: "giám đốc có quyền, ấn duyệt là auto qua 2 bước luôn",
-- "giám đốc vs admin quyền cao nhất") — Monsieur Claude
--  · Chờ kế toán kiểm → Chờ thanh toán khi người bấm có quyền giám đốc (chi_gd / Supreme); ghi luôn người kiểm + người duyệt là người đó.
--  · Bỏ chặn "người kiểm lượt 1 không tự xác nhận lượt 2" — chỉ người có quyền giám đốc mới tới được lượt 2, kế toán vẫn không tự duyệt.
-- Vá trên định nghĩa đang chạy (có phiên cloud song song), không chép đè cả hàm.
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_luu_chi'::regproc);
  n := length(d);
  d := replace(d, $a$    or (v_tu = 'cho_gd' and v_tt in ('cho_tt','tu_choi') and v_gd)$a$,
                  $a$    or (v_tu = 'cho_gd' and v_tt in ('cho_tt','tu_choi') and v_gd)
    or (v_tu = 'cho_duyet' and v_tt = 'cho_tt' and v_gd)   -- 16/10: giám đốc duyệt thẳng qua 2 bước$a$);
  if length(d) = n then raise exception 'khong thay cho chuyen trang thai'; end if;
  n := length(d);
  d := replace(d, $a$  if v_doi and v_tu = 'cho_gd' and v_tt = 'cho_tt' and v_cu.kiem_boi = u.ho_ten then
    raise exception 'Người đã kiểm lượt 1 không tự xác nhận lượt 2 — cần giám đốc xác nhận' using errcode = '42501';
  end if;
$a$, '');
  if length(d) = n then raise exception 'khong thay cho chan tu duyet'; end if;
  n := length(d);
  d := replace(d, $a$    kiem_boi     = case when v_doi and v_tt = 'cho_gd' then u.ho_ten$a$,
                  $a$    kiem_boi     = case when v_doi and (v_tt = 'cho_gd' or (v_tt = 'cho_tt' and v_tu = 'cho_duyet')) then u.ho_ten$a$);
  d := replace(d, $a$    kiem_luc     = case when v_doi and v_tt = 'cho_gd' then now()$a$,
                  $a$    kiem_luc     = case when v_doi and (v_tt = 'cho_gd' or (v_tt = 'cho_tt' and v_tu = 'cho_duyet')) then now()$a$);
  if length(d) = n then raise exception 'khong thay cho kiem_boi'; end if;
  execute d;
end $$;
