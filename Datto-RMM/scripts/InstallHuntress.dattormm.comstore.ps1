# Copyright (c) 2023 Huntress Labs, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the Huntress Labs nor the names of its contributors may be used to endorse or promote products derived from this software
#      without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL HUNTRESS LABS BE LIABLE FOR ANY DIRECT, 
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS 
# OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Authors: Alan Bishop, Sharon Martin, John Ferrell, Dave Kleinatland, Cameron Granger


# The Huntress installer needs an Account Key and an Organization Key (a user specified name or description) which is used to affiliate an Agent with a
# specific Organization within the Huntress Partner's Account. These keys can be hard coded below or passed in when the script is run.
# For more details, see our KB article  https://support.huntress.io/hc/en-us/articles/4404004936339-Deploying-Huntress-with-PowerShell

# Usage (remove brackets [] and substitute <variable> for your value):
# powershell -executionpolicy bypass -f ./InstallHuntress.powershellv2.ps1 [-acctkey <account_key>] [-orgkey <organization_key>] [-tags <tags>] [-reregister] [-reinstall] [-uninstall] [-repair]
#
# example:
# powershell -executionpolicy bypass -f ./InstallHuntress.powershellv2.ps1 -acctkey "0b8a694b2eb7b642069" -orgkey "Buzzword Company Name" -tags "production,US West" 

# Optional command line params, this has to be the first line in the script.
param (
  [string]$acctkey,
  [string]$orgkey,
  [string]$tags,
  [switch]$reregister,
  [switch]$reinstall,
  [switch]$uninstall, 
  [switch]$repair
)

$TagsKey = "__TAGS__"
if ($env:HUNTRESS_TAGS) {
    $TagsKey = $env:HUNTRESS_TAGS
}

# The account key should be stored in the DattoRMM account variable HUNTRESS_ACCOUNT_KEY
$AccountKey = "__ACCOUNT_KEY__"
if ($env:HUNTRESS_ACCOUNT_KEY) {
    $AccountKey = $env:HUNTRESS_ACCOUNT_KEY
}
# Use the CS_PROFILE_NAME environment variable as the OrganizationKey
# This should always be set by the DattoRMM agent. If not, there is likely
# an issue with the agent.
$OrganizationKey = $env:CS_PROFILE_NAME
if (!$env:CS_PROFILE_NAME) { $OrganizationKey = 'MISSING_CS_PROFILE_NAME' }


##############################################################################
## Begin user modified variables
##############################################################################


# Set to "Continue" to enable verbose logging.
$DebugPreference = "SilentlyContinue"

# Legacy, spinning HDD, or overloaded machines may require tuning this value. Most modern end points install in 10 seconds
# 3rd party security software (AV/EDR/etc) may significantly slow down the install if Huntress exclusions aren't properly put in!
# Read more about exclusions here https://support.huntress.io/hc/en-us/articles/4404005178771
$timeout         = 120         # number of seconds to wait before continuing the install

# Currently a fresh install of Huntress + EDR is approximately 100mb, double this for safety as fresh installs can bloat up in size slightly at first
# This can vary based on several factors including process creation rate, if EDR is installed or not, as well as number of users in the c:\users folder
$estimatedSpaceNeeded = 200111222


##############################################################################
## Do not modify anything below this line
##############################################################################

# These are used by the Huntress support team when troubleshooting.
$ScriptVersion = "Version 2, major revision 7, 2024 January 24"
$ScriptType = "PowerShell"

# variables used throughout this script
$X64 = 64
$X86 = 32
$InstallerName              = "HuntressInstaller.exe"
$InstallerPath              = Join-Path $Env:TMP $InstallerName
$HuntressKeyPath            = "HKLM:\SOFTWARE\Huntress Labs\Huntress"
$HuntressRegKey             = "HKLM:\SOFTWARE\Huntress Labs"
$ScriptFailed               = "Script Failed!"
$SupportMessage             = "Please send the error message to support@huntress.com"
$HuntressAgentServiceName   = "HuntressAgent"
$HuntressUpdaterServiceName = "HuntressUpdater"
$HuntressEDRServiceName     = "HuntressRio"

# attempt to use a more central temporary location for the log file rather than the installing users folder
if (Test-Path (Join-Path $env:SystemRoot "\temp")) {
    $DebugLog = Join-Path $env:SystemRoot "\temp\HuntressPoShInstaller.log"
} else {
    $DebugLog = Join-Path $Env:TMP HuntressPoShInstaller.log
}

# Find poorly written code faster with the most stringent setting.
Set-StrictMode -Version Latest

# Pull various software versions for logging purposes
$PoShVersion   = $PsVersionTable.PsVersion.Major
$KernelVersion = [System.Environment]::OSVersion.Version
$BuildVersion  = [System.Environment]::OSVersion.Version.Build

# Check kernel version to download the appropriate installer for the OS version
# kernel 6.1+ can use the regular Huntress agent, kernel versions 6.0 and lower require the legacy installer
$LegacyCommandsRequired = $false
if ($KernelVersion.Major -eq 6) {
    if ($KernelVersion.Minor -lt 1) {
        $LegacyCommandsRequired = $true
    }
} elseif ($KernelVersion.Major -lt 6) {
    $LegacyCommandsRequired = $true
}

