# Copyright (c) 2020 Huntress Labs, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the Huntress Labs nor the names of its contributors
#      may be used to endorse or promote products derived from this software
#      without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL HUNTRESS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
# OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


# The Huntress installer needs an Account Key and an Organization Key (a user
# specified name or description) which is used to affiliate an Agent with a
# specific Organization within the Huntress Partner's Account. The Organization
# Key can hard coded below or passed in when the script is run.

# See https://support.huntress.io/article/7-using-account-and-organization-keys
# for more details.

# Usage:
# powershell -executionpolicy bypass -f ./InstallHuntress.powershellv1.ps1 [-acctkey <account_key>] [-orgkey <organization_key>]

# !!! You can hard code your account and organization keys below or specify them on the command line

# optional command line params, this has to be the first line in the script
param (
  [string]$acctkey,
  [string]$orgkey,
  [switch]$reregister,
  [switch]$reinstall
)

# Replace __ACCOUNT_KEY__ with your account secret key
$AccountKey = "__ACCOUNT_KEY__"

# Replace __ORGANIZATION_KEY__ with a unique identifier for the organization/client
$OrganizationKey = "__ORGANIZATION_KEY__"

# set to 1 to enable verbose logging
$DebugPrintEnabled = 0

##############################################################################
## The following should not need to be adjusted

# Find poorly written code faster with the most stringent setting
Set-StrictMode -Version Latest

# do not modify the following variables
# these are used by the Huntress support team when troubleshooting
$ScriptVersion = "2020 February 1; revision 1"
$ScriptType = "PowerShell"

# check for an account key specified on the command line
if ( ! [string]::IsNullOrEmpty($acctkey)) {
    $AccountKey = $acctkey
}

# check for an organization key specified on the command line
if ( ! [string]::IsNullOrEmpty($orgkey)) {
    $OrganizationKey = $orgkey
}
$OrganizationKey = $OrganizationKey.Trim()

# Variables used throughout the Huntress Deployment Script
$X64 = 64
$X86 = 32
$InstallerName = "HuntressInstaller.exe"
$InstallerPath = Join-Path $Env:TMP $InstallerName
$DownloadURL = "https://update.huntress.io/download/" + $AccountKey + "/" + $InstallerName
$HuntressAgentServiceName = "HuntressAgent"
$HuntressUpdaterServiceName = "HuntressUpdater"

$ScriptFailed = "Script Failed!"

$SupportMessage = "Please send the error message to the Huntress Team for help at support@huntresslabs.com"

function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

function Confirm-ServiceExists ($service) {
    if (Get-Service $service -ErrorAction SilentlyContinue) {
        return $true
    }
    return $false
}

function Confirm-ServiceRunning ($service) {
    $arrService = Get-Service $service
    $status = $arrService.Status.ToString()
    if ($status.ToLower() -eq 'running') {
        return $true
    }
    return $false
}

function Debug-Print ($msg) {
    if ($DebugPrintEnabled -eq 1) {
        Write-Host "$(Get-TimeStamp) [DEBUG] $msg"
    }
}

function Get-WindowsArchitecture {
    if ($env:ProgramW6432) {
        $WindowsArchitecture = $X64
    } else {
        $WindowsArchitecture = $X86
    }

    return $WindowsArchitecture
}

function Get-Installer {
    Debug-Print("downloading installer...")

    # Ensure a secure TLS version is used
    # $ProtocolsSupported = [enum]::GetValues('Net.SecurityProtocolType')
    # if ($ProtocolsSupported -contains 'Tls13') {
    #     [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 12288)
    # } elseif ($ProtocolsSupported -contains 'Tls12') {
    #     [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
    # } else {
    #     $err = "ERROR: This host does not support a secure version of TLS. Please patch the OS and try again."
    #     Write-Host "$(Get-TimeStamp) $err"
    #     throw $ScriptFailed + " " + $err
    # }

    # The above does not work on Windows 7 SP1 with PS 2.0 which supports TLS12, but TLS12 not listed
    # in the protocol types
    #
    # PS C:\Users\admin> $PSVersionTable.PSVersion.ToString()
    # 2.0
    # PS C:\Users\admin> [enum]::GetValues('Net.SecurityProtocolType')
    # Ssl3
    # Tls
    # PS C:\Users\admin>  [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
    # PS C:\Users\admin>  [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 12288)
    # Exception setting "SecurityProtocol": "The requested security protocol is not supported."
    # At line:1 char:29
    # +  [Net.ServicePointManager]:: <<<< SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 12288)
    #     + CategoryInfo          : InvalidOperation: (:) [], RuntimeException
    #     + FullyQualifiedErrorId : PropertyAssignmentException

    # For TLS 1.2 support
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
    } catch {
        $msg = $_.Exception.Message
        $err = "ERROR: Unable to enable TLS 1.2."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $msg"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $msg + " " + $SupportMessage
    }

    $WebClient = New-Object System.Net.WebClient

    try {
        $WebClient.DownloadFile($DownloadURL, $InstallerPath)
    } catch {
        $msg = $_.Exception.Message
        $err = "ERROR: Download from $DownloadURL failed."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $msg"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $msg + " " + $SupportMessage
    }

    if ( ! (Test-Path $InstallerPath) ) {
        $err = "ERROR: Failed to download the Huntress Installer from $DownloadURL."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }
    Debug-Print("installer downloaded to $InstallerPath...")
}

