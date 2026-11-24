-- 24/11/2026 (VIEC 419) — Sơ đồ kế toán "Luồng PO – Công nợ – Thanh toán" bước 4–5 + luồng riêng trung gian. — Monsieur Claude
-- (1) Thanh toán ngay tại hồ sơ đối tác (NCC nước ngoài / Vận chuyển & Logistics / NCC Kiot): chọn nhiều khoản công nợ, trả toàn bộ / 1 phần,
--     chọn TK chi, kế thừa STK nhận → kt_tt_lap tạo phiếu chi trên Thu–Chi (qua kt_luu_chi — giữ nguyên luật duyệt / tự chi),
--     gắn phiếu vào đối tác (kt_ncc_gan) và ghi từng khoản đã trả (kt_tt_khoan; NCC Kiot → kt_ncc_phan_bo gắn phiếu nhập).
--     Khoản chỉ tính "đã trả" khi phiếu chi Đã chi tiền; phiếu còn chờ duyệt = "đang chờ duyệt"; phiếu từ chối / xoá = bỏ.
-- (2) Trung gian 2 bước: lần chuyển tiền (kt_tt_nn) gắn đơn vị trung gian (tg_ncc_id) → số dư giữ hộ = tiền chuyển − phần đã trả hộ;
--     kt_tt_nn_tra_ho: xác nhận trung gian đã trả hộ NCC / PO → thêm dòng phân bổ (FIFO các lần chuyển còn số dư) → giảm công nợ NCC, PO cập nhật.

create table if not exists kt_tt_khoan (
  id bigserial primary key,
  chi_id bigint not null references kt_chi(id),
  ncc_id bigint not null references kt_ncc(id),
  loai text not null check (loai in ('po','cp','lo')),   -- po: tiền hàng + chi phí trả NCC của PO · cp: 1 dòng chi phí khác của PO (đơn vị nhận tiền) · lo: phí vận chuyển của lô
  po_id bigint references kt_po(id),
  cp_k text,                                              -- khoá dòng chi phí khác (chi_phi[].k)
  lo_id bigint,
  te text not null default 'VND',
  so_tien numeric not null check (so_tien > 0),           -- theo tiền tệ của khoản
  vnd numeric not null check (vnd >= 0),                  -- phần của phiếu chi (đ)
  ghi_chu text,
  tao_boi text, tao_luc timestamptz default now()
);
create index if not exists kt_tt_khoan_chi on kt_tt_khoan(chi_id);
create index if not exists kt_tt_khoan_ncc on kt_tt_khoan(ncc_id);
alter table kt_tt_khoan enable row level security;
revoke all on kt_tt_khoan from anon, authenticated;

alter table kt_tt_nn add column if not exists tg_ncc_id bigint references kt_ncc(id);

-- khoá ổn định cho từng dòng chi phí khác của PO (thanh toán từng dòng); dòng mới app tự cấp k khi thêm
update kt_po set chi_phi = (select jsonb_agg(case when e ? 'k' then e else e || jsonb_build_object('k', substr(md5(random()::text || clock_timestamp()::text), 1, 10)) end order by o)
                              from jsonb_array_elements(chi_phi) with ordinality x(e, o))
 where jsonb_typeof(chi_phi) = 'array' and jsonb_array_length(chi_phi) > 0 and exists (select 1 from jsonb_array_elements(chi_phi) e where not e ? 'k');

create or replace function kt_tt_khoan_ds(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'chi_id', k.chi_id, 'ncc_id', k.ncc_id, 'loai', k.loai, 'po_id', k.po_id, 'cp_k', k.cp_k, 'lo_id', k.lo_id,
      'te', k.te, 'so_tien', k.so_tien, 'vnd', k.vnd, 'ghi_chu', k.ghi_chu, 'tao_boi', k.tao_boi, 'tao_luc', k.tao_luc,
      'tt', c.trang_thai, 'ngay', coalesce(c.ngay_tt, c.ngay_de_nghi), 'chi_tien', c.so_tien, 'tk', (select ten from kt_tai_khoan where id = c.tai_khoan_id)) order by k.id desc)
    from kt_tt_khoan k join kt_chi c on c.id = k.chi_id and not c.da_xoa), '[]');