# Check for an account key specified on the command line.
if ( ! [string]::IsNullOrEmpty($acctkey) ) {
    $AccountKey = $acctkey
}

# Check for an organization key specified on the command line.
if ( ! [string]::IsNullOrEmpty($orgkey) ) {
    $OrganizationKey = $orgkey
}

# Check for tags specified on the command line.
if ( ! [string]::IsNullOrEmpty($tags) ) {
    $TagsKey = $tags
}

# pick the appropriate file to download based on the OS version
if ($LegacyCommandsRequired -eq $true) {
    # For Windows Vista, Server 2008 (PoSh 2, kernel <= 6.0)
    $DownloadURL = "https://update.huntress.io/legacy_download/" + $AccountKey + "/" + $InstallerName
} else {
    # For Windows 7+, Server 2008 R2+ (PoSh 3+)
    $DownloadURL = "https://update.huntress.io/download/" + $AccountKey + "/" + $InstallerName
}

# 32bit PoSh on 64bit Windows is unable to interact with certain assets, so we check for this condition first with PoSh
$PowerShellArch = $X86
# 8 byte pointer is 64bit
if ([IntPtr]::size -eq 8) {
   $PowerShellArch = $X64
}

# Now we grab the Windows architecture
$WindowsArchitecture = $X86
if ($env:ProgramW6432) {
    $WindowsArchitecture = $X64
}

# Checking to see if Huntress was installed before this script was run
$isHuntressInstalled = $false
if ((test-path "c:\program files\Huntress\HuntressAgent.exe") -OR (test-path "c:\program files (x86)\Huntress\HuntressAgent.exe")){
    $isHuntressInstalled = $true
}

# time stamps for logging purposes
function Get-TimeStamp {
    return "[{0:yyyy/MM/dd} {0:HH:mm:ss}]" -f (Get-Date)
}

# adds time stamp to a message and then writes that to the log file
function LogMessage ($msg) {
    Add-Content $DebugLog "$(Get-TimeStamp) $msg"
    Write-Output "$(Get-TimeStamp) $msg"
}

# test that all required parameters were passed, and that they are in the correct format
function Test-Parameters {
    LogMessage "Verifying received parameters..."

    # If reregister and reinstall were both flagged, just reregister as it is the more robust option
    if ($reregister -and $reinstall) {
        LogMessage "Specified -reregister and -reinstall, defaulting to reregister."
        $reinstall = $false
    }

    # Ensure we have an account key (hard coded or passed params) and that it's in the correct form
    if ($AccountKey -eq "__ACCOUNT_KEY__") {
        $err = "AccountKey not set! Suggest using the -acctkey flag followed by your account key (you can find it in the Downloads section of your Huntress portal)."
        LogMessage $err
        Write-Output $err -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err
        exit 1
    } elseif ($AccountKey.length -ne 32) {
        $err = "Invalid AccountKey specified (incorrect length)! Suggest double checking the key was copy/pasted in its entirety"
        LogMessage $err
        Write-Output $err -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err
        exit 1
    } elseif (($AccountKey -match '[^a-zA-Z0-9]')) {
        $err = "Invalid AccountKey specified (invalid characters found)! Suggest double checking the key was copy/pasted fully"
        LogMessage $err
        Write-Output $err -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err
        exit 1
    }

    # Ensure we have an organization key (hard coded or passed params).
    if ($OrganizationKey -eq "__ORGANIZATION_KEY__") {
        $err = "OrganizationKey not specified! This is a user defined identifier set by you (usually your customer's organization name)"
        LogMessage $err
        Write-Output $err -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err
        exit 1
    } elseif ($OrganizationKey.length -lt 1) {
        $err = "Invalid OrganizationKey specified (length should be > 0)!"
        LogMessage $err
        Write-Output $err -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err
        exit 1
    }
    LogMessage "Parameters verified."
}

# Force kill a process by process name
function KillProcessByName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName
    )

    $processes = Get-Process | Where-Object { $_.ProcessName -eq $ProcessName }
    $processCount = $processes | Measure-Object | Select-Object -ExpandProperty Count

    if ($processCount -eq 0) {
        LogMessage "No processes with the name '$ProcessName' are currently running."
    }
    else {
        foreach ($process in $processes) {
            try {
                $processID = $process.Id
                Stop-Process -Id $processID -Force
                LogMessage "Killed process '$ProcessName' (ID $processID) successfully."
            }
            catch {
                LogMessage "Failed to kill process '$ProcessName' (ID $processID): $($_.Exception.Message)"
            }
        }
    }
}

# check to see if the Huntress service exists (agent or updater)
function Confirm-ServiceExists ($service) {
    if (Get-Service $service -ErrorAction SilentlyContinue) {
        return $true
    }
    return $false
}

# check to see if the Huntress service is running (agent or updater)
function Confirm-ServiceRunning ($service) {
    $arrService = Get-Service $service
    $status = $arrService.Status.ToString()
    if ($status.ToLower() -eq 'running') {
        return $true
    }
    return $false
}

