@echo off
for /f "delims=." %%s in ('reg query "HKLM\SECURITY\SAM\Domains\Builtin\Aliases\Members"') do set AdminSID=%%s-500
set "AdminSID=%AdminSID:HKEY_LOCAL_MACHINE\SECURITY\SAM\Domains\Builtin\Aliases\Members\=%"
reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\ProfileService\References\%AdminSID%" /v RefCount /t REG_BINARY /d 02000000 /f
LSAgetRights.exe -c
reg load "HKU\%AdminSID%" X:\Users\Administrator\NTUSER.DAT
