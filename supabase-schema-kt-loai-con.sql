-- 22/10/2026 (anh): "các loại chi dropdown chỉ lấy mục cha; cuối giờ mỗi ngày tự phân loại thành mục con theo mục cha + nội dung phiếu để làm P&L;
-- mục con chỉ hiện trong phiếu chi tiết, tự động, không cho sửa; khó quá không phân biệt nổi thì để giám đốc xử lý — hạng mục Cần chú ý: Loại chi KXĐ". — Monsieur Claude
alter table kt_chi add column if not exists loai_con_id int references kt_loai(id), add column if not exists loai_con_kxd boolean not null default false,
  add column if not exists loai_con_boi text, add column if not exists loai_con_luc timestamptz;

-- kt_bo_dau(text) đã có sẵn (bỏ dấu + chữ thường) — dùng lại
-- mục cha (gốc) của 1 loại
create or replace function public.kt_loai_goc(p int) returns int language sql stable set search_path = public as $f$
  with recursive t as (select id, cha_id from kt_loai where id = p union all select l.id, l.cha_id from kt_loai l join t on l.id = t.cha_id)
  select id from t where cha_id is null limit 1 $f$;
create or replace function public.kt_loai_thuoc(p_con int, p_cha int) returns boolean language sql stable set search_path = public as $f$
  with recursive t as (select id, cha_id from kt_loai where id = p_con union all select l.id, l.cha_id from kt_loai l join t on l.id = t.cha_id)
  select exists (select 1 from t where id = p_cha) $f$;

-- luật phân loại mục con (từ khoá trên nội dung + người nhận, đã bỏ dấu, chữ thường); thứ tự nhỏ xét trước
create table if not exists kt_luat_loai_con (id serial primary key, loai_con_id int not null references kt_loai(id), mau text not null, thu_tu int not null default 100, hoat_dong boolean not null default true);
alter table kt_luat_loai_con enable row level security; revoke all on kt_luat_loai_con from anon, authenticated;
insert into kt_luat_loai_con (loai_con_id, mau, thu_tu) select * from (values
  (87,$q$\yseo\y$q$,10),
  (88,$q$thiet ke|design$q$,20),
  (89,$q$quay|dung video|edit video|video$q$,30),
  (90,$q$chup anh|chup hinh|photo$q$,40),
  (91,$q$co van hinh anh$q$,50),
  (92,$q$quang cao|\yads\y|facebook|tiktok|\ymeta\y|google ads|nap tien (fb|tk quang cao)|chay qc|\yqc\y$q$,60),
  (93,$q$pancake|phan mem (ho tro )?mkt|botcake|harasocial|haravan|zalo oa$q$,70),
  (86,$q$marketing|mkt|kol|koc|livestream|booking|seeding|in an|bang ron|banner|standee|to roi|catalog$q$,80),
  (77,$q$phan mem|kiotviet|kiot viet|misa|domain|ten mien|hosting|server|google workspace|gmail|icloud|chatgpt|claude|canva|license|chat ?gpt|gia han pm$q$,90),
  (78,$q$dich vu ke toan|bao cao thue|kiem toan|phap ly|luat su|cong chung|thu tuc|dkkd|dang ky kinh doanh|dia diem kinh doanh$q$,100),
  (83,$q$dao tao|khoa hoc|hoc phi|training|top ?cv|tuyen dung|vieclam|viec lam$q$,110),
  (81,$q$team building|sinh nhat|lien hoan|qua tet|qua trung thu|teambuilding|du lich$q$,120),
  (108,$q$phi ngan hang|phi chuyen tien|phi chuyen khoan|phi giao dich|phi quan ly tk|qltk|sms ?banking|bsms|phi dich vu sms|phi rut tien|phi nop tien|thu phi$q$,130),
  (107,$q$van phong pham|vpp|giay in|but bi|muc in|do muc$q$,140),
  (110,$q$hong huy|hang hong|vo hong|huy hang$q$,150),
  (96,$q$tien dien(?! thoai)$q$,160),
  (97,$q$tien nuoc|nuoc sinh hoat$q$,170),
  (98,$q$dien thoai|cuoc vien thong|sim|di dong$q$,180),
  (99,$q$internet|wifi|cap quang|\yfpt\y|\yvnpt\y|viettel internet$q$,190),
  (70,$q$thue kho|kho tong$q$,200),
  (95,$q$thue (cua hang|mat bang|nha)|tien nha|mat bang$q$,210),
  (101,$q$bao bi|bang dinh|thung carton|thung giay|hop|xop|mang (bong|pe)|tui (nilon|zip)|day buoc$q$,220),
  (102,$q$van chuyen|ship|giao hang|\ycod\y|ghn|ghtk|viettel ?post|nhat tin|j&t|jt express|ninja|xe tai|xe om|grab|cuoc xe|boc xep|chanh xe$q$,230),
  (105,$q$khau hao|dieu hoa|cay nong lanh|may tinh moi|mua may|tam san|ban ghe|lap dat$q$,240),
  (104,$q$sua chua|bao hanh|bao tri|thay the|sua (may|xe|dien|nuoc|cua)$q$,250),
  (66,$q$hoa hong|thuong doanh so|thuong ban hang$q$,260),
  (74,$q$luong (bgd|giam doc|ban giam doc)$q$,270),
  (75,$q$luong (ke toan|van phong|backoffice|hanh chinh|nhan su)$q$,280),
  (69,$q$luong kho|nhan vien kho$q$,290),
  (109,$q$quy ngoai|quy kho|than tai$q$,300),
  (65,$q$luong|bhxh|bao hiem xa hoi|thuong|phu cap|tang ca$q$,310),
  (76,$q$van phong|hanh chinh|nuoc uong|ve sinh|tiep khach|cong tac|xang|di lai|ve may bay|khach san|luu tru$q$,320)) v(a, b, c) where not exists (select 1 from kt_luat_loai_con);

