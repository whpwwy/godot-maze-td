@echo off
rem ================================================================
rem  Maze Tower Defense  -  double-click this file to play.
rem
rem  What it does:
rem    1. works out this project's root folder from this file's path
rem    2. locates the Godot 4 executable (PATH, GODOT_BIN, or common
rem       install locations) - no absolute path is baked in
rem    3. points Godot's user:// and the GPU shader cache at a folder
rem       inside this project, so nothing is written outside it
rem    4. starts the game immediately - there is no title screen
rem
rem  Optional: set GODOT_BIN to the full path of godot.exe if the
rem  auto-detection cannot find your installation.
rem ================================================================

call "%~dp0tools\_godot.cmd"

if not defined GODOT_EXE (
	echo.
	echo [ERROR] Could not find the Godot executable.
	echo.
	echo   * install Godot 4.7 or newer, then either
	echo       - add it to PATH, or
	echo       - set the environment variable GODOT_BIN to godot.exe
	echo.
	echo   * this project is plain GDScript and needs no build step
	echo.
	pause
	exit /b 1
)

echo Launching Maze Tower Defense...
echo   Godot : %GODOT_EXE%
echo   Folder: %GAME_ROOT%
echo.

"%GODOT_EXE%" --path "%GAME_ROOT%"
if errorlevel 1 (
	echo.
	echo [ERROR] Godot exited with an error. See the messages above.
	pause
)
exit /b 0
