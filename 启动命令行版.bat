@echo off
chcp 65001 >nul 2>&1
title Trae Work 账号切换工具 - 命令行版
cd /d "%~dp0"
echo 正在启动 Trae Work 账号切换工具 (命令行版)...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "TraeWorkAccountSwitcher.ps1"
pause
