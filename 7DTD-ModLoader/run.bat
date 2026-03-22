@echo off
set "script=%~dp0ModLoader.ps1"
set "scriptdir=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "Start-Process powershell -Verb RunAs -WorkingDirectory '%scriptdir%' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%script%\"'"
exit