# Stop the Agent and Updater services
function StopHuntressServices {
    LogMessage "Stopping Huntress services..."
    if (Confirm-ServiceExists($HuntressAgentServiceName)) {
        Stop-Service -Name "$HuntressAgentServiceName"
    } else {
        LogMessage "$($HuntressAgentServiceName) not found, nothing to stop"
    }
    if (Confirm-ServiceExists($HuntressUpdaterServiceName)) {
        Stop-Service -Name "$HuntressUpdaterServiceName"
    } else {
        LogMessage "$($HuntressUpdaterServiceName) not found, nothing to stop"
    }
}

# Ensure the installer was not modified during download by validating the file signature.
function verifyInstaller ($file) {
    $varChain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain
    try {
        $varChain.Build((Get-AuthenticodeSignature -FilePath "$file").SignerCertificate) | out-null
    } catch [System.Management.Automation.MethodInvocationException] {
        $err = ( "ERROR: '$file' did not contain a valid digital certificate. " +
                 "Something may have corrupted/modified the file during the download process. " +
                 "Suggest trying again, contact support@huntress.com if it fails >2 times")
        LogMessage $err
        LogMessage $SupportMessage
        Write-Output $err -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }
}

# Prevent conflicting file from preventing creation of installation directory.
function prepareAgentPath {
    $path = getAgentPath
    if (Test-Path $path -PathType Leaf) {
        $backup = "$path.bak"
        $err = "WARNING: '$path' already exists and is not a directory, renaming to '$backup'."
        Write-Output $err -ForegroundColor white -BackgroundColor red
        Rename-Item -Path $path -NewName $backup -Force
    }
}

# download the Huntress installer
function Get-Installer {
    $msg = "Downloading installer to '$InstallerPath'..."
    LogMessage $msg

    # Ensure a secure TLS version is used.
    $ProtocolsSupported = [enum]::GetValues('Net.SecurityProtocolType')
    if ( ($ProtocolsSupported -contains 'Tls13') -and ($ProtocolsSupported -contains 'Tls12') ) {
        # Use only TLS 1.3 or 1.2
        LogMessage "Using TLS 1.3 or 1.2..."
        [Net.ServicePointManager]::SecurityProtocol = (
            [Enum]::ToObject([Net.SecurityProtocolType], 12288) -bOR [Enum]::ToObject([Net.SecurityProtocolType], 3072)
        )
    } else {
        LogMessage "Using TLS 1.2..."
        try {
            # In certain .NET 4.0 patch levels, SecurityProtocolType does not have a TLS 1.2 entry.
            # Rather than check for 'Tls12', we force-set TLS 1.2 and catch the error if it's truly unsupported.
            [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
        } catch {
            $msg = $_.Exception.Message
            $err = "ERROR: Unable to use a secure version of TLS. Please verify Hotfix KB3140245 is installed."
            LogMessage $msg
            LogMessage $err
            throw $ScriptFailed + " " + $msg + " " + $err
        }
    }

    # Delete stale installer before downloading the most recent installer
    if (Test-Path $InstallerPath -PathType Leaf) {
        $err = "WARNING: '$InstallerPath' already exists, deleting stale Huntress Installer."
        LogMessage $err
        Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue
    }

    # Attempt to download the correct installer for the given OS, retry if it fails
    $attempts = 6
    $delay = 60
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $WebClient = New-Object System.Net.WebClient
        try {
            $WebClient.DownloadFile($DownloadURL, $InstallerPath)
            break
        } catch {
            $msg = $_.Exception.Message
            $err = "WARNING: Failed to download the Huntress Installer ($attempt/$attempts), retrying in $delay seconds."
            LogMessage $msg
            LogMessage $err
            Start-Sleep -Seconds $delay
        }
    }

    # Ensure the file downloaded correctly, if not, throw error
    if ( ! (Test-Path $InstallerPath) ) {
        $err = "ERROR: Failed to download the Huntress Installer. Try accessing $($DownloadURL) from the host where the download failed. Please contact support@huntress.io if the problem persists."
        LogMessage $err
        throw $ScriptFailed + " " + $err
    }

    $msg = "Installer downloaded to '$InstallerPath'..."
    LogMessage $msg
}

