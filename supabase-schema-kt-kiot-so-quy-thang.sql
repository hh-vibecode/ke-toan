-- 23/11/2026 (VIEC 417): phiếu thu Kiot lập / sửa LÙI NGÀY (vd TT012123 lập 23/11, ngày phiếu 04/11) không vào app tới 23:50
-- vì lượt kéo 15 phút chỉ quét sổ quỹ 10 ngày gần nhất theo ngày phiếu. Anh: "thêm phiên 16h" → rồi "2h / lần": lịch 2 tiếng / lần 08:25–22:25 VN (phút 25 né lượt kéo 15 phút :17 / :32 và thu-hd-ngay :10)
-- quét sổ quỹ từ đầu tháng (10 ngày đầu tháng quét từ đầu tháng trước) + chép phiếu thu sang app. Chạy thử 863 phiếu / 6 giây.
-- Khoá cron lấy từ lịch kt-kiot-doi-chieu lúc chạy, không ghi vào file. Monsieur Claude
select cron.schedule('kt-kiot-so-quy-thang', '25 1-15/2 * * *', $c$
  select public.kt_goi_edge('kt-kiot-so-quy-thang', 'kt-kiot',
    jsonb_build_object('tu', to_char(date_trunc('month', (now() at time zone 'Asia/Ho_Chi_Minh') - interval '10 days'), 'YYYY-MM-DD'), 'chi', jsonb_build_array('so_quy')),
    (select (regexp_match(command, '''([0-9a-f]{40,})'''))[1] from cron.job where jobname = 'kt-kiot-doi-chieu'), 150000)
$c$);
