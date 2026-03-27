@echo off
echo Starting Git Check...
cd c:\Users\ACER\Downloads\tooltracker-backend
git status > c:\Users\ACER\Downloads\tooltracker-backend\git_status.txt 2>&1
git remote -v >> c:\Users\ACER\Downloads\tooltracker-backend\git_status.txt 2>&1
echo Done. >> c:\Users\ACER\Downloads\tooltracker-backend\git_status.txt 2>&1
