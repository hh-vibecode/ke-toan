-- DỌN NHÀ HÀNG AMHP (Saikung / Hongkong) KHỎI APP KẾ TOÁN (12/10/2026) — Monsieur Claude
-- Anh 12/10: "cái gì liên quan tới nhà hàng clear hết khỏi app này". 2 nhà hàng AMHP là dịch vụ khác (đã tháo dỡ đầu 2026), không thuộc app.
-- DỌN: 2 đơn vị "Nhà Hàng Saikung AMHP" / "Nhà Hàng Hongkong AMHP" · phiếu chi vận hành / tháo dỡ 2 nhà hàng · phiếu thu Kiot của nhà hàng
--       (bán đồ nhà hàng, AEON hoàn cọc mặt bằng). Phiếu ẩn (da_xoa) chứ không xoá cứng — vẫn tra lại được nếu cần.
-- GIỮ: chi tiếp khách / liên hoan ở nhà hàng NGOÀI và khách mua đồ thờ có tên "nhà hàng" (chi phí / doanh thu của việc bán đồ thờ).
-- Tất cả phiếu dọn đều TRƯỚC 01/09/2026 → không ảnh hưởng số dư tài khoản (app tính số dư từ tồn đầu 01/09).
-- Kiot: bảng kt_bo_qua_nguon chặn kt_dong_bo_kiot() chép lại (sửa trong supabase-schema-kt-kiot.sql).

create table if not exists public.kt_bo_qua_nguon (
  ma_nguon text primary key, ly_do text not null, luc timestamptz not null default now());
alter table public.kt_bo_qua_nguon enable row level security;
revoke all on public.kt_bo_qua_nguon from anon, authenticated;

-- Phiếu thu Kiot của nhà hàng (theo mã nguồn, không theo số tiền)
insert into kt_bo_qua_nguon (ma_nguon, ly_do)
select ma_nguon, 'Nhà hàng AMHP — không thuộc app (anh 12/10/2026)' from kt_thu where id in (22375, 23583, 23106, 15358, 15359) and ma_nguon is not null
on conflict (ma_nguon) do nothing;
update kt_thu set da_xoa = true, sua_luc = now(), sua_boi = 'Hệ thống (dọn nhà hàng AMHP — anh 12/10)'
 where id in (22375, 23583, 23106, 15358, 15359) and not da_xoa;

-- Phiếu chi của 2 nhà hàng (vận hành tháng 12–2, tháo dỡ, liên hoan chia tay nhân sự nhà hàng)
update kt_chi set da_xoa = true, bo_phan_id = null, sua_luc = now(), sua_boi = 'Hệ thống (dọn nhà hàng AMHP — anh 12/10)',
       ghi_chu = concat_ws(' · ', nullif(ghi_chu, ''), 'Ẩn 12/10/2026: nhà hàng AMHP, không thuộc app')
 where id in (1105, 1119, 1120, 1076, 1307, 1375, 1128, 1157, 1182, 1317, 1319, 1332, 1362, 899) and not da_xoa;
update kt_chi set bo_phan_id = null where bo_phan_id in (select id from kt_don_vi where ten ~* 'nhà hàng');

-- 2 đơn vị nhà hàng
delete from kt_don_vi where ten ~* 'nhà hàng' and id not in (select don_vi_id from kt_thu where don_vi_id is not null
  union select don_vi_id from kt_cong_no where don_vi_id is not null union select don_vi_id from kt_tai_san where don_vi_id is not null);

-- câu hỏi đã trả lời về 2 ký hiệu hoá đơn nhà hàng
delete from kt_cau_hoi where tieu_de like 'Hong Kong Center và Saikung Hot Pot%';