# check if the agent downloaded, is a valid install file, if those match up then run the installer
function Install-Huntress ($OrganizationKey) {
    # check that the installer downloaded and wasn't quarantined 
    LogMessage "Checking for installer '$InstallerPath'..."
    if ( ! (Test-Path $InstallerPath) ) {
        $err = "ERROR: The installer was unexpectedly removed from $InstallerPath"
        $msg = ($err + "`n"+
            "A security product may have quarantined the installer. Please check " +
            "your logs. If the issue continues to occur, please send the log to the Huntress " +
            "Team for help at support@huntresslabs.com")
        LogMessage $msg
        Write-Output $msg -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    # verify the installer's integrity
    verifyInstaller($InstallerPath)

    LogMessage "Executing installer..."
    prepareAgentPath
    # if $Tags value exists install using the provided tags, otherwise no tags
    if (($Tags) -or ($TagsKey -ne "__TAGS__")) {
        $process = Start-Process $InstallerPath "/ACCT_KEY=`"$AccountKey`" /ORG_KEY=`"$OrganizationKey`" /TAGS=`"$TagsKey`" /S" -PassThru
    } else {
        $process = Start-Process $InstallerPath "/ACCT_KEY=`"$AccountKey`" /ORG_KEY=`"$OrganizationKey`" /S" -PassThru
    }

    try {
        $process | Wait-Process -Timeout $timeout -ErrorAction Stop
    } catch {
        $process | Stop-Process -Force
        $err = "ERROR: Installer failed to complete in $timeout seconds. Possible interference from a security product?"
        Write-Output $err -ForegroundColor white -BackgroundColor red
        LogMessage $err
        LogMessage $SupportMessage
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }
}

# Test that the Huntress agent was able to install, register, and start service correctly
function Test-Installation {
    # Get the file locations of some of the Huntress executables and setting up some registry related variables
    $HuntressDirectory        = getAgentPath
    $hUpdaterPath            = Join-Path $HuntressDirectory "hUpdate.exe"
    $HuntressAgentPath        = Join-Path $HuntressDirectory "HuntressAgent.exe"
    $HuntressUpdaterPath      = Join-Path $HuntressDirectory "HuntressUpdater.exe"
    $AgentIdKeyValueName      = "AgentId"
    $OrganizationKeyValueName = "OrganizationKey"
    $TagsValueName            = "Tags"

    LogMessage "Verifying installation..."

    # Watch the agent logs for registration event, log if succeeded, waiting no longer than 10 seconds before outputting failure to log
    $didAgentRegister = $false
    for ($i = 0; $i -le 40; $i++) {
        if (Test-Path "$($HuntressDirectory)\HuntressAgent.log") {
            $linesFromLog = Get-Content "$($HuntressDirectory)\HuntressAgent.log" | Select-Object -first 4
            ForEach ($line in $linesFromLog) {
                if ($line -like "*Huntress agent registered*") {
                    LogMessage "Agent successfully registered in $($i/4) seconds"
                    $didAgentRegister = $true
                    Start-Sleep -Milliseconds 250
                    $i=100
                }
            }
        }
        Start-Sleep -Milliseconds 250
    }
    if ( ! $didAgentRegister) {
        $err = "WARNING: It does not appear the agent has successfully registered. Check 3rd party AV exclusion lists to ensure Huntress is excluded."
        Write-Output $err -ForegroundColor white -BackgroundColor red
        LogMessage ($err + $SupportMessage)
    }

    # Ensure the critical files were created.
    foreach ( $file in ($HuntressAgentPath, $HuntressUpdaterPath, $hUpdaterPath) ) {
        if ( ! (Test-Path $file) ) {
            $err = "ERROR: $file did not exist. Check your AV/security software quarantine"
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }
        LogMessage "'$file' is present."
    }

    # Check for Legacy OS, any kernel below 6.2 cannot run Huntress EDR (so we skip that check) 
    if ( ($KernelVersion.major -eq 6 -and $KernelVersion.minor -lt 2) -or ($KernelVersion.major -lt 6) ) {
        $services = @($HuntressAgentServiceName, $HuntressUpdaterServiceName)
        $err = "WARNING: Legacy OS detected, Huntress EDR will not be installed"
        LogMessage $err
    } else {
        $services = @($HuntressAgentServiceName, $HuntressUpdaterServiceName, $HuntressEDRServiceName)
    }

    # Ensure the services are installed and running.
    foreach ($svc in $services) {
        # check if the service is installed
        if ( ! (Confirm-ServiceExists($svc))) {
            # if Huntress was installed before this script started and Rio is missing then we log that, but continue with this script
            if ($svc -eq $HuntressEDRServiceName) {
                if ($isHuntressInstalled) {
                    LogMessage "ERROR: The $svc service is not installed. You may need to wait 20 minutes, reboot, or reinstall the agent (if this machine is indeed Huntress EDR compatible)"
                    LogMessage "See more about compatibility here: https://support.huntress.io/hc/en-us/articles/4410699983891-Supported-Operating-Systems-System-Requirements-Compatibility"
                } else {
                    LogMessage "New install detected. It may take 24 hours for Huntress EDR (Rio) to install!"
                }
            } else {
                LogMessage "$($svc) service is missing! $($SupportMessage)"
                throw "$($ScriptFailed) $($svc) service is missing! + $($SupportMessage)"
            }
        }
        # check if the service is running, attempt to restart if not (only for base agent).
        elseif ( (! (Confirm-ServiceRunning($svc))) -AND ($svc -eq $HuntressAgentServiceName)) {
            Start-Service $svc
            # if still not running, log and give up, else inform of success
            if (! (Confirm-ServiceRunning($svc))) {
                LogMessage "ERROR: The $($svc) service is not running. Attempting to restart"
                Start-Service $svc
                if (! (Confirm-ServiceRunning($svc))) {
                    throw "$($ScriptFailed) ERROR: restart of service $($svc) failed. $($SupportMessage)"
                }
            } else {
            LogMessage "'$svc' is running."
            }
        }
    }


    # look for a condition that prevents checking registry keys, if not then check for registry keys
    if ( ($PowerShellArch -eq $X86) -and ($WindowsArchitecture -eq $X64) ) {
        LogMessage "WARNING: Can't verify registry settings due to 32bit PowerShell on 64bit host. Please run PowerShell in 64 bit mode"
    } else {
        # Ensure the Huntress registry key is present.
        if ( ! (Test-Path $HuntressKeyPath) ) {
            $err = "ERROR: The registry key '$HuntressKeyPath' did not exist. You may need to reinstall with the -reregister flag"
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }

        # Ensure the Huntress registry values are present.
        $HuntressKeyObject = Get-ItemProperty $HuntressKeyPath
        foreach ( $value in ($AgentIdKeyValueName, $OrganizationKeyValueName, $TagsValueName) ) {
            If ( ! (Get-Member -inputobject $HuntressKeyObject -name $value -Membertype Properties) ) {
                $err = "ERROR: The registry value $value did not exist within $HuntressKeyPath. You may need to reinstall with the -reregister flag"
                LogMessage $err
                LogMessage $SupportMessage
                throw $ScriptFailed + " " + $err + " " + $SupportMessage
            }
        }
    }

    # Verify the agent registered (if not blocked by 32/64 bit incompatibilities).
    if ( ($PowerShellArch -eq $X86) -and ($WindowsArchitecture -eq $X64) ) {
        LogMessage "WARNING: Can't verify agent registration due to 32bit PowerShell on 64bit host."
    } else {
        If ($HuntressKeyObject.$AgentIdKeyValueName -eq 0) {
            $err = ("ERROR: The agent did not register. Check the log (%ProgramFiles%\Huntress\HuntressAgent.log) for errors.")
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }
        LogMessage "Agent registered."
    }
    LogMessage "Installation verified!"
}

# prepare to reregister by stopping the Huntress service and deleting all the registry keys
function PrepReregister {
    LogMessage "Preparing to re-register agent..."
    StopHuntressServices
    $HuntressKeyPath = "HKLM:\SOFTWARE\Huntress Labs\Huntress"
    Remove-Item -Path "$HuntressKeyPath" -Recurse -ErrorAction SilentlyContinue
}

# looks at the Huntress log to return true if the agent is orphaned, false if the agent is active AB
function isOrphan {
    # find the Huntress log file or state that it can't be found
    if (Test-Path 'C:\Program Files\Huntress\HuntressAgent.log') {
        $Path = 'C:\Program Files\Huntress\HuntressAgent.log'
    } elseif (Test-Path 'C:\Program Files (x86)\Huntress\HuntressAgent.log') {
        $Path = 'C:\Program Files (x86)\Huntress\HuntressAgent.log'
    } elseif ($isHuntressInstalled) {
        LogMessage "Unable to locate log file, thus unable to check if orphaned"
        return $false
    } else {
        LogMessage "New machine, no need to run through orphan checker"
        return $false
    }

    # if the log was found, look through the last 10 lines for the orphaned agent error code
    if ($Path -match 'HuntressAgent.log') {
        $linesFromLog = Get-Content $Path | Select-Object -last 10
        ForEach ($line in $linesFromLog)    { 
            if ($line -like "*bad status code: 401*") {
                return $true
            }
        } 
    }
    return $false
}

# Check if the script is being run with admin access AB
function testAdministrator {  
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)  
}

