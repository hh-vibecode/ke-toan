-- TẠM ỨNG & HOÀN ỨNG — làm lại theo anh 16/10/2026 tối — Monsieur Claude
-- Anh: "tạm ứng hoàn ứng dồn vào 1 … chỉ khi người hoàn ứng hoàn ứng lại và được xác nhận tiền về lại thì mới clear,
--       còn không vẫn dừng ở đã tạm ứng chưa clear phiếu, cần theo dõi".
--  · Trang chủ: 2 lựa chọn Đề nghị thanh toán | Tạm ứng & hoàn ứng (bên trong: Xin tạm ứng / Hoàn ứng = TRẢ LẠI TIỀN đã ứng).
--  · Phiếu hoàn ứng = báo đã trả lại tiền (số tiền, ngày, ảnh chuyển khoản) — không phải chi phí, không chi tiền.
--  · Kế toán "Xác nhận tiền về" (kt_xac_nhan_hoan_ung): chọn khoản tạm ứng + tài khoản nhận → tạo PHIẾU THU (loại "Thu hoàn ứng", vào dòng tiền)
--    + 1 lần hoàn bằng tiền gắn phiếu thu → khoản tạm ứng chỉ CLEAR khi tổng tiền đã về = số đã ứng. Thay "quyết toán chứng từ" (kt_quyet_toan_hoan_ung — bỏ).
create or replace view public.kt_v_chi_ht as
  select c.id chi_id, c.loai_id,
         coalesce(pt->>'thang', c.thang_ht, to_char(coalesce(c.ngay_su_dung, c.ngay_de_nghi, c.ngay_tt), 'YYYY-MM')) thang,
         (pb->>'don_vi_id')::int don_vi_id,
         coalesce((pt->>'so_tien')::numeric, c.so_tien) * coalesce((pb->>'so_tien')::numeric / nullif(c.so_tien, 0), 1) tien
    from kt_chi c
    left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' and jsonb_array_length(c.phan_bo_thang) > 0 then c.phan_bo_thang end) pt on true
    left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' and jsonb_array_length(c.phan_bo) > 0 then c.phan_bo end) pb on true
   where not c.da_xoa and c.trang_thai in ('cho_tt', 'da_tt') and not c.la_tam_ung and c.loai_dn = 'thanh_toan';
revoke all on public.kt_v_chi_ht from anon, authenticated;

drop function if exists public.kt_quyet_toan_hoan_ung(text, bigint, bigint, integer);
insert into kt_loai (nhom, ten, nhom_bc, thu_tu) select 'thu', 'Thu hoàn ứng', (select nhom_bc from kt_loai where nhom = 'thu' and ten = 'Thu khác'), 90
 where not exists (select 1 from kt_loai where nhom = 'thu' and ten = 'Thu hoàn ứng');

