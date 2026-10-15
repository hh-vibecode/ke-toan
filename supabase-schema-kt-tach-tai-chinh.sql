-- TÁCH LOẠI CHI TÀI CHÍNH (15/10/2026, anh: "1 tháng không thể chi mấy tỉ, chắc chắn có sai sót" → "sửa đi"). Monsieur Claude
-- Loại "FINANCE - Tài chính - vay,lãi" gộp cả TRẢ GỐC VAY (~4,9 tỷ T5–T10) + trả thẻ tín dụng → Tổng chi bị đội lên mấy tỷ / tháng.
-- Tách 3 loại: Trả gốc vay (không phải chi phí — chỉ là trả lại tiền mượn) · Trả thẻ tín dụng · Lãi vay & phí tài chính (đổi tên loại cũ).
-- Cả 3 nhóm báo cáo "Chi tài chính" → P&L không đổi (chỉ lấy OPEX), Dòng tiền xếp vào hoạt động tài chính.
-- Xếp lại phiếu cũ theo nội dung, mỗi phiếu ghi nhật ký (gỡ được). Xoá 2 phiếu trùng từ sheet cũ (#1472, #1473).

insert into kt_loai (nhom, ten, nhom_bc, cach_chia, thu_tu)
select 'chi', t, 'Chi tài chính', 'rieng', tt from (values ('FINANCE - Trả gốc vay', 121), ('FINANCE - Trả thẻ tín dụng', 122)) v(t, tt)
where not exists (select 1 from kt_loai where nhom = 'chi' and ten = v.t);
update kt_loai set ten = 'FINANCE - Lãi vay & phí tài chính' where id = 13 and ten = 'FINANCE - Tài chính - vay,lãi';

with m as (select id, ten from kt_loai where nhom = 'chi' and ten in ('FINANCE - Trả gốc vay', 'FINANCE - Trả thẻ tín dụng')),
x as (
  select c.id, c.loai_id cu,
    case when c.noi_dung ~* '(sao ke|sao kê|visa|thẻ tín dụng|the tin dung|\mSK\M|credit card)' then 'FINANCE - Trả thẻ tín dụng'
         when c.noi_dung ~* '(gốc|\mgoc\M)'
           or (c.noi_dung ~* '(thu no|thu nợ|tk ?vay|tkvay|tai khoan vay|tài khoản vay|tra no tk|trả nợ tk|tra no vay|trả nợ vay|tat toan tai khoan vay|thau chi|thấu chi|khoản vay|khoan vay)'
               and c.noi_dung !~* '(lãi|\mlai\M|\mphi\M|phí)') then 'FINANCE - Trả gốc vay' end moi
    from kt_chi c where not c.da_xoa and c.loai_id = 13),
u as (update kt_chi c set loai_id = m.id from x join m on m.ten = x.moi where c.id = x.id returning c.id, m.ten)
insert into kt_nhat_ky (nguoi, bang, dong_id, hanh_dong, du_lieu)
select 'Hệ thống', 'kt_chi', u.id, 'tach_loai_tai_chinh', jsonb_build_object('loai_cu', 'FINANCE - Tài chính - vay,lãi', 'loai_moi', u.ten) from u;

-- luật loại chi: trả thẻ → loại thẻ mới; thêm luật trả gốc vay
update kt_luat_loai_chi set loai_id = (select id from kt_loai where nhom = 'chi' and ten = 'FINANCE - Trả thẻ tín dụng') where id = 9;
insert into kt_luat_loai_chi (thu_tu, ten, mau, loai_id, hoat_dong)
select (select coalesce(max(thu_tu), 0) + 10 from kt_luat_loai_chi), 'Ngân hàng thu nợ / trả gốc khoản vay',
       'thu no tkv|thu no tk ?vay|thanh toan tk ?vay|tra no tk vay|trả nợ tk vay|tat toan tai khoan vay', (select id from kt_loai where nhom = 'chi' and ten = 'FINANCE - Trả gốc vay'), true
where not exists (select 1 from kt_luat_loai_chi where ten = 'Ngân hàng thu nợ / trả gốc khoản vay');

-- 2 phiếu trùng (sheet cũ kéo 2 lần, cùng nội dung, số tiền, ngày): ẩn bản sau
update kt_chi set da_xoa = true, ghi_chu = concat_ws(' ', ghi_chu, '[Trùng phiếu #' || case id when 1473 then 1060 else 1061 end || ' — kéo từ sheet cũ 2 lần, ẩn 15/10/2026]')
 where id in (1472, 1473) and not da_xoa
   and exists (select 1 from kt_chi o where o.id = case kt_chi.id when 1473 then 1060 else 1061 end and not o.da_xoa and o.so_tien = kt_chi.so_tien and o.noi_dung = kt_chi.noi_dung);
insert into kt_nhat_ky (nguoi, bang, dong_id, hanh_dong, du_lieu)
select 'Hệ thống', 'kt_chi', id, 'xoa', jsonb_build_object('ly_do', 'trùng phiếu kéo từ sheet cũ') from kt_chi where id in (1472, 1473) and da_xoa
  and not exists (select 1 from kt_nhat_ky k where k.bang = 'kt_chi' and k.dong_id = kt_chi.id and k.hanh_dong = 'xoa');
