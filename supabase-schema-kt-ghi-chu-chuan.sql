-- 28/10/2026 — Công nợ khách: PA3 (anh chốt) + LUỒNG GHI CHÚ CHUẨN trên hoá đơn Kiot. Monsieur Claude
-- Kế toán: "công nợ cần tách nợ thật / COD chưa thu hồi / đơn sẽ trả hàng (kể cả trả 1 phần); đơn tranh chấp treo trên Kiot chưa làm phiếu trả".
-- Anh: "cứ bảo viết tách dòng rõ ràng ra rồi m lọc sau". Mẫu ghi chú: mỗi ý 1 dòng "Nhãn: giá trị" —
--   Thu COD: 3.400.000 · Cọc: 1.000.000 · Chưa lấy hàng: 2.000.000 · Trả hàng: 1.200.000 · Đóng hàng: … · Giao hàng: … · Vận chuyển: … · Hoá đơn: có / không
-- Bộ đọc vẫn hiểu kiểu ghi cũ ("Miễn phí ship, thu cod 370.000", "Thu COD 3tr4", "Diệp, Tuấn ĐH"…).
-- Soát 306 ghi chú từ 01/09: SỬA LỖI đọc cũ — "Cọc: không" ở dòng trên "Thu cod …" bị hiểu là "không thu cod" (5 đơn COD 19/10 thành nợ thật).
-- Kế toán sửa tay từng hoá đơn (bảng kt_no_tach: số tiền sẽ trả hàng / COD / chưa lấy hàng — trả 1 phần được); có số tay thì bỏ qua ghi chú.
-- Phiếu trả hàng Kiot gắn hoá đơn → tự trừ phần "sẽ trả hàng"; đánh dấu > 30 ngày chưa có phiếu trả → nhắc (tra_lau).

-- số tiền đứng ĐẦU chuỗi (sau ":" / khoảng trắng): 1.050.000 · 1.050.000đ · 3tr4 · 3tr900k · 12tr356 · 19tr · 1 triệu · 405k · 5.456k · 0 · "không" → 0; "30%" → null
create or replace function public.kt_doc_tien(p text) returns numeric language plpgsql immutable set search_path = public as $$
declare s text := kt_bo_dau(p); m text[]; a numeric;
begin
  if s ~ '^[\s:=-]*(khong|ko)([^a-z]|$)' then return 0; end if;
  m := regexp_match(s, '^[\s:=-]*(\d[\d.,]*)(?![\d.,])\s*(?:(trieu|tr|k)(?![a-z]))?\s*(\d{1,3})?(?!\d)\s*(%)?');
  if m is null or m[4] is not null then return null; end if;
  a := nullif(regexp_replace(rtrim(m[1], '.,'), '[.,]', '', 'g'), '')::numeric;
  if a is null then return null; end if;
  if m[2] in ('tr', 'trieu') then return a * 1000000 + coalesce(m[3]::numeric * power(10, 3 - length(m[3])) * 1000, 0); end if;
  if m[2] = 'k' then return a * 1000; end if;
  return a;
end $$;

-- đọc ghi chú hoá đơn → jsonb {cod, cod_tien, coc, tra_hang, tra_tien, chua_lay, chua_lay_tien, dong_hang[], giao_hang[]}
-- *_tien null = có nhưng không ghi số (tính cả phần còn nợ của hoá đơn)
create or replace function public.kt_doc_ghi_chu(p text) returns jsonb language plpgsql immutable set search_path = public as $$
declare l text; u text; v numeric; t text; nm text; ten text[]; cho text[] := '{}'; cuoi text[] := '{}';
  cod_co boolean := false; cod_tien numeric; coc numeric; tra_co boolean := false; tra numeric; cl_co boolean := false; cl numeric;
  dh text[] := '{}'; gh text[] := '{}';
