@echo off
rem Lịch Windows kt-sao-luu-chung-tu (15:30 thứ 2 - thứ 7): sao lưu kho chứng từ app kế toán sang Google Drive — Monsieur Claude
set ELECTRON_RUN_AS_NODE=1
cd /d C:\Users\HP\Desktop\ke-toan
"D:\Microsoft VS Code\Code.exe" scripts\sao-luu-chung-tu.js ktdrive-ghi: >> "%LOCALAPPDATA%\kt-sao-luu-chung-tu.log" 2>&1
