-- 23/10/2026 (anh): "từ chối cho vào thẻ KXĐ làm gì, đã từ chối là coi như bỏ đi không tính gì hết" → bước tự phân loại mục con bỏ qua phiếu từ chối; gỡ KXĐ phiếu đã từ chối. — Monsieur Claude
CREATE OR REPLACE FUNCTION public.kt_phan_loai_con()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c record; con int; n_khop int := 0; n_kxd int := 0;
begin
  for c in select x.id, x.loai_id, kt_bo_dau(x.noi_dung || ' ' || coalesce(x.thu_huong_ten, '')) t from kt_chi x
            where not x.da_xoa and x.loai_id is not null and x.loai_con_id is null and not x.loai_con_kxd and x.trang_thai not in ('tu_choi', 'tu_choi_tt')
              and exists (select 1 from kt_loai l where l.id = x.loai_id and l.cha_id is null and l.ma is not null) loop
    if not exists (select 1 from kt_loai l where l.cha_id = c.loai_id) then con := c.loai_id;
    else select r.loai_con_id into con from kt_luat_loai_con r where r.hoat_dong and kt_loai_thuoc(r.loai_con_id, c.loai_id) and c.t ~ r.mau order by r.thu_tu, r.id limit 1; end if;
    if con is not null then update kt_chi set loai_con_id = con, loai_con_boi = 'Hệ thống', loai_con_luc = now() where id = c.id; n_khop := n_khop + 1;
    else update kt_chi set loai_con_kxd = true, loai_con_boi = 'Hệ thống', loai_con_luc = now() where id = c.id; n_kxd := n_kxd + 1; end if;
  end loop;
  return jsonb_build_object('phan_loai', n_khop, 'kxd', n_kxd);
end $function$;
update kt_chi set loai_con_kxd = false where loai_con_kxd and trang_thai in ('tu_choi', 'tu_choi_tt');
