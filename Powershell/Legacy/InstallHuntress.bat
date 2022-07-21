@echo off

rem This batch file was created as a wrapper for RMM tools that support
rem Powershell scripts, but don't give you the option to control the
rem executionpolicy options and pass arguments.

rem Replace __ACCOUNT_KEY__ with your Huntress account key.
rem This batch file takes a single argument, the Organization Key.
rem This can be passed in when the script is run.
set ACCTKEY=__ACCOUNT_KEY__

rem Some RMM agents are 32-bit only, so they will start 32-bit Powershell.
rem If the 64-bit Powershell exists, we'll use that.
set POWERSHELL=powershell
if exist %SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe (
    set POWERSHELL=%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe
)

rem We assume the RMM copies this batch script and the Powershell script to the same directory
%POWERSHELL% -executionpolicy bypass -f ./InstallHuntress.powershellv1.ps1 -acctkey %ACCTKEY% -orgkey %1
