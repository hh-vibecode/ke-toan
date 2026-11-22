-- 16/11/2026 — VẬN CHUYỂN NỘI ĐỊA: GỢI Ý KÉO PHIẾU CHI (mục "Phí vận chuyển" / tên hãng / chữ cước, vận chuyển, ship, COD, tiền xe — không lấy cả mục cha vì lẫn tiền mua xốp, thùng, nilon) (anh: "vận chuyển nội địa kéo với phiếu chi chưa, nhận diện các phiếu của các đơn vị như Nhất Tín, Viettel Post
-- để hiện đề xuất kéo cho dễ"). Phiếu chi trong kỳ, loại "Phí vận chuyển" (mục cha Chi phí đóng gói & vận chuyển) hoặc nội dung / người thụ hưởng có tên hãng
-- (Nhất Tín, GHN, Viettel Post, GHTK, J&T, VNPost, Ahamove, Lalamove, Grab, Ninja Van, Best, nhà xe…), bỏ cước quốc tế (TQ, cont, tàu, COSCO…), chưa kéo, chưa bỏ qua.
-- Đoán hãng + cách trả ("cấn trừ / thu hộ / COD" → trừ vào tiền COD; còn lại công ty trả). Kéo = tạo chuyến gắn phiếu chi (tự tạo đơn vị nếu chưa có). — Monsieur Claude
create table if not exists public.kt_vc_bo_qua (chi_id bigint primary key, boi text, luc timestamptz not null default now());
alter table public.kt_vc_bo_qua enable row level security;
revoke all on public.kt_vc_bo_qua from public, anon, authenticated;

-- đoán hãng từ chữ (đã lower)
create or replace function public.kt_vc_hang(p text) returns text language sql immutable as $$
  select case
    when p ~ '(nhất tín|nhat tin|nhất tin|^nt$|\mnt\M)' then 'Nhất Tín'
    when p ~ '(\mghn\M|giao hàng nhanh)' then 'GHN'
    when p ~ '(viettel ?post|\mvtp\M)' then 'Viettel Post'
    when p ~ '(\mghtk\M|giao hàng tiết kiệm)' then 'GHTK'
    when p ~ '(j&t|\mjt express|j&t express)' then 'J&T Express'
    when p ~ '(vnpost|bưu điện)' then 'VNPost'
    when p ~ 'ahamove' then 'Ahamove' when p ~ 'lalamove' then 'Lalamove' when p ~ '\mgrab' then 'Grab'
    when p ~ 'ninja ?van' then 'Ninja Van' when p ~ 'best express' then 'Best Express'
    when p ~ '(nhà xe|xe khách)' then 'Nhà xe'
  end
$$;

create or replace function public.kt_vc_goi_y(p_phien text, p_tu date, p_den date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien, 'ncc');
  return coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'ngay', z.ngay, 'so_tien', z.so_tien, 'th', z.thu_huong_ten, 'nd', z.noi_dung, 'tt', z.trang_thai,
           'hang', z.hang, 'dv_id', (select d.id from kt_vc_dv d where not d.da_xoa and (lower(d.ten) = lower(z.hang) or (z.hang is not null and kt_vc_hang(lower(d.ten)) = z.hang)) order by d.id limit 1),
           'cach', case when z.t ~ '(cấn trừ|can tru|thu hộ|thu ho|\mcod\M)' then 'tru_cod' else 'cong_ty_tra' end,
           'co_so', case when jsonb_typeof(z.phan_bo) = 'array' and jsonb_array_length(z.phan_bo) = 1 then (z.phan_bo->0->>'don_vi_id')::int end)
         order by z.ngay desc, z.id desc)
    from (select c.id, coalesce(c.ngay_tt, c.ngay_de_nghi) ngay, c.so_tien, c.thu_huong_ten, c.noi_dung, c.trang_thai, c.phan_bo, x.t, kt_vc_hang(x.t) hang
            from kt_chi c cross join lateral (select lower(concat_ws(' ', c.thu_huong_ten, c.noi_dung, c.ghi_chu)) t) x
           where not c.da_xoa and not c.la_tam_ung and c.trang_thai not in ('tu_choi', 'tu_choi_tt')
             and coalesce(c.ngay_tt, c.ngay_de_nghi) between p_tu and p_den
             -- 16/11 anh: "sao đưa cả cước điện thoại với cước internet vào đây" — "cước" phải đi kèm chữ vận chuyển; loại hẳn viễn thông
             and (c.loai_con_id = 102 or kt_vc_hang(x.t) is not null
                  or x.t ~ '(cước (vc|vận|hàng|đơn|ship|xe|chuyển|tiền hàng|gửi)|thu cước|vận chuyển|\mvc\M|\mship|tiền xe|\mcod\M)')
             and x.t !~ '(\mtq\M|trung quốc|\mcont\M|container|cước tàu|cosco|nhập khẩu|quốc tế)'
             and x.t !~ '(điện thoại|internet|wifi|wi-fi|viễn thông|di động|\msim\M|cáp quang|truyền hình|\m[345]g\M|fpt telecom|\mvnpt\M|mobifone|vinaphone|viettel(?! ?post)|\mgftth|ftth)'
             and not exists (select 1 from kt_vc_chuyen v where v.chi_id = c.id and not v.da_xoa)
             and not exists (select 1 from kt_vc_bo_qua b where b.chi_id = c.id)) z), '[]');
