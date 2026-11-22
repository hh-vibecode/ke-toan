-- 10/11/2026 anh: "DNTT các phiếu chi lương / chi BHXH — còn vướng chia theo từng cơ sở, khoảng 50% chi từ khoản vay, 50% chi từ két tiền mặt —
-- xử lý thế nào để không phải làm DNTT tách quá nhỏ (tự tách thì hơn 10 phiếu nhỏ)".
-- Chia theo cơ sở: 1 phiếu đã phân bổ nhiều đơn vị (phan_bo) — không cần tách. Chỉ NGUỒN TIỀN buộc mỗi tài khoản 1 phiếu chi (sổ quỹ / số dư từng TK).
-- → kt_chia_nguon_chi: 1 lần bấm chia phiếu theo nhiều tài khoản đi tiền: dòng 1 = phiếu gốc (đổi TK nếu khác), dòng 2.. = phiếu tách (kt_tach_chi:
-- phân bổ cơ sở / tháng chia theo tỷ lệ, chứng từ ở phiếu gốc, ghi chú "Tách từ PC…"), mỗi phiếu đúng tài khoản. Phiếu đang Chờ chi tiền → đổi TK qua
-- kt_doi_tk_chi (báo thủ quỹ / giám đốc như đổi tay). Chỉ khi phiếu chưa chi (Chờ xác nhận / Chờ GĐ / Chờ chi tiền). — Monsieur Claude
create or replace function public.kt_chia_nguon_chi(p_phien text, p_id bigint, p_ds jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; r jsonb; i int := 0; v bigint; tk int; tien numeric; tong numeric; t kt_tai_khoan; moi bigint[] := '{}';
begin
  u := kt_chan(p_phien, 'chi', true);
  if not kt_co_quyen(u, 'chi_duyet') then raise exception 'Chỉ kế toán (quyền xác nhận) chia nguồn tiền' using errcode = '42501'; end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi'; end if;
  if c.trang_thai not in ('cho_duyet', 'cho_gd', 'cho_tt') then raise exception 'Chỉ chia nguồn khi phiếu chưa chi tiền'; end if;
  if jsonb_typeof(p_ds) <> 'array' or jsonb_array_length(p_ds) < 2 then raise exception 'Cần ít nhất 2 nguồn tiền'; end if;
  select sum((e->>'so_tien')::numeric) into tong from jsonb_array_elements(p_ds) e;
  if tong is distinct from c.so_tien then raise exception 'Tổng các nguồn (%) phải bằng số tiền phiếu (%)', tong, c.so_tien; end if;
  for r in select e from jsonb_array_elements(p_ds) e loop
    tk := (r->>'tk')::int; tien := (r->>'so_tien')::numeric;
    if tien is null or tien <= 0 then raise exception 'Số tiền từng nguồn phải > 0'; end if;
    select * into t from kt_tai_khoan where id = tk and hoat_dong;
    if t.id is null then raise exception 'Tài khoản không hợp lệ'; end if;
  end loop;
  -- dòng 2..n: tách sang phiếu mới rồi gán tài khoản
  for r in select e from jsonb_array_elements(p_ds) with ordinality x(e, n) where n > 1 order by n loop
    tk := (r->>'tk')::int; tien := (r->>'so_tien')::numeric; select * into t from kt_tai_khoan where id = tk;
    v := kt_tach_chi(p_phien, p_id, tien, left(c.noi_dung || ' — chi từ ' || t.ten, 300), null);
    moi := moi || v;
    if c.trang_thai = 'cho_tt' then perform kt_doi_tk_chi(p_phien, v, tk);
    else update kt_chi set tai_khoan_id = tk where id = v; end if;
  end loop;
  -- dòng 1: phiếu gốc (phần còn lại = số tiền dòng 1) giữ / đổi tài khoản
  tk := (p_ds->0->>'tk')::int;
  if c.tai_khoan_id is distinct from tk then
    if c.trang_thai = 'cho_tt' then perform kt_doi_tk_chi(p_phien, p_id, tk); else update kt_chi set tai_khoan_id = tk where id = p_id; end if;
  end if;
  perform kt_ghi_nhat_ky(coalesce(u.ho_ten, u.ten_dang_nhap), 'kt_chi', p_id, 'chia_nguon', jsonb_build_object('nguon', p_ds, 'phieu_moi', to_jsonb(moi)));
  return jsonb_build_object('goc', p_id, 'moi', to_jsonb(moi));
end $$;
revoke execute on function public.kt_chia_nguon_chi(text, bigint, jsonb) from public;
grant execute on function public.kt_chia_nguon_chi(text, bigint, jsonb) to anon, authenticated;
