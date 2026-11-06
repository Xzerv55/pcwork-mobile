@echo off
set GRADLE_VERSION=8.4
set BASE=%USERPROFILE%\.gradle\pcwork-wrapper
set DIST=%BASE%\gradle-%GRADLE_VERSION%
if not exist "%DIST%\bin\gradle.bat" (
  if not exist "%BASE%" mkdir "%BASE%"
  powershell -NoProfile -Command "Invoke-WebRequest -Uri https://services.gradle.org/distributions/gradle-%GRADLE_VERSION%-bin.zip -OutFile '%BASE%\gradle-%GRADLE_VERSION%-bin.zip'"
  powershell -NoProfile -Command "Expand-Archive -Force '%BASE%\gradle-%GRADLE_VERSION%-bin.zip' '%BASE%'"
)
call "%DIST%\bin\gradle.bat" %*
