' Chạy dong-bo-sheet-dinh-ky.js ẩn cửa sổ (Task Scheduler "kt-dong-bo-sheet-dn", 16/10/2026) — Monsieur Claude
Set sh = CreateObject("WScript.Shell")
sh.Environment("PROCESS")("ELECTRON_RUN_AS_NODE") = "1"
sh.Run """D:\Microsoft VS Code\Code.exe"" ""C:\Users\HP\Desktop\ke-toan\scripts\dong-bo-sheet-dinh-ky.js""", 0, True
