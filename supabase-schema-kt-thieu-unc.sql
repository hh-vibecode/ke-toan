-- Phiếu chi ĐÃ CHI nhưng THIẾU ẢNH GIAO DỊCH (uỷ nhiệm chi / phiếu chi ký nhận) — nhắc admin up đủ chứng từ
-- (19/10/2026, anh: "bổ sung các khoản chưa update hình ảnh giao dịch để làm lời nhắc cho admin up đủ chứng từ", "thêm cả vào cảnh báo công việc cần xử lý").
-- Đủ = có file tên "UNC…" (ô Ảnh giao dịch trên app) hoặc link UNC cũ từ sheet. Từ 01/09/2026 (mốc tiền của app). — Monsieur Claude
create or replace function public.kt_thieu_unc(c kt_chi) returns boolean language sql stable set search_path = public as $$
  select c.trang_thai = 'da_tt' and not c.da_xoa and c.ngay_tt >= date '2026-09-01' and coalesce(trim(c.unc), '') = ''
     and not exists (select 1 from kt_chung_tu k where k.bang = 'chi' and k.dong_id = c.id and not k.da_xoa and k.ten_file ilike 'UNC%');
$$;
revoke all on function public.kt_thieu_unc(kt_chi) from public;

do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_ds'::regproc); n := length(d);
  d := replace(d, $a$'nghi_loai', kt_nghi_loai(c))$a$, $a$'nghi_loai', kt_nghi_loai(c), 'thieu_unc', kt_thieu_unc(c))$a$);
  if length(d) = n then raise exception 'kt_ds: khong thay cho'; end if; execute d;

  d := pg_get_functiondef('public.kt_bao_cao'::regproc); n := length(d);
  d := replace(d, $a$       'dc_chua_xac_nhan', (select count(*) from kt_dieu_chuyen where not da_xoa and not da_xac_nhan),$a$,
                  $a$       'chi_thieu_unc', (select count(*) from kt_chi c where c.trang_thai = 'da_tt' and kt_thieu_unc(c)),
       'dc_chua_xac_nhan', (select count(*) from kt_dieu_chuyen where not da_xoa and not da_xac_nhan),$a$);
  if length(d) = n then raise exception 'kt_bao_cao: khong thay cho'; end if; execute d;
end $$;
