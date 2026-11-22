-- Giám đốc lùi bước phiếu chi (20/10/2026, anh: "cho giám đốc có quyền lùi bước cho phiếu"):
-- Chờ chi tiền → Chờ xác nhận; Từ chối / Từ chối thanh toán → Chờ xác nhận (mở lại). (Đã chi tiền → Chờ chi tiền: supabase-schema-kt-huy-da-chi.sql.) — Monsieur Claude
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_luu_chi'::regproc); n := length(d);
  d := replace(d, $a$    or (v_tu = 'da_tt' and v_tt = 'cho_tt' and (v_duyet or v_gd))$a$,
                  $a$    or (v_tu = 'da_tt' and v_tt = 'cho_tt' and (v_duyet or v_gd))
    or (v_tu = 'cho_tt' and v_tt = 'cho_duyet' and v_gd)                          -- 20/10: GĐ lùi về chờ xác nhận
    or (v_tu in ('tu_choi','tu_choi_tt') and v_tt = 'cho_duyet' and v_gd)         -- 20/10: GĐ mở lại phiếu bị từ chối$a$);
  if length(d) = n then raise exception 'kt_luu_chi: khong thay cho'; end if; execute d;
end $$;
