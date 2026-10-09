-- =========================================================================
-- APP KẾ TOÁN — TRANG "ĐỐI SOÁT LỖI" (anh chốt 09/10/2026) — Monsieur Claude
-- Anh: "phần đối soát lỗi tách riêng ra, sau có lỗi thì m báo vô phần đấy — tham khảo Daily Task của app MKT/Sale".
-- Một hàm gom MỌI loại lỗi thành nhóm (số đếm + danh sách dòng bấm tới chỗ sửa). Chỉ xét từ 01/09/2026 (luồng chuẩn).
--   ai = 'ke_toan' (kế toán sửa) | 'he_thong' (lỗi job / dữ liệu kéo — Claude / người làm app sửa).
-- Thêm loại lỗi mới: thêm 1 khối vào hàm này (+ dòng trên trang Logic).
-- =========================================================================
create or replace function public.kt_doi_soat(p_phien text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; moc date := date '2026-09-01'; hom date := (now() at time zone 'Asia/Ho_Chi_Minh')::date; r jsonb := '[]';
  dong jsonb; v_keo timestamptz; v_bo int;
begin
  u := kt_chan(p_phien);
  if not (kt_co_quyen(u, 'chi') or kt_co_quyen(u, 'tong_quan')) then raise exception 'Tài khoản chưa được cấp quyền xem đối soát' using errcode = '42501'; end if;
  -- chi: mô tả chung 1 dòng
  -- 1. Nghi trùng
  select coalesce(jsonb_agg(jsonb_build_object('bang','chi','id',id,'ngay',coalesce(ngay_tt,ngay_de_nghi),'so_tien',so_tien,'mo_ta',left(noi_dung,90),'chi_tiet','Trùng số tiền với '||nghi_trung) order by id desc), '[]')
    into dong from kt_chi where not da_xoa and nghi_trung is not null and trang_thai <> 'tu_choi';
  r := r || jsonb_build_object('ma','nghi_trung','ten','Phiếu Kiot nghi trùng phiếu đã có','ai','ke_toan','huong_dan','Mở phiếu → "Cùng 1 khoản — gộp" hoặc "2 khoản khác nhau"','ds',dong);
  -- 2. Nghi sai loại chi
  select coalesce(jsonb_agg(jsonb_build_object('bang','chi','id',c.id,'ngay',coalesce(c.ngay_tt,c.ngay_de_nghi),'so_tien',c.so_tien,'mo_ta',left(c.noi_dung,90),
      'chi_tiet',(select ten from kt_loai where id=c.loai_id)||' → nên là '||(kt_nghi_loai(c)->>'loai')) order by c.id desc), '[]')
    into dong from kt_chi c where not c.da_xoa and kt_nghi_loai(c) is not null;
  r := r || jsonb_build_object('ma','nghi_loai','ten','Phiếu chi nghi chọn sai loại','ai','ke_toan','huong_dan','Mở phiếu → "Đổi sang loại theo luật" hoặc "Giữ loại hiện tại"','ds',dong);
  -- 3. Đã thanh toán nhưng thiếu TK / loại (ghi chú gắn lúc chép sheet)
  select coalesce(jsonb_agg(jsonb_build_object('bang','chi','id',id,'ngay',coalesce(ngay_tt,ngay_de_nghi),'so_tien',so_tien,'mo_ta',left(noi_dung,90),
      'chi_tiet',substring(ghi_chu from 'thiếu ([^—\]]+)')) order by id desc), '[]')
    into dong from kt_chi where not da_xoa and trang_thai = 'cho_tt' and ghi_chu like '[Sheet cũ ghi Đã thanh toán nhưng thiếu%' and coalesce(ngay_tt,ngay_de_nghi) >= moc;
  r := r || jsonb_build_object('ma','thieu_tt','ten','Sheet ghi đã thanh toán nhưng thiếu tài khoản / loại chi','ai','ke_toan','huong_dan','Mở phiếu → chọn tài khoản chi, loại chi → "Đã thanh toán"','ds',dong);
  -- 4. Kéo từ sheet cũ, chưa ai bổ sung
  select coalesce(jsonb_agg(jsonb_build_object('bang','chi','id',id,'ngay',coalesce(ngay_tt,ngay_de_nghi),'so_tien',so_tien,'mo_ta',left(noi_dung,90),'chi_tiet','Người đề nghị: '||nguoi_de_nghi) order by id desc), '[]')
    into dong from kt_chi where not da_xoa and sua_boi is null and ghi_chu like '[Kéo từ sheet cũ%' and coalesce(ngay_tt,ngay_de_nghi) >= moc;
  r := r || jsonb_build_object('ma','bo_sung','ten','Phiếu kéo từ sheet cũ cần bổ sung (người đề nghị, chứng từ)','ai','ke_toan','huong_dan','Mở phiếu → "Sửa đề nghị", điền người đề nghị → Lưu (nhãn tự mất)','ds',dong);
  -- 5. HĐ đỏ chưa nhận quá 30 ngày
  select coalesce(jsonb_agg(jsonb_build_object('bang','chi','id',id,'ngay',ngay_tt,'so_tien',so_tien,'mo_ta',left(noi_dung,90),'chi_tiet','Đã trả '||(hom-ngay_tt)||' ngày, chưa nhận HĐ đỏ') order by ngay_tt), '[]')
    into dong from kt_chi where not da_xoa and trang_thai = 'da_tt' and co_hd_do and not hd_do_nhan and ngay_tt >= moc and ngay_tt < hom - 30;
  r := r || jsonb_build_object('ma','hd_do','ten','Hoá đơn đỏ chưa nhận quá 30 ngày','ai','ke_toan','huong_dan','Đòi HĐ nhà cung cấp; nhận rồi thì mở phiếu tick "Đã nhận hoá đơn đỏ"','ds',dong);
  -- 6. Điều chuyển chưa xác nhận
  select coalesce(jsonb_agg(jsonb_build_object('bang','dieu_chuyen','id',d.id,'ngay',d.ngay,'so_tien',d.so_tien,'mo_ta',left(d.noi_dung,90),
      'chi_tiet',coalesce((select ten from kt_tai_khoan where id=d.tk_di_id),'?')||' → '||coalesce((select ten from kt_tai_khoan where id=d.tk_nhan_id),'?')) order by d.ngay), '[]')
    into dong from kt_dieu_chuyen d where not d.da_xoa and not d.da_xac_nhan and d.ngay >= moc;
  r := r || jsonb_build_object('ma','dc','ten','Điều chuyển chưa xác nhận','ai','ke_toan','huong_dan','Mở điều chuyển → tick "Kế toán đã xác nhận"','ds',dong);
  -- 7. Chi quá hạn mong muốn trả
  select coalesce(jsonb_agg(jsonb_build_object('bang','chi','id',id,'ngay',han_tt,'so_tien',so_tien,'mo_ta',left(noi_dung,90),'chi_tiet','Quá hạn '||(hom-han_tt)||' ngày · '||kt_ten_tt_chi(trang_thai)) order by han_tt), '[]')
    into dong from kt_chi where not da_xoa and trang_thai in ('cho_duyet','cho_gd','cho_tt') and han_tt < hom;
  r := r || jsonb_build_object('ma','qua_han','ten','Chi quá hạn mong muốn trả','ai','ke_toan','huong_dan','Duyệt / thanh toán hoặc từ chối','ds',dong);
  -- 8 + 9. Tài khoản: tồn âm · lệch số dư thực tế (sao kê / đếm két) với sổ sách
  with so as (select tk.id, tk.ten, tk.ton_dau + coalesce((select sum(b.vao-b.ra) from kt_v_bien_dong b where b.tai_khoan_id=tk.id and b.ngay>=tk.ngay_ton_dau),0) cuoi
                from kt_tai_khoan tk where tk.hoat_dong)
  select coalesce(jsonb_agg(jsonb_build_object('bang','tai_khoan','id',id,'ngay',hom,'so_tien',cuoi,'mo_ta',ten,'chi_tiet','Số dư sổ sách âm') order by cuoi), '[]')
    into dong from so where cuoi < 0;
  r := r || jsonb_build_object('ma','tk_am','ten','Tài khoản số dư sổ sách bị âm','ai','ke_toan','huong_dan','Thường do thiếu phiếu thu / điều chuyển vào, hoặc chi ghi nhầm tài khoản — đối chiếu sao kê','ds',dong);
  with tt as (select distinct on (t.tai_khoan_id) t.tai_khoan_id, t.ngay, t.so_tien from kt_ton_thuc_te t where t.ngay >= moc order by t.tai_khoan_id, t.ngay desc),
   so as (select tt.*, tk.ten, tk.ton_dau + coalesce((select sum(b.vao-b.ra) from kt_v_bien_dong b where b.tai_khoan_id=tk.id and b.ngay>=tk.ngay_ton_dau and b.ngay<=tt.ngay),0) so_sach
            from tt join kt_tai_khoan tk on tk.id = tt.tai_khoan_id)
  select coalesce(jsonb_agg(jsonb_build_object('bang','tai_khoan','id',tai_khoan_id,'ngay',ngay,'so_tien',so_sach-so_tien,'mo_ta',ten,
      'chi_tiet','Sổ sách '||replace(to_char(so_sach,'FM999G999G999G990'),',','.')||' · thực tế '||replace(to_char(so_tien,'FM999G999G999G990'),',','.')) order by abs(so_sach-so_tien) desc), '[]')
    into dong from so where so_sach <> so_tien;
  r := r || jsonb_build_object('ma','lech_so_du','ten','Số dư sổ sách lệch số dư thực tế (sao kê / đếm két)','ai','ke_toan','huong_dan','Mở Dòng tiền → tài khoản đó → tìm ngày bắt đầu lệch','ds',dong);
  -- 9b. Hoá đơn 3TShop ngày sai năm (ngoài 01/01/2025 → hôm nay) — kế toán sửa trên file xuất 3TShop
  select coalesce(jsonb_agg(jsonb_build_object('bang','thue','id',id,'ngay',ngay,'so_tien',thanh_tien,'mo_ta',case hkd when 'HT' then 'Hiền Thủy' when 'CT' then 'Chánh Tâm' else 'Shidai' end||' · '||case chieu when 'ra' then 'HĐ bán' else 'nhập' end||' '||coalesce(so_hd,'')||' · '||left(coalesce(ten,''),50),
      'chi_tiet','Ngày '||coalesce(to_char(ngay,'DD/MM/YYYY'),'trống')||' — sai năm?') order by hkd, dong), '[]')
    into dong from kt_thue_hd where ngay is null or ngay not between date '2025-01-01' and hom + 1;
  r := r || jsonb_build_object('ma','thue_ngay','ten','Hoá đơn 3TShop ghi ngày sai năm','ai','ke_toan','huong_dan','Sửa ngày trên file 3TShop xuất ra rồi báo Claude kéo lại','ds',dong);
  -- 10–12. Lỗi hệ thống
  select max(keo_luc) into v_keo from kt_kiot_so_quy;
  select coalesce(jsonb_agg(jsonb_build_object('bang','nhat_ky','id',id,'ngay',(luc at time zone 'Asia/Ho_Chi_Minh')::date,'mo_ta','Job kéo Kiot lỗi','chi_tiet',left(du_lieu->>'loi',120)) order by id desc), '[]')
    into dong from kt_nhat_ky where hanh_dong = 'keo_kiot_loi' and luc > now() - interval '3 days'
      and id > (select coalesce(max(id), 0) from kt_nhat_ky where hanh_dong = 'keo_kiot');   -- lỗi đã có lần chạy thành công sau đó = đã hết
  if v_keo is null or v_keo < now() - interval '6 hours' then
    dong := dong || jsonb_build_array(jsonb_build_object('bang','he_thong','id',0,'ngay',hom,'mo_ta','Kiot quá 6 giờ chưa kéo được','chi_tiet','Lần kéo gần nhất: '||coalesce(to_char(v_keo at time zone 'Asia/Ho_Chi_Minh','HH24:MI DD/MM'),'chưa có')));
  end if;
  select (du_lieu->'so_quy'->'dong_bo'->>'bo_qua_khong_ghep_tk')::int into v_bo from kt_nhat_ky where hanh_dong = 'keo_kiot' order by id desc limit 1;
  if coalesce(v_bo,0) > 0 then dong := dong || jsonb_build_array(jsonb_build_object('bang','he_thong','id',0,'ngay',hom,'mo_ta','Phiếu thu Kiot không ghép được tài khoản','chi_tiet',v_bo||' phiếu bị bỏ qua — tài khoản Kiot mới chưa có trong danh mục app')); end if;
  if not exists (select 1 from kt_ton_kho_ngay where ngay >= hom - 1) and extract(hour from now() at time zone 'Asia/Ho_Chi_Minh') >= 1 then
    dong := dong || jsonb_build_array(jsonb_build_object('bang','he_thong','id',0,'ngay',hom,'mo_ta','Chụp tồn kho cuối ngày bị lỡ','chi_tiet','Không có bản chụp tồn kho hôm qua'));
  end if;
  r := r || jsonb_build_object('ma','he_thong','ten','Lỗi hệ thống (job Kiot, tồn kho)','ai','he_thong','huong_dan','Không phải lỗi nhập liệu — báo Claude / người làm app','ds',dong);
  return r;
end $$;
revoke execute on function public.kt_doi_soat(text) from public;
grant execute on function public.kt_doi_soat(text) to anon, authenticated;
