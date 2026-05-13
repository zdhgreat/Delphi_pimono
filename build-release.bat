@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM ============================================================
REM PiMono ZIP 绿色包打包脚本
REM 用法: 双击运行或在命令行执行 build-release.bat
REM 前置: 需要先编译好 Release 版本的 PiMono.exe
REM ============================================================

set VERSION=1.0.0
set APP_NAME=PiMono
set DIST_NAME=%APP_NAME%-v%VERSION%
set OUTPUT_DIR=Output
set TEMP_DIR=%OUTPUT_DIR%\%DIST_NAME%

echo ============================================
echo   PiMono v%VERSION% 绿色包打包工具
echo ============================================
echo.

REM 检查必要文件是否存在
if not exist "PiMono.exe" (
    echo [错误] 找不到 PiMono.exe
    echo 请先在 Delphi IDE 中编译 Release 版本。
    pause
    exit /b 1
)

if not exist "WebView2Loader.dll" (
    echo [错误] 找不到 WebView2Loader.dll
    echo 请确保 WebView2Loader.dll 在当前目录下。
    pause
    exit /b 1
)

if not exist "WebUI\index.html" (
    echo [错误] 找不到 WebUI\index.html
    echo 请确保 WebUI 目录存在且包含前端文件。
    pause
    exit /b 1
)

REM 创建输出目录
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

REM 清理旧的临时目录
if exist "%TEMP_DIR%" (
    echo [清理] 移除旧的临时目录...
    rmdir /s /q "%TEMP_DIR%"
)

REM 创建临时打包目录
mkdir "%TEMP_DIR%"

echo [1/4] 复制 PiMono.exe...
copy /y "PiMono.exe" "%TEMP_DIR%\" >nul

echo [2/4] 复制 WebView2Loader.dll...
copy /y "WebView2Loader.dll" "%TEMP_DIR%\" >nul

echo [3/4] 复制 WebUI 目录...
xcopy "WebUI" "%TEMP_DIR%\WebUI\" /e /i /q >nul

echo [4/4] 生成 README.txt...
(
echo PiMono v%VERSION% - AI Agent Desktop Client
echo ============================================
echo.
echo 使用方法:
echo   1. 解压此压缩包到任意目录
echo   2. 双击 PiMono.exe 启动
echo   3. 首次启动后在设置中配置 API Endpoint 和 API Key
echo.
echo 系统要求:
echo   - Windows 10 1803+ 或 Windows 11
echo   - Microsoft Edge WebView2 Runtime
echo     ^(Windows 10 20H2+ 和 Windows 11 通常已预装^)
echo     如未安装请访问: https://go.microsoft.com/fwlink/p/?LinkId=2124703
echo.
echo 配置文件位置:
echo   - 用户设置: %%APPDATA%%\PiMono\settings.json
echo   - 技能存储: %%APPDATA%%\PiMono\skills\
echo   - 日志目录: %%LOCALAPPDATA%%\PiMono\Logs\
echo.
echo GitHub: https://github.com/pimono
) > "%TEMP_DIR%\README.txt"

REM 删除旧的 ZIP 文件
if exist "%OUTPUT_DIR%\%DIST_NAME%.zip" (
    del /q "%OUTPUT_DIR%\%DIST_NAME%.zip"
)

REM 使用 PowerShell 压缩
echo.
echo [打包] 正在压缩...
powershell -NoProfile -Command "Compress-Archive -Path '%TEMP_DIR%\*' -DestinationPath '%OUTPUT_DIR%\%DIST_NAME%.zip' -Force"

if %ERRORLEVEL% neq 0 (
    echo [错误] 压缩失败！
    pause
    exit /b 1
)

REM 清理临时目录
rmdir /s /q "%TEMP_DIR%"

echo.
echo ============================================
echo   打包完成！
echo.
echo   输出文件: %OUTPUT_DIR%\%DIST_NAME%.zip
echo ============================================

REM 显示文件大小
for %%A in ("%OUTPUT_DIR%\%DIST_NAME%.zip") do (
    echo   文件大小: %%~zA 字素 ^(约 %%~zAKB^)
)

echo.
pause
