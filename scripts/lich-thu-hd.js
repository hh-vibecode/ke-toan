// Lịch kéo "phiếu thu chia hoá đơn" Kiot (Edge kt-kiot, chế độ thu_hd) — 21/11/2026. Monsieur Claude
// Trước: 3 lượt đêm × 3–4 tháng → ban đêm Kiot chậm, quá 150 giây → 504, bảng kt_kiot_hd_thu đứng từ 18/11.
// Nay: 6 lượt đêm × 2 tháng (giờ VN 00:40 · 00:52 · 00:57 · 01:07 · 01:12 · 01:22, né phút 2/17/32/47 của kt-kiot)
//      + lượt ban ngày kt-kiot-thu-hd-ngay mỗi giờ phút 10, 08:10–22:10 VN: chỉ kéo khi có phiếu thu cục mới (kt_thu_hd_can_keo).
// Khoá x-kt-cron chép từ lịch kt-kiot đang chạy, KHÔNG in ra, không nằm trong file.
const { sql } = require('./sql');
const URL_EDGE = 'https://bcrpxfvvjsjpvbksqzls.supabase.co/functions/v1/kt-kiot';
const LICH = [
  ['kt-kiot-thu-hd-1', '40 17 * * *', { thu_hd: { lui: [0, 1] } }],
  ['kt-kiot-thu-hd-2', '52 17 * * *', { thu_hd: { lui: [2, 3] } }],
  ['kt-kiot-thu-hd-3', '57 17 * * *', { thu_hd: { lui: [4, 5] } }],
  ['kt-kiot-thu-hd-4', '7 18 * * *', { thu_hd: { lui: [6, 7] } }],
  ['kt-kiot-thu-hd-5', '12 18 * * *', { thu_hd: { lui: [8, 9] } }],
  ['kt-kiot-thu-hd-6', '22 18 * * *', { thu_hd: { lui: [10, 11] } }],
  ['kt-kiot-thu-hd-ngay', '10 1-15 * * *', { thu_hd: { tu_dong: true } }],
];
(async () => {
  for (const [ten, gio, body] of LICH) {
    // khoá lấy ngay trong SQL từ lệnh của lịch kt-kiot → không qua máy này
    await sql(`do $d$ declare k text := substring((select command from cron.job where jobname = 'kt-kiot') from 'x-kt-cron'', ''([0-9a-f]+)''');
      begin
        if k is null then raise exception 'không đọc được khoá từ lịch kt-kiot'; end if;
        perform cron.unschedule('${ten}') where exists (select 1 from cron.job where jobname = '${ten}');
        perform cron.schedule('${ten}', '${gio}', format($c$select net.http_post(url := '${URL_EDGE}',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-kt-cron', %L), body := '${JSON.stringify(body)}'::jsonb, timeout_milliseconds := 200000)$c$, k));
      end $d$`);
  }
  console.log(JSON.stringify(await sql(`select jobname, schedule, active, substring(command from 'body := ''([^'']+)''') body from cron.job where jobname like 'kt-kiot-thu-hd%' order by jobname`), null, 1));
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
