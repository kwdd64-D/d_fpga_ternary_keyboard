@echo off
set ROOT=D:\ulx3s\d_fpga
set OUT=D:\ulx3s\d_fpga\docs\d_fpga_filelist.md
chcp 65001 > nul

echo # D FPGA File List > "%OUT%"
echo. >> "%OUT%"
echo Generated: %date% %time% >> "%OUT%"
echo. >> "%OUT%"
echo ``` >> "%OUT%"

tree "%ROOT%" /F /A | findstr /V "\.import" >> "%OUT%"

echo ``` >> "%OUT%"
echo Done! d_fpga_filelist.md.
pause