@echo off
SETLOCAL ENABLEDELAYEDEXPANSION

set "WB_ROOT=%APP_ROOT%"
set "WB_ARCH=%APP_ARCH%"
set "WB_HOST_LANG=%APP_HOST_LANG%"

cd /d "%WB_ROOT%\"
title WimBuilder(%cd%)

if "x%_WB_EXEC_MODE%"=="x1" set WB_RUNAS_TI=1
if "x%WB_RUNAS_TI%"=="x" (
  set WB_RUNAS_TI=1
  NSudoC.exe -UseCurrentConsole -Wait -U:T "%~0"
  goto :EOF
)

title WimBuilder(%cd%)

if "x%_WB_EXEC_MODE%"=="x1" (
  title WimBuilder^(%cd%^) - Don't close this console window while building
)

call DisAutoRun

rem ======generate logfile name======
rem ">" mark will cause *ECHO* error, change to "*"
rem i.e. Mount [WIM] -> [PATH] ---> Mount [WIM] -* [PATH]
rem set gt:=^^^>
set gt:=*
for /f "delims=" %%t in ('cscript.exe //nologo bin\TimeStamp.vbs') do set LOGSUFFIX=%%t
set "LOGFILE=%Factory%\log\%LOGSUFFIX%.log"


rem ======define var======
if "x%WB_PROJECT%"=="x" call :NO_ENV_CONF WB_PROJECT
set "LOGFILE=%Factory%\log\%WB_PROJECT%\%LOGSUFFIX%.log"
call :MKPATH "%LOGFILE%"
rem type nul>"%LOGFILE%"

set BUILD_LOGTIME=%LOGSUFFIX%
set "BUILD_LOGNAME=%BUILD_LOGTIME%_Build[LOG]_%WB_PROJECT%.log"

if "x%WB_BASE%"=="x" call :NO_ENV_CONF WB_BASE
set _WB_BASE_EXTRACTED=0
set "_WB_TAR_DIR=%Factory%\target\%WB_PROJECT%"
set "_WB_MNT_DIR=%_WB_TAR_DIR%\mounted"

call :GETNAME "%WB_BASE%"
set "_WB_PE_WIM=%_WB_TAR_DIR%\%RET_GETNAME%"

call :MKPATH "%Factory%\target\%WB_PROJECT%\"

rem full path for macro(s)
set "_WB_MNT_PATH=%WB_ROOT%\%_WB_MNT_DIR%"
set "_WB_TMP_DIR=%WB_ROOT%\%Factory%\tmp\%WB_PROJECT%"

set "WB_PROJECT_PATH=%WB_ROOT%\Projects\%WB_PROJECT%"

call :MKPATH "%_WB_TMP_DIR%\"
if exist "%_WB_TMP_DIR%\_AddFiles.txt" (
  rem type nul>"%_WB_TMP_DIR%\_AddFiles.txt"
  del /f /q "%_WB_TMP_DIR%\_AddFiles.txt"
)

rem load patches options
if exist "%_WB_TMP_DIR%\_patches_opt.bat" (
  call "%_WB_TMP_DIR%\_patches_opt.bat"
)

rem call prepare.bat before mounting
if exist "%WB_PROJECT_PATH%\_CustomFiles_\_Prepare_.bat" (
    pushd "%WB_PROJECT_PATH%\_CustomFiles_\"
    call _Prepare_.bat :BEFORE_WIM_BUILD
    popd
)

echo WimBuilder - v%WB_VER_STR%
set TIMER_START=
for /f "delims=" %%t in ('cscript.exe //nologo bin\Timer.vbs') do set TIMER_START=%%t
call :cecho PHRASE "%TIMER_START% - Building Start ..."

echo.
rem ";" can't be pass to CALL LABEL, so use a ":" for it
call :CLOG 97:104m "[%WB_PROJECT%] --- build information"
set WB_
echo.
set BUILD_
echo.

rem extract winre.wim from install.wim
if /i not "%WB_BASE%"=="winre.wim" goto :PHRASE_GETINFO
if "x%WB_SRC%"=="x" (
  call :cecho ERROR "mount base wim file failed(can't get winre.wim)."
  call :CLEANUP
)