function Install-Huntress ($OrganizationKey) {
    Debug-Print("Checking for installer file...$InstallerPath")
    if ( ! (Test-Path $InstallerPath) ) {
        $err = "ERROR: The installer was unexpectedly removed from $InstallerPath"
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host ("$(Get-TimeStamp) A security product may have quarantined the installer. Please check " +
                               "your logs. If the issue continues to occur, please send the log to the Huntress " +
                               "Team for help at support@huntresslabs.com")
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    Debug-Print("Executing installer...")
    $timeout = 30 # seconds
    $process = Start-Process $InstallerPath "/ACCT_KEY=`"$AccountKey`" /ORG_KEY=`"$OrganizationKey`" /S" -PassThru
    try {
        $process | Wait-Process -Timeout $timeout -ErrorAction Stop
    } catch {
        $process | Stop-Process -Force
        $err = "ERROR: Installer failed to complete in $timeout seconds."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }
}

function Test-Installation {
    Debug-Print("Verifying installation...")

    # Give the agent a few seconds to start and register
    Start-Sleep -Seconds 8

    # Ensure we resolve the correct Huntress directory regardless of operating system or process architecture.
    $WindowsArchitecture = Get-WindowsArchitecture
    if ($WindowsArchitecture -eq $X86) {
        $HuntressDirPath = Join-Path $Env:ProgramFiles "Huntress"
    } elseif ($WindowsArchitecture -eq $X64) {
        $HuntressDirPath = Join-Path $Env:ProgramW6432 "Huntress"
    } else {
        $err = "ERROR: Failed to determine the Windows Architecture. Received $WindowsArchitecture."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    $HuntressAgentPath = Join-Path $HuntressDirPath "HuntressAgent.exe"
    $HuntressUpdaterPath = Join-Path $HuntressDirPath "HuntressUpdater.exe"
    $WyUpdaterPath = Join-Path $HuntressDirPath "wyUpdate.exe"
    $HuntressKeyPath = "HKLM:\SOFTWARE\Huntress Labs\Huntress"
    $AgentIdKeyValueName = "AgentId"
    $OrganizationKeyValueName = "OrganizationKey"
    $TagsValueName = "Tags"

    # Ensure the Huntress installation directory was created.
    if ( ! (Test-Path $HuntressDirPath) ) {
        $err = "ERROR: The expected Huntress directory $HuntressDirPath did not exist."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    # Ensure the Huntress agent was created.
    if ( ! (Test-Path $HuntressAgentPath) ) {
        $err = "ERROR: The expected Huntress agent $HuntressAgentPath did not exist."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    # Ensure the Huntress updater was created.
    if ( ! (Test-Path $HuntressUpdaterPath) ) {
        $err = "ERROR: The Huntress updater ($HuntressUpdaterPath) did not exist."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    # Ensure our wyUpdate dependency was created.
    if ( ! (Test-Path $WyUpdaterPath) ) {
        $err = "ERROR: The wyUpdate executable ($WyUpdaterPath) did not exist."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    # Ensure the Huntress registry key is present.
    if ( ! (Test-Path $HuntressKeyPath) ) {
        $err = "ERROR: The Huntress registry key '$HuntressKeyPath' did not exist."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    $HuntressKeyObject = Get-ItemProperty $HuntressKeyPath

    # Ensure the Huntress registry key is not empty.
    if ( ! ($HuntressKeyObject) ) {
        $err = "ERROR: The Huntress registry key was empty."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    # Ensure the AgentId value is present within the Huntress registry key.
    If ( ! (Get-Member -inputobject $HuntressKeyObject -name $AgentIdKeyValueName -Membertype Properties) ) {
        $err = "ERROR: The registry value $AgentIdKeyValueName did not exist within $HuntressKeyPath."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    # Ensure the OrganizationKey value is present within the Huntress registry key.
    if ( ! (Get-Member -inputobject $HuntressKeyObject -name $OrganizationKeyValueName -Membertype Properties) ) {
        $err = "ERROR: The registry value $OrganizationKeyValueName did not exist within $HuntressKeyPath"
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    # Ensure the Tags value is present within the Huntress registry key.
    if ( ! (Get-Member -inputobject $HuntressKeyObject -name $TagsValueName -Membertype Properties) ) {
        $err = "ERROR: The registry value $TagsValueName did not exist within $HuntressKeyPath"
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    # Ensure the service was installed
    if ( ! (Confirm-ServiceExists($HuntressAgentServiceName)) ) {
        $err = "ERROR: The Huntress Agent service did not install."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    # Verify service was started
    if ( ! (Confirm-ServiceRunning($HuntressAgentServiceName)) ) {
        $err = "ERROR: The Huntress Agent service is not running."
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    # Ensure the AgentId value is set within the Huntress registry key.
    If ($HuntressKeyObject.$AgentIdKeyValueName -eq 0) {
        $err = ("ERROR: The agent did not register. Check the log (%ProgramFiles%\Huntress\HuntressAgent.log) for errors.")
        Write-Host "$(Get-TimeStamp) $err"
        Write-Host "$(Get-TimeStamp) $SupportMessage"
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    Debug-Print("Installation verified...")
}

function StopHuntressServices {
    Write-Host "$(Get-TimeStamp) Stopping Huntress services"
    Stop-Service -Name "$HuntressAgentServiceName"
    Stop-Service -Name "$HuntressUpdaterServiceName"
}

function PrepReregister {
    Write-Host "$(Get-TimeStamp) prepping to reregister agent"
    StopHuntressServices

    $HuntressKeyPath = "HKLM:\SOFTWARE\Huntress Labs\Huntress"
    Remove-Item -Path "$HuntressKeyPath" -Recurse -ErrorAction SilentlyContinue
}

function main () {
    if ($reregister -And $reinstall) {
        Write-Warning "$(Get-TimeStamp) Cannot specify `-reregister` and `-reinstall` flags"
        exit 1
    }
    # make sure we have an account key (either hard coded or from the command line params)
    Debug-Print("Checking for AccountKey...")
    if ($AccountKey -eq "__ACCOUNT_KEY__") {
        Write-Warning "$(Get-TimeStamp) AccountKey not set, exiting script!"
        exit 1
    } elseif ($AccountKey.length -ne 32) {
        Write-Warning "$(Get-TimeStamp) Invalid AccountKey specified, exiting script!"
        exit 1
    }

    # make sure we have an org key (either hard coded or from the command line params)
    if ($OrganizationKey -eq "__ORGANIZATION_KEY__") {
        Write-Warning "$(Get-TimeStamp) OrganizationKey not specified, exiting script!"
        exit 1
    } elseif ($OrganizationKey.length -lt 1) {
        Write-Warning "$(Get-TimeStamp) Invalid OrganizationKey specified (length is 0), exiting script!"
        exit 1
    }

    Write-Host "$(Get-TimeStamp) Script type: $ScriptType"
    Write-Host "$(Get-TimeStamp) Script version: $ScriptVersion"
    Write-Host "$(Get-TimeStamp) Host name: $env:computerName"
    Write-Host "$(Get-TimeStamp) Host OS: " (get-WMiObject -computername $env:computername -Class win32_operatingSystem).caption
    Write-Host "$(Get-TimeStamp) Host Architecture: " (Get-WindowsArchitecture)
    $masked = $AccountKey.Substring(0,8) + "XXXXXXXXXXXXXXXXXXXXXXX"
    Write-Host "$(Get-TimeStamp) AccountKey: $masked"
    Write-Host "$(Get-TimeStamp) OrganizationKey: " $OrganizationKey
    Write-Host "$(Get-TimeStamp) reregister agent: " $reregister

    if ($reregister) {
        PrepReregister
    } elseif ($reinstall) {
        Write-Host "$(Get-TimeStamp) Re-installing agent"
        StopHuntressServices
    } else {
        Debug-Print("Checking for HuntressAgent service...")
        if ( Confirm-ServiceExists($HuntressAgentServiceName)) {
            $err = "The Huntress Agent is already installed. Exiting."
            Write-Host "$(Get-TimeStamp) $err"
            exit 0
        }
    }

    Get-Installer
    Install-Huntress $OrganizationKey
    Test-Installation
    Write-Host "$(Get-TimeStamp) Huntress Agent successfully installed"
}

try
{
    main
} catch {
    $ErrorMessage = $_.Exception.Message
    Write-Host "$(Get-TimeStamp) $ErrorMessage"
    exit 1
}
