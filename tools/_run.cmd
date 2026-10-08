@echo off
rem ============================================================
rem  tools\_run.cmd  <godot args...>
rem  Runs Godot in the right environment (godot path + in-project user dir).
rem ============================================================
call "%~dp0_godot.cmd"
if not defined GODOT_EXE (
	echo [ERROR] Godot executable not found.
	echo         Install Godot 4.7+ and add it to PATH, or set GODOT_BIN to godot.exe.
	exit /b 1
)
"%GODOT_EXE%" --path "%GAME_ROOT%" %*
exit /b %ERRORLEVEL%