begin
  for l in select btrim(regexp_replace(x, '^\s*\d+\s*[.)]\s*', '')) from regexp_split_to_table(normalize(coalesce(p, ''), NFC), '\r?\n|\s+/\s+') x loop   -- 1 ý / dòng; " / " (có khoảng trắng) cũng là ngắt ý (Chánh Tâm hay ghi), "21/9" không ngắt
    continue when l = '';
    u := kt_bo_dau(l);
    -- COD (bỏ "không thu cod" — chỉ khi đứng liền nhau trên CÙNG dòng)
    if u ~ '(^|[^a-z0-9])cod([^a-z]|$)' and u !~ '(khong|ko|k)[ \t]+(thu[ \t]+)?cod' then
      v := kt_doc_tien(substring(u from 'cod(.*)$'));
      if v is null then cod_co := true;
      elsif v > 0 then cod_co := true; cod_tien := greatest(coalesce(cod_tien, 0), v); end if;
    end if;
    -- cọc (số tiền khách đã đặt trước)
    if u ~ '(^|[^a-z])coc([^a-z]|$)' then
      v := kt_doc_tien(substring(u from 'coc(.*)$'));
      if v > 0 then coc := greatest(coalesce(coc, 0), v); end if;
    end if;
    -- trả hàng (CHỈ dòng chuẩn "Trả hàng: …" / "Sẽ trả hàng: …" / "#trahang …" — chữ "trả" trong câu thường quá nhiều nghĩa)
    if u ~ '^(#\s*)?(se\s+)?tra\s*hang\s*:' or u ~ '#\s*tra\s*hang' then
      tra_co := true; v := kt_doc_tien(coalesce(substring(u from ':(.*)$'), substring(u from '#\s*tra\s*hang(.*)$')));
      if v > 0 then tra := coalesce(tra, 0) + v; end if;
    end if;
    -- chưa lấy hàng: dòng chuẩn có số tiền, hoặc từ khoá cũ (cả đơn)
    if u ~ '^chua\s*lay\s*hang\s*:' then
      cl_co := true; v := kt_doc_tien(substring(u from ':(.*)$')); if v > 0 then cl := coalesce(cl, 0) + v; end if;
    elsif u ~ 'chua\s*(lay|nhan|giao)|gui lai|giu hang|de lai|hen lay|chua di hang' then cl_co := true;
    end if;
    -- người đóng / giao hàng — dòng chuẩn "Đóng hàng: A, B" (cả "1. Người đóng hàng 2: …")
    if u ~ '^(nguoi\s+)?dong\s*hang(\s*\d+)?\s*:' then
      dh := dh || array(select btrim(x) from regexp_split_to_table(substring(l from ':(.*)$'), '[,;]') x where btrim(x) <> '');
    elsif u ~ '^(nguoi\s+)?giao\s*hang(\s*\d+)?\s*:' then
      gh := gh || array(select btrim(x) from regexp_split_to_table(substring(l from ':(.*)$'), '[,;]') x where btrim(x) <> '');
    elsif l ~ '(^|[^[:alpha:]])(ĐH|GH)([^[:alpha:]]|$)' and l !~ ':' then
      -- kiểu ghi tắt cũ: "Diệp, Tuấn ĐH" · "Diệp ĐH, GH" · "Lệ ĐH, Hào GH"
      cho := '{}';
      foreach t in array regexp_split_to_array(l, '\s*,\s*') loop
        if t ~ '(^|\s)(ĐH|GH)$' then
          nm := btrim(regexp_replace(t, '(^|\s)(ĐH|GH)$', ''));
          if nm <> '' then cho := cho || nm; end if;
          ten := case when cardinality(cho) > 0 then cho else cuoi end;
          ten := array(select x from unnest(ten) x where x !~ '\d' and array_length(regexp_split_to_array(x, '\s+'), 1) <= 4);
          if t ~ 'ĐH$' then dh := dh || ten; else gh := gh || ten; end if;
          cuoi := ten; cho := '{}';
        else cho := cho || btrim(t); end if;
      end loop;
    end if;
  end loop;
  return jsonb_build_object('cod', cod_co, 'cod_tien', cod_tien, 'coc', coc, 'tra_hang', tra_co, 'tra_tien', tra,
    'chua_lay', cl_co, 'chua_lay_tien', cl, 'dong_hang', to_jsonb(dh), 'giao_hang', to_jsonb(gh));
