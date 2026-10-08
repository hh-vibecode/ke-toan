// Kiểm thử luồng mới 08/10 (Monsieur Claude): báo cáo Kiot + vay / tài sản. Ghi thử rồi XOÁ CỨNG. Chạy: node scripts/kiem-thu-luong-moi.js
// kiểm thử thêm các hàm luồng mới (đọc) + vay / tài sản (ghi rồi xoá cứng)
const {docKhoa}=require('./khoa');const {sql}=require('./sql');const K=docKhoa();
const H={apikey:K.ANON_KEY,Authorization:'Bearer '+K.ANON_KEY,'Content-Type':'application/json'};
const rpc=async(fn,a)=>{const r=await fetch('https://bcrpxfvvjsjpvbksqzls.supabase.co/rest/v1/rpc/'+fn,{method:'POST',headers:H,body:JSON.stringify(a)});const t=await r.text();return {s:r.status,j:t?JSON.parse(t):null}};
(async()=>{const p=(await rpc('kt_dang_nhap',{p_tk:'hai',p_mk:K.KT_MK_HAI,p_nho:false})).j.phien;let ok=0,loi=0;const kq=(t,d,g)=>{d?ok++:loi++;console.log((d?'ĐẠT ':'LỖI ')+t+(g?' — '+g:''))};
 for(const fn of ['kt_bc_ban_hang','kt_bc_khach','kt_bc_ncc','kt_bc_hang','kt_bc_pl','kt_quy_cua_hang']){const r=await rpc(fn,{p_phien:p,p_tu:'2026-09-01',p_den:'2026-09-30'});kq('đọc '+fn,r.s===200,r.s===200?'':JSON.stringify(r.j).slice(0,150))}
 for(const fn of ['kt_ds_vay','kt_ds_tai_san']){const r=await rpc(fn,{p_phien:p});kq('đọc '+fn,r.s===200,r.s===200?'':JSON.stringify(r.j).slice(0,150))}
 const v=await rpc('kt_luu_vay',{p_phien:p,p_dong:{ten:'KIỂM THỬ vay',so_tien:100000000,ngay_vay:'2026-09-01',lai_suat:9.5,hinh_thuc:'goc_cuoi_ky'}});kq('ghi khoản vay',v.s===200);
 const vt=await rpc('kt_luu_vay_tra',{p_phien:p,p_dong:{vay_id:v.j,ngay:'2026-09-30',goc:10000000,lai:790000,da_tra:true}});kq('ghi lần trả',vt.s===200);
 const dv=(await rpc('kt_ds_vay',{p_phien:p})).j.find(x=>x.id===v.j);kq('dư nợ = 90.000.000, lãi đã trả 790.000',dv&&+dv.so_tien-+dv.goc_da_tra===90000000&&+dv.lai_da_tra===790000,dv&&(dv.so_tien-dv.goc_da_tra)+' · '+dv.lai_da_tra);
 const ts=await rpc('kt_luu_tai_san',{p_phien:p,p_dong:{ten:'KIỂM THỬ tài sản',nguyen_gia:36000000,ngay_mua:'2026-01-15',so_thang_kh:36}});kq('ghi tài sản',ts.s===200);
 const t=(await rpc('kt_ds_tai_san',{p_phien:p,p_den:'2026-10-15'})).j.find(x=>x.id===ts.j);kq('khấu hao 1.000.000/tháng, luỹ kế 9 tháng = 9.000.000',t&&+t.kh_thang===1000000&&+t.kh_luy_ke===9000000,t&&t.kh_thang+' · '+t.kh_luy_ke);
 const pl=(await rpc('kt_bc_pl',{p_phien:p,p_tu:'2026-09-01',p_den:'2026-09-30'})).j;kq('P&L có lãi vay thử 790.000',pl.lai_vay.some(x=>+x.lai===790000));
 await sql(`delete from kt_vay_tra where vay_id in (select id from kt_vay where ten='KIỂM THỬ vay'); delete from kt_vay where ten='KIỂM THỬ vay'; delete from kt_tai_san where ten='KIỂM THỬ tài sản'; delete from kt_nhat_ky where du_lieu::text like '%KIỂM THỬ%'`);
 await rpc('kt_dang_xuat',{p_phien:p});console.log(`\nKẾT QUẢ: ${ok} đạt · ${loi} lỗi (đã xoá dữ liệu thử)`)})();
