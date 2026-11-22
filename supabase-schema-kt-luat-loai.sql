-- =========================================================================
-- APP KẾ TOÁN — LUẬT LOẠI CHI + "NGHI SAI LOẠI" (anh chốt 09/10/2026) — Monsieur Claude
-- Anh: "từ ngày t với m bắt đầu áp dụng app thì m gán phần này vào phần nghi báo lỗi nếu kế toán sai, còn trước đó m hỗ trợ (sửa) trước".
-- * kt_luat_loai_chi: luật chốt loại chi theo nội dung (Claude quyết theo bản chất khoản chi — xem scripts/chot-loai-chi.js).
-- * TRƯỚC ngày áp dụng: Claude đã tự chuẩn hoá phiếu cũ (scripts/chot-loai-chi.js ghi — 37 phiếu, có nhật ký).
-- * TỪ ngày áp dụng (kt_cai_dat 'ngay_ap_dung_app'; để trống = chưa bật): phiếu chi có loại khác luật → cờ "nghi sai loại",
--   KHÔNG tự sửa; kế toán bấm Đổi sang loại theo luật / Giữ loại hiện tại (kt_xu_ly_loai).
-- File này ĐỊNH NGHĨA LẠI kt_ds (thêm nghi_loai) — chạy SAU supabase-schema-kt-thong-bao.sql.
-- =========================================================================
create table if not exists public.kt_cai_dat (khoa text primary key, gia_tri text, sua_luc timestamptz not null default now());
alter table public.kt_cai_dat enable row level security;
revoke all on public.kt_cai_dat from anon, authenticated;
insert into kt_cai_dat (khoa, gia_tri) values ('ngay_ap_dung_app', null) on conflict (khoa) do nothing;

create table if not exists public.kt_luat_loai_chi (
  id serial primary key, thu_tu int not null default 100, ten text not null, mau text not null, loai_id int not null references public.kt_loai(id),
  hoat_dong boolean not null default true, tao_luc timestamptz not null default now());
alter table public.kt_luat_loai_chi enable row level security;
revoke all on public.kt_luat_loai_chi from anon, authenticated;
delete from kt_luat_loai_chi;
insert into kt_luat_loai_chi (thu_tu, ten, mau, loai_id) values
  (10, $kt$Trả thẻ tín dụng công ty (sao kê, phí lãi thẻ)$kt$, $kt$visa business|thanh to[aá]n sk|k[yỳ] sao k[eê]|phi va lai$kt$, (select id from kt_loai where nhom = 'chi' and ten = $kt$FINANCE - Tài chính - vay,lãi$kt$)),
  (20, $kt$Phí dịch vụ ngân hàng$kt$, $kt$qltk|sms ?banking|thu phi dich vu sms|phí ngân hàng|phi ngan hang|phí nộp tiền vào|phi quan ly tk$kt$, (select id from kt_loai where nhom = 'chi' and ten = $kt$OPEX - Vận hành & Quản lí$kt$)),
  (30, $kt$Mua hàng nhập: phí chuyển tiền NN, vận chuyển TQ$kt$, $kt$ctnn|vận chuyển tq|vc tq|van chuyen tq$kt$, (select id from kt_loai where nhom = 'chi' and ten = $kt$COGS - Giá vốn & Nhập Hàng$kt$)),
  (40, $kt$NCC hàng hoá (Thảo Nến)$kt$, $kt$ncc thảo nến$kt$, (select id from kt_loai where nhom = 'chi' and ten = $kt$COGS - Giá vốn & Nhập Hàng$kt$)),
  (50, $kt$Tiền điện$kt$, $kt$tiền điện(?! thoại)$kt$, (select id from kt_loai where nhom = 'chi' and ten = $kt$OPEX - Vận hành & Quản lí$kt$)),
  (60, $kt$Bù quỹ ngoài cửa hàng$kt$, $kt$quỹ ngoài$kt$, (select id from kt_loai where nhom = 'chi' and ten = $kt$OPEX - Vận hành & Quản lí$kt$)),
  (70, $kt$Chưa rõ nguyên nhân$kt$, $kt$chưa rõ nguyên nhân$kt$, (select id from kt_loai where nhom = 'chi' and ten = $kt$OPEX - Khác$kt$)),
  (80, $kt$Chuyển tiền mặt cho bà Bùi Thị Hiền$kt$, $kt$bùi thị hiền$kt$, (select id from kt_loai where nhom = 'chi' and ten = $kt$OPEX - Khác$kt$));

alter table public.kt_chi add column if not exists bo_qua_loai boolean not null default false;   -- kế toán xác nhận giữ loại khác luật

