-- XOÁ KHOẢN VAY KÉO THEO CÁC LẦN NHẬN / TRẢ (29/10/2026, báo lỗi #23). Monsieur Claude
-- Trước: kt_xoa('vay') chỉ ẩn dòng kt_vay → các lần nhận tiền / trả nợ (có gắn tài khoản) vẫn tính vào số dư tài khoản → lệch tiền.
-- Giờ: xoá khoản vay thì ẩn luôn mọi lần nhận / trả còn sống của khoản đó (ghi nhật ký từng dòng).
create or replace function public.kt_xoa(p_phien text, p_bang text, p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare u kt_nguoi_dung; r record;
begin
  u := kt_chan(p_phien, case when p_bang = 'cong_no_thu' then 'cong_no' when p_bang in ('vay_tra', 'vay_nhan') then 'vay' when p_bang = 'tam_ung_hoan' then 'tam_ung' else p_bang end, true);
  if p_bang not in ('thu','chi','dieu_chuyen','cong_no','cong_no_thu','sap_tra','vay','vay_tra','vay_nhan','tai_san','tam_ung','tam_ung_hoan') then raise exception 'Bảng không hợp lệ'; end if;
  execute format('update public.%I set da_xoa = true where id = $1', 'kt_' || p_bang) using p_id;
  if p_bang = 'thu' then update kt_thu set xoa_tay = true where id = p_id; end if;   -- 24/10: đồng bộ Kiot không hồi sinh phiếu người dùng đã xoá
  perform kt_ghi_nhat_ky(u.ho_ten, 'kt_' || p_bang, p_id, 'xoa', null);
  if p_bang = 'vay' then   -- 29/10: kéo theo các lần nhận / trả
    for r in update kt_vay_nhan set da_xoa = true where vay_id = p_id and not da_xoa returning id loop
      perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vay_nhan', r.id, 'xoa', jsonb_build_object('theo_khoan_vay', p_id));
    end loop;
    for r in update kt_vay_tra set da_xoa = true where vay_id = p_id and not da_xoa returning id loop
      perform kt_ghi_nhat_ky(u.ho_ten, 'kt_vay_tra', r.id, 'xoa', jsonb_build_object('theo_khoan_vay', p_id));
    end loop;
  end if;
end $$;

-- Dọn các khoản vay đã xoá trước đây mà lần nhận / trả còn sống
do $$ declare r record;
begin
  for r in update kt_vay_tra t set da_xoa = true from kt_vay v where v.id = t.vay_id and v.da_xoa and not t.da_xoa returning t.id, t.vay_id loop
    perform kt_ghi_nhat_ky('Hệ thống', 'kt_vay_tra', r.id, 'xoa', jsonb_build_object('theo_khoan_vay', r.vay_id, 'ly_do', 'khoản vay đã xoá — báo lỗi #23'));
  end loop;
  for r in update kt_vay_nhan n set da_xoa = true from kt_vay v where v.id = n.vay_id and v.da_xoa and not n.da_xoa returning n.id, n.vay_id loop
    perform kt_ghi_nhat_ky('Hệ thống', 'kt_vay_nhan', r.id, 'xoa', jsonb_build_object('theo_khoan_vay', r.vay_id, 'ly_do', 'khoản vay đã xoá — báo lỗi #23'));
  end loop;
end $$;