end $$;

-- kế toán nhập tay theo từng hoá đơn (PA3): có dòng = dùng số tay, bỏ qua ghi chú
create table if not exists public.kt_no_tach (
  hoa_don_id bigint primary key,
  tra_hang numeric not null default 0 check (tra_hang >= 0),
  cod numeric not null default 0 check (cod >= 0),
  chua_lay numeric not null default 0 check (chua_lay >= 0),
  ly_do text,
  tra_luc timestamptz,          -- lúc đặt / đổi số "sẽ trả hàng" (phiếu trả Kiot từ lúc này mới trừ)
  sua_boi text, sua_luc timestamptz not null default now());
alter table public.kt_no_tach enable row level security;
revoke all on public.kt_no_tach from anon, authenticated;

-- chia phần còn nợ của 1 hoá đơn: sẽ trả hàng → COD → chưa lấy hàng → còn lại là nợ thật
create or replace function public.kt_no_tach_hd(p_hd bigint, p_phan numeric, p_cod boolean, p_gc text, p_ngay timestamptz, p_da_tra numeric)
 returns jsonb language plpgsql stable set search_path = public as $$
declare t kt_no_tach; d jsonb := kt_doc_ghi_chu(p_gc); tra numeric; cod numeric; cl numeric; ng text; tu timestamptz; da numeric := 0;
  a_tra numeric; a_cod numeric; a_cl numeric; phan numeric := greatest(coalesce(p_phan, 0), 0);
begin
  select * into t from kt_no_tach where hoa_don_id = p_hd;
  if t.hoa_don_id is not null then tra := t.tra_hang; cod := t.cod; cl := t.chua_lay; ng := 'tay'; tu := t.tra_luc;
  else ng := 'ghi_chu';
    tra := case when (d->>'tra_hang')::boolean then coalesce((d->>'tra_tien')::numeric, phan) else 0 end;
    cod := case when coalesce(p_cod, false) or (d->>'cod')::boolean then coalesce((d->>'cod_tien')::numeric, phan) else 0 end;
    cl := case when (d->>'chua_lay')::boolean then coalesce((d->>'chua_lay_tien')::numeric, phan) else 0 end;
    tu := p_ngay;
  end if;
  if tra > 0 then   -- phiếu trả hàng Kiot gắn hoá đơn này (từ lúc đánh dấu) → trừ dần
    select coalesce(sum(tong_tra), 0) into da from kt_kiot_tra_hang where hoa_don_id = p_hd and trang_thai = 1 and (tu is null or ngay >= tu);
    tra := greatest(tra - da, 0);
  end if;
  a_tra := least(tra, phan); a_cod := least(cod, phan - a_tra); a_cl := least(cl, phan - a_tra - a_cod);
  return jsonb_build_object('tra', a_tra, 'cod', a_cod, 'cl', a_cl, 'that', phan - a_tra - a_cod - a_cl, 'nguon', ng, 'da_tra_hang', da,
    'tra_lau', a_tra > 0 and coalesce(tu, p_ngay) < now() - interval '30 days',
    -- ghi chú có cọc mà phần còn nợ vẫn dư ra thành nợ thật → nghi tiền cọc chưa ghi vào Kiot (kế toán kiểm)
    'coc_ngoai', least(greatest(phan - a_tra - a_cod - a_cl, 0), coalesce((d->>'coc')::numeric, 0)));
end $$;

create or replace function public.kt_luu_no_tach(p_phien text, p_hd bigint, p_tra numeric, p_cod numeric, p_cl numeric, p_ly_do text, p_xoa boolean default false)
 returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; h kt_kiot_hoa_don; c kt_no_tach;