-- Phiếu có loại khác luật (chỉ phiếu từ ngày áp dụng app, chưa bấm "Giữ") → {luat, loai_id, loai}; không thì null
create or replace function public.kt_nghi_loai(c kt_chi) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('luat', r.ten, 'loai_id', r.loai_id, 'loai', l.ten)
    from kt_luat_loai_chi r join kt_loai l on l.id = r.loai_id, kt_cai_dat s
   where s.khoa = 'ngay_ap_dung_app' and s.gia_tri is not null and r.hoat_dong
     and not c.da_xoa and not c.bo_qua_loai and c.loai_id is not null and c.loai_id <> r.loai_id
     and coalesce(c.ngay_tt, c.ngay_de_nghi) >= s.gia_tri::date and c.noi_dung ~* r.mau
     and r.thu_tu = (select min(r2.thu_tu) from kt_luat_loai_chi r2 where r2.hoat_dong and c.noi_dung ~* r2.mau)
   limit 1;
$$;
revoke execute on function public.kt_nghi_loai(kt_chi) from public, anon, authenticated;

create or replace function public.kt_ds(p_phien text, p_bang text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; v_tat boolean;
begin
  if p_bang = 'chi' then
    u := kt_chan(p_phien);
    v_tat := kt_co_quyen(u, 'chi');
    if not v_tat and not kt_co_quyen(u, 'chi_de_nghi') then
      raise exception 'Tài khoản chưa được cấp quyền xem trang này' using errcode = '42501';
    end if;
    return coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object('so_ct', (select count(*) from kt_chung_tu k
        where k.bang = 'chi' and k.dong_id = c.id and not k.da_xoa), 'nghi_loai', kt_nghi_loai(c)) order by coalesce(c.ngay_tt, c.ngay_de_nghi) desc, c.id desc) from kt_chi c
      where not da_xoa and (v_tat or c.tao_boi = u.ho_ten) and (ngay_de_nghi between p_tu and p_den or ngay_tt between p_tu and p_den
        or trang_thai in ('cho_duyet','cho_gd','cho_tt'))), '[]');
  end if;
  perform kt_chan(p_phien, p_bang);
  if p_bang = 'thu' then
    return coalesce((select jsonb_agg(to_jsonb(t) || jsonb_build_object('so_ct', (select count(*) from kt_chung_tu k
        where k.bang = 'thu' and k.dong_id = t.id and not k.da_xoa)) order by t.ngay desc, t.id desc) from kt_thu t
      where not da_xoa and ngay between p_tu and p_den), '[]');
  elsif p_bang = 'dieu_chuyen' then
    return coalesce((select jsonb_agg(to_jsonb(d) || jsonb_build_object('so_ct', (select count(*) from kt_chung_tu k
        where k.bang = 'dieu_chuyen' and k.dong_id = d.id and not k.da_xoa)) order by d.ngay desc, d.id desc) from kt_dieu_chuyen d
      where not da_xoa and ngay between p_tu and p_den), '[]');
  elsif p_bang = 'cong_no' then
    return coalesce((select jsonb_agg(x order by x->>'ngay' desc) from (
      select to_jsonb(n) || jsonb_build_object('da_thu', coalesce(t.da_thu, 0), 'lan_thu', coalesce(t.lan, '[]'::jsonb),
        'con_no', n.so_tien - n.tra_hang - coalesce(t.da_thu, 0)) x
      from kt_cong_no n
      left join lateral (select sum(so_tien) da_thu, jsonb_agg(jsonb_build_object('id', id, 'ngay', ngay, 'so_tien', so_tien,
          'ghi_chu', ghi_chu) order by ngay) lan from kt_cong_no_thu where cong_no_id = n.id and not da_xoa) t on true
      where not n.da_xoa and (n.ngay between p_tu and p_den or n.so_tien - n.tra_hang - coalesce(t.da_thu, 0) <> 0)) s), '[]');
  elsif p_bang = 'sap_tra' then
    return coalesce((select jsonb_agg(to_jsonb(s) order by s.da_tra, s.han nulls last) from kt_sap_tra s where not da_xoa), '[]');
  end if;
  raise exception 'Bảng không hợp lệ';
end $$;

-- Xử lý cờ nghi sai loại: p_doi = true → đổi sang loại theo luật; false → giữ loại hiện tại (không báo nữa). Quyền: kế toán (chi_duyet).
create or replace function public.kt_xu_ly_loai(p_phien text, p_id bigint, p_doi boolean) returns void
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; c kt_chi; n jsonb;
begin
  u := kt_chan(p_phien, 'chi_duyet');
  select * into c from kt_chi where id = p_id and not da_xoa; if c.id is null then raise exception 'Không tìm thấy phiếu %', p_id; end if;
  n := kt_nghi_loai(c); if n is null then raise exception 'Phiếu % không bị nghi sai loại', p_id; end if;
  if p_doi then update kt_chi set loai_id = (n->>'loai_id')::int, sua_boi = u.ho_ten, sua_luc = now() where id = p_id;
  else update kt_chi set bo_qua_loai = true where id = p_id; end if;
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_chi', p_id, case when p_doi then 'doi_loai_theo_luat' else 'giu_loai' end, n);
end $$;
revoke execute on function public.kt_xu_ly_loai(text, bigint, boolean) from public;
grant execute on function public.kt_xu_ly_loai(text, bigint, boolean) to anon, authenticated;
