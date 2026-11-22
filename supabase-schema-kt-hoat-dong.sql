-- HOẠT ĐỘNG của phiếu: lịch sử đủ vết + BÌNH LUẬN (16/10/2026, anh Hải: "lịch sử phiếu lưu vết đủ hết từ bước người tạo",
-- "thêm phần bình luận nếu mọi người cần trao đổi về phiếu, đẩy vào chuông thông báo những người trong phiếu") — Monsieur Claude
create table if not exists public.kt_binh_luan (
  id bigserial primary key,
  bang text not null,                 -- 'chi' (sau mở rộng thu / dieu_chuyen…)
  dong_id bigint not null,
  nguoi_id int references public.kt_nguoi_dung(id),
  nguoi text not null,
  noi_dung text not null check (length(trim(noi_dung)) between 1 and 2000),
  tao_luc timestamptz not null default now(),
  da_xoa boolean not null default false
);
create index if not exists kt_binh_luan_dong on public.kt_binh_luan (bang, dong_id);
alter table public.kt_binh_luan enable row level security;
revoke all on public.kt_binh_luan from anon, authenticated;
revoke all on sequence public.kt_binh_luan_id_seq from anon, authenticated;

-- Danh sách hoạt động 1 phiếu: tạo · mọi lần đổi trạng thái / sửa (nhật ký, kèm ảnh chụp dòng để so trường đổi) · chứng từ · bình luận
create or replace function public.kt_hoat_dong(p_phien text, p_bang text, p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi;
begin
  if p_bang <> 'chi' then raise exception 'Chưa hỗ trợ bảng %', p_bang; end if;
  u := kt_chan_dong(p_phien, p_bang, array[p_id], false);
  select * into c from kt_chi where id = p_id;
  return jsonb_build_object(
    'tao', jsonb_build_object('luc', c.tao_luc, 'ai', c.tao_boi, 'nguoi_de_nghi', c.nguoi_de_nghi, 'nguon', c.nguon),
    'nhat_ky', coalesce((select jsonb_agg(jsonb_build_object('luc', n.luc, 'ai', n.nguoi, 'viec', n.hanh_dong, 'dl', n.du_lieu) order by n.luc, n.id)
        from kt_nhat_ky n where n.bang = 'kt_chi' and n.dong_id = p_id), '[]'),
    'chung_tu', coalesce((select jsonb_agg(jsonb_build_object('luc', k.tao_luc, 'ai', k.tao_boi, 'ten', k.ten_file, 'xoa', k.da_xoa) order by k.tao_luc)
        from kt_chung_tu k where k.bang = 'chi' and k.dong_id = p_id), '[]'),
    'binh_luan', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'luc', b.tao_luc, 'ai', b.nguoi, 'nd', b.noi_dung, 'cua_toi', b.nguoi_id = u.id) order by b.tao_luc)
        from kt_binh_luan b where b.bang = p_bang and b.dong_id = p_id and not b.da_xoa), '[]'));
end $$;

-- Thêm bình luận → chuông cho những người trong phiếu (người tạo / đề nghị, người xác nhận, người đã bình luận, người chi tiền theo bước)
create or replace function public.kt_them_binh_luan(p_phien text, p_bang text, p_id bigint, p_noi_dung text)
returns bigint language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; v_id bigint; v_ai int[]; v_so text;
begin
  if p_bang <> 'chi' then raise exception 'Chưa hỗ trợ bảng %', p_bang; end if;
  u := kt_chan_dong(p_phien, p_bang, array[p_id], false);   -- xem được phiếu là bình luận được
  if coalesce(trim(p_noi_dung), '') = '' then raise exception 'Nhập nội dung bình luận'; end if;
  select * into c from kt_chi where id = p_id and not da_xoa;
  if c.id is null then raise exception 'Không tìm thấy phiếu #%', p_id; end if;
  insert into kt_binh_luan (bang, dong_id, nguoi_id, nguoi, noi_dung) values (p_bang, p_id, u.id, u.ho_ten, left(trim(p_noi_dung), 2000)) returning id into v_id;
  v_ai := kt_ai_ten(array[c.tao_boi, c.nguoi_de_nghi, c.kiem_boi, c.nguoi_duyet, c.sua_boi]
            || coalesce((select array_agg(distinct nguoi) from kt_binh_luan where bang = p_bang and dong_id = p_id and not da_xoa), '{}'), u.id);
  if c.trang_thai in ('cho_duyet','cho_gd') then v_ai := v_ai || kt_ai_ke_toan(u.id) || kt_ai_giam_doc(u.id); end if;
  if c.trang_thai in ('cho_tt','da_tt') then
    if coalesce((select thu_quy_chi from kt_tai_khoan where id = c.tai_khoan_id), false)
      then v_ai := v_ai || array(select id from kt_nguoi_dung where hoat_dong and 'chi_tt' = any(quyen) and id <> u.id);
      else v_ai := v_ai || kt_ai_giam_doc(u.id); end if;
  end if;
  v_so := 'PC' || lpad(p_id::text, 6, '0');
  perform kt_bao(array(select distinct x from unnest(v_ai) x where x <> u.id), u.ho_ten, 'chi_binh_luan', 'Bình luận phiếu ' || v_so,
    left(trim(p_noi_dung), 160) || ' — ' || left(c.noi_dung, 60), p_bang, p_id);
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, 'binh_luan', jsonb_build_object('binh_luan_id', v_id));
  return v_id;
end $$;

-- Xoá bình luận của chính mình
create or replace function public.kt_xoa_binh_luan(p_phien text, p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung;
begin
  u := kt_chan(p_phien);
  update kt_binh_luan set da_xoa = true where id = p_id and nguoi_id = u.id;
  if not found then raise exception 'Chỉ xoá được bình luận của mình'; end if;
end $$;

revoke all on function public.kt_hoat_dong(text, text, bigint), public.kt_them_binh_luan(text, text, bigint, text), public.kt_xoa_binh_luan(text, bigint) from public;
grant execute on function public.kt_hoat_dong(text, text, bigint), public.kt_them_binh_luan(text, text, bigint, text), public.kt_xoa_binh_luan(text, bigint) to anon;
