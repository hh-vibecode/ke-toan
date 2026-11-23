// BẢNG LỊCH CHẠY GỌI EDGE của app kế toán — 1 nguồn duy nhất (21/11/2026, anh: "rà lại hết lịch chạy, sắp xếp lại cho hợp lý"). Monsieur Claude
// Chạy: node scripts/lich-kt.js  → đặt lại đúng các lịch dưới đây (lịch SQL thuần không đụng). Thêm / đổi lịch Edge: sửa ở ĐÂY rồi chạy lại.
// Mọi lịch gọi qua kt_goi_edge (supabase-schema-kt-lich-soat.sql) → ghi kt_lich_goi → kt_lich_soat (phút 08, 38) soát kết quả thật + chuông.
// Khoá x-kt-cron lấy ngay trong SQL từ lệnh lịch kt-kiot đang chạy → không qua máy này, không nằm trong file.
// Giờ trong cột "gio" là giờ máy chủ (UTC) = giờ VN − 7. Nguyên tắc xếp:
//   - Edge bị cắt ở 150 giây → mỗi lượt giữ < 95 giây (lượt dài thì tách); Edge tự dừng ở 95 giây và ghi phần bỏ lại.
//   - Việc gọi Kiot ban đêm không chồng nhau, né phút 02 / 17 / 32 / 47 (kéo Kiot 15 phút); việc gọi MISA để riêng.
//   - Việc phụ thuộc chạy sau việc nó cần: kéo đủ hàng 23:20 → chụp tồn 23:40; HĐ MISA 00:25–00:35 → ghép / tính sao kê 01:30.
const { sql } = require('./sql');
const LICH = [
  // [tên lịch, giờ UTC, Edge, body, chờ tối đa (ms), điều kiện SQL (tuỳ chọn)]
  ['kt-kiot',              '2,17,32,47 * * * *', 'kt-kiot', {}, 170000],                                      // 15 phút / lần
  ['kt-kiot-hang-dem',     '20 16 * * *', 'kt-kiot', { day_du: ['hang'] }, 170000],                          // 23:20 VN — ~40 giây
  ['kt-kiot-doi-chieu',    '50 16 * * *', 'kt-kiot', { doi_chieu: { lich: 'thang' } }, 170000],              // 23:50 VN — tháng này + tháng trước
  ['kt-kiot-doi-chieu-2',  '37 18 * * *', 'kt-kiot', { doi_chieu: { chi_cu: true, cong_no: true } }, 170000], // 01:37 VN — tháng cũ xoay vòng + công nợ (22/11: dời khỏi 00:10–01:00, Kiot treo lệnh nặng khung đó)
  ['kt-kiot-thu-hd-1',     '40 17 * * *', 'kt-kiot', { thu_hd: { lui: [0, 1] } }, 170000],                   // 00:40 VN
  ['kt-kiot-thu-hd-2',     '52 17 * * *', 'kt-kiot', { thu_hd: { lui: [2, 3] } }, 170000],                   // 00:52
  ['kt-kiot-thu-hd-3',     '57 17 * * *', 'kt-kiot', { thu_hd: { lui: [4, 5] } }, 170000],                   // 00:57
  ['kt-kiot-thu-hd-4',     '7 18 * * *',  'kt-kiot', { thu_hd: { lui: [6, 7] } }, 170000],                   // 01:07
  ['kt-kiot-thu-hd-5',     '12 18 * * *', 'kt-kiot', { thu_hd: { lui: [8, 9] } }, 170000],                   // 01:12
  ['kt-kiot-thu-hd-6',     '22 18 * * *', 'kt-kiot', { thu_hd: { lui: [10, 11] } }, 170000],                 // 01:22
  ['kt-kiot-thu-hd-ngay',  '10 1-15 * * *', 'kt-kiot', { thu_hd: { tu_dong: true } }, 170000],               // 08:10–22:10 VN, chỉ khi có phiếu thu mới
  ['kt-luu-luong',         '55 16 * * *', 'kt-luu-luong', {}, 60000],                                        // 23:55 VN
  ['kt-meinvoice',         '25 17 * * *', 'kt-meinvoice', {}, 170000],                                       // 00:25 VN
  ['kt-meinvoice-trua',    '25 5 * * *',  'kt-meinvoice', {}, 170000],                                       // 12:25 VN
  ['kt-meinvoice-bot',     '35 17 * * *', 'kt-meinvoice-bot', {}, 170000],                                   // 00:35 VN
  ['kt-meinvoice-bot-trua','35 5 * * *',  'kt-meinvoice-bot', {}, 170000],                                   // 12:35 VN
  ['kt-hd-pdf-ra',         '0 6,18 * * *', 'kt-meinvoice', { pdf_xem: true }, 170000],                       // 13:00 · 01:00 VN
  ['kt-hd-pdf-vao',        '5 6,18 * * *', 'kt-meinvoice-bot', { pdf_xem: true }, 170000],                   // 13:05 · 01:05 VN
  ['kt-sao-ke',            '30 6,18 * * *', 'kt-sao-ke', {}, 170000],                                        // 13:30 · 01:30 VN
  ['kt-sao-ke-moi',        '0 */2 * * *', 'kt-sao-ke?moi=1', {}, 170000, 'public.kt_sao_ke_cho_xu_ly()'],    // 2 tiếng / lần khi có kỳ sao kê chờ
  ['kt-so-hh',             '40 14 * * *', 'kt-so-hh', {}, 170000],                                           // 21:40 VN
];
// Lịch body tính theo ngày (không đặt ở đây): kt-kiot-so-quy-thang 16:00 VN — quét sổ quỹ từ đầu tháng, bắt phiếu Kiot lập lùi ngày
// → supabase-schema-kt-kiot-so-quy-thang.sql (23/11/2026, VIEC 417). Monsieur Claude
const LICH_SQL = [['kt-lich-soat', '8,38 * * * *', 'select public.kt_lich_soat()']];   // soát kết quả thật mọi lịch Edge
(async () => {
  for (const [ten, gio, ham, body, cho, dk] of LICH) {
    const lenh = `select public.kt_goi_edge(%L, %L, %L::jsonb, %L, ${cho})` + (dk ? ' where ' + dk : '');
    await sql(`do $d$ declare k text := substring((select command from cron.job where jobname = 'kt-kiot') from 'x-kt-cron'', ''([0-9a-f]+)''');
      begin
        if k is null then k := substring((select command from cron.job where jobname = 'kt-kiot') from 'kt_goi_edge\\(''kt-kiot'', ''kt-kiot'', ''\\{\\}''::jsonb, ''([0-9a-f]+)''');
        end if;
        if k is null then raise exception 'không đọc được khoá từ lịch kt-kiot'; end if;
        perform cron.unschedule('${ten}') where exists (select 1 from cron.job where jobname = '${ten}');
        perform cron.schedule('${ten}', '${gio}', format($c$${lenh}$c$, '${ten}', '${ham}', '${JSON.stringify(body)}', k));
      end $d$`);
  }
  for (const [ten, gio, lenh] of LICH_SQL) {
    await sql(`select cron.unschedule('${ten}') where exists (select 1 from cron.job where jobname = '${ten}')`);
    await sql(`select cron.schedule('${ten}', '${gio}', $c$${lenh}$c$)`);
  }
  const ds = await sql(`select jobname, schedule, regexp_replace(command, '[0-9a-f]{30,}', '***', 'g') lenh from cron.job where jobname like 'kt-%' order by jobname`);
  for (const r of ds) console.log(r.jobname.padEnd(24), r.schedule.padEnd(20), r.lenh.replace(/\s+/g, ' ').slice(0, 130));
})().catch(e => { console.error('DỪNG:', e.message); process.exit(1); });
