-- 22/10/2026 anh: phiếu chi 3 lựa chọn hạch toán — Hạch toán / Chi phí cá nhân / Không hạch toán.
-- Cá nhân → tự là không hạch toán + sang nhóm "Giao dịch cá nhân"; Không hạch toán (khoản công ty không tính chi phí, vd nộp lại BHXH) → ở lại nhóm công ty.
-- Monsieur Claude
alter table kt_chi add column if not exists ca_nhan boolean not null default false;

-- Giữ quy tắc ở máy chủ: cá nhân ⇒ không hạch toán; bật hạch toán ⇒ bỏ cá nhân (kt_dat_hach_toan cũ vẫn đúng)
create or replace function public.kt_chi_ca_nhan_tg() returns trigger language plpgsql set search_path to 'public' as $f$
begin
  if new.ca_nhan then new.khong_hach_toan := true; end if;
  if not new.khong_hach_toan then new.ca_nhan := false; end if;
  return new;
end $f$;
drop trigger if exists kt_chi_ca_nhan on kt_chi;
create trigger kt_chi_ca_nhan before insert or update of ca_nhan, khong_hach_toan on kt_chi for each row execute function kt_chi_ca_nhan_tg();

-- kt_luu_chi: nhận thêm p_dong.ca_nhan (cùng điều kiện quyền như khong_hach_toan). Vá tại chỗ, chạy lại không vá trùng.
do $d$ declare d text := pg_get_functiondef('kt_luu_chi(text,jsonb)'::regprocedure); n int := length(d);
begin
  if position('ca_nhan' in d) > 0 then return; end if;
  d := replace(d, $s$tao_boi, khong_hach_toan, noi_dung_ck)$s$, $s$tao_boi, khong_hach_toan, noi_dung_ck, ca_nhan)$s$);
  d := replace(d, $s$coalesce((p_dong->>'khong_hach_toan')::boolean, false), nullif(left(trim(p_dong->>'noi_dung_ck'), 50), ''))$s$,
                  $s$coalesce((p_dong->>'khong_hach_toan')::boolean, false), nullif(left(trim(p_dong->>'noi_dung_ck'), 50), ''), coalesce((p_dong->>'ca_nhan')::boolean, false))$s$);
  d := replace(d, $s$then coalesce((p_dong->>'khong_hach_toan')::boolean, khong_hach_toan) else khong_hach_toan end,$s$,
                  $s$then coalesce((p_dong->>'khong_hach_toan')::boolean, khong_hach_toan) else khong_hach_toan end,
    ca_nhan = case when v_ghi or (v_cu.tao_boi = u.ho_ten and coalesce(v_cu.trang_thai, 'cho_duyet') = 'cho_duyet') then coalesce((p_dong->>'ca_nhan')::boolean, ca_nhan) else ca_nhan end,$s$);
  if length(d) - n < 200 then raise exception 'Vá kt_luu_chi không khớp mẫu — dừng'; end if;
  execute d;
end $d$;

-- Ô chọn 3 loại trong khung chi tiết phiếu (thay ô tick "Có hạch toán chi phí")
create or replace function public.kt_dat_kieu_ht(p_phien text, p_id bigint, p_kieu text) returns void
 language plpgsql security definer set search_path to 'public' as $f$
declare u kt_nguoi_dung;
begin
  if p_kieu not in ('co','khong','ca_nhan') then raise exception 'Kiểu hạch toán không hợp lệ'; end if;
  u := kt_chan(p_phien, 'chi', true);
  perform kt_dat_hach_toan(p_phien, 'chi', p_id, p_kieu = 'co');
  update kt_chi set ca_nhan = (p_kieu = 'ca_nhan') where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'sua', jsonb_build_object('kieu_hach_toan', p_kieu));
end $f$;
revoke all on function public.kt_dat_kieu_ht(text,bigint,text) from public; grant execute on function public.kt_dat_kieu_ht(text,bigint,text) to anon;

-- Dữ liệu cũ (22/10 chỉ có 2 phiếu không hạch toán): #1729 "Chuyển tiền cá nhân" → cá nhân; #1670 nộp lại BHXH → giữ không hạch toán (công ty)
update kt_chi set ca_nhan = true where id = 1729 and khong_hach_toan;
