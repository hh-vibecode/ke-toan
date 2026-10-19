-- @NHẮC TÊN trong bình luận (19/10/2026, anh: "mention được mọi người có trong luồng app kế toán, họ nhận chuông thông báo").
-- kt_them_binh_luan thêm p_nhac_den int[] = những người được @: báo chuông riêng "X nhắc tới bạn ở PC…" (không báo trùng lần 2).
-- kt_ds_ten_nguoi: danh sách tên để gõ @ (mọi tài khoản đăng nhập dùng được, chỉ trả id + họ tên). — Monsieur Claude
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_them_binh_luan'::regproc); n := length(d);
  d := replace(d, 'p_nhac boolean DEFAULT false)', 'p_nhac boolean DEFAULT false, p_nhac_den integer[] DEFAULT NULL::integer[])');
  d := replace(d, $a$perform kt_bao(array(select distinct x from unnest(v_ai) x where x <> u.id),$a$,
                  $a$perform kt_bao(array(select distinct x from unnest(v_ai) x where x <> u.id and not (x = any(coalesce(p_nhac_den, '{}')))),$a$);
  d := replace(d, $a$  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, 'binh_luan',$a$,
                  $a$  if coalesce(array_length(p_nhac_den, 1), 0) > 0 then
    perform kt_bao(array(select distinct x from unnest(p_nhac_den) x where x <> u.id and exists (select 1 from kt_nguoi_dung k where k.id = x and k.hoat_dong)),
      u.ho_ten, 'chi_binh_luan', u.ho_ten || ' nhắc tới bạn ở ' || v_so,
      left(trim(p_noi_dung), 160) || ' — ' || left(coalesce(t->>'noi_dung', t->>'ten', ''), 60), p_bang, p_id);
  end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, 'binh_luan',$a$);
  if length(d) - n < 300 then raise exception 'kt_them_binh_luan: khong thay du cho (%)', length(d) - n; end if;
  drop function public.kt_them_binh_luan(text, text, bigint, text, boolean);
  execute d;
end $$;
revoke all on function public.kt_them_binh_luan(text, text, bigint, text, boolean, integer[]) from public;
grant execute on function public.kt_them_binh_luan(text, text, bigint, text, boolean, integer[]) to anon;

create or replace function public.kt_ds_ten_nguoi(p_phien text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform kt_chan(p_phien);
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'ten', ho_ten) order by ho_ten) from kt_nguoi_dung
    where hoat_dong and ten_dang_nhap not like 'tam-%'), '[]');
end $$;
revoke all on function public.kt_ds_ten_nguoi(text) from public;
grant execute on function public.kt_ds_ten_nguoi(text) to anon;
