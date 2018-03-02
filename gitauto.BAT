@echo off
git status
git add .
git commit -m "upd"
@echo on
set /p branchname="Enter Branch NAME: "
git push origin %branchname%