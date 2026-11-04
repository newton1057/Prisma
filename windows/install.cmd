@echo off
setlocal
chcp 65001 >nul
set "ROOT=%~dp0"
set "PS=%ROOT%windows\install.ps1"
if not exist "%PS%" set "PS=%ROOT%install.ps1"
if not exist "%PS%" (
    echo No encontre windows\install.ps1 junto a este archivo.
    echo Descomprime el ZIP completo y vuelve a ejecutar "Instalar Prisma.cmd".
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS%"
if errorlevel 1 (
    echo.
    echo No se pudo instalar Prisma. Revisa el mensaje anterior.
    pause
    exit /b 1
)
echo.
echo Prisma esta instalado. Abre Ajustes desde el icono de la bandeja para conectar tus agentes.
pause
