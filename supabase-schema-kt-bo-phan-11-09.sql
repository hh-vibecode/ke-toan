-- 09/11/2026 kế toán (anh chuyển): (3) "Trong phiếu DNTT bỏ bớt BP thị trường và BP sales onl ra" → bỏ dấu "là bộ phận đề nghị chi" (la_bo_phan)
--   — 2 đơn vị vẫn còn (cơ sở chịu chi phí, phân bổ, báo cáo); phiếu cũ giữ nguyên bộ phận (form phiếu chi app vẫn hiện bộ phận đang chọn).
-- (4) "Kho Shidai đổi thành BP Sales Sỉ" → đơn vị 4 đổi tên (tên cũ lưu ten_cu để file / sheet cũ vẫn khớp); nhãn cơ sở trên báo cáo đổi ở index.html (CS3). — Monsieur Claude
update kt_don_vi set la_bo_phan = false where id in (5, 6);
update kt_don_vi set ten = 'BP Sales Sỉ', ten_cu = (select array_agg(distinct x) from unnest(coalesce(ten_cu, '{}') || array['BP Sỉ Shidai', 'Kho Shidai']) x) where id = 4;