end $$;

-- p_dong: {ncc_id, phieu:{noi_dung, so_tien, ngay, tai_khoan_id, loai_id, bo_phan_id, thu_huong_ten, thu_huong_nh, thu_huong_stk, noi_dung_ck, trang_thai ('da_tt' | null), nguoi_nhan_tien},
--          khoan:[{loai:'po'|'cp'|'lo', po_id, cp_k, lo_id, te, so_tien, vnd}], nhap:[{nhap_id, so_tien}] (NCC Kiot)}
create or replace function kt_tt_lap(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; n kt_ncc; ph jsonb := coalesce(p_dong->'phieu', '{}'); v_ncc bigint := nullif(p_dong->>'ncc_id', '')::bigint;
  v_id bigint; v_tien numeric := nullif(ph->>'so_tien', '')::numeric; v_kh numeric; v_nh numeric; e jsonb; v_ngay date := coalesce(nullif(ph->>'ngay', '')::date, (now() at time zone 'Asia/Ho_Chi_Minh')::date);
begin
  u := kt_chan(p_phien, 'ncc', true);
  select * into n from kt_ncc where id = v_ncc and not da_xoa;
  if n.id is null then raise exception 'Không thấy đối tác'; end if;
  if coalesce(v_tien, 0) <= 0 then raise exception 'Số tiền thanh toán phải lớn hơn 0'; end if;
  if jsonb_array_length(coalesce(p_dong->'khoan', '[]')) + jsonb_array_length(coalesce(p_dong->'nhap', '[]')) = 0 then raise exception 'Chọn ít nhất 1 khoản công nợ'; end if;
  select coalesce(sum((x->>'vnd')::numeric), 0) into v_kh from jsonb_array_elements(coalesce(p_dong->'khoan', '[]')) x;
  select coalesce(sum((x->>'so_tien')::numeric), 0) into v_nh from jsonb_array_elements(coalesce(p_dong->'nhap', '[]')) x;
  if abs(v_kh + v_nh - v_tien) > 1 then raise exception 'Tổng các khoản (% đ) khác số tiền phiếu chi (% đ)', round(v_kh + v_nh), round(v_tien); end if;
  for e in select * from jsonb_array_elements(coalesce(p_dong->'khoan', '[]')) loop
    if e->>'loai' not in ('po','cp','lo') or coalesce((e->>'so_tien')::numeric, 0) <= 0 then raise exception 'Khoản thanh toán không hợp lệ'; end if;
    if e->>'loai' in ('po','cp') and not exists (select 1 from kt_po p where p.id = (e->>'po_id')::bigint and not p.da_xoa) then raise exception 'Không thấy PO của khoản thanh toán'; end if;
    if e->>'loai' = 'po' and not exists (select 1 from kt_po p where p.id = (e->>'po_id')::bigint and p.ncc_id = v_ncc) then raise exception 'PO không thuộc nhà cung cấp này'; end if;
    if e->>'loai' = 'cp' and not exists (select 1 from kt_po p, jsonb_array_elements(p.chi_phi) z where p.id = (e->>'po_id')::bigint and z->>'k' = e->>'cp_k' and nullif(z->>'dvn_id', '')::bigint = v_ncc) then
      raise exception 'Dòng chi phí không còn chọn đơn vị này làm Đơn vị nhận tiền (PO đã sửa?) — tải lại trang'; end if;
    if e->>'loai' = 'lo' and not exists (select 1 from kt_lo_nk l where l.id = (e->>'lo_id')::bigint and l.dv_vc_id = v_ncc and not l.da_xoa) then raise exception 'Lô hàng không còn chọn đơn vị vận chuyển này'; end if;
  end loop;
  -- phiếu chi trên Thu–Chi: cùng luật duyệt (tự chi khi có quyền, còn lại thành đề nghị chờ duyệt)
  v_id := kt_luu_chi(p_phien, jsonb_strip_nulls(jsonb_build_object('noi_dung', ph->>'noi_dung', 'so_tien', v_tien, 'ngay_de_nghi', v_ngay, 'ngay_su_dung', v_ngay,
    'bo_phan_id', nullif(ph->>'bo_phan_id', ''), 'thu_huong_ten', ph->>'thu_huong_ten', 'thu_huong_nh', ph->>'thu_huong_nh', 'thu_huong_stk', ph->>'thu_huong_stk',
    'noi_dung_ck', ph->>'noi_dung_ck', 'ghi_chu', ph->>'ghi_chu', 'loai_id', nullif(ph->>'loai_id', ''), 'tai_khoan_id', nullif(ph->>'tai_khoan_id', ''),
    'trang_thai', nullif(ph->>'trang_thai', ''), 'ngay_tt', case when ph->>'trang_thai' = 'da_tt' then v_ngay end, 'nguoi_nhan_tien', ph->>'nguoi_nhan_tien')));
  insert into kt_ncc_gan (bang, dong_id, ncc_id, tao_boi) values ('chi', v_id, v_ncc, u.ho_ten)
    on conflict (bang, dong_id) do update set ncc_id = excluded.ncc_id, ho_so_id = null, tao_boi = excluded.tao_boi, tao_luc = now();
  insert into kt_tt_khoan (chi_id, ncc_id, loai, po_id, cp_k, lo_id, te, so_tien, vnd, tao_boi)
    select v_id, v_ncc, x->>'loai', nullif(x->>'po_id', '')::bigint, nullif(x->>'cp_k', ''), nullif(x->>'lo_id', '')::bigint, coalesce(nullif(x->>'te', ''), 'VND'), (x->>'so_tien')::numeric, round((x->>'vnd')::numeric), u.ho_ten
      from jsonb_array_elements(coalesce(p_dong->'khoan', '[]')) x;
  if jsonb_array_length(coalesce(p_dong->'nhap', '[]')) > 0 then
    perform kt_ncc_phan_bo_luu(p_phien, v_ncc, 'chi', v_id, p_dong->'nhap');
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_tt_khoan', v_id, 'thanh_toan_doi_tac', p_dong);
  return v_id;
end $$;

-- lưu lần thanh toán trung gian: thêm đơn vị trung gian (tg_ncc_id) + giữ ngày xác nhận trả hộ của từng dòng phân bổ
create or replace function kt_tt_nn_luu(p_phien text, p_dong jsonb) returns bigint
language plpgsql security definer set search_path = public as $function$
declare u kt_nguoi_dung; v bigint := nullif(p_dong->>'id', '')::bigint; pb jsonb; tong numeric := coalesce(nullif(p_dong->>'so_tien_nt', '')::numeric, 0);
  v_te text := coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'); v_pte text := nullif(p_dong->>'pb_tien_te', ''); v_pty numeric := nullif(p_dong->>'pb_ty_gia', '')::numeric;
  v_tg bigint := nullif(p_dong->>'tg_ncc_id', '')::bigint;
begin
  u := kt_chan(p_phien, 'ncc', true);
  if tong <= 0 then raise exception 'Nhập số tiền nguyên tệ'; end if;
  if nullif(p_dong->>'ty_gia', '') is not null and (p_dong->>'ty_gia')::numeric <= 0 then raise exception 'Tỷ giá phải lớn hơn 0'; end if;
  if v_tg is not null and not exists (select 1 from kt_ncc where id = v_tg and loai = 'trung_gian' and not da_xoa) then raise exception 'Đơn vị trung gian không hợp lệ'; end if;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('ncc_id', nullif(e->>'ncc_id', '')::bigint, 'ncc_ten', e->>'ncc_ten', 'po_id', nullif(e->>'po_id', '')::bigint,
           'so_tien_nt', (e->>'so_tien_nt')::numeric, 'ghi_chu', nullif(btrim(e->>'ghi_chu'), ''), 'ngay', nullif(e->>'ngay', ''), 'xn_boi', nullif(e->>'xn_boi', '')))), '[]') into pb
    from jsonb_array_elements(coalesce(p_dong->'phan_bo', '[]')) e where coalesce(nullif(e->>'so_tien_nt', '')::numeric, 0) > 0;
  if exists (select 1 from jsonb_array_elements(pb) e where e->>'ncc_id' is null) then raise exception 'Mỗi dòng phân bổ chọn nhà cung cấp'; end if;
  if v_pte is null or v_pte = v_te then v_pte := null; v_pty := null;
  elsif coalesce(v_pty, 0) <= 0 then raise exception 'Nhập tỷ giá đổi % sang % để phân bổ', v_te, v_pte; end if;
  if (select coalesce(sum((e->>'so_tien_nt')::numeric), 0) from jsonb_array_elements(pb) e) > round(tong * coalesce(v_pty, 1), 2) + 0.01 then raise exception 'Tổng phân bổ lớn hơn số tiền chuyển%', case when v_pty is not null then ' (đã quy đổi sang ' || v_pte || ')' else '' end; end if;
  if v is null then
    insert into kt_tt_nn (ngay, tk_id, chi_id, ben_nhan, tien_te, so_tien_nt, ty_gia, phi, phan_bo, ghi_chu, tao_boi, pb_tien_te, pb_ty_gia, phi_tk_id, tg_ncc_id)
    values (coalesce(nullif(p_dong->>'ngay', '')::date, current_date), nullif(p_dong->>'tk_id', '')::bigint, nullif(p_dong->>'chi_id', '')::bigint, nullif(btrim(p_dong->>'ben_nhan'), ''),
      coalesce(nullif(p_dong->>'tien_te', ''), 'CNY'), tong, nullif(p_dong->>'ty_gia', '')::numeric, nullif(p_dong->>'phi', '')::numeric, pb, nullif(btrim(p_dong->>'ghi_chu'), ''), u.ho_ten, v_pte, v_pty, nullif(p_dong->>'phi_tk_id', '')::bigint, v_tg)
    returning id into v;
  else
    update kt_tt_nn set ngay = coalesce(nullif(p_dong->>'ngay', '')::date, ngay), tk_id = nullif(p_dong->>'tk_id', '')::bigint, chi_id = nullif(p_dong->>'chi_id', '')::bigint,
      ben_nhan = nullif(btrim(p_dong->>'ben_nhan'), ''), tien_te = coalesce(nullif(p_dong->>'tien_te', ''), tien_te), so_tien_nt = tong, ty_gia = nullif(p_dong->>'ty_gia', '')::numeric,
      phi = nullif(p_dong->>'phi', '')::numeric, phi_tk_id = nullif(p_dong->>'phi_tk_id', '')::bigint, phan_bo = pb, pb_tien_te = v_pte, pb_ty_gia = v_pty, ghi_chu = nullif(btrim(p_dong->>'ghi_chu'), ''),
      tg_ncc_id = case when p_dong ? 'tg_ncc_id' then v_tg else tg_ncc_id end, sua_boi = u.ho_ten, sua_luc = now()
     where id = v and not da_xoa;
    if not found then raise exception 'Không thấy lần thanh toán'; end if;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_tt_nn', v, case when p_dong->>'id' is null then 'them' else 'sua' end, p_dong);
  return v;
