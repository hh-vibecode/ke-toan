-- Phiếu "Chờ chi tiền": đổi tài khoản đi tiền sau khi đã xác nhận (19/10/2026, kế toán: "1 khoản đã duyệt chi từ két rồi nhưng sau đó đổi ý,
-- thì chị phải là người sửa lại phiếu đó à"). Người xác nhận (kế toán có quyền xác nhận / giám đốc) đổi 1 bước, báo chuông người chi mới.
-- Thủ quỹ KHÔNG tự đổi tài khoản (trước: kt_luu_chi cho thủ quỹ ghi đè tai_khoan_id lúc bấm Đã chi). — Monsieur Claude
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_luu_chi'::regproc); n := length(d);
  d := replace(d, $a$v_tk := coalesce((p_dong->>'tai_khoan_id')::int, v_cu.tai_khoan_id);$a$,
                  $a$v_tk := case when v_duyet or v_gd then coalesce((p_dong->>'tai_khoan_id')::int, v_cu.tai_khoan_id) else v_cu.tai_khoan_id end;$a$);
  d := replace(d, $a$tai_khoan_id = case when v_duyet or v_gd or v_tq then coalesce((p_dong->>'tai_khoan_id')::int, tai_khoan_id) else tai_khoan_id end,$a$,
                  $a$tai_khoan_id = case when v_duyet or v_gd then coalesce((p_dong->>'tai_khoan_id')::int, tai_khoan_id) else tai_khoan_id end,$a$);
  if length(d) - n < 40 then raise exception 'kt_luu_chi: khong thay du cho (%)', length(d) - n; end if; execute d;
end $$;

create or replace function public.kt_doi_tk_chi(p_phien text, p_id bigint, p_tk int)
returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; t kt_tai_khoan; v_tom text;
begin
  u := kt_chan(p_phien);
  if not kt_co_quyen(u, 'chi_duyet') and not kt_co_quyen(u, 'chi_gd') then
    raise exception 'Chỉ người xác nhận (kế toán có quyền xác nhận / giám đốc) đổi được tài khoản đi tiền' using errcode = '42501';
  end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi #%', p_id; end if;
  if c.trang_thai <> 'cho_tt' then raise exception 'Chỉ đổi được tài khoản khi phiếu đang chờ chi tiền'; end if;
  select * into t from kt_tai_khoan where id = p_tk and hoat_dong;
  if t.id is null then raise exception 'Tài khoản không hợp lệ'; end if;
  if c.tai_khoan_id = p_tk then return; end if;
  update kt_chi set tai_khoan_id = p_tk, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'doi_tk', jsonb_build_object('tu', c.tai_khoan_id, 'sang', p_tk));
  v_tom := left(c.noi_dung, 120) || ' · ' || replace(to_char(c.so_tien, 'FM999G999G999G999'), ',', '.') || ' đ · chi từ ' || t.ten;
  if coalesce(t.thu_quy_chi, false) then
    perform kt_bao(array(select id from kt_nguoi_dung where hoat_dong and 'chi_tt' = any(quyen) and id <> u.id), u.ho_ten, 'chi_cho_tt', 'Đổi tài khoản đi tiền — thủ quỹ chi', v_tom, 'chi', p_id);
  else
    perform kt_bao(kt_ai_giam_doc(u.id), u.ho_ten, 'chi_cho_tt', 'Đổi tài khoản đi tiền — giám đốc chi từ tài khoản cá nhân', v_tom, 'chi', p_id);
  end if;
end $$;
revoke all on function public.kt_doi_tk_chi(text, bigint, int) from public;
grant execute on function public.kt_doi_tk_chi(text, bigint, int) to anon;