-- mọi đường ghi loại chi (app, đồng bộ sheet, luật) quy về mục cha; ghi mục con thì giữ làm loai_con_id; đổi mục cha thì chờ phân loại lại
create or replace function public.kt_chi_loai_cha() returns trigger language plpgsql set search_path = public as $f$
declare g int;
begin
  if new.loai_id is null then new.loai_con_id := null; new.loai_con_kxd := false; return new; end if;
  g := kt_loai_goc(new.loai_id);
  if g is not null and g <> new.loai_id then
    new.loai_con_id := new.loai_id; new.loai_id := g; new.loai_con_kxd := false; new.loai_con_boi := coalesce(new.loai_con_boi, 'Ghi trực tiếp'); new.loai_con_luc := now();
  elsif tg_op = 'UPDATE' and new.loai_id is distinct from old.loai_id then
    new.loai_con_id := null; new.loai_con_kxd := false; new.loai_con_boi := null; new.loai_con_luc := null;
  end if;
  return new;
end $f$;
drop trigger if exists kt_chi_loai_cha on kt_chi;
create trigger kt_chi_loai_cha before insert or update of loai_id on kt_chi for each row execute function kt_chi_loai_cha();

-- phân loại mục con (chạy 23:00 mỗi ngày + chạy tay): mục cha không có con → chính nó; khớp luật → mục con; không khớp → KXĐ (giám đốc chọn)
create or replace function public.kt_phan_loai_con() returns jsonb language plpgsql security definer set search_path = public as $f$
declare c record; con int; n_khop int := 0; n_kxd int := 0;
begin
  for c in select x.id, x.loai_id, kt_bo_dau(x.noi_dung || ' ' || coalesce(x.thu_huong_ten, '')) t from kt_chi x
            where not x.da_xoa and x.loai_id is not null and x.loai_con_id is null and not x.loai_con_kxd
              and exists (select 1 from kt_loai l where l.id = x.loai_id and l.cha_id is null and l.ma is not null) loop
    if not exists (select 1 from kt_loai l where l.cha_id = c.loai_id) then con := c.loai_id;
    else select r.loai_con_id into con from kt_luat_loai_con r where r.hoat_dong and kt_loai_thuoc(r.loai_con_id, c.loai_id) and c.t ~ r.mau order by r.thu_tu, r.id limit 1; end if;
    if con is not null then update kt_chi set loai_con_id = con, loai_con_boi = 'Hệ thống', loai_con_luc = now() where id = c.id; n_khop := n_khop + 1;
    else update kt_chi set loai_con_kxd = true, loai_con_boi = 'Hệ thống', loai_con_luc = now() where id = c.id; n_kxd := n_kxd + 1; end if;
  end loop;
  return jsonb_build_object('phan_loai', n_khop, 'kxd', n_kxd);
end $f$;
revoke all on function public.kt_phan_loai_con() from public, anon;

-- giám đốc chọn mục con cho phiếu KXĐ
create or replace function public.kt_dat_loai_con(p_phien text, p_id bigint, p_con int) returns void language plpgsql security definer set search_path = public as $f$
declare u kt_nguoi_dung; c kt_chi;
begin
  u := kt_chan(p_phien);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  if not kt_co_quyen(u, 'chi_gd') then raise exception 'Chỉ giám đốc chọn mục con cho phiếu loại chi KXĐ' using errcode = '42501'; end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu chi'; end if;
  if p_con is null or not kt_loai_thuoc(p_con, c.loai_id) or p_con = c.loai_id then raise exception 'Mục con không thuộc mục cha của phiếu'; end if;
  update kt_chi set loai_con_id = p_con, loai_con_kxd = false, loai_con_boi = u.ho_ten, loai_con_luc = now() where id = p_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'dat_loai_con', jsonb_build_object('loai_con_id', p_con));
end $f$;
revoke all on function public.kt_dat_loai_con(text, bigint, int) from public; grant execute on function public.kt_dat_loai_con(text, bigint, int) to anon;

