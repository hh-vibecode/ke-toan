-- NHẮC VIỆC trên phiếu (19/10/2026, anh: "khi note vào phiếu nợ chứng từ cần bổ sung thì có phần nhắc nhở, sau cần tìm vẫn lọc được";
-- "người tạo phiếu không có acc thì thấy thông báo sao"). Bình luận tick "Nhắc việc" = việc cần làm, mở tới khi có người bấm "Đã xong".
--  · người có tài khoản: chuông ngay + nhãn "Cần bổ sung" trên danh sách + mục lọc + mỗi sáng nhắc lại việc mở quá 2 ngày (lịch kt-nhac-viec)
--  · người gửi qua link công khai (không tài khoản): KHÔNG làm — anh: "người không có acc thì thôi, giám đốc với kế toán up thay". — Monsieur Claude
alter table public.kt_binh_luan add column if not exists nhac boolean not null default false;
alter table public.kt_binh_luan add column if not exists nhac_xong_luc timestamptz;
alter table public.kt_binh_luan add column if not exists nhac_xong_boi text;
create index if not exists kt_binh_luan_nhac_mo on public.kt_binh_luan (bang, dong_id) where nhac and nhac_xong_luc is null and not da_xoa;

-- số việc nhắc đang mở của 1 phiếu
create or replace function public.kt_nhac_mo(p_bang text, p_id bigint) returns int language sql stable set search_path = public as $$
  select count(*)::int from kt_binh_luan where bang = p_bang and dong_id = p_id and nhac and nhac_xong_luc is null and not da_xoa;
$$;
revoke all on function public.kt_nhac_mo(text, bigint) from public;

-- thêm bình luận: thêm tham số p_nhac
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_them_binh_luan'::regproc); n := length(d);
  d := replace(d, 'kt_them_binh_luan(p_phien text, p_bang text, p_id bigint, p_noi_dung text)', 'kt_them_binh_luan(p_phien text, p_bang text, p_id bigint, p_noi_dung text, p_nhac boolean DEFAULT false)');
  d := replace(d, $a$insert into kt_binh_luan (bang, dong_id, nguoi_id, nguoi, noi_dung) values (p_bang, p_id, u.id, u.ho_ten, left(trim(p_noi_dung), 2000)) returning id into v_id;$a$,
                  $a$insert into kt_binh_luan (bang, dong_id, nguoi_id, nguoi, noi_dung, nhac) values (p_bang, p_id, u.id, u.ho_ten, left(trim(p_noi_dung), 2000), coalesce(p_nhac, false)) returning id into v_id;$a$);
  d := replace(d, $a$'chi_binh_luan', 'Bình luận ' || v_so,$a$, $a$'chi_binh_luan', case when coalesce(p_nhac, false) then 'Cần bổ sung ' else 'Bình luận ' end || v_so,$a$);
  if length(d) - n < 60 then raise exception 'kt_them_binh_luan: khong thay du cho (%)', length(d) - n; end if;
  drop function public.kt_them_binh_luan(text, text, bigint, text);
  execute d;
end $$;
revoke all on function public.kt_them_binh_luan(text, text, bigint, text, boolean) from public;
grant execute on function public.kt_them_binh_luan(text, text, bigint, text, boolean) to anon;

-- đánh dấu xong / mở lại 1 việc nhắc (ai xem được phiếu là làm được)
create or replace function public.kt_xong_nhac(p_phien text, p_bl_id bigint, p_xong boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; b kt_binh_luan;
begin
  select * into b from kt_binh_luan where id = p_bl_id and not da_xoa and nhac;
  if b.id is null then raise exception 'Không tìm thấy việc nhắc'; end if;
  u := kt_chan_dong(p_phien, b.bang, array[b.dong_id], false);
  update kt_binh_luan set nhac_xong_luc = case when p_xong then now() end, nhac_xong_boi = case when p_xong then u.ho_ten end where id = p_bl_id;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || b.bang, b.dong_id, case when p_xong then 'nhac_xong' else 'nhac_mo_lai' end, jsonb_build_object('binh_luan_id', p_bl_id));
end $$;
revoke all on function public.kt_xong_nhac(text, bigint, boolean) from public;
grant execute on function public.kt_xong_nhac(text, bigint, boolean) to anon;

-- hoạt động: trả thêm cờ nhắc
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_hoat_dong'::regproc); n := length(d);
  d := replace(d, $a$'cua_toi', b.nguoi_id = u.id)$a$, $a$'cua_toi', b.nguoi_id = u.id, 'nhac', b.nhac, 'xong_luc', b.nhac_xong_luc, 'xong_boi', b.nhac_xong_boi)$a$);
  if length(d) = n then raise exception 'kt_hoat_dong: khong thay cho'; end if; execute d;
end $$;

-- danh sách phiếu: số việc nhắc đang mở
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_ds'::regproc); n := length(d);
  d := replace(d, $a$'nghi_loai', kt_nghi_loai(c), 'thieu_unc', kt_thieu_unc(c))$a$, $a$'nghi_loai', kt_nghi_loai(c), 'thieu_unc', kt_thieu_unc(c), 'nhac_mo', kt_nhac_mo('chi', c.id))$a$);
  d := replace(d, $a$where k.bang = 'thu' and k.dong_id = t.id and not k.da_xoa))$a$, $a$where k.bang = 'thu' and k.dong_id = t.id and not k.da_xoa), 'nhac_mo', kt_nhac_mo('thu', t.id))$a$);
  if length(d) - n < 60 then raise exception 'kt_ds: khong thay du cho (%)', length(d) - n; end if; execute d;
end $$;

-- phiếu công khai: chỉ sửa số file tối đa hiển thị cho khớp giới hạn 60 (supabase-schema-kt-60-file.sql)
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_xem_de_nghi'::regproc); n := length(d);
  if position('and p.so_file < 15)' in d) = 0 then raise exception 'kt_xem_de_nghi: khong thay cho'; end if;
  d := replace(d, 'and p.so_file < 15)', 'and p.so_file < 60)'); n := n + 1;
  execute d;
end $$;

-- mỗi sáng 8:00 (giờ VN): nhắc lại việc còn mở quá 2 ngày cho người ghi nhắc + kế toán
create or replace function public.kt_nhac_lai_hang_ngay() returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; v_ma constant jsonb := '{"chi":"PC","thu":"PT","dieu_chuyen":"DC","tam_ung":"TU","vay":"VAY"}';
begin
  for r in select * from kt_binh_luan where nhac and nhac_xong_luc is null and not da_xoa and tao_luc < now() - interval '2 days' loop
    perform kt_bao(array(select distinct x from unnest(array[r.nguoi_id] || kt_ai_ke_toan(0)) x where x is not null), 'Hệ thống', 'chi_binh_luan',
      'Còn cần bổ sung ' || (v_ma->>r.bang) || lpad(r.dong_id::text, 6, '0') || ' (' || (current_date - r.tao_luc::date) || ' ngày)', left(r.noi_dung, 160), r.bang, r.dong_id);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.kt_nhac_lai_hang_ngay() from public, anon;
select cron.unschedule('kt-nhac-viec') where exists (select 1 from cron.job where jobname = 'kt-nhac-viec');
select cron.schedule('kt-nhac-viec', '0 1 * * *', 'select public.kt_nhac_lai_hang_ngay()');