call :MKPATH "%_WB_PE_WIM%"
call wimextract "%WB_SRC%" %WB_SRC_INDEX% "Windows\System32\Recovery\WinRe.wim" --dest-dir="%Factory%\target\%WB_PROJECT%" --no-acls --nullglob
if not exist "%_WB_PE_WIM%" (
  call :cecho ERROR "mount base wim file failed(can't get winre.wim)."
  call :CLEANUP
)
set _WB_BASE_EXTRACTED=1
set "WB_BASE=%_WB_PE_WIM%"

:PHRASE_GETINFO
call :cecho PHRASE "PHRASE:Get WIM image INFO"
for /f "tokens=1,2 delims=:(" %%i in ('DismX /Get-WimInfo /WimFile:"%WB_BASE%" /Index:%WB_BASE_INDEX% /English') do (
  if "%%i"=="Architecture " set WB_PE_ARCH=%%j
  if "%%i"=="Version " set WB_PE_VER=%%j
  if "%%i"=="ServicePack Build " set WB_PE_BUIID=%%j
  if "x!LANG_FLAG!"=="x1" (
    set WB_PE_LANG=%%i
    set LANG_FLAG=
  )
  if "%%i"=="Languages " set LANG_FLAG=1
)

if "x%WB_PE_LANG%"=="x" (
    call :cecho ERROR "Get WIM image's information failed."
    goto :EOF
)

set "WB_PE_ARCH=%WB_PE_ARCH: =%"
set "WB_PE_VER=%WB_PE_VER: =%"
set "WB_PE_BUIID=%WB_PE_BUIID: =%"
rem here is TAB, not SPACE 
set "WB_PE_LANG=%WB_PE_LANG:	=%"
set "WB_PE_LANG=%WB_PE_LANG: =%"

set WB_PE_
echo.
call :cecho PHRASE "PHRASE:Mount WIM image"

rem check X: driver
set NO_X_SUBST=0
if "x%X%"=="x--" (
  set NO_X_SUBST=1
  goto :SUBST_CHECK_END
)

if exist %X%\ (
  call :cecho WARN "%X% is already use."
  call :setp yTry "Try SUBST %X% /D?[y/n]:"
)
if "%yTry%"=="y" SUBST %X% /D
if "%yTry%"=="Y" SUBST %X% /D
if exist %X%\ (
  call :cecho ERROR "%X% is already in use, goto CLEANUP."
  call :CLEANUP
)
:SUBST_CHECK_END

rem extract sources registry
if "x%WB_SRC%"=="x" goto :BASE_MOUNT

rem TODO: check if %WB_SRC% is wim file or folder
rem if exist "%WB_SRC%\" (echo WB_SRC is src dir) else (echo WB_SRC is src wim)

set "WB_SRC_DIR=%Factory%\target\%WB_PROJECT%\install"
call :MKPATH "%WB_SRC_DIR%\"
call wimextract "%WB_SRC%" %WB_SRC_INDEX% @"%WB_ROOT%\bin\SRC_REGFILES.txt" --dest-dir="%WB_SRC_DIR%" --no-acls --nullglob

:BASE_MOUNT
rem PHRASE:mount WIM
if "x%WB_BASE_INDEX%"=="x" set WB_BASE_INDEX=1
if "x%WB_SRC_INDEX%"=="x" set WB_SRC_INDEX=1

call :MKPATH "%_WB_PE_WIM%"

if "%_WB_BASE_EXTRACTED%"=="1" goto :BASE_WIM_PREPARED

call copy /y "%WB_BASE%" "%_WB_PE_WIM%"

:BASE_WIM_PREPARED


rem export working paths
set "WB_TEMP=%_WB_TMP_DIR%"
set "WB_TMP=%_WB_TMP_DIR%"

rem call prepare.bat before mounting
if exist "%WB_PROJECT_PATH%\prepare.bat" (
    call "%WB_PROJECT_PATH%\prepare.bat" :BEFORE_WIM_MOUNT
)

call WIM_Mounter "%_WB_PE_WIM%" %WB_BASE_INDEX% "%_WB_MNT_DIR%" base_wim_mounted
if not "%base_wim_mounted%"=="1" (
  call :cecho ERROR "mount base wim file failed."
  call :CLEANUP
)

