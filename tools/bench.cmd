@echo off
rem ================================================================
rem  tools\bench.cmd  -  automated AI playthrough + performance bench.
rem
rem  Opens the real game window and lets a scripted AI play a whole
rem  match at 3x speed while performance is sampled.  On finish it
rem  writes bench_result.txt and autoplay_log.txt into the project's
rem  test-output folder and takes screenshots.
rem
rem  Extra arguments are forwarded, for example:
rem     bench.cmd --bench-mode=ceiling --bench-time=30
rem     bench.cmd --soak
rem ================================================================

call "%~dp0_run.cmd" --bench --bench-time=3600 --seed=20261008 --ledger-full %*

echo.
echo Bench finished. See bench_result.txt / autoplay_log.txt in the
echo project's test-output folder.
echo.
pause
exit /b 0
