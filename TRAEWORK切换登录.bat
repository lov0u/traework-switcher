@echo off
chcp 936 >nul 2>&1
title Trae Work Account Switcher
cd /d "%~dp0"

:: Check admin privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c cd /d \"%~dp0\" && powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0TraeWorkAccountSwitcher-GUI.ps1\"' -Verb RunAs"
    exit /b
)

echo Starting TRAE WORK Multi-Account Switcher v5.2...
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0TraeWorkAccountSwitcher-GUI.ps1"
if %errorlevel% neq 0 (
    echo.
    echo [Error] Launch failed, error code: %errorlevel%
    echo Please try: Right-click this file ^> Run as administrator
    echo.
    pause
)
