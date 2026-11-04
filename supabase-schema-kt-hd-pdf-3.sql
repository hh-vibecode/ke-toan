-- 03/11/2026: chạy bù PDF hoá đơn không được kẹt mãi vì vài HĐ MISA không trả file: chiều nào 20 phút không thêm được file nào
-- thì thôi gọi chiều đó; cả 2 chiều hết việc / đứng yên → gỡ lịch kt-hd-pdf-bu + ghi nhật ký số HĐ còn lại. — Monsieur Claude
create or replace function public.kt_hd_pdf_bu() returns text language plpgsql security definer set search_path = public, cron as $$
declare c text; con_ra int; con_vao int; dung_ra boolean; dung_vao boolean;
begin
  select count(*) into con_ra from kt_hd_can_pdf_xem('ra', 5000);
  select count(*) into con_vao from kt_hd_can_pdf_xem('vao', 5000);
  dung_ra := con_ra > 0 and not exists (select 1 from kt_hd_pdf where chieu = 'ra' and luc > now() - interval '20 minutes');
  dung_vao := con_vao > 0 and not exists (select 1 from kt_hd_pdf where chieu = 'vao' and luc > now() - interval '20 minutes');
  if (con_ra = 0 or dung_ra) and (con_vao = 0 or dung_vao) then
    perform cron.unschedule('kt-hd-pdf-bu');
    insert into kt_nhat_ky (nguoi, bang, hanh_dong, du_lieu) values ('Hệ thống', 'kt_hd_pdf', 'tai_pdf_hd_bu_xong',
      jsonb_build_object('con_ra', con_ra, 'con_vao', con_vao,
        'ra', (select count(*) from kt_hd_pdf where chieu = 'ra'), 'vao', (select count(*) from kt_hd_pdf where chieu = 'vao')));
    return 'xong · còn ' || con_ra || ' ra · ' || con_vao || ' vào không tải được';
  end if;
  if con_ra > 0 and not dung_ra then select command into c from cron.job where jobname = 'kt-hd-pdf-ra'; execute c; end if;
  if con_vao > 0 and not dung_vao then select command into c from cron.job where jobname = 'kt-hd-pdf-vao'; execute c; end if;
  return con_ra || ' ra · ' || con_vao || ' vào';
end $$;
revoke execute on function public.kt_hd_pdf_bu() from public, anon, authenticated;
