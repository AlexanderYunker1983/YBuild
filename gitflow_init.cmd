@echo off
cd ..
git branch --no-track production
git branch --set-upstream-to=origin/production production
git flow init -f -d
git config gitflow.branch.master production
git config gitflow.branch.develop master
git config gitflow.prefix.feature feature/
git config gitflow.prefix.release release/
git config gitflow.prefix.hotfix hotfix/
git config gitflow.prefix.bugfix bugfix/
git config gitflow.prefix.support support/