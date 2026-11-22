-- Hoạt động + bình luận cho MỌI phiếu Thu chi & Ngân quỹ (19/10/2026, anh: "toàn bộ thu chi ngân quỹ trình bày về dạng popup + các nút tính năng giống chi")
-- Trước: chỉ phiếu chi. Nay: chi · thu · dieu_chuyen · tam_ung · vay. Quyền xem phiếu = quyền bình luận (kt_chan_dong theo trang). — Monsieur Claude
create or replace function public.kt_hoat_dong(p_phien text, p_bang text, p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u kt_nguoi_dung; t jsonb;
begin
  if p_bang not in ('chi','thu','dieu_chuyen','tam_ung','vay') then raise exception 'Chưa hỗ trợ bảng %', p_bang; end if;
  u := kt_chan_dong(p_phien, p_bang, array[p_id], false);
  execute format('select to_jsonb(x) from public.%I x where id = $1', 'kt_' || p_bang) into t using p_id;
  return jsonb_build_object(
    'tao', jsonb_build_object('luc', t->'tao_luc', 'ai', t->>'tao_boi', 'nguoi_de_nghi', t->>'nguoi_de_nghi', 'nguon', t->>'nguon'),
    'nhat_ky', coalesce((select jsonb_agg(jsonb_build_object('luc', n.luc, 'ai', n.nguoi, 'viec', n.hanh_dong, 'dl', n.du_lieu) order by n.luc, n.id)
        from kt_nhat_ky n where n.bang = 'kt_' || p_bang and n.dong_id = p_id), '[]'),
    'chung_tu', coalesce((select jsonb_agg(jsonb_build_object('luc', k.tao_luc, 'ai', k.tao_boi, 'ten', k.ten_file, 'xoa', k.da_xoa) order by k.tao_luc)
        from kt_chung_tu k where k.bang = p_bang and k.dong_id = p_id), '[]'),
    'binh_luan', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'luc', b.tao_luc, 'ai', b.nguoi, 'nd', b.noi_dung, 'cua_toi', b.nguoi_id = u.id) order by b.tao_luc)
        from kt_binh_luan b where b.bang = p_bang and b.dong_id = p_id and not b.da_xoa), '[]'));
end $$;

create or replace function public.kt_them_binh_luan(p_phien text, p_bang text, p_id bigint, p_noi_dung text)
returns bigint language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; t jsonb; v_id bigint; v_ai int[]; v_so text;
  v_ma constant jsonb := '{"chi":"PC","thu":"PT","dieu_chuyen":"DC","tam_ung":"TU","vay":"VAY"}';
begin
  if p_bang not in ('chi','thu','dieu_chuyen','tam_ung','vay') then raise exception 'Chưa hỗ trợ bảng %', p_bang; end if;
  u := kt_chan_dong(p_phien, p_bang, array[p_id], false);   -- xem được phiếu là bình luận được
  if coalesce(trim(p_noi_dung), '') = '' then raise exception 'Nhập nội dung bình luận'; end if;
  execute format('select to_jsonb(x) from public.%I x where id = $1 and not coalesce(x.da_xoa, false)', 'kt_' || p_bang) into t using p_id;
  if t is null then raise exception 'Không tìm thấy phiếu #%', p_id; end if;
  insert into kt_binh_luan (bang, dong_id, nguoi_id, nguoi, noi_dung) values (p_bang, p_id, u.id, u.ho_ten, left(trim(p_noi_dung), 2000)) returning id into v_id;
  -- người trong phiếu: người tạo / sửa / đề nghị / xác nhận + người đã bình luận + kế toán
  v_ai := kt_ai_ten(array[t->>'tao_boi', t->>'sua_boi', t->>'nguoi_de_nghi', t->>'kiem_boi', t->>'nguoi_duyet', t->>'xac_nhan_boi']
            || coalesce((select array_agg(distinct nguoi) from kt_binh_luan where bang = p_bang and dong_id = p_id and not da_xoa), '{}'), u.id)
          || kt_ai_ke_toan(u.id);
  if p_bang = 'chi' then
    select * into c from kt_chi where id = p_id;
    if c.trang_thai in ('cho_duyet','cho_gd') then v_ai := v_ai || kt_ai_giam_doc(u.id); end if;
    if c.trang_thai in ('cho_tt','da_tt') then
      if coalesce((select thu_quy_chi from kt_tai_khoan where id = c.tai_khoan_id), false)
        then v_ai := v_ai || array(select id from kt_nguoi_dung where hoat_dong and 'chi_tt' = any(quyen) and id <> u.id);
        else v_ai := v_ai || kt_ai_giam_doc(u.id); end if;
    end if;
  end if;
  v_so := (v_ma->>p_bang) || lpad(p_id::text, 6, '0');
  perform kt_bao(array(select distinct x from unnest(v_ai) x where x <> u.id), u.ho_ten, 'chi_binh_luan', 'Bình luận ' || v_so,
    left(trim(p_noi_dung), 160) || ' — ' || left(coalesce(t->>'noi_dung', t->>'ten', ''), 60), p_bang, p_id);
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, 'binh_luan', jsonb_build_object('binh_luan_id', v_id));
  return v_id;
end $$;
revoke all on function public.kt_hoat_dong(text, text, bigint), public.kt_them_binh_luan(text, text, bigint, text) from public;
grant execute on function public.kt_hoat_dong(text, text, bigint), public.kt_them_binh_luan(text, text, bigint, text) to anon;