begin
  u := kt_chan(p_phien, 'khach_hang', true);
  if coalesce(current_setting('kt.chi_xem', true), '') = '1' then raise exception 'Đang ở chế độ Xem như — chỉ xem'; end if;
  select * into h from kt_kiot_hoa_don where id = p_hd;
  if h.id is null then raise exception 'Không tìm thấy hoá đơn'; end if;
  select * into c from kt_no_tach where hoa_don_id = p_hd;
  if p_xoa then
    delete from kt_no_tach where hoa_don_id = p_hd;
    perform kt_ghi_nhat_ky(u.ho_ten, 'kt_no_tach', p_hd, 'xoa', to_jsonb(c));
    return;
  end if;
  if coalesce(p_tra, 0) < 0 or coalesce(p_cod, 0) < 0 or coalesce(p_cl, 0) < 0 then raise exception 'Số tiền không được âm'; end if;
  if coalesce(p_tra, 0) + coalesce(p_cod, 0) + coalesce(p_cl, 0) > h.tong then
    raise exception 'Tổng sẽ trả hàng + COD + chưa lấy hàng (%) lớn hơn giá trị hoá đơn (%)', coalesce(p_tra, 0) + coalesce(p_cod, 0) + coalesce(p_cl, 0), h.tong; end if;
  insert into kt_no_tach (hoa_don_id, tra_hang, cod, chua_lay, ly_do, tra_luc, sua_boi, sua_luc)
  values (p_hd, coalesce(p_tra, 0), coalesce(p_cod, 0), coalesce(p_cl, 0), nullif(btrim(coalesce(p_ly_do, '')), ''), case when coalesce(p_tra, 0) > 0 then now() end, u.ho_ten, now())
  on conflict (hoa_don_id) do update set tra_hang = excluded.tra_hang, cod = excluded.cod, chua_lay = excluded.chua_lay, ly_do = excluded.ly_do,
    tra_luc = case when excluded.tra_hang = 0 then null when excluded.tra_hang <> kt_no_tach.tra_hang or kt_no_tach.tra_luc is null then now() else kt_no_tach.tra_luc end,
    sua_boi = excluded.sua_boi, sua_luc = now();
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_no_tach', p_hd, 'sua', jsonb_build_object('ma', h.ma, 'tra_hang', p_tra, 'cod', p_cod, 'chua_lay', p_cl, 'ly_do', p_ly_do, 'cu', to_jsonb(c)));
end $$;
revoke all on function public.kt_luu_no_tach(text, bigint, numeric, numeric, numeric, text, boolean) from public;
grant execute on function public.kt_luu_no_tach(text, bigint, numeric, numeric, numeric, text, boolean) to anon;

