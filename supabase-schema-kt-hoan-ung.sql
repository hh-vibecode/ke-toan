-- PHIẾU TRANG CHỦ 3 LOẠI: ĐỀ NGHỊ THANH TOÁN / TẠM ỨNG / HOÀN ỨNG (16/10/2026, anh Hải) — Monsieur Claude
-- Hoàn ứng = người đã ứng tiền nộp QUYẾT TOÁN (chi thực tế + chứng từ + đơn vị chịu chi phí + hoá đơn xuất về). KHÔNG chi tiền lần nữa:
--   kế toán bấm Quyết toán ở Tạm ứng & hoàn ứng → chọn khoản tạm ứng + loại chi → app ghi 1 lần hoàn ứng bằng chứng từ (tối đa số còn phải hoàn),
--   phiếu sang trạng thái 'quyet_toan' (vào CHI PHÍ hạch toán, không vào dòng tiền), báo chênh lệch: dương = công ty trả thêm (tạo phiếu đề nghị riêng),
--   âm = người ứng nộp lại tiền (ghi hoàn bằng tiền + phiếu thu như trước).
alter table public.kt_chi add column if not exists loai_dn text not null default 'thanh_toan',
  add column if not exists tu_da_ung numeric, add column if not exists tam_ung_id bigint references public.kt_tam_ung(id);
alter table public.kt_chi drop constraint if exists kt_chi_loai_dn_check;
alter table public.kt_chi add constraint kt_chi_loai_dn_check check (loai_dn in ('thanh_toan', 'tam_ung', 'hoan_ung'));
update public.kt_chi set loai_dn = 'tam_ung' where la_tam_ung and loai_dn <> 'tam_ung';
alter table public.kt_chi drop constraint if exists kt_chi_trang_thai_check;
alter table public.kt_chi add constraint kt_chi_trang_thai_check
  check (trang_thai in ('cho_duyet','cho_gd','tu_choi','cho_tt','da_tt','tu_choi_tt','quyet_toan'));

-- giữ loai_dn khớp ô tạm ứng; phiếu hoàn ứng không được đi luồng chi tiền
create or replace function public.kt_chi_loai_dn_tg() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.la_tam_ung then new.loai_dn := 'tam_ung';
  elsif new.loai_dn = 'tam_ung' then new.loai_dn := 'thanh_toan'; end if;
  if new.loai_dn = 'hoan_ung' and new.trang_thai in ('cho_gd', 'cho_tt', 'da_tt')
     and (tg_op = 'INSERT' or new.trang_thai is distinct from old.trang_thai) then
    raise exception 'Phiếu hoàn ứng không chi tiền — quyết toán ở mục Tạm ứng & hoàn ứng (nút Quyết toán)';
  end if;
  return new;
end $$;
drop trigger if exists kt_chi_loai_dn on public.kt_chi;
create trigger kt_chi_loai_dn before insert or update of la_tam_ung, loai_dn, trang_thai on public.kt_chi
  for each row execute function public.kt_chi_loai_dn_tg();

-- chi phí hạch toán: thêm phiếu hoàn ứng đã quyết toán
create or replace view public.kt_v_chi_ht as
  select c.id chi_id, c.loai_id,
         coalesce(pt->>'thang', c.thang_ht, to_char(coalesce(c.ngay_su_dung, c.ngay_de_nghi, c.ngay_tt), 'YYYY-MM')) thang,
         (pb->>'don_vi_id')::int don_vi_id,
         coalesce((pt->>'so_tien')::numeric, c.so_tien) * coalesce((pb->>'so_tien')::numeric / nullif(c.so_tien, 0), 1) tien
    from kt_chi c
    left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' and jsonb_array_length(c.phan_bo_thang) > 0 then c.phan_bo_thang end) pt on true
    left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' and jsonb_array_length(c.phan_bo) > 0 then c.phan_bo end) pb on true
   where not c.da_xoa and c.trang_thai in ('cho_tt', 'da_tt', 'quyet_toan') and not c.la_tam_ung;
