@echo off
cd c:\Users\ACER\Downloads\tooltracker-backend
git status > %~dp0git_status.txt
git remote -v >> %~dp0git_status.txt
echo DONE >> %~dp0git_status.txt
