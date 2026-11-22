' Chạy keo-file-dong-tien.js ẩn cửa sổ (Task Scheduler "kt-keo-file-dong-tien", 16/10/2026) — Monsieur Claude
' Đăng ký (1 lần, máy anh): schtasks /Create /TN kt-keo-file-dong-tien /SC MINUTE /MO 30 /TR "wscript.exe \"C:\Users\HP\Desktop\ke-toan\scripts\keo-file-dong-tien.vbs\"" /F
Set sh = CreateObject("WScript.Shell")
sh.Environment("PROCESS")("ELECTRON_RUN_AS_NODE") = "1"
sh.Run """D:\Microsoft VS Code\Code.exe"" ""C:\Users\HP\Desktop\ke-toan\scripts\keo-file-dong-tien.js""", 0, True
