-- Bỏ mục "Hoá đơn 3TShop ghi ngày sai năm" khỏi Đối soát lỗi (16/10/2026, anh Hải: "clear cái này đi, tương tự không care nữa") — Monsieur Claude
-- Chỉ bỏ cảnh báo; dữ liệu hoá đơn (kt_thue_hd) giữ nguyên. Vá trên định nghĩa đang chạy.
do $$
declare d text; n int;
begin
  d := pg_get_functiondef('public.kt_doi_soat'::regproc);
  n := length(d);
  d := replace(d, $a$into dong from kt_thue_hd where ngay is null or ngay not between date '2025-01-01' and hom + 1;$a$,
                  $a$into dong from kt_thue_hd where false;   -- 16/10 anh: không theo dõi ngày sai năm nữa$a$);
  d := replace(d, $a$  r := r || jsonb_build_object('ma','thue_ngay','ten','Hoá đơn 3TShop ghi ngày sai năm','ai','ke_toan','huong_dan','Sửa ngày trên file 3TShop xuất ra rồi báo Claude kéo lại','ds',dong);$a$,
                  $a$  -- (16/10) bỏ nhóm ngày sai năm — anh không theo dõi nữa$a$);
  if length(d) = n then raise exception 'khong thay nhom thue_ngay'; end if;
  if d ~ '''thue_ngay''' then raise exception 'nhom thue_ngay van con'; end if;
  execute d;
end $$;
