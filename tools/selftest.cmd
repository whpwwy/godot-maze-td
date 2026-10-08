@echo off
rem ================================================================
rem  tools\selftest.cmd  -  headless logic self-test (no window).
rem
rem  Runs every assertion in src\SelfTest.gd: maze generation, flow
rem  field pathfinding, tower blocking, enemy movement, bullets,
rem  economy ledger, tower formulas, wave table, capacity limits.
rem
rem  The result log is written by the game itself into the project's
rem  test-output folder (search for SELFTEST_RESULT=PASS).
rem ================================================================

call "%~dp0_run.cmd" --headless --selftest

echo.
echo Self-test finished. Look for the line "SELFTEST_RESULT=PASS"
echo in the log written under the project's test-output folder.
echo.
pause
exit /b 0
