# Copyright (c) 2017 Huntress Labs, Inc.
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
# DISCLAIMED. IN NO EVENT SHALL OPENDNS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
# OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# The Huntress installer needs an Organization Key (user specified name or
# description) which is used to affiliate an Agent with a specific
# Organization within the Huntress Partner's Account. The Organization Key is
# passed in when the script is scheduled to run.

# Replace __KEY__ with your account key
# See https://support.huntress.io/article/7-using-account-and-organization-keys
$AccountSecretKey = "__KEY__"

# OrganizationKey is passed in when script is scheduled
$OrganizationKey = $env:ORG_KEY

# Variables used throughout the Huntress Deployment Script
$X64 = 64
$X86 = 32
$InstallerName = "HuntressAgent.exe"
$InstallerPath = Join-Path $Env:TMP $InstallerName
$DownloadURL = "https://huntress.io/download/" + $AccountSecretKey + "/" + $InstallerName

function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}


function Get-WindowsArchitecture {
    If ($env:ProgramW6432) {
        $WindowsArchitecture = $X64
    } Else {
        $WindowsArchitecture = $X86
    }

    return $WindowsArchitecture
}

function Get-Installer {
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile($DownloadURL, $InstallerPath)
    If ( ! (Test-Path $InstallerPath)) {
        $DownloadError = "Failed to download the Huntress Installer from $DownloadURL"
        Write-Host "$(Get-TimeStamp) $DownloadError"
        Write-Host ("$(Get-TimeStamp) Verify you correctly added your secret key to the first line of the " +
                               "Huntress Deployment Script.")
        throw $DownloadError
    }
}

function Install-Huntress ($OrganizationKey) {
    If ( ! (Test-Path $InstallerPath)) {
        $InstallerError = "The installer was unexpectedly removed from $InstallerPath"
        Write-Host "$(Get-TimeStamp) $InstallerError"
        Write-Host ("$(Get-TimeStamp) A security product may have quarantined the installer. Please check " +
                               "your logs. If the issue continues to occur, please send this log to the Huntress " +
                               "Team for help via support@huntresslabs.com")
        throw $InstallerError
    }

    Start-Process $InstallerPath "/ACCT_KEY=`"$AccountSecretKey`" /ORG_KEY=`"$OrganizationKey`" /S" -Wait
}


