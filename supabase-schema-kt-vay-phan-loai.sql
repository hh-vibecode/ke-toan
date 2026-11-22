-- 26/10/2026 (anh): "khoản vay & lãi vay cho lọc theo từng ngân hàng, theo khoản cá nhân hoặc công ty, ngắn hạn hoặc trung dài hạn, với tài sản đảm bảo".
-- kt_vay thêm: chu_vay ('cong_ty' / 'ca_nhan'), ky_han ('ngan' / 'trung_dai'), co_tsdb (true = có TSĐB, false = tín chấp, null = chưa nhập), tsdb (mô tả tài sản).
-- Phân loại sẵn dữ liệu cũ: tên có "cá nhân" → cá nhân; đáo hạn > 12 tháng (+7 ngày) sau ngày vay → trung dài hạn, khoản hạn mức / ngắn hạn không ngày đáo hạn → ngắn hạn.
-- Gộp tên ngân hàng VCB → Vietcombank. kt_luu_vay lưu thêm 4 trường (định nghĩa lấy từ CSDL 26/10, chèn 1 lệnh update trước ghi nhật ký). — Monsieur Claude
alter table kt_vay add column if not exists chu_vay text check (chu_vay in ('cong_ty', 'ca_nhan'));
alter table kt_vay add column if not exists ky_han text check (ky_han in ('ngan', 'trung_dai'));
alter table kt_vay add column if not exists co_tsdb boolean;
alter table kt_vay add column if not exists tsdb text;

update kt_vay set ben_cho_vay = 'Vietcombank' where ben_cho_vay = 'VCB';
update kt_vay set chu_vay = case when ten ilike '%cá nhân%' then 'ca_nhan' else 'cong_ty' end where chu_vay is null;
update kt_vay set ky_han = case when ngay_dao_han is not null and ngay_dao_han > (ngay_vay + interval '12 months' + interval '7 days')::date then 'trung_dai'
                                when ngay_dao_han is not null then 'ngan'
                                when ten ~* '(hạn mức|thấu chi|khế ước|TK vay 40)' then 'ngan' end
 where ky_han is null;

do $do$
declare d text := pg_get_functiondef('kt_luu_vay'::regproc); a text := '  perform kt_ghi_nhat_ky(u.ho_ten, ''kt_vay'', v_id,';
begin
  if position('chu_vay' in d) > 0 then return; end if;
  if position(a in d) = 0 then raise exception 'kt_luu_vay đã đổi — không chèn được'; end if;
  d := replace(d, a, '  -- 26/10: phân loại (lọc trang Vay)' || chr(10) ||
    '  update kt_vay set chu_vay = coalesce(nullif(p_dong->>''chu_vay'', ''''), chu_vay), ky_han = coalesce(nullif(p_dong->>''ky_han'', ''''), ky_han),' || chr(10) ||
    '         co_tsdb = case when p_dong ? ''co_tsdb'' then nullif(p_dong->>''co_tsdb'', '''')::boolean else co_tsdb end,' || chr(10) ||
    '         tsdb = case when p_dong ? ''tsdb'' then nullif(trim(p_dong->>''tsdb''), '''') else tsdb end where id = v_id;' || chr(10) || a);
  execute d;
end $do$;
