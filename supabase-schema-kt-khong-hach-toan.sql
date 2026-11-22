-- Phiếu chi "KHÔNG HẠCH TOÁN CHI PHÍ" (19/10/2026, anh: "phiếu chi lúc tạo / chỉnh sửa thêm nút không hạch toán chi phí, để phục vụ các giao dịch cá nhân không phục vụ công ty")
-- Vẫn là tiền thật ra khỏi tài khoản (sổ quỹ / dòng tiền / số dư) nhưng KHÔNG vào chi phí, P&L, báo cáo quản trị; không bắt buộc loại chi. — Monsieur Claude
alter table public.kt_chi add column if not exists khong_hach_toan boolean not null default false;

-- đã thanh toán: phải có loại chi, trừ phiếu không hạch toán
alter table public.kt_chi drop constraint if exists kt_chi_tt_du;
alter table public.kt_chi add constraint kt_chi_tt_du check (trang_thai <> 'da_tt' or (ngay_tt is not null and tai_khoan_id is not null and (loai_id is not null or khong_hach_toan)));

-- view chi phí hạch toán (P&L, Tổng quan, báo cáo quản trị, xem chi tiết số) bỏ phiếu không hạch toán
do $$
declare d text;
begin
  d := pg_get_viewdef('public.kt_v_chi_ht'::regclass);
  if position('khong_hach_toan' in d) = 0 then
    d := replace(d, '(NOT c.la_tam_ung)', '(NOT c.la_tam_ung) AND (NOT c.khong_hach_toan)');
    if position('khong_hach_toan' in d) = 0 then raise exception 'kt_v_chi_ht: khong thay cho'; end if;
    execute 'create or replace view public.kt_v_chi_ht as ' || d;
  end if;
end $$;

-- các hàm đọc thẳng kt_chi để tính CHI PHÍ (không đụng dòng tiền)
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_chi_phi_ht'::regproc); n := length(d);
  d := replace(d, $a$and c.trang_thai in ('cho_tt', 'da_tt') and not c.la_tam_ung and c.loai_id is null$a$, $a$and c.trang_thai in ('cho_tt', 'da_tt') and not c.la_tam_ung and not c.khong_hach_toan and c.loai_id is null$a$);
  if length(d) = n then raise exception 'kt_chi_phi_ht: khong thay cho'; end if; execute d;

  d := pg_get_functiondef('public.kt_bc_pl'::regproc); n := length(d);
  d := replace(d, $a$where not c.da_xoa and c.trang_thai = 'da_tt'$a$, $a$where not c.da_xoa and c.trang_thai = 'da_tt' and not c.khong_hach_toan$a$);
  if length(d) = n then raise exception 'kt_bc_pl: khong thay cho'; end if; execute d;

  -- kt_luu_chi: lưu cờ khi tạo + khi sửa nội dung
  d := pg_get_functiondef('public.kt_luu_chi'::regproc); n := length(d);
  d := replace(d, $a$thu_huong_stk, phan_bo, han_tt, co_hd_do, ghi_chu, chung_tu, tao_boi)$a$, $a$thu_huong_stk, phan_bo, han_tt, co_hd_do, ghi_chu, chung_tu, tao_boi, khong_hach_toan)$a$);
  d := replace(d, $a$coalesce(array(select jsonb_array_elements_text(p_dong->'chung_tu')), '{}'), u.ho_ten)$a$, $a$coalesce(array(select jsonb_array_elements_text(p_dong->'chung_tu')), '{}'), u.ho_ten, coalesce((p_dong->>'khong_hach_toan')::boolean, false))$a$);
  d := replace(d, $a$      co_hd_do = coalesce((p_dong->>'co_hd_do')::boolean,false), ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''),$a$,
                  $a$      co_hd_do = coalesce((p_dong->>'co_hd_do')::boolean,false), ghi_chu = nullif(trim(p_dong->>'ghi_chu'),''),
      khong_hach_toan = coalesce((p_dong->>'khong_hach_toan')::boolean, khong_hach_toan),$a$);
  if length(d) - n < 150 then raise exception 'kt_luu_chi: khong thay du cho (%)', length(d) - n; end if; execute d;
end $$;

-- kt_pl_ct (P&L cũ, xem chi tiết): bỏ phiếu không hạch toán nếu có điều kiện trạng thái đã TT
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_pl_ct'::regproc); n := length(d);
  d := regexp_replace(d, $r$(where\s+not\s+c\.da_xoa)$r$, '\1 and not c.khong_hach_toan');
  if length(d) <> n then execute d; end if;
end $$;

-- Sửa 19/10: bỏ tick trên phiếu ĐÃ CHI phải đặt cờ cùng lệnh với loại chi (ràng buộc kt_chi_tt_du kiểm theo từng lệnh)
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_luu_chi'::regproc); n := length(d);
  d := replace(d, $a$      khong_hach_toan = coalesce((p_dong->>'khong_hach_toan')::boolean, khong_hach_toan),
$a$, '');
  d := replace(d, $a$  update kt_chi set
    trang_thai   = case when v_doi then v_tt else trang_thai end,$a$, $a$  if coalesce((p_dong->>'khong_hach_toan')::boolean, v_cu.khong_hach_toan, false) = false and coalesce(v_tt, v_cu.trang_thai) = 'da_tt'
     and coalesce((p_dong->>'loai_id')::int, v_cu.loai_id) is null then
    raise exception 'Phiếu đã chi tiền: bỏ "Không hạch toán chi phí" thì chọn loại chi';
  end if;
  update kt_chi set
    trang_thai   = case when v_doi then v_tt else trang_thai end,
    khong_hach_toan = case when v_ghi or v_cu.tao_boi = u.ho_ten then coalesce((p_dong->>'khong_hach_toan')::boolean, khong_hach_toan) else khong_hach_toan end,$a$);
  if length(d) - n < 300 then raise exception 'kt_luu_chi: khong thay du cho (%)', length(d) - n; end if; execute d;
end $$;