do $x$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_gui_de_nghi'::regproc);
  n := length(d); d := replace(d, $a$  if v_tu then p_dong := p_dong || jsonb_build_object('co_hd_do'$a$, $a$  if v_tu or v_loai = 'hoan_ung' then p_dong := p_dong || jsonb_build_object('co_hd_do'$a$);
  if length(d) = n then raise exception 'kt_gui_de_nghi: khong thay co_hd_do'; end if;
  n := length(d); d := replace(d, $a$  if not v_tu and coalesce(v_hdve, '') not in$a$, $a$  if v_loai = 'thanh_toan' and coalesce(v_hdve, '') not in$a$);
  if length(d) = n then raise exception 'kt_gui_de_nghi: khong thay hd_ve'; end if;
  n := length(d); d := replace(d, $a$(jsonb_array_length(v_pb) = 0 and not v_tu)$a$, $a$(jsonb_array_length(v_pb) = 0 and v_loai = 'thanh_toan')$a$);
  if length(d) = n then raise exception 'kt_gui_de_nghi: khong thay phan_bo'; end if;
  n := length(d); d := replace(d, $a$if v_du is null or v_du <= 0 or v_du <> round(v_du) then raise exception 'Nhập số tiền đã tạm ứng'; end if;$a$,
    $a$if v_du is not null and (v_du <= 0 or v_du <> round(v_du)) then v_du := null; end if;   -- hoàn ứng: số đã ứng chỉ để kế toán dò, không bắt buộc$a$);
  if length(d) = n then raise exception 'kt_gui_de_nghi: khong thay v_du'; end if;
  n := length(d); d := replace(d, $a$'Phiếu HOÀN ỨNG (quyết toán tạm ứng) mới — chờ kế toán quyết toán'$a$, $a$'Phiếu HOÀN ỨNG (trả lại tiền tạm ứng) — chờ kế toán xác nhận tiền về'$a$);
  if length(d) = n then raise exception 'kt_gui_de_nghi: khong thay thong bao'; end if;
  execute d;
end $x$;

-- Xác nhận tiền hoàn ứng đã về: phiếu thu + hoàn bằng tiền; p_chi_id = phiếu hoàn ứng gửi từ trang chủ (nếu có) → 'quyet_toan' (= đã xác nhận)
create or replace function public.kt_xac_nhan_hoan_ung(p_phien text, p_tam_ung_id bigint, p_so_tien numeric, p_tai_khoan_id int, p_ngay date, p_chi_id bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; t kt_tam_ung; v_con numeric; v_thu bigint; c kt_chi;
begin
  u := kt_chan(p_phien, 'tam_ung', true);
  select * into t from kt_tam_ung where id = p_tam_ung_id and not da_xoa for update;
  if t.id is null then raise exception 'Không thấy khoản tạm ứng'; end if;
  v_con := t.so_tien - coalesce((select sum(so_tien) from kt_tam_ung_hoan where tam_ung_id = t.id and not da_xoa), 0);
  if v_con <= 0 then raise exception 'Khoản tạm ứng này đã clear'; end if;
  if p_so_tien is null or p_so_tien <= 0 or p_so_tien <> round(p_so_tien) then raise exception 'Số tiền không hợp lệ'; end if;
  if p_so_tien > v_con then raise exception 'Số tiền về (%) lớn hơn số còn phải hoàn (%)', replace(to_char(p_so_tien, 'FM999G999G999G999'), ',', '.'), replace(to_char(v_con, 'FM999G999G999G999'), ',', '.'); end if;
  if p_ngay is null then raise exception 'Nhập ngày tiền về'; end if;
  if not exists (select 1 from kt_tai_khoan where id = p_tai_khoan_id and hoat_dong and loai <> 'vay') then raise exception 'Chọn tài khoản nhận tiền'; end if;
  if p_chi_id is not null then
    select * into c from kt_chi where id = p_chi_id and not da_xoa for update;
    if c.id is null or c.loai_dn <> 'hoan_ung' or c.trang_thai <> 'cho_duyet' then raise exception 'Phiếu hoàn ứng không hợp lệ hoặc đã xử lý'; end if;
  end if;
  insert into kt_thu (ngay, noi_dung, so_tien, tai_khoan_id, loai_id, ghi_chu, trang_thai, nguon, tao_boi)
  values (p_ngay, left('Hoàn ứng: ' || t.nguoi_nhan || coalesce(' — ' || t.ly_do, ''), 500), p_so_tien, p_tai_khoan_id,
          (select id from kt_loai where nhom = 'thu' and ten = 'Thu hoàn ứng'),
          'Khoản tạm ứng #' || t.id || coalesce(' · phiếu hoàn ứng #' || p_chi_id, ''), 'da_duyet', 'tay', u.ho_ten)
  returning id into v_thu;
  insert into kt_tam_ung_hoan (tam_ung_id, ngay, hinh_thuc, so_tien, thu_id, ghi_chu, tao_boi)
  values (t.id, p_ngay, 'tien', p_so_tien, v_thu, 'Đã xác nhận tiền về' || coalesce(' · phiếu hoàn ứng #' || p_chi_id, ''), u.ho_ten);
  if p_chi_id is not null then
    update kt_chi set trang_thai = 'quyet_toan', tam_ung_id = t.id, nguoi_duyet = u.ho_ten, duyet_luc = now() where id = p_chi_id;
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_tam_ung', t.id, 'hoan_tien', jsonb_build_object('so_tien', p_so_tien, 'thu_id', v_thu, 'chi_id', p_chi_id));
  return jsonb_build_object('thu_id', v_thu, 'con_lai', v_con - p_so_tien);
end $$;
revoke execute on function public.kt_xac_nhan_hoan_ung(text, bigint, numeric, integer, date, bigint) from public;
grant execute on function public.kt_xac_nhan_hoan_ung(text, bigint, numeric, integer, date, bigint) to anon, authenticated;
