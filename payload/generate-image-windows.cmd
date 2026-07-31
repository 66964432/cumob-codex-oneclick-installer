@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"

rem When Codex launches this skill from a restricted shell, USERPROFILE /
rem GetFolderPath may be empty. Infer CODEX_HOME from the installed skill path:
rem <CODEX_HOME>\skills\cumob-image-generation4codex\scripts\generate-image-windows.cmd
if not defined CODEX_HOME (
  for %%I in ("%SCRIPT_DIR%..\..\..") do set "CUMOB_INFERRED_CODEX_HOME=%%~fI"
  if defined CUMOB_INFERRED_CODEX_HOME if exist "%CUMOB_INFERRED_CODEX_HOME%\config.toml" (
    set "CODEX_HOME=%CUMOB_INFERRED_CODEX_HOME%"
  )
)
if /i "%CUMOB_IMAGE_FORCE_POWERSHELL%"=="1" goto use_powershell

where node.exe >nul 2>&1
if errorlevel 1 goto try_python
set "NODE_MAJOR="
for /f "usebackq delims=" %%V in (`node.exe -p "Number(process.versions.node.split('.')[0])" 2^>nul`) do set "NODE_MAJOR=%%V"
if "%NODE_MAJOR%"=="" goto try_python
if %NODE_MAJOR% LSS 18 goto try_python

:use_node
if not exist "%SCRIPT_DIR%generate-image.mjs" goto try_python
node.exe "%SCRIPT_DIR%generate-image.mjs" %*
exit /b %ERRORLEVEL%

:try_python
if not exist "%SCRIPT_DIR%generate-image.py" goto use_powershell
where py.exe >nul 2>&1
if errorlevel 1 goto try_python_exe
py.exe -3 -c "import sys" >nul 2>&1
if errorlevel 1 goto try_python_exe

:use_py
py.exe -3 "%SCRIPT_DIR%generate-image.py" %*
exit /b %ERRORLEVEL%

:try_python_exe
where python.exe >nul 2>&1
if errorlevel 1 goto try_python3_exe
python.exe -c "import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)" >nul 2>&1
if errorlevel 1 goto try_python3_exe
python.exe "%SCRIPT_DIR%generate-image.py" %*
exit /b %ERRORLEVEL%

:try_python3_exe
where python3.exe >nul 2>&1
if errorlevel 1 goto use_powershell
python3.exe -c "import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)" >nul 2>&1
if errorlevel 1 goto use_powershell
python3.exe "%SCRIPT_DIR%generate-image.py" %*
exit /b %ERRORLEVEL%

:use_powershell
where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo Error: Windows PowerShell is required for the image-generation fallback. 1>&2
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%generate-image.ps1" %*
exit /b %ERRORLEVEL%
