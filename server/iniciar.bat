@echo off
rem ISP CONFIG — servidor local (Windows). Doble clic para arrancar.
rem Requiere PHP 8 en el PATH  (o php.exe copiado junto a este archivo).
cd /d "%~dp0"

set PHP=php
if exist "%~dp0php.exe" set PHP=%~dp0php.exe

"%PHP%" -v >nul 2>&1
if errorlevel 1 (
  echo.
  echo   No encontre PHP en el PATH.
  echo   1) Baja PHP desde https://windows.php.net/download/  (x64, zip)
  echo   2) Descomprime en C:\php  y agrega C:\php al PATH  (o copia php.exe aqui)
  echo   3) En php.ini habilita:  extension=pdo_sqlite  y  extension=sqlite3
  echo.
  pause
  exit /b 1
)

if not exist "data\isp.sqlite" "%PHP%" scripts\seed.php
if errorlevel 1 pause & exit /b 1

echo.
echo   Servidor ISP CONFIG en  http://%COMPUTERNAME%:8080
echo   Prueba:  http://127.0.0.1:8080/health
echo   En la APK: Admin - Nube -  http://IP-de-esta-PC:8080
echo   Ctrl+C para detener.
echo.
"%PHP%" -S 0.0.0.0:8080 -t public
pause
