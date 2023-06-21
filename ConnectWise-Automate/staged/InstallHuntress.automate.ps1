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
# DISCLAIMED. IN NO EVENT SHALL HUNTRESS LABS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
# OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


# The Huntress installer needs an Account Key and an Organization Key (a user
# specified name or description) which is used to affiliate an Agent with a
# specific Organization within the Huntress Partner's Account. These keys can be
# hard coded below or passed in when the script is run.

# See https://support.huntress.io/article/7-using-account-and-organization-keys
# for more details.

# Usage:
# powershell -executionpolicy bypass -f ./InstallHuntress.powershellv1.ps1 [-acctkey <account_key>] [-orgkey <organization_key>]

# Optional command line params, this has to be the first line in the script.
param (
  [string]$acctkey,
  [string]$orgkey,
  [switch]$reregister,
  [switch]$reinstall
)

# The Huntress account secret comes from the Automate @acct_key@ global parameter.
$AccountKey = "@acct_key@"

# Use the Automate clientname as the Huntress organization key.
$OrganizationKey = "%clientname%"

# Set to "Continue" to enable verbose logging.
$DebugPreference = "SilentlyContinue"

##############################################################################
## The following should not need to be adjusted.

# Find poorly written code faster with the most stringent setting.
Set-StrictMode -Version Latest

# Do not modify the following variables.
# These are used by the Huntress support team when troubleshooting.
$ScriptVersion = "Version 2, major revision 7, 2023 May 1"
$ScriptType = "Automate"

# Check for an account key specified on the command line.
if ( ! [string]::IsNullOrEmpty($acctkey) ) {
    $AccountKey = $acctkey
}
$AccountKey = $AccountKey.Trim()

# Check for an organization key specified on the command line.
if ( ! [string]::IsNullOrEmpty($orgkey) ) {
    $OrganizationKey = $orgkey
}
$OrganizationKey = $OrganizationKey.Trim()

# Variables used throughout the Huntress Deployment Script.
$X64 = 64
$X86 = 32
$InstallerName = "HuntressInstaller.exe"
$InstallerPath = Join-Path $Env:TMP $InstallerName
$DebugLog = Join-Path $Env:TMP HuntressInstaller.log
$DownloadURL = "https://update.huntress.io/download/" + $AccountKey + "/" + $InstallerName
$HuntressAgentServiceName = "HuntressAgent"
$HuntressUpdaterServiceName = "HuntressUpdater"

$ScriptFailed = "Script Failed!"
$SupportMessage = "Please send the error message to the Huntress Team for help at support@huntress.com"

function Get-TimeStamp {
    return "[{0:yyyy/MM/dd} {0:HH:mm:ss}]" -f (Get-Date)
}

function LogMessage ($msg) {
    Add-Content $DebugLog "$(Get-TimeStamp) $msg"
    Write-Host "$(Get-TimeStamp) $msg"
}

