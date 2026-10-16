-- XEM NHƯ (view as) — 16/10/2026, anh Hải: "làm cái view as như bên MKT app, để t xem view các tài khoản chuẩn chưa" — Monsieur Claude
-- Supreme bấm "Xem như" 1 tài khoản → app mở PHIÊN THẬT của tài khoản đó (đúng menu, nút, dữ liệu theo quyền của họ) nhưng CHỈ XEM:
-- phiên có cờ chi_xem → kt_chan bật kt.chi_xem cho giao dịch → trigger trên MỌI bảng kt_* chặn thêm / sửa / xoá. Phiên hết hạn sau 2 giờ.
-- Bảng kt_* tạo SAU file này phải gắn trigger kt_tg_chi_xem (vòng lặp cuối file chạy lại được).
alter table public.kt_phien add column if not exists chi_xem boolean not null default false;
alter table public.kt_phien add column if not exists xem_boi int;

create or replace function public.kt_tg_chi_xem() returns trigger language plpgsql as $$
begin
  if current_setting('kt.chi_xem', true) = '1' then
    raise exception 'Đang ở chế độ Xem như — chỉ xem, không sửa được (thoát Xem như để làm việc)' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;

-- kt_chan: phiên Xem như → bật cờ chỉ xem cho cả giao dịch
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_chan'::regproc); n := length(d);
  d := replace(d, $a$  perform set_config('kt.nguoi', coalesce(u.ho_ten, u.ten_dang_nhap), true);$a$,
                  $a$  perform set_config('kt.nguoi', coalesce(u.ho_ten, u.ten_dang_nhap), true);
  -- 16/10: phiên "Xem như" của Supreme → chỉ xem (trigger kt_tg_chi_xem chặn mọi lệnh ghi)
  if exists (select 1 from kt_phien p where p.token_hash = encode(digest(coalesce(p_phien, ''), 'sha256'), 'hex') and p.chi_xem) then
    perform set_config('kt.chi_xem', '1', true);
  end if;$a$);
  if length(d) = n then raise exception 'kt_chan: khong thay cho'; end if;
  execute d;
end $$;

-- Supreme tạo phiên Xem như cho 1 tài khoản
create or replace function public.kt_xem_nhu(p_phien text, p_nguoi_id int)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u kt_nguoi_dung; t kt_nguoi_dung; v_tok text;
begin
  u := kt_chan(p_phien);
  if u.vi_tri <> 'supreme' then raise exception 'Chỉ Supreme dùng được Xem như' using errcode = '42501'; end if;
  if current_setting('kt.chi_xem', true) = '1' then raise exception 'Đang Xem như — thoát ra trước'; end if;
  select * into t from kt_nguoi_dung where id = p_nguoi_id and hoat_dong;
  if t.id is null then raise exception 'Không tìm thấy tài khoản đang hoạt động'; end if;
  v_tok := encode(gen_random_bytes(32), 'hex');
  insert into kt_phien (token_hash, nguoi_dung_id, het_han, chi_xem, xem_boi) values (encode(digest(v_tok, 'sha256'), 'hex'), t.id, now() + interval '2 hours', true, u.id);
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_phien', t.id, 'xem_nhu', jsonb_build_object('xem', t.ten_dang_nhap));
  return jsonb_build_object('phien', v_tok, 'toi', kt_toi(t));
end $$;
revoke all on function public.kt_xem_nhu(text, int) from public;
grant execute on function public.kt_xem_nhu(text, int) to anon;

-- gắn trigger chỉ-xem lên mọi bảng kt_* (trừ kt_phien để đăng xuất / thoát Xem như vẫn chạy)
do $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname = 'public' and tablename like 'kt\_%' and tablename <> 'kt_phien' loop
    execute format('drop trigger if exists kt_chi_xem on public.%I', r.tablename);
    execute format('create trigger kt_chi_xem before insert or update or delete on public.%I for each row execute function public.kt_tg_chi_xem()', r.tablename);
  end loop;
end $$;