end $$;

-- kéo: p_ds = [{chi_id, dv_id?, hang?, cach_tt, co_so?}] → mỗi phiếu 1 chuyến (đơn vị chưa có thì tạo theo tên hãng)
create or replace function public.kt_vc_keo(p_phien text, p_ds jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; r jsonb; c kt_chi; dv bigint; n int := 0; v_ten text;
begin
  u := kt_chan(p_phien, 'ncc', true);
  for r in select e from jsonb_array_elements(coalesce(p_ds, '[]')) e loop
    select * into c from kt_chi where id = (r->>'chi_id')::bigint and not da_xoa;
    if c.id is null or exists (select 1 from kt_vc_chuyen where chi_id = c.id and not da_xoa) then continue; end if;
    dv := nullif(r->>'dv_id', '')::bigint;
    if dv is null then
      v_ten := coalesce(nullif(btrim(r->>'hang'), ''), 'Khác');
      select id into dv from kt_vc_dv where not da_xoa and lower(btrim(kt_vc_dv.ten)) = lower(v_ten) limit 1;
      if dv is null then
        insert into kt_vc_dv (ten, loai, cach_tt, tao_boi) values (v_ten, case when v_ten = 'Nhà xe' then 'nha_xe' when v_ten = 'Khác' then 'khac' else 'chuyen_phat' end,
               coalesce(nullif(r->>'cach_tt', ''), 'cong_ty_tra'), u.ho_ten) returning id into dv;
      end if;
    end if;
    insert into kt_vc_chuyen (ngay, dv_id, co_so, noi_dung, so_tien, cach_tt, chi_id, tao_boi)
    values (coalesce(c.ngay_tt, c.ngay_de_nghi, current_date), dv, nullif(r->>'co_so', '')::int, left(c.noi_dung, 300), c.so_tien,
            coalesce(nullif(r->>'cach_tt', ''), 'cong_ty_tra'), c.id, u.ho_ten);
    n := n + 1;
  end loop;
  if n > 0 then perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vc_chuyen', null, 'keo_phieu_chi', jsonb_build_object('so', n)); end if;
  return n;
end $$;

create or replace function public.kt_vc_bo_qua_luu(p_phien text, p_ids bigint[]) returns int
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; n int;
begin
  u := kt_chan(p_phien, 'ncc', true);
  insert into kt_vc_bo_qua (chi_id, boi) select unnest(p_ids), u.ho_ten on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

do $$ declare f text; begin
  foreach f in array array['kt_vc_goi_y(text, date, date)', 'kt_vc_keo(text, jsonb)', 'kt_vc_bo_qua_luu(text, bigint[])'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop; end $$;
