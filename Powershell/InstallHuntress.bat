@echo off

rem This batch file was created as a wrapper for RMM tools that support Powershell scripts, but don't give the option to control the
rem executionpolicy options and/or pass arguments. 

rem This requires InstallHuntress.powershellv2.ps1 dated July 21, 2022 !
rem You can always find the most updated version here: https://github.com/huntresslabs/deployment-scripts/tree/main/Powershell

rem Replace __ACCOUNT_KEY__ below with your Huntress account key. 
set ACCTKEY=__ACCOUNT_KEY__

rem This batch file takes up to 2 arguments, your org key and a tag (optional)
rem
rem Example below will install using the org key "Johns IT" and attach the tag "production" to the end point:
rem      .\huntress.bat "Johns IT" "production"    
rem 
rem Example below will just install using the org key "IT Solutions"      
rem      .\huntress.bat "IT Solutions"

rem Some RMM agents are 32-bit only, so they will start 32-bit Powershell. If the 64-bit Powershell exists, we'll use that.
set POWERSHELL=powershell
if exist %SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe (
    set POWERSHELL=%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe
)

rem if 2 params were passed, the 2nd set is tags, 1st is org key
if [%~2]==[] goto NOTAGS
%POWERSHELL% -executionpolicy bypass -f ./InstallHuntress.powershellv2.ps1 -acctkey %ACCTKEY% -orgkey %1 -tags %2
goto END

rem if only 1 param was passed, it's the org key
:NOTAGS
%POWERSHELL% -executionpolicy bypass -f ./InstallHuntress.powershellv2.ps1 -acctkey %ACCTKEY% -orgkey %1


:END