revoke all on public.kt_v_chi_ht from anon, authenticated;

-- form công khai: loai_dn + số tiền đã tạm ứng (vá trên bản đang chạy)
do $x$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_gui_de_nghi'::regproc);
  n := length(d); d := replace(d, $a$v_tu boolean := coalesce(p_dong->>'la_tam_ung', '') = 'true';$a$,
    $a$v_loai text := case when p_dong->>'loai_dn' in ('tam_ung', 'hoan_ung') then p_dong->>'loai_dn' when coalesce(p_dong->>'la_tam_ung', '') = 'true' then 'tam_ung' else 'thanh_toan' end;
  v_tu boolean := v_loai = 'tam_ung'; v_du numeric;$a$);
  if length(d) = n then raise exception 'kt_gui_de_nghi: khong thay v_tu'; end if;
  n := length(d); d := replace(d, $a$  if length(v_th) < 2 or length(v_th) > 150 then raise exception 'Nhập tên người / đơn vị thụ hưởng'; end if;$a$,
    $a$  if v_loai = 'hoan_ung' and length(v_th) < 2 then v_th := v_nguoi; end if;   -- hoàn ứng: không nhận tiền qua phiếu này
  if length(v_th) < 2 or length(v_th) > 150 then raise exception 'Nhập tên người / đơn vị thụ hưởng'; end if;$a$);
  if length(d) = n then raise exception 'kt_gui_de_nghi: khong thay thu huong'; end if;
  n := length(d); d := replace(d, $a$v_ck := coalesce(p_dong->>'hinh_thuc', 'ck') <> 'tien_mat';$a$,
    $a$v_ck := coalesce(p_dong->>'hinh_thuc', 'ck') <> 'tien_mat' and v_loai <> 'hoan_ung';$a$);
  if length(d) = n then raise exception 'kt_gui_de_nghi: khong thay v_ck'; end if;
  n := length(d); d := replace(d, $a$  if length(coalesce(v_gc, '')) > 500 then$a$,
    $a$  if v_loai = 'hoan_ung' then
    begin v_du := (p_dong->>'tu_da_ung')::numeric; exception when others then v_du := null; end;
    if v_du is null or v_du <= 0 or v_du <> round(v_du) then raise exception 'Nhập số tiền đã tạm ứng'; end if;
  end if;
  if length(coalesce(v_gc, '')) > 500 then$a$);
  if length(d) = n then raise exception 'kt_gui_de_nghi: khong thay ghi chu'; end if;
  n := length(d); d := replace(d, $a$tao_boi, hd_ve, la_tam_ung)$a$, $a$tao_boi, hd_ve, la_tam_ung, loai_dn, tu_da_ung)$a$);
  if length(d) = n then raise exception 'kt_gui_de_nghi: khong thay cot insert'; end if;
  n := length(d); d := replace(d, $a$v_hdve, v_tu)$a$, $a$v_hdve, v_tu, v_loai, v_du)$a$);
  if length(d) = n then raise exception 'kt_gui_de_nghi: khong thay values'; end if;
  n := length(d); d := replace(d, $a$case when v_tu then 'Phiếu đề nghị TẠM ỨNG mới — chờ kế toán kiểm' else$a$,
    $a$case when v_tu then 'Phiếu đề nghị TẠM ỨNG mới — chờ kế toán kiểm' when v_loai = 'hoan_ung' then 'Phiếu HOÀN ỨNG (quyết toán tạm ứng) mới — chờ kế toán quyết toán' else$a$);
  if length(d) = n then raise exception 'kt_gui_de_nghi: khong thay thong bao'; end if;
  execute d;
end $x$;