-- công nợ khách: dùng kt_no_tach_hd (bản đầy đủ 2 hàm đang chạy)
CREATE OR REPLACE FUNCTION public.kt_cong_no_dt(p_phien text, p_loai text DEFAULT 'kh'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; r jsonb; han int;
begin
  perform kt_chan(p_phien, case when p_loai = 'ncc' then 'ncc' else 'khach_hang' end);
  select coalesce(nullif(gia_tri, '')::int, 30) into han from kt_cai_dat where khoa = case when p_loai = 'ncc' then 'han_no_ncc_ngay' else 'han_no_kh_ngay' end;
  han := coalesce(han, 30);
  with dt as (
    select id, ma, ten, sdt, cong_no no, tong_mua tong from kt_kiot_khach where p_loai = 'kh' and cong_no <> 0
    union all select id, ma, ten, sdt, cong_no, tong_nhap from kt_kiot_ncc where p_loai = 'ncc' and cong_no <> 0),
  ct as (   -- hoá đơn bán (khách) / phiếu nhập (NCC) đã hoàn thành
    select khach_id dt_id, id, ngay, chi_nhanh, tong, nv_ban nv, cod, ghi_chu, da_tra from kt_kiot_hoa_don where p_loai = 'kh' and trang_thai in (1, 3) and tong > 0
    union all select ncc_id, id, ngay, chi_nhanh, tong, null, null::boolean, null::text, null::numeric from kt_kiot_nhap_hang where p_loai = 'ncc' and trang_thai = 3 and tong > 0),
  lk as (select ct.*, d.no, sum(ct.tong) over (partition by ct.dt_id order by ct.ngay desc, ct.id desc) cum
           from ct join dt d on d.id = ct.dt_id where d.no > 0),
  pb0 as (select dt_id, id, chi_nhanh, ngay ngay_tz, (ngay at time zone 'Asia/Ho_Chi_Minh')::date ngay, tong, least(tong, no - (cum - tong)) phan, cod, ghi_chu, da_tra from lk where cum - tong < no),
  -- 28/10/2026 PA3: chia phần còn nợ của từng hoá đơn theo SỐ TIỀN (sẽ trả hàng → COD → chưa lấy hàng → nợ thật), không gán cả hoá đơn 1 loại
  pb as (select pb0.*, case when p_loai = 'kh' then kt_no_tach_hd(id, phan, cod, ghi_chu, ngay_tz, da_tra) end s from pb0),
  g as (select dt_id, sum(phan) da_gan, sum(tong) tong_ct, min(ngay) cu_nhat, count(*) so_ct, (array_agg(chi_nhanh order by ngay desc))[1] cn,
          sum(phan) filter (where hom - ngay <= 30) b1, sum(phan) filter (where hom - ngay between 31 and 60) b2,
          sum(phan) filter (where hom - ngay between 61 and 90) b3, sum(phan) filter (where hom - ngay > 90) b4,
          sum((s->>'cod')::numeric) n_cod, sum((s->>'cl')::numeric) n_cl, sum((s->>'tra')::numeric) n_tra,
          count(*) filter (where (s->>'tra_lau')::boolean) tra_lau, sum((s->>'coc_ngoai')::numeric) coc_ngoai
          from pb group by 1),
  cn_cuoi as (select distinct on (dt_id) dt_id, chi_nhanh, nv from ct order by dt_id, ngay desc),
  -- người phụ trách (14/10/2026): gán tay (kt_cong_no_pt) > NV bán phiếu gần nhất quy về tên trong Nhân sự (tên hoặc tên trên Kiot) > tên Kiot thô
  ns as (select id, ten, bo_phan_id, array(select lower(btrim(x)) from unnest(ten_kiot || ten) x) ten_kt from kt_nhan_su)
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'ma', d.ma, 'ten', d.ten, 'sdt', d.sdt, 'no', d.no, 'tong', d.tong,
      'cn', coalesce(g.cn, c.chi_nhanh), 'so_ct', coalesce(g.so_ct, 0), 'cu_nhat', g.cu_nhat, 'tuoi', hom - g.cu_nhat,
      'b1', coalesce(g.b1, 0), 'b2', coalesce(g.b2, 0), 'b3', coalesce(g.b3, 0), 'b4', coalesce(g.b4, 0),
      'truoc_2026', greatest(d.no - coalesce(g.da_gan, 0), 0), 'nv', coalesce(ng.ten, nk.ten, c.nv), 'nv_id', coalesce(ng.id, nk.id), 'nv_gan', pt.nhan_su_id is not null, 'nv_kiot', c.nv, 'han', han,
      -- 16/10/2026 (kế toán): tách nợ thật / COD chưa thu hồi / khách chưa lấy hàng (theo hoá đơn đang tính nợ)
      'no_cod', coalesce(g.n_cod, 0), 'no_chua_lay', coalesce(g.n_cl, 0), 'no_tra_hang', coalesce(g.n_tra, 0),
      'no_that', d.no - coalesce(g.n_cod, 0) - coalesce(g.n_cl, 0) - coalesce(g.n_tra, 0), 'tra_lau', coalesce(g.tra_lau, 0), 'coc_ngoai', coalesce(g.coc_ngoai, 0),
      -- tổng các chứng từ đang tính nợ (+ phần nợ trước 2026) · đã thanh toán = tổng − còn nợ · đến hạn = chứng từ nợ cũ nhất + số ngày được nợ
      'tong_ct', coalesce(g.tong_ct, 0) + greatest(d.no - coalesce(g.da_gan, 0), 0), 'den_han', g.cu_nhat + han,
      'qua_han', case when d.no > 0 and g.cu_nhat is not null then greatest(hom - (g.cu_nhat + han), 0) end) order by d.no desc), '[]') into r
    from dt d left join g on g.dt_id = d.id left join cn_cuoi c on c.dt_id = d.id
    left join kt_cong_no_pt pt on pt.loai = p_loai and pt.dt_id = d.id left join ns ng on ng.id = pt.nhan_su_id
    left join lateral (select n.id, n.ten from ns n where c.nv is not null and lower(btrim(c.nv)) = any(n.ten_kt) limit 1) nk on true;
  return r;
