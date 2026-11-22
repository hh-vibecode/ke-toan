-- 03/11/2026 anh: "tải lâu nhỉ, kéo từ MISA về à, có cách nào kéo ảnh về lưu ở chỗ mình để mở cho nhanh"
-- → tải sẵn PDF mọi hoá đơn công ty (ra: meInvoice · vào: MISA Bot) về kt-chung-tu hd/{chieu}/{mã}.pdf, chạy ngầm mỗi giờ
-- (Edge kt-meinvoice / kt-meinvoice-bot, body {"pdf_xem":true}); kt_hd_pdf ghi hoá đơn nào đã có file. — Monsieur Claude
create table if not exists public.kt_hd_pdf (
  ma text primary key,
  chieu text not null,
  duong text not null,
  kich_thuoc int,
  luc timestamptz not null default now()
);
alter table public.kt_hd_pdf enable row level security;
revoke all on public.kt_hd_pdf from anon, authenticated;

-- hoá đơn công ty chưa có PDF lưu sẵn (mới nhất trước)
create or replace function public.kt_hd_can_pdf_xem(p_chieu text, p_n int default 30)
returns table(ma text, so_hd text, ky_hieu text, ngay date) language sql stable security definer set search_path = public as $$
  select distinct on (h.ma_ngoai) h.ma_ngoai, h.so_hd, h.ky_hieu, h.ngay from kt_thue_hd h
   where h.hkd = 'CTY' and h.chieu = p_chieu and h.ma_ngoai is not null and h.ngay >= '2026-01-01'
     and not exists (select 1 from kt_hd_pdf p where p.ma = h.ma_ngoai)
   order by h.ma_ngoai, h.ngay desc
$$;
revoke execute on function public.kt_hd_can_pdf_xem(text, int) from public, anon, authenticated;

-- lịch chạy ngầm: lệnh chép từ lịch kéo đêm, chỉ đổi body (không ghi khoá ra file)
do $$ declare c text; begin
  select replace(command, 'body := ''{}''::jsonb', 'body := ''{"pdf_xem":true}''::jsonb') into c from cron.job where jobname = 'kt-meinvoice';
  if c is null or c not like '%pdf_xem%' then raise exception 'khong tao duoc lenh kt-hd-pdf-ra'; end if;
  perform cron.schedule('kt-hd-pdf-ra', '50 * * * *', c);
  select replace(command, 'body := ''{}''::jsonb', 'body := ''{"pdf_xem":true}''::jsonb') into c from cron.job where jobname = 'kt-meinvoice-bot';
  if c is null or c not like '%pdf_xem%' then raise exception 'khong tao duoc lenh kt-hd-pdf-vao'; end if;
  perform cron.schedule('kt-hd-pdf-vao', '55 * * * *', c);
end $$;