# Ensure the disk has enough space for the install files + agent, then write results to the log AB
function checkFreeDiskSpace {
    # Using an older disk query to be backwards compatible with PoSh 2, catch WMI errors and check repository
    try {
        $freeSpace = (Get-WmiObject -query "Select * from Win32_LogicalDisk where DeviceID='c:'" | Select-Object FreeSpace).FreeSpace
    } catch {
        LogMessage "WMI issues discovered (free space query), attempting to fix the repository"
        winmgmt -verifyrepository
        $drives = get-psdrive
        foreach ($drive in $drives) {
            if ($drive.Name -eq "C") { 
                $freeSpace = $drive.Free
            }
        }
    }
    $freeSpaceNice = $freeSpace.ToString('N0')
    if ($freeSpace -lt $estimatedSpaceNeeded) {
        $err = "Low disk space detected, you may have troubles completing this install. Only $($freeSpaceNice) bytes remaining (need about $($estimatedSpaceNeeded.ToString('N0'))."
        Write-Output $err -ForegroundColor white -BackgroundColor red
        LogMessage $err
    } else {
        LogMessage "Free disk space: $($freeSpaceNice)"
    }
}

# determine the path in which Huntress is installed AB
function getAgentPath {
    # Ensure we resolve the correct Huntress directory regardless of operating system or process architecture.
    if ($WindowsArchitecture -eq $X64) {
        return (Join-Path $Env:ProgramW6432 "Huntress")  
    } else {
        return (Join-Path $Env:ProgramFiles "Huntress")
    }    
}

# attempt to run a process and log the results AB 
function runProcess ($process, $flags, $name){
    try {
        $proc = Start-Process $process $flags -PassThru
        Wait-Process -Timeout $timeout -ErrorAction Stop -InputObject $proc
        LogMessage "$($name) finished"
    } catch {
        $e = $_.Exception
        $msg = $e.Message
        # Gather all the exceptions and their children
        while ($e.InnerException) {
          $e = $e.InnerException
          $msg += "`n" + $e.Message
        }

        # Try to kill hung processs
        if ($proc) {
            Stop-Process $proc.id -Force  -ErrorAction SilentlyContinue
        }

        $err = "ERROR: $($name) running as '$($process) $($flags)' failed to complete in $timeout seconds, full error message: '$($msg).'"
        Write-Host $err -ForegroundColor white -BackgroundColor red
        LogMessage $err
        copyLogAndExit
    }
}