end $function$;

CREATE OR REPLACE FUNCTION public.kt_cong_no_dt_ct(p_phien text, p_loai text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; d record; r jsonb;
begin
  perform kt_chan(p_phien, case when p_loai = 'ncc' then 'ncc' else 'khach_hang' end);
  if p_loai = 'ncc' then select id, ma, ten, sdt, cong_no no, tong_nhap tong, null::text loai into d from kt_kiot_ncc where id = p_id;
  else select id, ma, ten, sdt, cong_no no, tong_mua tong, loai::text loai into d from kt_kiot_khach where id = p_id; end if;
  if d.id is null then return null; end if;
  with ct as (
    select id, ma, ngay, chi_nhanh, tong, da_tra, ghi_chu, cod from kt_kiot_hoa_don where p_loai <> 'ncc' and khach_id = p_id and trang_thai in (1, 3)
    union all select id, ma, ngay, chi_nhanh, tong, da_tra, null, null from kt_kiot_nhap_hang where p_loai = 'ncc' and ncc_id = p_id and trang_thai = 3),
  lk as (select ct.*, sum(tong) over (order by ngay desc, id desc) cum from ct where tong > 0)
  select jsonb_build_object(
    'dt', jsonb_build_object('id', d.id, 'ma', d.ma, 'ten', d.ten, 'sdt', d.sdt, 'no', d.no, 'tong', d.tong, 'loai', d.loai),
    'dang_no', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'tong', tong,
        'id', id, 'ghi_chu', ghi_chu, 'cod', cod, 'con_no', least(tong, d.no - (cum - tong)), 'tuoi', hom - (ngay at time zone 'Asia/Ho_Chi_Minh')::date,
        -- 28/10 PA3: phần còn nợ chia theo số tiền + số kế toán nhập tay (nếu có)
        'tach', case when p_loai <> 'ncc' then kt_no_tach_hd(id, least(tong, d.no - (cum - tong)), cod, ghi_chu, ngay, da_tra) end,
        'tay', (select jsonb_build_object('tra_hang', t.tra_hang, 'cod', t.cod, 'chua_lay', t.chua_lay, 'ly_do', t.ly_do, 'sua_boi', t.sua_boi, 'sua_luc', t.sua_luc) from kt_no_tach t where t.hoa_don_id = lk.id))
        order by ngay desc), '[]')
        from lk where d.no > 0 and cum - tong < d.no),
    'gan_day', (select coalesce(jsonb_agg(x order by x->>'ngay' desc), '[]') from (select jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date,
        'cn', chi_nhanh, 'tong', tong, 'da_tra', da_tra) x from ct order by ngay desc limit 15) t),
    'tra_tien', (select coalesce(jsonb_agg(jsonb_build_object('ma', ma, 'ngay', (ngay at time zone 'Asia/Ho_Chi_Minh')::date, 'cn', chi_nhanh, 'so_tien', so_tien,
        'pt', phuong_thuc, 'nd', noi_dung) order by ngay desc), '[]') from (select * from kt_kiot_so_quy
        where la_thu = (p_loai <> 'ncc') and trang_thai = '0' and lower(trim(doi_tac)) = lower(trim(d.ten)) order by ngay desc limit 15) q)) into r;
  return r;
end $function$;
