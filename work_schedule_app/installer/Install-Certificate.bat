@echo off
echo ============================================
echo   Manager Schedule App - Certificate Setup
echo ============================================
echo.

:: Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Please run this as Administrator!
    echo Right-click and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo Installing certificate...
echo.

:: Import the certificate
certutil -addstore "TrustedPeople" "%~dp0ManagerScheduleApp.cer"

if %errorLevel% equ 0 (
    echo.
    echo ============================================
    echo   Certificate installed successfully!
    echo   You can now install ManagerScheduleApp.msix
    echo ============================================
) else (
    echo.
    echo ERROR: Failed to install certificate.
    echo Please make sure ManagerScheduleApp.cer is in the same folder.
)

echo.
pause
