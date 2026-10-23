-- 23/10/2026 (anh: "PDF HĐ bán ra cho phiếu thu — nó có cho kéo ảnh không"): API meInvoice có POST /invoice/Download?downloadDataType=Pdf
-- theo TransactionID (mã tra cứu) → file PDF đã ký số. Lưu mã tra cứu vào kt_thue_hd.ma_ngoai khi kéo HĐ bán ra (kt_nap_meinvoice),
-- Edge kt-meinvoice tải PDF các HĐ đã gắn phiếu thu vào chứng từ phiếu (thu/{thu}/misa_{ký hiệu-số}.pdf). — Monsieur Claude
create or replace function public.kt_nap_meinvoice(p_thang text, p_ds jsonb) returns integer
  language plpgsql security definer set search_path = public as $f$
declare n int;
begin
  if p_thang !~ '^\d{4}-\d{2}$' then raise exception 'tháng sai: %', p_thang; end if;
  delete from kt_thue_hd where nguon = 'meinvoice:' || p_thang;
  insert into kt_thue_hd (hkd, chieu, so_hd, mau, ky_hieu, ngay, mst, nguoi_mua, ten, thanh_tien, tien_thue, tong, ghi_chu, nguon, ma_ngoai)
  select 'CTY', 'ra', x->>'so_hd', x->>'mau', x->>'ky_hieu', (x->>'ngay')::date, nullif(x->>'mst', ''), x->>'nguoi_mua', x->>'ten',
         (x->>'thanh_tien')::numeric, (x->>'tien_thue')::numeric, (x->>'tong')::numeric, nullif(x->>'ghi_chu', ''), 'meinvoice:' || p_thang, nullif(x->>'ma', '')
    from jsonb_array_elements(p_ds) x;
  get diagnostics n = row_count;
  return n;
end $f$;

-- HĐ bán ra đã gắn phiếu thu, có mã tra cứu, chưa có PDF trong chứng từ
create or replace function public.kt_hd_ra_can_pdf(p_n int default 20) returns table(thu_id bigint, hd_ma text, so_hd text, ky_hieu text, ma_tra_cuu text)
  language sql stable security definer set search_path = public as $f$
  select g.thu_id, g.hd_ma, g.so_hd, g.ky_hieu, max(t.ma_ngoai) from kt_thu_hd g
    join kt_thue_hd t on t.nguon like 'meinvoice:%' and t.ky_hieu || '-' || t.so_hd = g.hd_ma and t.ma_ngoai is not null
   where not exists (select 1 from kt_chung_tu k where k.duong_dan = 'thu/' || g.thu_id || '/misa_' || g.hd_ma || '.pdf')
   group by 1, 2, 3, 4 order by max(g.luc) desc limit p_n $f$;
revoke all on function public.kt_hd_ra_can_pdf(int), public.kt_nap_meinvoice(text, jsonb) from anon, authenticated, public;
