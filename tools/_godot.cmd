@echo off
rem ============================================================
rem  _godot.cmd  -  locate Godot, redirect user:// into the project
rem  Called by the launcher .cmd in the project root, and by
rem  NOTE: intentionally no setlocal - variables must survive.
rem  NOTE: ASCII only (cmd.exe reads .cmd in the ANSI codepage).
rem ============================================================

pushd "%~dp0.."
set "GAME_ROOT=%CD%"
popd

rem --- remember the real LOCALAPPDATA before we override it ---
set "_REAL_LOCALAPPDATA=%LOCALAPPDATA%"

rem --- redirect Godot user:// dir into the project so nothing is written outside ---
set "APPDATA=%GAME_ROOT%\.godot_userdata"
if not exist "%APPDATA%" mkdir "%APPDATA%" >nul 2>nul

rem --- also redirect LOCALAPPDATA: the GPU driver would otherwise write its
rem --- shader cache to C:\Users\...\AppData\Local\NVIDIA\GLCache (outside the
rem --- project).  Keep everything inside the project instead.
set "LOCALAPPDATA=%GAME_ROOT%\.godot_userdata\LocalAppData"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%" >nul 2>nul

rem --- locate godot.exe (no single hard-coded absolute path) ---
set "GODOT_EXE="
if defined GODOT_BIN set "GODOT_EXE=%GODOT_BIN%"
if not defined GODOT_EXE (
	for /f "delims=" %%i in ('where godot.exe 2^>nul') do (
		if not defined GODOT_EXE set "GODOT_EXE=%%i"
	)
)
if not defined GODOT_EXE if exist "D:\Godot\godot.exe" set "GODOT_EXE=D:\Godot\godot.exe"
if not defined GODOT_EXE if exist "%_REAL_LOCALAPPDATA%\Programs\Godot\godot.exe" set "GODOT_EXE=%_REAL_LOCALAPPDATA%\Programs\Godot\godot.exe"
if not defined GODOT_EXE if exist "%ProgramFiles%\Godot\godot.exe" set "GODOT_EXE=%ProgramFiles%\Godot\godot.exe"
if not defined GODOT_EXE if exist "C:\Program Files\Godot\godot.exe" set "GODOT_EXE=C:\Program Files\Godot\godot.exe"
