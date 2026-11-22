-- Phiếu đề nghị công khai: tối đa 60 file hồ sơ (trước 15) — 19/10/2026, kế toán thông báo các bộ phận "upload ảnh chứng từ không giới hạn,
-- up riêng từng ảnh, không cần gom PDF". Link công khai không đăng nhập nên vẫn giữ mức trần chống lạm dụng. — Monsieur Claude
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_phieu_theo_ma'::regproc);
  n := length(d) - length(replace(d, 'so_file >= 15', ''));
  if n = 0 then raise exception 'kt_phieu_theo_ma: khong thay cho'; end if;
  d := replace(replace(d, 'so_file >= 15', 'so_file >= 60'), 'tối đa 15 file', 'tối đa 60 file');
  execute d;
end $$;
