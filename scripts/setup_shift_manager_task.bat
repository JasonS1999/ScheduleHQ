@echo off
REM =============================================================================
REM Setup Windows Task Scheduler for Shift Manager CSV Uploader
REM Run this script as Administrator
REM =============================================================================

echo.
echo ============================================================
echo  ScheduleHQ Shift Manager Upload - Task Scheduler Setup
echo ============================================================
echo.

REM Check for admin privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: This script requires Administrator privileges.
    echo Please right-click and select "Run as administrator"
    pause
    exit /b 1
)

REM Get the directory where this script is located
set SCRIPT_DIR=%~dp0
set PYTHON_SCRIPT=%SCRIPT_DIR%shift_manager_uploader.py

REM Check if Python script exists
if not exist "%PYTHON_SCRIPT%" (
    echo ERROR: shift_manager_uploader.py not found in %SCRIPT_DIR%
    pause
    exit /b 1
)

REM Task name
set TASK_NAME=ScheduleHQ Shift Manager Upload

REM Delete existing task if it exists
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1

REM Create the scheduled task
REM Runs daily at 8:00 AM
echo Creating scheduled task: %TASK_NAME%
echo.

schtasks /create ^
    /tn "%TASK_NAME%" ^
    /tr "python \"%PYTHON_SCRIPT%\"" ^
    /sc daily ^
    /st 08:00 ^
    /ru "%USERNAME%" ^
    /rl HIGHEST ^
    /f

if %errorLevel% equ 0 (
    echo.
    echo ============================================================
    echo  SUCCESS! Task created successfully.
    echo ============================================================
    echo.
    echo Task Name: %TASK_NAME%
    echo Schedule:  Daily at 8:00 AM
    echo Script:    %PYTHON_SCRIPT%
    echo.
    echo To view or modify the task:
    echo   1. Open Task Scheduler (taskschd.msc)
    echo   2. Look for "%TASK_NAME%"
    echo.
    echo To run the task manually:
    echo   schtasks /run /tn "%TASK_NAME%"
    echo.
) else (
    echo.
    echo ERROR: Failed to create scheduled task.
    echo Please check the error message above.
)

pause