# Fully uninstall the agent AB 
function uninstallHuntress {
    $agentPath         = getAgentPath
    $updaterPath       = Join-Path $agentPath "HuntressUpdater.exe"
    $exeAgentPath      = Join-Path $agentPath "HuntressAgent.exe"
    $uninstallerPath   = Join-Path $agentPath "Uninstall.exe"
    $wasUninstallerRun = $false

    # speed this up by stopping services first
    Stop-Service "huntressrio" -ErrorAction SilentlyContinue
    Stop-Service "huntressupdater" -ErrorAction SilentlyContinue
    Stop-Service "huntressagent" -ErrorAction SilentlyContinue

    # Force kill the executables so they're not hangin around
    KillProcessByName "HuntressAgent.exe"
    KillProcessByName "HuntressUpdater.exe"
    KillProcessByName "HuntressRio.exe"

    # attempt to use the built in uninstaller, if not found use the uninstallers built into the Agent and Updater
    if (Test-Path $agentPath) {
        # run uninstaller.exe, if not found run the Agent's built in uninstaller and the Updater's built in uninstaller
        if (Test-Path $uninstallerPath) {
            runProcess "$($uninstallerPath)" "/S" "Uninstall.exe"
            $wasUninstallerRun = $true
        } elseif (Test-Path $exeAgentPath) {
            runProcess "$($exeAgentPath)" "/S" "Huntress Agent uninstaller"
            $wasUninstallerRun = $true
        } elseif (Test-Path $updaterPath) {
            runProcess "$($updaterPath)" "/S" "Updater uninstaller"
            $wasUninstallerRun = $true
        } else {
            LogMessage "Agent path found but no uninstallers found. Attempting to manually uninstall"
        }
    } else {
        $err = "Note: unable to find Huntress install folder. Attempting to manually uninstall."
        Write-Output $err -ForegroundColor white -BackgroundColor red
        LogMessage $err
    }

    # if uninstaller was run, loop until Huntress assets are all successfully removed, or exit & report if timer exceeds 15 seconds
    if ($wasUninstallerRun) {
        for ($i = 0; $i -le 15; $i++) {
            if ((Test-Path $exeAgentPath) -OR (Test-Path $HuntressRegKey)){
                Start-Sleep 1
             } else {
                LogMessage "Agent successfully uninstall in $($i) seconds"
                $i = 100
            }
            if ($i -eq 15) {
                $err = "Uninstall not complete after $($i) seconds"
                LogMessage $err
                Write-Output $err -ForegroundColor white -BackgroundColor red
            }
        }
    }

    # look for the Huntress directory, if found then delete
    if (Test-Path $agentPath) {
        Remove-Item -LiteralPath $agentPath -Force -Recurse -ErrorAction SilentlyContinue
        LogMessage "Manual cleanup of Huntress folder: success"
    } else {
        LogMessage "Manual cleanup of Huntress folder: folder not found"
    }

    # look for the registry keys, if exist then delete
    if (Test-Path $HuntressRegKey) {
        Get-Item -path $HuntressRegKey | Remove-Item -recurse
        LogMessage "Manually deleted Huntress registry keys"
    } else {
        LogMessage "No registry keys found, uninstallation complete"
    }
}

# grab the currently installed agent version AB
function getAgentVersion {
    $exeAgentPath = Join-Path (getAgentPath) "HuntressAgent.exe"
    $agentVersion = (Get-Item $exeAgentPath).VersionInfo.FileVersion
    return $agentVersion
}

# ensure all the Huntress services are running AB
function repairAgent {
    # check that service exists before we attempt to start it
    $HuntressService = Get-Service -name "HuntressAgent" -ErrorAction SilentlyContinue
    $UpdaterService  = Get-Service -name "HuntressUpdater" -ErrorAction SilentlyContinue
    $RioService      = Get-Service -name "HuntressRio" -ErrorAction SilentlyContinue
    $DidRepairFinish = $true

    # if each service doesn't exist we'll be returning false, else start the service
    if ($null -eq $HuntressService){
        LogMessage "Repair was unable to find the HuntressService, this machine will need Huntress uninstalled and reinstalled in order to maintain security"
        $DidRepairFinish = $false
    } else {
        Start-Service HuntressAgent
        LogMessage "Repair started HuntressAgent service"
    }
    if ($null -eq $UpdaterService){
        LogMessage "Repair was unable to find the UpdaterService, this machine will need Huntress uninstalled and reinstalled in order to continue receiving updates."
        $DidRepairFinish = $false
    } else {
        Start-Service HuntressUpdater
        LogMessage "Repair started HuntressUpdater service"
    }

    # For Rio/EDR we don't return false as we don't know if it's a fresh install that hasn't received Rio yet, but still attempt to restart service
    if (($null -eq $RioService) -AND $isHuntressInstalled){
        LogMessage "Repair was unable to find the RioService. If this is a fresh install it may take up to 24 hours for Rio to install. Otherwise please contact support to ensure EDR coverage."
    } elseif ($null -eq $RioService) {
        LogMessaage "Fresh install detected, it can take up to 24 hours for Rio to install."
    } else {
        Start-Service HuntressRio
        LogMessage "Repair started HuntressRio service"
    }

    return $DidRepairFinish
}

