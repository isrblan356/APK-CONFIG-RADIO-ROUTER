@echo off
rem ISP CONFIG — servidor local (Windows). Doble clic para arrancar.
rem Requiere PHP 8 en el PATH (o php.exe copiado junto a este archivo).
rem Si existe php-isp-config.ini (lo crea instalar.bat) se usa para activar SQLite.
cd /d "%~dp0"

set PHP=php
if exist "%~dp0php.exe" set PHP=%~dp0php.exe

set INIOPT=
if exist "%~dp0php-isp-config.ini" set INIOPT=-c "%~dp0php-isp-config.ini"

"%PHP%" %INIOPT% -v >nul 2>&1
if errorlevel 1 (
  echo.
  echo   No encontre PHP en el PATH (o no arranca).
  echo   Opcion rapida: ejecuta instalar.bat  (busca/instala PHP solo).
  echo   A mano: baja PHP desde https://windows.php.net/download/  (x64, zip),
  echo   descomprime junto a este archivo y activa extension=pdo_sqlite
  echo   y extension=sqlite3 en php.ini.
  echo.
  pause
  exit /b 1
)

if not exist "data" mkdir "data"
if not exist "data\isp.sqlite" "%PHP%" %INIOPT% scripts\seed.php
if errorlevel 1 pause & exit /b 1

echo.
echo   Servidor ISP CONFIG en  http://%COMPUTERNAME%:8080
echo   Prueba:  http://127.0.0.1:8080/health
echo   Panel web (nodos, APs, firmware, IPs):  http://127.0.0.1:8080/admin
echo   En la APK: Admin - Nube -  http://IP-de-esta-PC:8080
echo   Ctrl+C para detener.
echo.
start "" "http://localhost:8080/admin"
"%PHP%" %INIOPT% -S 0.0.0.0:8080 -t public
pause