-- phiếu hoàn ứng chờ quyết toán + khoản tạm ứng gợi ý (cùng tên người, còn phải hoàn)
create or replace function public.kt_ds_hoan_ung_cho(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'tam_ung');
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'ngay', c.ngay_de_nghi, 'nguoi', c.nguoi_de_nghi, 'bo_phan_id', c.bo_phan_id, 'noi_dung', c.noi_dung,
      'so_tien', c.so_tien, 'tu_da_ung', c.tu_da_ung, 'hd_ve', c.hd_ve, 'co_hd_do', c.co_hd_do, 'loai_id', c.loai_id,
      'goi_y', (select coalesce(jsonb_agg(t.id order by t.ngay), '[]') from kt_tam_ung t where not t.da_xoa
                  and lower(btrim(t.nguoi_nhan)) = lower(btrim(c.nguoi_de_nghi))
                  and t.so_tien > coalesce((select sum(h.so_tien) from kt_tam_ung_hoan h where h.tam_ung_id = t.id and not h.da_xoa), 0)))
      order by c.ngay_de_nghi, c.id)
    from kt_chi c where not c.da_xoa and c.loai_dn = 'hoan_ung' and c.trang_thai = 'cho_duyet'), '[]');
end $$;

-- Quyết toán: ghi hoàn ứng bằng chứng từ (tối đa số còn phải hoàn), phiếu → 'quyet_toan' (vào chi phí), trả chênh lệch
create or replace function public.kt_quyet_toan_hoan_ung(p_phien text, p_chi_id bigint, p_tam_ung_id bigint, p_loai_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; v_con numeric; v_hoan numeric;
begin
  u := kt_chan(p_phien, 'tam_ung', true);
  select * into c from kt_chi where id = p_chi_id and not da_xoa for update;
  if c.id is null or c.loai_dn <> 'hoan_ung' then raise exception 'Không phải phiếu hoàn ứng'; end if;
  if c.trang_thai <> 'cho_duyet' then raise exception 'Phiếu này đã xử lý'; end if;
  if p_loai_id is null or not exists (select 1 from kt_loai where id = p_loai_id and nhom = 'chi') then raise exception 'Chọn loại chi cho chi phí quyết toán'; end if;
  select t.so_tien - coalesce((select sum(h.so_tien) from kt_tam_ung_hoan h where h.tam_ung_id = t.id and not h.da_xoa), 0)
    into v_con from kt_tam_ung t where t.id = p_tam_ung_id and not t.da_xoa for update;
  if v_con is null then raise exception 'Không thấy khoản tạm ứng'; end if;
  if v_con <= 0 then raise exception 'Khoản tạm ứng này đã hoàn đủ'; end if;
  v_hoan := least(c.so_tien, v_con);
  insert into kt_tam_ung_hoan (tam_ung_id, ngay, hinh_thuc, so_tien, ghi_chu, tao_boi)
  values (p_tam_ung_id, (now() at time zone 'Asia/Ho_Chi_Minh')::date, 'chung_tu', v_hoan, 'Quyết toán theo phiếu hoàn ứng #' || c.id, u.ho_ten);
  update kt_chi set trang_thai = 'quyet_toan', tam_ung_id = p_tam_ung_id, loai_id = p_loai_id, nguoi_duyet = u.ho_ten, duyet_luc = now() where id = c.id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', c.id, 'quyet_toan', jsonb_build_object('tam_ung_id', p_tam_ung_id, 'hoan', v_hoan, 'loai_id', p_loai_id));
  -- chenh > 0: chi thực tế vượt số còn phải hoàn → công ty trả thêm; chenh < 0: người ứng còn phải nộp lại
  return jsonb_build_object('hoan', v_hoan, 'chenh', c.so_tien - v_con);
end $$;
do $$ declare f text; begin
  foreach f in array array['kt_ds_hoan_ung_cho(text)','kt_quyet_toan_hoan_ung(text, bigint, bigint, integer)'] loop
    execute format('revoke execute on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop; end $$;