# Agent will not function when communication is blocked so exit the script if too much communication is blocked AB
# return true if connectivity is acceptable, false if too many connections fail
function testNetworkConnectivity {
    # number of URL's that can fail the connectivity before the agent refuses to install (the test fails incorrectly sometimes, so 1 failure is acceptable)
    $connectivityTolerance = 1

    $URLs = @("huntress.io", "huntresscdn.com", "update.huntress.io", "eetee.huntress.io", "huntress-installers.s3.amazonaws.com", "huntress-updates.s3.amazonaws.com", "huntress-uploads.s3.us-west-2.amazonaws.com",
              "huntress-user-uploads.s3.amazonaws.com", "huntress-rio.s3.amazonaws.com", "huntress-survey-results.s3.amazonaws.com")
    foreach ($URL in $URLs) {
        if (! (Test-NetConnection $URL -Port 443).TcpTestSucceeded) {
            $err = "WARNING, connectivity to Huntress URL's is being interrupted. You MUST open port 443 for $($URL) in order for the Huntress agent to function."
            Write-Output $err -ForegroundColor white -BackgroundColor red
            LogMessage $err
            $connectivityTolerance --
        } else {
            LogMessage "Connection succeeded to $($URL) on port 443!"
        }
    }
    if ($connectivityTolerance -lt 0) {
        Write-Output "Please fix the closed port 443 for the above domains before attempting to install" -ForegroundColor white -BackgroundColor red
        $err = "Too many connections failed $($connectivityTolerance), exiting"
        LogMessage $err
        Write-Output "$($err), $($SupportMessage)" -ForegroundColor white -BackgroundColor red
        return $false
    }
    return $true
}

# Log useful data about the machine for troubleshooting AB
function logInfo {
    # gather info on the host for logging purposes
    LogMessage "Script type: '$ScriptType'"
    LogMessage "Script version: '$ScriptVersion'"

    # if Huntress was already installed, pull version info
    LogMessage "Script cursory check, is Huntress installed already: $($isHuntressInstalled)"
    if ($isHuntressInstalled){
        LogMessage "Agent version $(getAgentVersion) found"
    }

    # Log OS details
    LogMessage $(systeminfo)

    #LogMessage "Host name: '$env:computerName'"
    try {  $os = (get-WMiObject -computername $env:computername -Class win32_operatingSystem).caption.Trim()
    } catch {
        LogMessage "WMI issues discovered (computer name query), attempting to fix the repository"
        winmgmt -verifyrepository
        $os = (get-itemproperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ProductName).ProductName
    }
    #LogMessage "Host OS: '$os'"
    #LogMessage "Host Build Version: $($BuildVersion)"

    LogMessage "Host Kernel Version: $($KernelVersion)"
    LogMessage "Detected Architecture (Windows 32/64 bit): '$($WindowsArchitecture)'"

    # Log PowerShell details
    LogMessage "PowerShell Architecture (PoSh 32/64 bit): '$PowerShellArch'"
    LogMessage "PowerShell version: $($PoShVersion).$($PSversionTable.PsVersion.Minor)"
    LogMessage "Powershell legacy detected: $($LegacyCommandsRequired)"
    if ($LegacyCommandsRequired) {
        LogMessage "Warning! Older version of PowerShell detected"
    }

    # Logging other details about the machine
    checkFreeDiskSpace
    LogMessage "Installer location: '$InstallerPath'"
    LogMessage "Installer log: '$DebugLog'"
    LogMessage "Administrator access: $(testAdministrator)"

    # Log machine uptime
    try
    {
        $uptime = ((Get-Date) - (GCIM Win32_OperatingSystem).LastBootUpTime).days
    } catch {
        LogMessage "Unable to determine system uptime"
        $uptime = 0
    }
    if ($uptime -gt 9) {
        LogMessage "Warning, high uptime detected  This machine may need a reboot in order to resolve Windows update-based file locks."
    } else {
        LogMessage "Days of uptime: $($uptime)"
    }

    # Logging TCP/IP configuration to ensure connectivity
    LogMessage "$(ipconfig)"

    # Log status of AD joined and the (in)ability to contact a DC
    try {
        $domainJoined = (gwmi win32_computersystem).PartOfDomain
    } catch {
        LogMessage "Warning, unable to determine if domain joined"
        $domainJoined = $false
    }

    if ( $domainJoined ) {
        try {
            $secureChannelStatus = Test-ComputerSecureChannel
        } catch {
            LogMessage "Warning, unable to Test-ComputerSecureChannel. If this isn't a DC, then the trust relationship with the DC may be broken"
            $secureChannelStatus = $false
        }
        if ( ! $secureChannelStatus) {
            LogMessage "Warning, AD joined machine without DC connectivity. Some services may be impacted such as Managed AV and in some rare cases Host Isolation."
        } else {
            LogMessage "AD joined and DC connectivity verified!"
        }
    }

    $areURLsAvailable = testNetworkConnectivity
    if ( ! $areURLsAvailable) {
        copyLogAndExit
    }

}

