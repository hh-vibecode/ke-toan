-- "Không hạch toán" cho cả 3 loại phiếu: chi · thu · điều chuyển (19/10/2026, anh: "bổ sung vào cả 3 đầu phiếu,
-- dạng 1 trong phiếu tạo mới có dấu * đỏ; dạng 2 trong chỉnh sửa ở chỗ phân bổ chi phí: tích có hạch toán mới mở phần phân bổ, khoản cá nhân thì khoá").
-- Thu không hạch toán: vẫn cộng tiền tài khoản, KHÔNG vào doanh thu / thu nhập trên P&L, không làm trọng số chia chi phí theo cơ sở.
-- Điều chuyển không hạch toán: đánh dấu giao dịch cá nhân (điều chuyển vốn không vào P&L). — Monsieur Claude
alter table public.kt_thu add column if not exists khong_hach_toan boolean not null default false;
alter table public.kt_dieu_chuyen add column if not exists khong_hach_toan boolean not null default false;

do $$
declare d text; n int;
begin
  -- kt_luu_thu
  d := pg_get_functiondef('public.kt_luu_thu'::regproc); n := length(d);
  d := replace(d, $a$loai_id, ghi_chu, trang_thai, tao_boi)$a$, $a$loai_id, ghi_chu, trang_thai, tao_boi, khong_hach_toan)$a$);
  d := replace(d, $a$coalesce(p_dong->>'trang_thai','da_duyet'), u.ho_ten) returning id into v_id;$a$,
                  $a$coalesce(p_dong->>'trang_thai','da_duyet'), u.ho_ten, coalesce((p_dong->>'khong_hach_toan')::boolean, false)) returning id into v_id;$a$);
  d := replace(d, $a$trang_thai = coalesce(p_dong->>'trang_thai', trang_thai),
      sua_boi$a$, $a$trang_thai = coalesce(p_dong->>'trang_thai', trang_thai),
      khong_hach_toan = coalesce((p_dong->>'khong_hach_toan')::boolean, khong_hach_toan), sua_boi$a$);
  if length(d) - n < 150 then raise exception 'kt_luu_thu: khong thay du cho (%)', length(d) - n; end if; execute d;

  -- kt_luu_dieu_chuyen
  d := pg_get_functiondef('public.kt_luu_dieu_chuyen'::regproc); n := length(d);
  d := replace(d, $a$ghi_chu, kiot, kiot_ly_do, tao_boi)$a$, $a$ghi_chu, kiot, kiot_ly_do, tao_boi, khong_hach_toan)$a$);
  d := replace(d, $a$nullif(trim(p_dong->>'kiot_ly_do'),''), u.ho_ten) returning id into v_id;$a$,
                  $a$nullif(trim(p_dong->>'kiot_ly_do'),''), u.ho_ten, coalesce((p_dong->>'khong_hach_toan')::boolean, false)) returning id into v_id;$a$);
  d := replace(d, $a$kiot_ly_do = nullif(trim(p_dong->>'kiot_ly_do'),''), sua_boi = u.ho_ten$a$,
                  $a$kiot_ly_do = nullif(trim(p_dong->>'kiot_ly_do'),''), khong_hach_toan = coalesce((p_dong->>'khong_hach_toan')::boolean, khong_hach_toan), sua_boi = u.ho_ten$a$);
  if length(d) - n < 150 then raise exception 'kt_luu_dieu_chuyen: khong thay du cho (%)', length(d) - n; end if; execute d;

  -- P&L: thu không hạch toán không vào doanh thu / thu nhập
  d := pg_get_functiondef('public.kt_bc_pl'::regproc); n := length(d);
  d := replace(d, $a$where not t.da_xoa and t.trang_thai = 'da_duyet' and t.ngay between p_tu and p_den group by 1, 2) x)$a$,
                  $a$where not t.da_xoa and t.trang_thai = 'da_duyet' and not t.khong_hach_toan and t.ngay between p_tu and p_den group by 1, 2) x)$a$);
  if length(d) = n then raise exception 'kt_bc_pl: khong thay cho'; end if; execute d;

  -- chia chi phí theo doanh thu cơ sở: bỏ thu không hạch toán
  d := pg_get_functiondef('public.kt_chi_phi_ht'::regproc); n := length(d);
  d := replace(d, $a$from kt_thu where not da_xoa and trang_thai = 'da_duyet' and ngay between p_tu and p_den and don_vi_id is not null$a$,
                  $a$from kt_thu where not da_xoa and trang_thai = 'da_duyet' and not khong_hach_toan and ngay between p_tu and p_den and don_vi_id is not null$a$);
  if length(d) = n then raise exception 'kt_chi_phi_ht: khong thay cho'; end if; execute d;
end $$;

-- Bật / tắt hạch toán ngay trong cửa sổ phiếu (dạng 2)
create or replace function public.kt_dat_hach_toan(p_phien text, p_bang text, p_id bigint, p_hach_toan boolean)
returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi;
begin
  if p_bang not in ('chi','thu','dieu_chuyen') then raise exception 'Chưa hỗ trợ bảng %', p_bang; end if;
  u := kt_chan(p_phien, p_bang, true);
  if p_bang = 'chi' then
    select * into c from kt_chi where id = p_id and not da_xoa;
    if c.id is null then raise exception 'Không tìm thấy phiếu chi #%', p_id; end if;
    if p_hach_toan and c.trang_thai = 'da_tt' and c.loai_id is null then
      raise exception 'Phiếu đã chi tiền: chọn loại chi trước rồi mới bật hạch toán';
    end if;
    update kt_chi set khong_hach_toan = not p_hach_toan, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  elsif p_bang = 'thu' then
    update kt_thu set khong_hach_toan = not p_hach_toan, sua_boi = u.ho_ten, sua_luc = now() where id = p_id and not da_xoa;
  else
    update kt_dieu_chuyen set khong_hach_toan = not p_hach_toan, sua_boi = u.ho_ten, sua_luc = now() where id = p_id and not da_xoa;
  end if;
  if not found then raise exception 'Không tìm thấy phiếu #%', p_id; end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, 'sua', jsonb_build_object('hach_toan', p_hach_toan));
end $$;
revoke all on function public.kt_dat_hach_toan(text, text, bigint, boolean) from public;
grant execute on function public.kt_dat_hach_toan(text, text, bigint, boolean) to anon;