rem NOTICE:explorer.exe don't show X:\ when running with Administrators right
if not "x%NO_X_SUBST%"=="x1" (
  SUBST %X% "%_WB_MNT_DIR%"
) else (
  set "X=%_WB_MNT_DIR%"
  echo.
  echo SET %%X%%=%_WB_MNT_DIR%
)
echo.
if "x%WB_SKIP_UFR%"=="x1" goto :PROJECT_BUILDING
rem update files ACL Right
call :cecho PHRASE "PHRASE:updating files' ACL rights"
if "x%WB_STRAIGHT_MODE%"=="x" pause
call :techo "Updating...(Please, be patient)"
call TrustedInstallerRight "%_WB_MNT_DIR%" 1>nul
if not "%GetLastError%"=="0" call :CLEANUP
call :techo "Update files with Administrators' FULL ACL rights successfully."
echo.

:PROJECT_BUILDING

rem call prepare.bat before hive load
if exist "%WB_PROJECT_PATH%\prepare.bat" (
    call "%WB_PROJECT_PATH%\prepare.bat" :BEFORE_HIVE_LOAD
)

if not "x%opt[build.load_hive_demand]%"=="xtrue" (
  call PERegPorter.bat Src LOAD 1>nul
  call PERegPorter.bat Tmp LOAD 1>nul
)

rem =========================================================
rem apply project patches
call ApplyProjectPatches.bat "%WB_PROJECT_PATH%"
rem =========================================================

cd /d "%WB_ROOT%\"
if "x%_WB_UNMOUNT_DEMAND%"=="x1" goto :UNMOUNT_END
call :CLEANUP 0
call WIM_Exporter "%_WB_PE_WIM%"
:UNMOUNT_END

set TIMER_END=
for /f "delims=" %%t in ('cscript.exe //nologo "%WB_ROOT%\bin\Timer.vbs"') do set TIMER_END=%%t

set TIMER_ELAPSED=
for /f "delims=" %%t in ('cscript.exe //nologo "%WB_ROOT%\bin\Timer.vbs" "%TIMER_START%" "%TIMER_END%"') do set TIMER_ELAPSED=%%t
call :cecho PHRASE "%TIMER_END% - Building completed in %TIMER_ELAPSED% seconds."

if "x%BUILD_LOGNAME%"=="x" goto :EOF
if not "x%_WB_EXEC_MODE%"=="x1" goto :EOF
pushd "%WB_ROOT%\_Factory_\log\%WB_PROJECT%\"
copy /y /b %BUILD_LOGTIME%.log+last_wimbuilder.log "%BUILD_LOGNAME%"
popd

goto :EOF

rem =========================================================

:MKPATH
if not exist "%~dp1" mkdir "%~dp1"
goto :EOF

:GETPATH
:GETNAME
set "RET_GETPATH=%~dp1"
set "RET_GETNAME=%~nx1"
goto :EOF

rem =========================================================
:i18n.t
if not "x%DEBUG_MODE%"=="x" echo %*
set i18n.str=
set i18n.log=
if "%I18N_LCID%"=="0" (
  if /i "x%~1"=="xECHO" (
    if "x%~3"=="x" (
      set "i18n.str=%~2"
      goto :EOF
    )
  )
)

set tmp_i=1
for /f "delims=" %%s in ('cscript.exe //nologo "%I18N_SCRIPT%" %*') do (
  set "i18n.str!tmp_i!=%%s"
  set /a tmp_i+=1
)
set tmp_i=
set "i18n.str=%i18n.str1%"
set "i18n.log=%i18n.str2%"
goto :EOF

:techo
call :i18n.t ECHO %*
echo %i18n.str%
goto :EOF

:setp
call :i18n.t SETP_%*
set /p %1=%i18n.str%
set p1=
goto :EOF

:cecho
call :i18n.t CLR_%*
echo %i18n.str% | cmdcolor.exe
goto :EOF

:LOG
call :i18n.t LOG %*
echo %i18n.str%
>>"%LOGFILE%" (echo %i18n.log%)
goto :EOF

:CLOG
call :i18n.t CLR_LOG_%*
echo %i18n.str% | cmdcolor.exe
>>"%LOGFILE%" (echo %i18n.log%)
goto :EOF

rem =========================================================
:WB_ERROR
call :CLOG ERROR %*
call :CLEANUP

:NO_ENV_CONF
call :CLOG ERROR "Please specify the @s in config file" %1
call :CLEANUP

:CLEANUP
call _Cleanup %1
if "x%1"=="x0" (
  goto :EOF
)
pause
exit 1