function Test-Parameters {
    LogMessage "Verifying received parameters..."

    # Ensure mutually exclusive parameters were not both specified.
    if ($reregister -and $reinstall) {
        $err = "Cannot specify both `-reregister` and `-reinstall` parameters, exiting script!"
        LogMessage $err
        exit 1
    }

    # Ensure we have an account key (either hard coded or from the command line params).
    if ($AccountKey -eq "__ACCOUNT_KEY__") {
        $err = "AccountKey not set!"
        LogMessage $err
        throw $ScriptFailed + " " + $err
        exit 1
    } elseif ($AccountKey.length -ne 32) {
        $err = "Invalid AccountKey specified (incorrect length)!"
        LogMessage $err
        throw $ScriptFailed + " " + $err
        exit 1
    }

    # Ensure we have an organization key (either hard coded or from the command line params).
    if ($OrganizationKey -eq "__ORGANIZATION_KEY__") {
        $err = "OrganizationKey not specified!"
        LogMessage $err
        throw $ScriptFailed + " " + $err
        exit 1
    } elseif ($OrganizationKey.length -lt 1) {
        $err = "Invalid OrganizationKey specified (length is 0)!"
        LogMessage $err
        throw $ScriptFailed + " " + $err
        exit 1
    }
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

function Get-WindowsArchitecture {
    if ($env:ProgramW6432) {
        $WindowsArchitecture = $X64
    } else {
        $WindowsArchitecture = $X86
    }

    return $WindowsArchitecture
}

function verifyInstaller ($file) {
    # Ensure the installer was not modified during download by validating the file signature.
    $varChain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain
    try {
        $varChain.Build((Get-AuthenticodeSignature -FilePath "$file").SignerCertificate) | out-null
    } catch [System.Management.Automation.MethodInvocationException] {
        $err = (
            "ERROR: '$file' did not contain a valid digital certificate. " +
            "Something may have corrupted/modified the file during the download process. " +
            "If the problem persists please file a support ticket.")
        LogMessage $err
        LogMessage $SupportMessage
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }
}

function Get-Installer {
    $msg = "Downloading installer to '$InstallerPath'..."
    LogMessage $msg

    # Ensure a secure TLS version is used.
    $ProtocolsSupported = [enum]::GetValues('Net.SecurityProtocolType')
    if ( ($ProtocolsSupported -contains 'Tls13') -and ($ProtocolsSupported -contains 'Tls12') ){
        LogMessage "Using TLS 1.3 or 1.2..."
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
    } else {
        LogMessage "Using TLS 1.2..."
        try {
            # In certain .NET 4.0 patch levels, SecurityProtocolType does not have a TLS 1.2 entry.
            # Rather than check for 'Tls12', we force-set TLS 1.2 and catch the error if it's truly unsupported.
            [Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        } catch {
            $msg = $_.Exception.Message
            $err = "ERROR: Unable to use a secure version of TLS. Please verify Hotfix KB3140245 is installed."
            LogMessage $msg
            LogMessage $err
            throw $ScriptFailed + " " + $msg + " " + $err
        }
    }

    $WebClient = New-Object System.Net.WebClient

    try {
        $WebClient.DownloadFile($DownloadURL, $InstallerPath)
    } catch {
        $msg = $_.Exception.Message
        $err = (
            "ERROR: Failed to download the Huntress Installer. Please try accessing $DownloadURL " +
            "from a web browser on the host where the download failed. If the issue persists, please " +
            "send the error message to the Huntress Team for help at support@huntress.com.")
        LogMessage $msg
        LogMessage $err
        throw $ScriptFailed + " " + $err + " " + $msg
    }

    if ( ! (Test-Path $InstallerPath) ) {
        $err = "ERROR: Failed to download the Huntress Installer from $DownloadURL."
        LogMessage $err
        LogMessage $SupportMessage
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    $msg = "Installer downloaded to '$InstallerPath'..."
    LogMessage $msg
}

function Install-Huntress ($OrganizationKey) {
    LogMessage "Checking for installer '$InstallerPath'..."
    if ( ! (Test-Path $InstallerPath) ) {
        $err = "ERROR: The installer was unexpectedly removed from $InstallerPath"
        $msg = (
            "A security product may have quarantined the installer. Please check " +
            "your logs. If the issue continues to occur, please send the log to the Huntress " +
            "Team for help at support@huntresslabs.com")
        LogMessage $err
        LogMessage $msg
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    verifyInstaller($InstallerPath)

    $msg = "Executing installer..."
    LogMessage $msg

    $timeout = 30 # Seconds
    $process = Start-Process $InstallerPath "/ACCT_KEY=`"$AccountKey`" /ORG_KEY=`"$OrganizationKey`" /S" -PassThru
    try {
        $process | Wait-Process -Timeout $timeout -ErrorAction Stop
    } catch {
        $process | Stop-Process -Force
        $err = "ERROR: Installer failed to complete in $timeout seconds."
        LogMessage $err
        LogMessage $SupportMessage
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }
}

function Test-Installation {
    LogMessage "Verifying installation..."

    # Give the agent a few seconds to start and register.
    Start-Sleep -Seconds 8

    # Ensure we resolve the correct Huntress directory regardless of operating system or process architecture.
    $WindowsArchitecture = Get-WindowsArchitecture
    if ($WindowsArchitecture -eq $X86) {
        $HuntressDirPath = Join-Path $Env:ProgramFiles "Huntress"
    } elseif ($WindowsArchitecture -eq $X64) {
        $HuntressDirPath = Join-Path $Env:ProgramW6432 "Huntress"
    } else {
        $err = "ERROR: Failed to determine the Windows Architecture. Received $WindowsArchitecture."
        LogMessage $err
        LogMessage $SupportMessage
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    $HuntressAgentPath = Join-Path $HuntressDirPath "HuntressAgent.exe"
    $HuntressUpdaterPath = Join-Path $HuntressDirPath "HuntressUpdater.exe"
    $hUpdaterPath = Join-Path $HuntressDirPath "hUpdate.exe"
    $HuntressKeyPath = "HKLM:\SOFTWARE\Huntress Labs\Huntress"
    $AgentIdKeyValueName = "AgentId"
    $OrganizationKeyValueName = "OrganizationKey"
    $TagsValueName = "Tags"

    # Ensure the critical files were created.
    foreach ( $file in ($HuntressAgentPath, $HuntressUpdaterPath, $hUpdaterPath) ) {
        if ( ! (Test-Path $file) ) {
            $err = "ERROR: $file did not exist."
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }
    }

    # Ensure the Huntress registry key is present.
    if ( ! (Test-Path $HuntressKeyPath) ) {
        $err = "ERROR: The registry key '$HuntressKeyPath' did not exist."
        LogMessage $err
        LogMessage $SupportMessage
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    $HuntressKeyObject = Get-ItemProperty $HuntressKeyPath

    # Ensure the Huntress registry values are present.
    foreach ( $value in ($AgentIdKeyValueName, $OrganizationKeyValueName, $TagsValueName) ) {
        If ( ! (Get-Member -inputobject $HuntressKeyObject -name $value -Membertype Properties) ) {
            $err = "ERROR: The registry value $value did not exist within $HuntressKeyPath."
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }
    }

    # Ensure the services are installed and running.
    foreach ( $svc in ($HuntressAgentServiceName, $HuntressUpdaterServiceName) ) {
        # service installed?
        if ( ! (Confirm-ServiceExists($svc)) ) {
            $err = "ERROR: The $svc service is not installed."
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }

        # service running?
        if ( ! (Confirm-ServiceRunning($svc)) ) {
            $err = "ERROR: The $svc service is not running."
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }
    }

    # Verify the agent registered.
    If ($HuntressKeyObject.$AgentIdKeyValueName -eq 0) {
        $err = ("ERROR: The agent did not register. Check the log (%ProgramFiles%\Huntress\HuntressAgent.log) for errors.")
        LogMessage $err
        LogMessage $SupportMessage
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    $msg = "Installation verified!"
    LogMessage $msg
}

function StopHuntressServices {
    LogMessage "Stopping Huntress services..."
    Stop-Service -Name "$HuntressAgentServiceName"
    Stop-Service -Name "$HuntressUpdaterServiceName"
}

function StartHuntressServices {
    LogMessage "Starting Huntress services..."
    Start-Service -Name "$HuntressAgentServiceName"
    Start-Service -Name "$HuntressUpdaterServiceName"
}

function PrepReregister {
    LogMessage "Preparing to re-register agent..."
    StopHuntressServices

    $HuntressKeyPath = "HKLM:\SOFTWARE\Huntress Labs\Huntress"
    Remove-Item -Path "$HuntressKeyPath" -Recurse -ErrorAction SilentlyContinue
}

function main () {
    LogMessage "Script type: '$ScriptType'"
    LogMessage "Script version: '$ScriptVersion'"
    LogMessage "Host name: '$env:computerName'"
    $os = (get-WMiObject -computername $env:computername -Class win32_operatingSystem).caption
    LogMessage "Host OS: '$os'"
    LogMessage "Host Architecture: '$(Get-WindowsArchitecture)'"
    LogMessage "Re-register agent: '$reregister'"
    LogMessage "Installer location: '$InstallerPath'"
    LogMessage "Installer log: '$DebugLog'"

    $masked = $AccountKey.Substring(0,10) + "XXXXXXXXXXXXXXXXXXXXXXX"
    LogMessage "AccountKey: '$masked'"
    LogMessage "OrganizationKey: '$OrganizationKey'"

    Test-Parameters

    if ($reregister) {
        PrepReregister
    } elseif ($reinstall) {
        LogMessage "Re-installing agent..."
        if ( !(Confirm-ServiceExists($HuntressAgentServiceName)) ) {
            $err = "The Huntress Agent is NOT installed; nothing to re-install. Exiting."
            LogMessage "$err"
            exit 1
        }
        StopHuntressServices
    } else {
        LogMessage "Checking for HuntressAgent service..."
        if ( Confirm-ServiceExists($HuntressAgentServiceName) ) {
            StartHuntressServices
            $err = "The Huntress Agent is already installed. Exiting."
            LogMessage "$err"
            exit 0
        }
    }

    Get-Installer
    Install-Huntress $OrganizationKey
    Test-Installation
    LogMessage "Huntress Agent successfully installed!"
}

try
{
    main
} catch {
    $ErrorMessage = $_.Exception.Message
    LogMessage $ErrorMessage
    exit 1
}
