-- 23/10/2026 (anh): "task kéo P&L 1–8 vào lại P&L chính" → trang Báo cáo → P&L lấy CHI PHÍ T1–T8 theo 4 file P&L kế toán (cột THỰC HIỆN,
-- đã nạp vào kt_pnl_cu ở phần so khớp); doanh thu / giá vốn vẫn từ Kiot; từ T9 vẫn tính từ phiếu chi trên app. Quyền xem như trang P&L. — Monsieur Claude
create or replace function public.kt_pnl_t18(p_phien text) returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin
  perform kt_chan(p_phien, 'pl');
  return coalesce((select jsonb_agg(jsonb_build_object('nguon', nguon, 'thang', thang, 'ma', ma, 'ten', ten, 'th', thuc_hien) order by nguon, thang, dong)
    from kt_pnl_cu where thang <= '2026-08'), '[]');
end $f$;
revoke all on function public.kt_pnl_t18(text) from public; grant execute on function public.kt_pnl_t18(text) to anon;
