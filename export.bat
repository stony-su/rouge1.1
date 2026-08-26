@echo off
REM ===========================================================================
REM  export.bat -- package both builds for Windows.
REM
REM  For each of BlockBreakoutGame (shipping) and admin (playtest), runs the
REM  standard LOVE pipeline end to end:
REM
REM      source folder  ->  .love  ->  fused .exe  ->  distributable .zip
REM
REM  Everything lands in dist\ :
REM      dist\<NAME>.love          the archive on its own
REM      dist\<NAME>\              the runnable payload (exe + runtime DLLs)
REM      dist\<NAME>-win64.zip     that payload, zipped for distribution
REM
REM  No external tools required -- zipping goes through .NET via PowerShell, so
REM  this does not need 7-Zip on PATH the way engine\love\build_windows.bat did.
REM
REM  Run it from anywhere; it locates everything relative to its own folder.
REM ===========================================================================

setlocal EnableExtensions
cd /d "%~dp0"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "DIST=%ROOT%\dist"
set "STAGE=%DIST%\.stage"

echo(
echo ===========================================================
echo   Ball Pit X  --  Windows export
echo ===========================================================

REM --- locate a LOVE runtime -------------------------------------------------
REM Prefer the clean standalone 11.5 drop at the repo root; fall back to the
REM copy bundled inside the game (the one run.bat launches), which is always
REM present. Either way the exe is fused against a runtime this game runs on.
set "RUNTIME="
if exist "%ROOT%\love-11.5-win64\love-11.5-win64\love.exe" set "RUNTIME=%ROOT%\love-11.5-win64\love-11.5-win64"
if not defined RUNTIME if exist "%ROOT%\love-11.5-win64\love.exe" set "RUNTIME=%ROOT%\love-11.5-win64"
if not defined RUNTIME if exist "%ROOT%\BlockBreakoutGame\engine\love\love.exe" set "RUNTIME=%ROOT%\BlockBreakoutGame\engine\love"
if not defined RUNTIME (
  echo [ERROR] No love.exe found. Looked in:
  echo         %ROOT%\love-11.5-win64\
  echo         %ROOT%\BlockBreakoutGame\engine\love\
  exit /b 1
)
echo   runtime : %RUNTIME%
echo   output  : %DIST%

REM --- clean slate -----------------------------------------------------------
if exist "%DIST%" rmdir /s /q "%DIST%"
mkdir "%DIST%" 2>nul
if not exist "%DIST%" (
  echo [ERROR] could not create %DIST%
  exit /b 1
)

call :build "BlockBreakoutGame" "BallPitX"
if errorlevel 1 goto :failed
call :build "admin" "BallPitX-Admin"
if errorlevel 1 goto :failed

REM --- tidy the staging area, keep the artifacts -----------------------------
if exist "%STAGE%" rmdir /s /q "%STAGE%"

echo(
echo ===========================================================
echo   Done. Artifacts in %DIST%
echo ===========================================================
dir /b "%DIST%"
echo(
exit /b 0

:failed
echo(
echo [FAILED] export aborted.
exit /b 1


REM ===========================================================================
REM  :build  <source folder>  <output name>
REM ===========================================================================
:build
set "SRC=%ROOT%\%~1"
set "NAME=%~2"
set "PAY=%DIST%\%NAME%"
set "S=%STAGE%\%NAME%"

echo(
echo -----------------------------------------------------------
echo   %NAME%   ^(from %~1^)
echo -----------------------------------------------------------

if not exist "%SRC%\main.lua" (
  echo   [ERROR] %SRC%\main.lua not found -- is that a game folder?
  exit /b 1
)
if not exist "%SRC%\conf.lua" (
  echo   [ERROR] %SRC%\conf.lua not found -- the window config must ship.
  exit /b 1
)

REM --- 1. stage the source ---------------------------------------------------
REM Copied to a staging folder first because the .love must NOT contain the
REM bundled runtime: engine\love is ~11MB of love.exe and DLLs that the fused
REM exe already provides, and shipping it inside the archive would double the
REM download for nothing. conf.lua IS kept -- it sets the window and identity.
echo   [1/4] staging source...
if exist "%S%" rmdir /s /q "%S%"
mkdir "%S%" 2>nul
robocopy "%SRC%" "%S%" /E /NFL /NDL /NJH /NJS /NP /NS /NC ^
  /XD "%SRC%\engine\love" "%SRC%\.git" "%SRC%\builds" "%SRC%\dist" ^
  /XF "*.love" "*.zip" "*.exe" "*.dll" >nul
REM robocopy uses 0-7 for success (files copied, extras present, etc.) and
REM 8+ for a real failure. Anything under 8 is fine.
if errorlevel 8 (
  echo   [ERROR] robocopy failed staging %SRC%
  exit /b 1
)
if not exist "%S%\main.lua" (
  echo   [ERROR] staging produced no main.lua
  exit /b 1
)

REM --- 2. zip the staged source into a .love ---------------------------------
REM No prefix, so main.lua sits at the archive ROOT -- LOVE will not run an
REM archive whose contents are nested inside a folder.
echo   [2/4] writing %NAME%.love ...
call :zipdir "%S%" "%DIST%\%NAME%.love" ""
if errorlevel 1 (
  echo   [ERROR] could not write %NAME%.love
  exit /b 1
)
if not exist "%DIST%\%NAME%.love" (
  echo   [ERROR] %NAME%.love missing after packing
  exit /b 1
)

REM --- 3. fuse runtime + archive into a single exe ---------------------------
REM This is the standard LOVE fuse: love.exe with the zip appended. LOVE finds
REM the archive attached to its own executable and mounts it as the game source.
echo   [3/4] fusing %NAME%.exe ...
mkdir "%PAY%" 2>nul
copy /b "%RUNTIME%\love.exe" + "%DIST%\%NAME%.love" "%PAY%\%NAME%.exe" >nul
if errorlevel 1 (
  echo   [ERROR] fuse failed
  exit /b 1
)
if not exist "%PAY%\%NAME%.exe" (
  echo   [ERROR] %NAME%.exe missing after fuse
  exit /b 1
)

REM The runtime DLLs must sit beside the exe -- a fused LOVE binary still links
REM against SDL2, OpenAL, love.dll and the VC runtime at load time.
for %%F in ("%RUNTIME%\*.dll") do copy /y "%%F" "%PAY%\" >nul
if exist "%RUNTIME%\license.txt" copy /y "%RUNTIME%\license.txt" "%PAY%\" >nul

REM --- 4. zip the payload ----------------------------------------------------
REM Prefixed with %NAME%/ so the zip holds a single folder and does not spray
REM loose DLLs into whatever directory it is extracted to.
echo   [4/4] writing %NAME%-win64.zip ...
call :zipdir "%PAY%" "%DIST%\%NAME%-win64.zip" "%NAME%/"
if errorlevel 1 (
  echo   [ERROR] could not write %NAME%-win64.zip
  exit /b 1
)
if not exist "%DIST%\%NAME%-win64.zip" (
  echo   [ERROR] %NAME%-win64.zip missing after packing
  exit /b 1
)

for %%A in ("%DIST%\%NAME%.love")      do echo         %NAME%.love        %%~zA bytes
for %%A in ("%PAY%\%NAME%.exe")        do echo         %NAME%.exe         %%~zA bytes
for %%A in ("%DIST%\%NAME%-win64.zip") do echo         %NAME%-win64.zip   %%~zA bytes
exit /b 0


REM ===========================================================================
REM  :zipdir  <source dir>  <output archive>  <entry prefix, "" for none>
REM
REM  Rolled by hand rather than with ZipFile::CreateFromDirectory, which on
REM  Windows PowerShell writes entry names with BACKSLASH separators. That is
REM  out of spec, and PhysFS -- what LOVE mounts archives with -- will not
REM  resolve them, so a .love built that way boots to a black screen with every
REM  require and every asset load failing. Adding entries individually lets the
REM  separator be normalised to '/', which is the only thing the format allows.
REM  The backslash is built as [char]92 rather than written literally: a ''
REM  inside the -Command string is mangled by PowerShell's own argument parser
REM  before the script ever sees it, and arrives as an empty string.
REM ===========================================================================
:zipdir
powershell -NoProfile -ExecutionPolicy Bypass -Command "$src='%~1'; $dst='%~2'; $pre='%~3'; $bs=[string][char]92; Add-Type -AssemblyName System.IO.Compression.FileSystem; $z=[System.IO.Compression.ZipFile]::Open($dst,'Create'); try { Get-ChildItem -LiteralPath $src -Recurse -File | ForEach-Object { $rel=$pre+$_.FullName.Substring($src.Length+1).Replace($bs,'/'); [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z,$_.FullName,$rel,'Optimal') } } finally { $z.Dispose() }"
exit /b %errorlevel%