function Test-Installation {
    # Ensure we resolve the correct Huntress directory regardless of operating system or process architecture.
    $WindowsArchitecture = Get-WindowsArchitecture
    If ($WindowsArchitecture -eq $X86) {
        $HuntressDirPath = Join-Path $Env:ProgramFiles "Huntress"
    } ElseIf ($WindowsArchitecture -eq $X64) {
        $HuntressDirPath = Join-Path $Env:ProgramW6432 "Huntress"
    } Else {
        $ArchitectureError = "Failed to determine the Windows Architecture. Received $WindowsArchitecure."
        Write-Host "$(Get-TimeStamp) $ArchitectureError"
        Write-Host ("$(Get-TimeStamp) Please send this log to the Huntress Team for help via " +
                               "support@huntresslabs.com")
        throw $ArchitectureError
    }

    $HuntressAgentPath = Join-Path $HuntressDirPath "HuntressAgent.exe"
    $HuntressUpdaterPath = Join-Path $HuntressDirPath "HuntressUpdater.exe"
    $WyUpdaterPath = Join-Path $HuntressDirPath "wyUpdate.exe"
    $HuntressKeyPath = "HKLM:\SOFTWARE\Huntress Labs\Huntress"
    $AccountKeyValueName = "AccountKey"
    $OrganizationKeyValueName = "OrganizationKey"
    $TagsValueName = "Tags"

    # Ensure the Huntress installation directory was created.
    If ( ! (Test-Path $HuntressDirPath)) {
        $HuntressInstallationError = "The expected Huntress directory $HuntressDirPath did not exist."
        Write-Host "$(Get-TimeStamp) $HuntressInstallationError"
        Write-Host ("$(Get-TimeStamp) Please send this log to the Huntress Team for help via " +
                               "support@huntresslabs.com")
        exit 1
    }

    # Ensure the Huntress agent was created.
    If ( ! (Test-Path $HuntressAgentPath)) {
        $HuntressInstallationError = "The expected Huntress agent $HuntressAgentPath did not exist."
        Write-Host "$(Get-TimeStamp) $HuntressInstallationError"
        Write-Host ("$(Get-TimeStamp) Please send this log to the Huntress Team for help via " +
                               "support@huntresslabs.com")
        exit 1
    }

    # Ensure the Huntress updater was created.
    If ( ! (Test-Path $HuntressUpdaterPath)) {
        $HuntressInstallationError = "The expected Huntress updater $HuntressUpdaterPath did not exist."
        Write-Host "$(Get-TimeStamp) $HuntressInstallationError"
        Write-Host ("$(Get-TimeStamp) Please send this log to the Huntress Team for help via " +
                               "support@huntresslabs.com")
        exit 1
    }

    # Ensure our wyUpdate dependency was created.
    If ( ! (Test-Path $WyUpdaterPath)) {
        $HuntressInstallationError = "The expected wyUpdate dependency $WyUpdaterPath did not exist."
        Write-Host "$(Get-TimeStamp) $HuntressInstallationError"
        Write-Host ("$(Get-TimeStamp) Please send this log to the Huntress Team for help via " +
                               "support@huntresslabs.com")
        exit 1
    }

    # Ensure the Huntress registry key is present.
     If ( ! (Test-Path $HuntressKeyPath)) {
        $HuntressRegistryError = "The expected Huntress registry key $HuntressKeyPath did not exist."
        Write-Host "$(Get-TimeStamp) $HuntressRegistryError"
        Write-Host ("$(Get-TimeStamp) Please send this log to the Huntress Team for help via " +
                               "support@huntresslabs.com")
        exit 1
    }

    $HuntressKeyObject = Get-ItemProperty $HuntressKeyPath

    # Ensure the Huntress registry key is not empty.
    If ( ! ($HuntressKeyObject)) {
        $HuntressRegistryError = "The Huntress registry key was empty."
        Write-Host "$(Get-TimeStamp) $HuntressRegistryError"
        Write-Host ("$(Get-TimeStamp) Please send this log to the Huntress Team for help via " +
                               "support@huntresslabs.com")
        exit 1
    }

    # Ensure the AccountKey value is present within the Huntress registry key.
    If ( ! (Get-Member -inputobject $HuntressKeyObject -name $AccountKeyValueName -Membertype Properties)) {
        $HuntressRegistryError = ("The expected Huntress registry value $AccountKeyValueName did not exist " +
                                  "within $HuntressKeyPath")
        Write-Host "$(Get-TimeStamp) $HuntressRegistryError"
        Write-Host ("$(Get-TimeStamp) Please send this log to the Huntress Team for help via " +
                               "support@huntresslabs.com")
        exit 1
    }

    # Ensure the OrganizationKey value is present within the Huntress registry key.
    If ( ! (Get-Member -inputobject $HuntressKeyObject -name $OrganizationKeyValueName -Membertype Properties)) {
        $HuntressRegistryError = ("The expected Huntress registry value $OrganizationKeyValueName did not exist " +
                                  "within $HuntressKeyPath")
        Write-Host "$(Get-TimeStamp) $HuntressRegistryError"
        Write-Host ("$(Get-TimeStamp) Please send this log to the Huntress Team for help via " +
                               "support@huntresslabs.com")
        exit 1
    }

    # Ensure the Tags value is present within the Huntress registry key.
    If ( ! (Get-Member -inputobject $HuntressKeyObject -name $TagsValueName -Membertype Properties)) {
        $HuntressRegistryError = ("The expected Huntress registry value $TagsKeyValueName did not exist within " +
                                  "$HuntressKeyPath")
        Write-Host "$(Get-TimeStamp) $HuntressRegistryError"
        Write-Host ("$(Get-TimeStamp) Please send this log to the Huntress Team for help via " +
                               "support@huntresslabs.com")
        exit 1
    }
}


function main {
    # TODO - Log debug information (OS, Arch, Language, etc)
    if ($AccountSecretKey -eq "__KEY__")
    {
        Write-Warning "AccountSecretKey not set, exiting script!"
        exit 1
    }
    if ($OrganizationKey -eq "ChangeMe")
    {
        Write-Warning "ORG_KEY not specified, exiting script!"
        exit 1
    }
    Write-Host "ORG_KEY Specified: " $OrganizationKey
    Get-Installer
    Install-Huntress $OrganizationKey
    Test-Installation
}

main
