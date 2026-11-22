-- 11/11/2026 anh: "thỉnh thoảng 3–5 ngày vào kiểm tra con backup chứng từ có còn chạy hay không".
-- Sao lưu chạy trên máy anh (lịch Windows kt-sao-luu-chung-tu 15:30 T2–T7) và ghi kt_nhat_ky 'sao_luu_drive' / 'sao_luu_drive_loi'.
-- → pg_cron kt-kiem-sao-luu mỗi ngày 17:30 giờ VN: nếu lần chạy THÀNH CÔNG gần nhất cũ hơn 3 ngày, hoặc lần chạy gần nhất bị lỗi → báo chuông
-- cho anh Hải (Supreme). Đã báo cùng nội dung trong 24 giờ thì thôi (không báo dồn). Không gọi ra ngoài. — Monsieur Claude
create or replace function public.kt_kiem_sao_luu() returns jsonb
language plpgsql security definer set search_path = public as $$
declare ok_luc timestamptz; cuoi kt_nhat_ky; v_tieu text; v_nd text; nhan int[];
begin
  select max(luc) into ok_luc from kt_nhat_ky where bang = 'kt_chung_tu' and hanh_dong = 'sao_luu_drive';
  select * into cuoi from kt_nhat_ky where bang = 'kt_chung_tu' and hanh_dong in ('sao_luu_drive', 'sao_luu_drive_loi') order by id desc limit 1;
  if cuoi.id is not null and cuoi.hanh_dong = 'sao_luu_drive_loi' then
    v_tieu := 'Sao lưu chứng từ bị lỗi';
    v_nd := 'Lần chạy ' || to_char(cuoi.luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ' lỗi: ' || left(coalesce(cuoi.du_lieu->>'loi_cuoi', cuoi.du_lieu->>'loi', '?'), 160);
  elsif ok_luc is null or ok_luc < now() - interval '3 days' then
    v_tieu := 'Sao lưu chứng từ không chạy hơn 3 ngày';
    v_nd := 'Lần sao lưu Drive thành công gần nhất: ' || coalesce(to_char(ok_luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM/YYYY'), 'chưa có') || ' — kiểm tra máy anh có bật lúc 15:30 và lịch Windows kt-sao-luu-chung-tu';
  else
    return jsonb_build_object('ok', true, 'lan_ok_cuoi', ok_luc);
  end if;
  if exists (select 1 from kt_thong_bao where loai = 'sao_luu' and tieu_de = v_tieu and tao_luc > now() - interval '24 hours') then
    return jsonb_build_object('ok', false, 'da_bao', true, 'tieu_de', v_tieu);
  end if;
  select array_agg(id) into nhan from kt_nguoi_dung where hoat_dong and vi_tri = 'supreme';
  perform kt_bao(nhan, 'Hệ thống', 'sao_luu', v_tieu, v_nd, null, null);
  return jsonb_build_object('ok', false, 'bao', v_tieu, 'nd', v_nd);
end $$;
revoke execute on function public.kt_kiem_sao_luu() from public, anon, authenticated;

select cron.unschedule('kt-kiem-sao-luu') where exists (select 1 from cron.job where jobname = 'kt-kiem-sao-luu');
select cron.schedule('kt-kiem-sao-luu', '30 10 * * *', 'select public.kt_kiem_sao_luu()');   -- 10:30 UTC = 17:30 giờ VN

-- 13/11/2026 anh: "bỏ luồng sao lưu đi nhé" → đã gỡ lịch: select cron.unschedule('kt-kiem-sao-luu'); lịch Windows kt-sao-luu-chung-tu tắt (Disabled). Bật lại thì chạy lại 2 dòng cron.schedule ở trên. — Monsieur Claude