end $function$;

-- bước 2 trung gian: xác nhận đã trả hộ NCC (+ PO) → trừ dần số dư giữ hộ của các lần chuyển cùng tiền tệ phân bổ (cũ trước)
-- p_dong: {tg_ncc_id, te, ncc_id, po_id, so_tien, ngay, ghi_chu}
create or replace function kt_tt_nn_tra_ho(p_phien text, p_dong jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_tg bigint := nullif(p_dong->>'tg_ncc_id', '')::bigint; v_te text := p_dong->>'te'; v_ncc bigint := nullif(p_dong->>'ncc_id', '')::bigint;
  v_po bigint := nullif(p_dong->>'po_id', '')::bigint; v_con numeric := round(coalesce(nullif(p_dong->>'so_tien', '')::numeric, 0), 2); v_ten text; r record; v_lay numeric; v_du numeric; v_ds jsonb := '[]';
begin
  u := kt_chan(p_phien, 'ncc', true);
  if v_con <= 0 then raise exception 'Nhập số tiền trung gian đã trả hộ'; end if;
  if not exists (select 1 from kt_ncc where id = v_tg and loai = 'trung_gian' and not da_xoa) then raise exception 'Không thấy đơn vị trung gian'; end if;
  select ten into v_ten from kt_ncc where id = v_ncc and not da_xoa;
  if v_ten is null then raise exception 'Chọn nhà cung cấp được trả hộ'; end if;
  if v_po is not null and not exists (select 1 from kt_po where id = v_po and ncc_id = v_ncc and not da_xoa) then raise exception 'PO không thuộc nhà cung cấp đã chọn'; end if;
  select coalesce(sum(round(t.so_tien_nt * coalesce(t.pb_ty_gia, 1), 2) - coalesce((select sum((e->>'so_tien_nt')::numeric) from jsonb_array_elements(t.phan_bo) e), 0)), 0) into v_du
    from kt_tt_nn t where t.tg_ncc_id = v_tg and not t.da_xoa and coalesce(t.pb_tien_te, t.tien_te) = v_te;
  if v_du + 0.01 < v_con then raise exception 'Số dư giữ hộ bằng % chỉ còn % — chuyển thêm tiền cho trung gian trước', v_te, to_char(v_du, 'FM999G999G990D00'); end if;
  for r in select t.id, round(t.so_tien_nt * coalesce(t.pb_ty_gia, 1), 2) - coalesce((select sum((e->>'so_tien_nt')::numeric) from jsonb_array_elements(t.phan_bo) e), 0) du
             from kt_tt_nn t where t.tg_ncc_id = v_tg and not t.da_xoa and coalesce(t.pb_tien_te, t.tien_te) = v_te order by t.ngay, t.id for update loop
    exit when v_con <= 0;
    if r.du <= 0.004 then continue; end if;
    v_lay := least(r.du, v_con);
    update kt_tt_nn set phan_bo = coalesce(phan_bo, '[]') || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('ncc_id', v_ncc, 'ncc_ten', v_ten, 'po_id', v_po, 'so_tien_nt', v_lay,
        'ghi_chu', nullif(btrim(p_dong->>'ghi_chu'), ''), 'ngay', coalesce(nullif(p_dong->>'ngay', ''), to_char((now() at time zone 'Asia/Ho_Chi_Minh')::date, 'YYYY-MM-DD')), 'xn_boi', u.ho_ten))),
      sua_boi = u.ho_ten, sua_luc = now() where id = r.id;
    v_ds := v_ds || jsonb_build_array(jsonb_build_object('tt_id', r.id, 'so_tien', v_lay));
    v_con := round(v_con - v_lay, 2);
  end loop;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_tt_nn', v_tg, 'tra_ho', p_dong || jsonb_build_object('lay', v_ds));
  return v_ds;
