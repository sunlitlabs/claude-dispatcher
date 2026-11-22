@echo off
powershell -NoLogo -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\session-registry\dispatch.ps1" %*