create or replace view public.kt_v_chi_ht as SELECT c.id AS chi_id,
    COALESCE(c.loai_con_id, c.loai_id) AS loai_id,
    COALESCE((pt.value ->> 'thang'::text), c.thang_ht, to_char((COALESCE(c.ngay_su_dung, c.ngay_de_nghi, c.ngay_tt))::timestamp with time zone, 'YYYY-MM'::text)) AS thang,
    ((pb.value ->> 'don_vi_id'::text))::integer AS don_vi_id,
    (COALESCE(((pt.value ->> 'so_tien'::text))::numeric, c.so_tien) * COALESCE((((pb.value ->> 'so_tien'::text))::numeric / NULLIF(c.so_tien, (0)::numeric)), (1)::numeric)) AS tien
   FROM ((kt_chi c
     LEFT JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN ((jsonb_typeof(c.phan_bo_thang) = 'array'::text) AND (jsonb_array_length(c.phan_bo_thang) > 0)) THEN c.phan_bo_thang
            ELSE NULL::jsonb
        END) pt(value) ON (true))
     LEFT JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN ((jsonb_typeof(c.phan_bo) = 'array'::text) AND (jsonb_array_length(c.phan_bo) > 0)) THEN c.phan_bo
            ELSE NULL::jsonb
        END) pb(value) ON (true))
  WHERE ((NOT c.da_xoa) AND (c.trang_thai = ANY (ARRAY['cho_tt'::text, 'da_tt'::text])) AND (NOT c.la_tam_ung) AND (NOT c.khong_hach_toan) AND (c.loai_dn = 'thanh_toan'::text));

CREATE OR REPLACE FUNCTION public.kt_pl_ct(p_phien text, p_loai integer[], p_tu date, p_den date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_t0 text := to_char(p_tu, 'YYYY-MM'); v_t1 text := to_char(p_den, 'YYYY-MM');
begin
  perform kt_chan(p_phien, 'pl');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'ngay', ngay_tt, 'so', so, 'nd', noi_dung, 'th', thu_huong_ten, 'loai', loai_id,
           'dv', dv, 'tien', tien) order by ngay_tt desc, id desc), '[]') from (
    select c.id, c.ngay_tt, coalesce(c.kiot_ma, 'PC' || lpad(c.id::text, 6, '0')) so, c.noi_dung, c.thu_huong_ten, coalesce(c.loai_con_id, c.loai_id) loai_id, (pb->>'don_vi_id')::int dv,
           round(sum(coalesce((pt->>'so_tien')::numeric, c.so_tien) * coalesce((pb->>'so_tien')::numeric / nullif(c.so_tien, 0), 1))) tien
      from kt_chi c
      left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo_thang) = 'array' and jsonb_array_length(c.phan_bo_thang) > 0 then c.phan_bo_thang end) pt on true
      left join lateral jsonb_array_elements(case when jsonb_typeof(c.phan_bo) = 'array' and jsonb_array_length(c.phan_bo) > 0 then c.phan_bo end) pb on true
     where not c.da_xoa and not c.khong_hach_toan and c.trang_thai = 'da_tt' and coalesce(c.loai_con_id, c.loai_id) = any(p_loai)
       and (case when pt is null then c.ngay_tt between p_tu and p_den else pt->>'thang' between v_t0 and v_t1 end)
     group by 1, 2, 3, 4, 5, 6, 7 limit 2000) x);
end $function$;

CREATE OR REPLACE FUNCTION public.kt_nghi_loai(c kt_chi)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('luat', r.ten, 'loai_id', r.loai_id, 'loai', l.ten)
    from kt_luat_loai_chi r join kt_loai l on l.id = r.loai_id, kt_cai_dat s
   where s.khoa = 'ngay_ap_dung_app' and s.gia_tri is not null and r.hoat_dong
     and not c.da_xoa and not c.bo_qua_loai and c.loai_id is not null and kt_loai_goc(c.loai_id) <> kt_loai_goc(r.loai_id)
     and coalesce(c.ngay_tt, c.ngay_de_nghi) >= s.gia_tri::date and c.noi_dung ~* r.mau
     and r.thu_tu = (select min(r2.thu_tu) from kt_luat_loai_chi r2 where r2.hoat_dong and c.noi_dung ~* r2.mau)
   limit 1;
$function$;

-- chuyển dữ liệu: loại đang là mục con → loai_id = mục cha, loai_con_id = mục con (trigger làm); gán từ khoá yếu (thap) → phân loại lại
update kt_chi set loai_id = loai_id where loai_id in (select id from kt_loai where cha_id is not null);
update kt_chi set loai_con_id = null, loai_con_boi = null, loai_con_luc = null where gan_loai_tu_dong = 'thap';
update kt_chi set loai_con_boi = 'Hệ thống' where loai_con_id is not null and gan_loai_tu_dong = 'vua';
update kt_chi set loai_con_boi = 'Kế toán (đã soát)' where loai_con_id is not null and gan_loai_tu_dong is null and loai_con_boi = 'Ghi trực tiếp';
select kt_phan_loai_con();
select cron.schedule('kt-phan-loai-con', '0 */4 * * *', 'select public.kt_phan_loai_con()');   -- 22/10 anh: 4 giờ / lần (trước 23:00 hằng ngày)
