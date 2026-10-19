-- Bỏ tên "Claude" khỏi dữ liệu app (anh 13/10: không ký tên trên giao diện / dữ liệu). Dấu ghi chú tự gán loại chi đổi thành "Hệ thống". — Monsieur Claude 19/10/2026
update kt_chi set ghi_chu = replace(ghi_chu, '[Claude gán loại chi', '[Hệ thống gán loại chi') where ghi_chu like '%[Claude gán loại chi%';
select count(*) con_lai from kt_chi where ghi_chu like '%Claude%';
update kt_cau_hoi set giai_thich = replace(replace(giai_thich, 'Claude', 'hệ thống'), 'claude', 'hệ thống'), tra_loi = replace(replace(tra_loi, 'Claude', 'hệ thống'), 'claude', 'hệ thống')
 where giai_thich ilike '%claude%' or tra_loi ilike '%claude%';