end $$;

grant execute on function kt_tt_khoan_ds(text), kt_tt_lap(text, jsonb), kt_tt_nn_luu(text, jsonb), kt_tt_nn_tra_ho(text, jsonb) to anon, authenticated;

-- phiếu chi lập tại hồ sơ đối tác: số tiền = tổng các khoản đã chia → không cho sửa số tiền ở Thu chi (lệch công nợ từng khoản); muốn đổi thì từ chối / xoá phiếu rồi lập lại tại hồ sơ
create or replace function kt_tt_khoan_khoa_tien() returns trigger language plpgsql set search_path = public as $$
begin
  if new.so_tien is distinct from old.so_tien and exists (select 1 from kt_tt_khoan where chi_id = new.id)
     and abs(coalesce((select sum(vnd) from kt_tt_khoan where chi_id = new.id), 0) - coalesce(new.so_tien, 0)) > 1 then
    raise exception 'Phiếu chi lập tại hồ sơ đối tác (đã chia cho từng khoản công nợ) — không sửa số tiền ở đây. Từ chối / xoá phiếu rồi lập lại tại hồ sơ đối tác.';
  end if;
  return new;
end $$;
drop trigger if exists kt_tt_khoan_khoa_tien on kt_chi;
create trigger kt_tt_khoan_khoa_tien before update of so_tien on kt_chi for each row execute function kt_tt_khoan_khoa_tien();