# DebugLog contains useful info not found in surveys, so copy to Huntress folder for higher visibility with future troubleshooting AB
# In the past we copied to the users temp folder, difficult to find on machines with lots of profiles. Solved this by always placing the log in the normal Huntress folder.
function copyLogAndExit {
    Start-Sleep 1
    $agentPath = getAgentPath
    $logLocation = Join-Path $agentPath "HuntressPoShInstaller.log"
    
    # If this is an unistall, we'll leave the log in the C:\temp dir otherwise,
    # we'll copy the log to the huntress directory
    if (!$uninstall){
        if (!(Test-Path -path $agentPath)) {New-Item $agentPath -Type Directory}
        Copy-Item -Path $DebugLog -Destination $logLocation -Force
        Write-Output "'$($DebugLog)' copied to '$logLocation'."
    }

    Write-Output "Script complete"
    exit 0
}


#########################################################################################
#                                  begin main function                                  #
#########################################################################################
function main () {
    if ($env:repairAgent -eq $true) {
        $repair = $true
    }
    if ($env:reregisterAgent -eq $true) {
        $reregister = $true
    }
    if ($env:uninstallAgent -eq $true) {
        $uninstall = $true
    }
    if ($env:reinstallAgent -eq $true) {
        $reinstall = $true
    }

    # Start the script with logging as much as we can as soon as we can. All your logging are belong to us, Zero Wang.
    logInfo

    # if run with the uninstall flag, exit so we don't reinstall the agent after
    if ($uninstall) {
        LogMessage "Uninstalling Huntress agent"
        uninstallHuntress
        copyLogAndExit
    }

    # if the agent is orphaned, switch to the full uninstall/reinstall (reregister flag)
    if ( !($reregister)) {
        if (isOrphan) {
            $err = 'Huntress Agent is orphaned, unable to use the provided flag. Switching to uninstall/reinstall (reregister flag)'
            Write-Output $err -ForegroundColor white -BackgroundColor red
            LogMessage "$err"
            $reregister = $true
        }
    }

    # if run with no flags and no account key, assume repair
    if (!$repair -and !$reregister -and !$uninstall -and !$reinstall -and ($AccountKey -eq "__ACCOUNT_KEY__")) {
        LogMessage "No flags or account key found! Defaulting to the -repair flag."
        $repair = $true
    }

    # if run with the repair flag, check if installed (install if not), if ver < 0.13.16 apply the fix
    if ($repair) {
        if (Test-Path(getAgentPath)){
            if (!(repairAgent)){

            } else {
                LogMessage "Repair complete!"
            }
            copyLogAndExit
        } else {
            LogMessage "Agent not found! Attempting to install"
            $reregister = $true
        }
    }

    # trim keys for blanks before use
    $AccountKey = $AccountKey.Trim()
    $OrganizationKey = $OrganizationKey.Trim()

    # check that all the parameters that were passed are valid
    Test-Parameters

    # Hide most of the account key in the logs, keeping the front and tail end for troubleshooting 
    if ($AccountKey -ne "__Account_Key__") {
        $masked = $AccountKey.Substring(0,4) + "************************" + $AccountKey.SubString(28,4)
        LogMessage "AccountKey: '$masked'"
        LogMessage "OrganizationKey: '$OrganizationKey'"
        LogMessage "Tags: $($Tags)"
    }

    # reregister > reinstall > uninstall > install (in decreasing order of impact)
    # reregister = reinstall + delete registry keys
    # reinstall  = install + stop Huntress service 
    if ($reregister) {
        LogMessage "Re-register agent: '$reregister'"
        if ( !(Confirm-ServiceExists($HuntressAgentServiceName))) {
            LogMessage "Run with the -reregister flag but the service wasn't found. Attempting to install...."
        }
        PrepReregister
    } elseif ($reinstall) {
        LogMessage "Re-install agent: '$reinstall'"
        if ( !(Confirm-ServiceExists($HuntressAgentServiceName)) ) {
            $err = "Script was run w/ reinstall flag but there's nothing to reinstall. Attempting to clean remnants, then install the agent fresh."
            LogMessage "$err"
            uninstallHuntress
            copyLogAndExit
        }
        StopHuntressServices
    } else {
        LogMessage "Checking for HuntressAgent service..."
        if ( Confirm-ServiceExists($HuntressAgentServiceName) ) {
            $err = "The Huntress Agent is already installed. Exiting with no changes. Suggest using -reregister or -reinstall flags"
            LogMessage "$err"
            Write-Output 'Huntress Agent is already installed. Suggest using the -reregister or -reinstall flags' -ForegroundColor white -BackgroundColor red
            copyLogAndExit
        }
    }

    Get-Installer
    Install-Huntress $OrganizationKey
    Test-Installation
    LogMessage "Huntress Agent successfully installed!"
    copyLogAndExit
}

try {
    main
} catch {
    $ErrorMessage = $_.Exception.Message
    LogMessage $ErrorMessage
    copyLogAndExit
}
