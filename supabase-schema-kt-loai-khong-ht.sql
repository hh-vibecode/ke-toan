-- 24/10/2026 kế toán (anh chuyển): bổ sung loại chi KHÔNG HẠCH TOÁN — "CP vận chuyển đã tính vào giá vốn; hoàn hàng đã tính trong phần trả hàng ở Kiot".
-- Cùng kiểu "Chi thanh toán tiền hàng" (#5) / "Chi đặt cọc" (#112): nhóm chi, không cha, không mã → ô Loại chi khi chọn "Không hạch toán". Monsieur Claude
insert into kt_loai (nhom, ten, nhom_bc, cach_chia, thu_tu, hoat_dong)
select 'chi', t.ten, 'Chi nhập hàng', 'rieng', t.tt, true from (values ('CP vận chuyển đã tính vào giá vốn', 3), ('Hoàn hàng đã tính trong trả hàng Kiot', 4)) t(ten, tt)
where not exists (select 1 from kt_loai l where l.nhom = 'chi' and l.ten = t.ten);
