@echo off
setlocal EnableExtensions
cd /d "%~dp0"
"C:\Program Files\swipl\bin\swipl.exe" -q -f none -s "%~dp0selfplay.pl" -g main -t halt