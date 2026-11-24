// Tắt SẠCH trình duyệt ẩn sau khi test (17/11/2026): Edge / Chrome tự khởi chạy lại tiến trình gốc mới không còn nằm dưới tiến trình ta spawn,
// nên p.kill() hay taskkill /T đều sót → dồn 22 trình duyệt ẩn (~4,6 GB), máy cạn bộ nhớ, phiên Claude bị ngắt. Cách chắc: tắt mọi msedge / chrome
// có dòng lệnh chứa tên thư mục tạm (ngẫu nhiên, riêng từng lần test) — không đụng trình duyệt anh đang dùng. Dùng: require('./tat-trinh-duyet')(thuMucTam). Monsieur Claude
const path = require('path'), { spawnSync } = require('child_process');
module.exports = function tatTheoThuMuc(dir) {
  const ten = path.basename(String(dir || '')).replace(/[^A-Za-z0-9._-]/g, '');
  if (ten.length < 6) return;   // tên thư mục quá ngắn → không chắc là của lần test, không tắt gì
  if (process.platform !== 'win32') { spawnSync('pkill', ['-f', ten], { stdio: 'ignore', timeout: 20000 }); return; }   // 24/11: máy Mac
  spawnSync('powershell', ['-NoProfile', '-Command',
    `Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'msedge.exe' -or $_.Name -eq 'chrome.exe') -and $_.CommandLine -like '*${ten}*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }`],
    { stdio: 'ignore', timeout: 20000 });
};
