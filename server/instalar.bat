@echo off
setlocal
title ISP CONFIG - servidor web
cd /d "%~dp0"

echo.
echo   ============================================
echo     ISP CONFIG - servidor web (PHP + SQLite)
echo   ============================================
echo.

rem ---------- 1) localizar o instalar PHP ----------
set "PHP="
for /f "delims=" %%P in ('where php 2^>nul') do ( set "PHP=%%P" & goto :encontrado )
if exist "%~dp0php.exe" ( set "PHP=%~dp0php.exe" & goto :encontrado )
if exist "%ProgramFiles%\PHP\php.exe" ( set "PHP=%ProgramFiles%\PHP\php.exe" & goto :encontrado )
for /d %%D in ("%ProgramFiles%\PHP\v8.*") do ( if exist "%%D\php.exe" ( set "PHP=%%D\php.exe" & goto :encontrado ) )

echo   No encontre PHP. Intentando instalarlo con winget...
where winget >nul 2>nul
if errorlevel 1 (
  echo.
  echo   [FALTA PHP y no hay winget]
  echo   1) Descarga PHP 8 desde https://windows.php.net/downloads/releases/
  echo      (x64 Thread Safe, archivo .zip)
  echo   2) Descomprime y copia la carpeta junto a este archivo, o
  echo   3) Agrega la carpeta de php.exe a la variable PATH.
  echo   Vuelve a ejecutar este archivo.
  echo.
  pause
  exit /b 1
)
winget install --id PHP.PHP.8.3 -e --accept-source-agreements --accept-package-agreements --disable-interactivity
set "PATH=%PATH%;%LOCALAPPDATA%\Microsoft\WinGet\Links;%ProgramFiles%\PHP\v8.3"
for /f "delims=" %%P in ('where php 2^>nul') do ( if not defined PHP set "PHP=%%P" )
if not defined PHP (
  for /r "%LOCALAPPDATA%\Microsoft\WinGet\Packages" %%P in (php.exe) do ( if not defined PHP if exist "%%P" set "PHP=%%P" )
)
if not defined PHP (
  echo.
  echo   [FALTO INSTALAR PHP] Revisa el mensaje de winget arriba,
  echo   o instala PHP manualmente desde https://windows.php.net/
  echo.
  pause
  exit /b 1
)

:encontrado
echo   PHP: %PHP%
for %%I in ("%PHP%") do set "PHPDIR=%%~dpI"

rem ---------- 2) php.ini propio con SQLite ----------
set "INIFILE=%~dp0php-isp-config.ini"
if not exist "%INIFILE%" (
  >"%INIFILE%" echo extension_dir="%PHPDIR%ext"
  >>"%INIFILE%" echo extension=pdo_sqlite
  >>"%INIFILE%" echo extension=sqlite3
  >>"%INIFILE%" echo display_errors=On
  >>"%INIFILE%" echo error_reporting=E_ALL
  >>"%INIFILE%" echo max_execution_time=120
  echo   php.ini creado: %INIFILE%
)

rem ---------- 3) base de datos con datos de ejemplo ----------
if not exist "%~dp0data" mkdir "%~dp0data"
if not exist "%~dp0data\isp.sqlite" (
  echo   Creando base de datos con los nodos de ejemplo...
  "%PHP%" -c "%INIFILE%" "%~dp0scripts\seed.php"
)

rem ---------- 4) servidor + navegador ----------
echo.
echo   Levantando servidor en http://localhost:8080 ...
start "ISP CONFIG (ventana minima - no cierres)" /min "%PHP%" -c "%INIFILE%" -S 0.0.0.0:8080 -t "%~dp0public"
timeout /t 2 /nobreak >nul
start "" "http://localhost:8080/admin"

echo.
echo   Panel web:  http://localhost:8080/admin
echo   Usuario:    admin      Contrasena: admin (cambiala en Ajustes)
echo   APK:        Admin - Nube - http://<IP-de-esta-PC^>:8080
echo.
echo   Para DETENER: cierra la ventana "ISP CONFIG" (la que esta minimizada).
echo.
pause
endlocal
