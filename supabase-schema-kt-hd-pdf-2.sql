-- 03/11/2026: (1) kt_hd_can_pdf_xem thiếu "limit p_n" → thêm; (2) anh: "ngày chạy 2 lần thôi, không cần mỗi tiếng" → lịch tải PDF 01:00 và 13:00 giờ VN
-- (sau 2 lượt kéo hoá đơn MISA 00:25 / 12:25); (3) chạy bù ~1.350 hoá đơn cũ: lịch tạm kt-hd-pdf-bu 3 phút / lượt, hết việc tự gỡ. — Monsieur Claude
create or replace function public.kt_hd_can_pdf_xem(p_chieu text, p_n int default 30)
returns table(ma text, so_hd text, ky_hieu text, ngay date) language sql stable security definer set search_path = public as $$
  select * from (select distinct on (h.ma_ngoai) h.ma_ngoai, h.so_hd, h.ky_hieu, h.ngay from kt_thue_hd h
   where h.hkd = 'CTY' and h.chieu = p_chieu and h.ma_ngoai is not null and h.ngay >= '2026-01-01'
     and not exists (select 1 from kt_hd_pdf p where p.ma = h.ma_ngoai)
   order by h.ma_ngoai, h.ngay desc) x order by x.ngay desc limit p_n
$$;
revoke execute on function public.kt_hd_can_pdf_xem(text, int) from public, anon, authenticated;
select cron.alter_job((select jobid from cron.job where jobname = 'kt-hd-pdf-ra'), schedule := '0 6,18 * * *');
select cron.alter_job((select jobid from cron.job where jobname = 'kt-hd-pdf-vao'), schedule := '5 6,18 * * *');
create or replace function public.kt_hd_pdf_bu() returns text language plpgsql security definer set search_path = public, cron as $$
declare c text; con_ra int; con_vao int;
begin
  select count(*) into con_ra from kt_hd_can_pdf_xem('ra', 5000);
  select count(*) into con_vao from kt_hd_can_pdf_xem('vao', 5000);
  if con_ra + con_vao = 0 then perform cron.unschedule('kt-hd-pdf-bu'); return 'xong'; end if;
  if con_ra > 0 then select command into c from cron.job where jobname = 'kt-hd-pdf-ra'; execute c; end if;
  if con_vao > 0 then select command into c from cron.job where jobname = 'kt-hd-pdf-vao'; execute c; end if;
  return con_ra || ' ra · ' || con_vao || ' vào';
end $$;
revoke execute on function public.kt_hd_pdf_bu() from public, anon, authenticated;
select cron.schedule('kt-hd-pdf-bu', '*/3 * * * *', 'select public.kt_hd_pdf_bu()');
select jobname, schedule from cron.job where jobname like 'kt-hd-pdf%' order by 1;
