-- 21/10/2026 (kế toán: "báo cáo P&L thiết kế như sheet, đầu mục cha có nút ẩn / hiện chi tiết; sửa các khoản đầu mục nhóm chi phí cho khớp danh mục này")
-- Danh mục chi phí 2–3 cấp theo sheet BÁO CÁO P&L: 9 nhóm cha (mã 1–9) + mục con (1.1, 5.1.1…). Loại OPEX cũ ẩn (hoat_dong = false),
-- gắn vào nhóm tương ứng để phiếu chưa gán lại vẫn cộng đúng nhóm. Phiếu cũ được hệ thống tự gán sang mục con (cột gan_loai_tu_dong: 'vua' / 'thap'
-- = cần kế toán soát; tự xoá khi đổi loại hoặc bấm xác nhận). — Monsieur Claude
alter table kt_loai add column if not exists cha_id int references kt_loai(id), add column if not exists ma text, add column if not exists la_nhom boolean not null default false;
alter table kt_chi add column if not exists gan_loai_tu_dong text;

do $$
declare g int; c int; nb text := 'Chi vận hành & quản lí';
  ds jsonb := '[
   ["1","Chi phí nhân sự",[["1.1","Chi phí lương BHXH nhân sự trực tiếp"],["1.2","Quỹ hoa hồng cửa hàng"]]],
   ["2","Chi phí BP Sales Online phân bổ",[]],
   ["3","Chi phí vận hành kho tổng phân bổ",[["3.1","Chi phí lương kho phân bổ"],["3.2","Chi phí thuê kho"],["3.3","Chi phí sửa chữa & khấu hao kho"],["3.4","Chi phí khác kho tổng phân bổ"]]],
   ["4","Chi phí tổng công ty phân bổ",[["4.1","Chi phí lương BGĐ"],["4.2","Chi phí lương BP Backoffice"],["4.3","Chi phí văn phòng & hành chính"],["4.4","Chi phí phần mềm & hệ thống"],["4.5","Chi phí kế toán - thuế - pháp lý"],["4.6","Chi phí ngân hàng - tài chính"],["4.7","Chi phí truyền thông công ty (không gắn sales)"],["4.8","Chi phí truyền thông nội bộ"],["4.9","Chi phí nghiên cứu & phát triển (R&D)"],["4.10","Chi phí đào tạo & phát triển nhân sự"],["4.11","Chi phí khác tổng công ty phân bổ"]]],
   ["5","Chi phí marketing",[["5.1","Chi phí dịch vụ MKT thuê ngoài"],["5.2","Chi phí chạy ads"],["5.3","Phần mềm hỗ trợ MKT"]]],
   ["6","Chi phí cửa hàng",[["6.1","Chi phí thuê cửa hàng"],["6.2","Tiền điện"],["6.3","Tiền nước"],["6.4","Tiền điện thoại"],["6.5","Tiền Internet"]]],
   ["7","Chi phí đóng gói & vận chuyển",[["7.1","Vật tư tiêu hao: bao bì, băng dính"],["7.2","Phí vận chuyển"]]],
   ["8","Chi phí sửa chữa & khấu hao",[["8.1","Chi phí sửa chữa bảo hành TSCĐ"],["8.2","Khấu hao công cụ dụng cụ, tài sản"]]],
   ["9","Chi phí khác",[["9.1","Văn phòng phẩm"],["9.2","Phí ngân hàng"],["9.3","Các chi phí khác"],["9.4","Chi phí hỏng huỷ"]]]]';
  n jsonb; k jsonb; i int := 0; j int;
begin
  if exists (select 1 from kt_loai where nhom = 'chi' and ma = '1') then return; end if;   -- chạy 1 lần
  for n in select * from jsonb_array_elements(ds) loop
    i := i + 1;
    insert into kt_loai (nhom, ten, nhom_bc, thu_tu, hoat_dong, ma, la_nhom)
    values ('chi', n->>1, nb, 1000 + i * 100, true, n->>0, jsonb_array_length(n->2) > 0) returning id into g;
    j := 0;
    for k in select * from jsonb_array_elements(n->2) loop
      j := j + 1;
      insert into kt_loai (nhom, ten, nhom_bc, thu_tu, hoat_dong, ma, cha_id) values ('chi', k->>1, nb, 1000 + i * 100 + j * 5, true, k->>0, g) returning id into c;
      if k->>0 = '5.1' then
        insert into kt_loai (nhom, ten, nhom_bc, thu_tu, hoat_dong, ma, cha_id) values
          ('chi','Chi phí bài SEO Web',nb,1000+i*100+j*5+1,true,'5.1.1',c),('chi','Thiết kế',nb,1000+i*100+j*5+2,true,'5.1.2',c),
          ('chi','Quay dựng video',nb,1000+i*100+j*5+3,true,'5.1.3',c),('chi','Chụp ảnh',nb,1000+i*100+j*5+4,true,'5.1.4',c),('chi','Cố vấn hình ảnh',nb,1000+i*100+j*5+4,true,'5.1.5',c);
      end if;
    end loop;
  end loop;
  -- loại OPEX cũ: ẩn, gắn vào nhóm mới (phiếu chưa gán lại vẫn cộng đúng nhóm)
  update kt_loai o set hoat_dong = false, cha_id = (select id from kt_loai x where x.nhom = 'chi' and x.ma = m.ma)
    from (values (6,'1'),(7,'5'),(8,'6'),(9,'7'),(10,'4'),(11,'9')) m(id, ma) where o.id = m.id;
  -- quy tắc tự gán loại: trỏ sang mục con mới
  update kt_luat_loai_chi r set loai_id = (select id from kt_loai x where x.nhom = 'chi' and x.ma = m.ma)
    from (values (10,'9.2'),(13,'6.2'),(14,'9.3'),(15,'9.3'),(16,'9.3')) m(id, ma) where r.id = m.id;
end $$;
