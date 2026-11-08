@echo off
setlocal
set GRADLE_VERSION=8.14.3
set BASE=%USERPROFILE%\.gradle\pcwork-wrapper
set DIST=%BASE%\gradle-%GRADLE_VERSION%
set ARCHIVE=%BASE%\gradle-%GRADLE_VERSION%-bin.zip
if not exist "%DIST%\bin\gradle.bat" (
  if not exist "%BASE%" mkdir "%BASE%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $urls=@('https://downloads.gradle.org/distributions/gradle-%GRADLE_VERSION%-bin.zip','https://services.gradle.org/distributions/gradle-%GRADLE_VERSION%-bin.zip'); $ok=$false; foreach($url in $urls){ try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile '%ARCHIVE%'; $zip=[System.IO.Compression.ZipFile]::OpenRead('%ARCHIVE%'); $zip.Dispose(); $ok=$true; break } catch { Remove-Item -Force '%ARCHIVE%' -ErrorAction SilentlyContinue } }; if(-not $ok){ throw 'Unable to download a valid Gradle distribution from configured mirrors.' }; Expand-Archive -Force '%ARCHIVE%' '%BASE%'"
  if errorlevel 1 exit /b 1
)
call "%DIST%\bin\gradle.bat" %*
exit /b %ERRORLEVEL%
