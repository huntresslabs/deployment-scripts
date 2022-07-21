# Copyright (c) 2022 Huntress Labs, Inc.
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


# The Huntress installer needs an Account Key and an Organization Key (a user
# specified name or description) which is used to affiliate an Agent with a
# specific Organization within the Huntress Partner's Account. These keys can be
# hard coded below or passed in when the script is run.

# For more details, see our KB article
# https://support.huntress.io/hc/en-us/articles/4404004936339-Deploying-Huntress-with-PowerShell

# Usage (remove brackets [] and substitute <variable> for your value):
# powershell -executionpolicy bypass -f ./InstallHuntress.powershellv2.ps1 [-acctkey <account_key>] [-orgkey <organization_key>] [-tags <tags>] [-reregister] [-reinstall] [-uninstall]
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
  [switch]$uninstall
)


##############################################################################
## Begin user modified variables
##############################################################################

# Replace __ACCOUNT_KEY__ with your account secret key (from your Huntress portal's "download agent" section)
$AccountKey = "__ACCOUNT_KEY__"

# Replace __ORGANIZATION_KEY__ with a unique identifier for the organization/client (your choice of naming scheme)
$OrganizationKey = "__ORGANIZATION_KEY__"

# Replace __TAGS__ with one or more tags, separated by commas (this field is optional!)
$TagsKey = "__TAGS__"

# Set to "Continue" to enable verbose logging.
$DebugPreference = "SilentlyContinue"

##############################################################################
## Do not modify anything below this line
##############################################################################


# Find poorly written code faster with the most stringent setting.
Set-StrictMode -Version Latest

# Check for old outdated Windows PowerShell (script works as low as PoSh 2.0, this is for logging/debugging)
$oldOS = $false
if ($PsVersionTable.PsVersion.Major -lt 3){
    $oldOS = $true
}

# These are used by the Huntress support team when troubleshooting.
$ScriptVersion = "2022 July 21; revision 2"
$ScriptType = "PowerShell"

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


# variables used throughout this script
$X64 = 64
$X86 = 32
$InstallerName   = "HuntressInstaller.exe"
$InstallerPath   = Join-Path $Env:TMP $InstallerName
$DebugLog        = Join-Path $Env:TMP HuntressInstaller.log
$DownloadURL     = "https://update.huntress.io/download/" + $AccountKey + "/" + $InstallerName
$HuntressKeyPath = "HKLM:\SOFTWARE\Huntress Labs\Huntress"
$HuntressRegKey  = "HKLM:\SOFTWARE\Huntress Labs"
$timeout         = 30  # Seconds to wait (used for installing/uninstalling)

# strings used throughout this script
$ScriptFailed               = "Script Failed!"
$SupportMessage             = "Please send the error message to support@huntress.com"
$HuntressAgentServiceName   = "HuntressAgent"
$HuntressUpdaterServiceName = "HuntressUpdater"

# 32bit PoSh on 64bit Windows is unable to interact with certain assets, so we check for this condition
$PowerShellArch = $X86
# 8 byte pointer is 64bit
if ([IntPtr]::size -eq 8) {
   $PowerShellArch = $X64
}

# time stamps for logging purposes
function Get-TimeStamp {
    return "[{0:yyyy/MM/dd} {0:HH:mm:ss}]" -f (Get-Date)
}

# adds time stamp to a message and then writes that to the log file
function LogMessage ($msg) {
    Add-Content $DebugLog "$(Get-TimeStamp) $msg"
    Write-Host "$(Get-TimeStamp) $msg"
}

# test that all required parameters were passed, and that they are in the correct format
function Test-Parameters {
    LogMessage "Verifying received parameters..."

    # If reregister and reinstall were both flagged, just reregister as it is the more robust option
    if ($reregister -and $reinstall) {
        $err = "Specified -reregister and -reinstall, defaulting to reregister."
        LogMessage $err
        $reinstall = $false
    }

    # Ensure we have an account key (either hard coded or from the command line params).
    if ($AccountKey -eq "__ACCOUNT_KEY__") {
        $err = "AccountKey not set! Suggest using the -acctkey flag followed by your account key."
        LogMessage $err
        Write-Host $err -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err
        exit 1
    } elseif ($AccountKey.length -ne 32) {
        $err = "Invalid AccountKey specified (incorrect length)! Suggest double checking the key was copy/pasted fully"
        LogMessage $err
        Write-Host $err -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err
        exit 1
    }

    # Ensure the account key doesn't have any invalid characters
    if ($AccountKey -match '[^a-zA-Z0-9]')
    {
        $err = "Invalid AccountKey specified (invalid characters found)! Suggest double checking the key was copy/pasted fully"
        LogMessage $err
        Write-Host $err -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err
        exit 1
    }


    # Ensure we have an organization key (either hard coded or from the command line params).
    if ($OrganizationKey -eq "__ORGANIZATION_KEY__") {
        $err = "OrganizationKey not specified! This is a user defined identifier set by you (usually your customer's organization name)"
        LogMessage $err
        Write-Host $err -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err
        exit 1
    } elseif ($OrganizationKey.length -lt 1) {
        $err = "Invalid OrganizationKey specified (length should be > 0)!"
        LogMessage $err
        Write-Host $err -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err
        exit 1
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

# return the architecture type (32 or 64 bit)
function Get-WindowsArchitecture {
    if ($env:ProgramW6432) {
        $WindowsArchitecture = $X64
    } else {
        $WindowsArchitecture = $X86
    }
    return $WindowsArchitecture
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
        Write-Host $err -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
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

    # Attempt to download the file, throw error if it fails
    $WebClient = New-Object System.Net.WebClient
    try {
        $WebClient.DownloadFile($DownloadURL, $InstallerPath)
    } catch {
        $msg = $_.Exception.Message
        $err = ( "ERROR: Failed to download the Huntress Installer. Please try accessing $DownloadURL " +
                 "from a web browser on the host where the download failed. If the issue persists, please " +
                "send the error message to the Huntress Team for help at support@huntress.com.")
        LogMessage $msg
        LogMessage $err
        throw $ScriptFailed + " " + $err + " " + $msg
    }

    # Ensure the file downloaded correctly, if not, throw error
    if ( ! (Test-Path $InstallerPath) ) {
        $err = "ERROR: Failed to download the Huntress Installer from $DownloadURL. Suggest testing the URL in a browser."
        LogMessage $err
        LogMessage $SupportMessage
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
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
        $msg = (
            "A security product may have quarantined the installer. Please check " +
            "your logs. If the issue continues to occur, please send the log to the Huntress " +
            "Team for help at support@huntresslabs.com")
        LogMessage $err
        LogMessage $msg
        Write-Host $err + $msg -ForegroundColor white -BackgroundColor red
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }

    # verify the installer's integrity
    verifyInstaller($InstallerPath)

    # execute the installer, stopping if it gets hung (security product interference)
    $msg = "Executing installer..."
    LogMessage $msg
    
    # if $Tags value exists install using the provided tags, otherwise no tags
    if ($Tags) {
        $process = Start-Process $InstallerPath "/ACCT_KEY=`"$AccountKey`" /ORG_KEY=`"$OrganizationKey`" /TAGS=`"$TagsKey`" /S" -PassThru
    } else {
        $process = Start-Process $InstallerPath "/ACCT_KEY=`"$AccountKey`" /ORG_KEY=`"$OrganizationKey`" /S" -PassThru
    }

    try {
        $process | Wait-Process -Timeout $timeout -ErrorAction Stop
    } catch {
        $process | Stop-Process -Force
        $err = "ERROR: Installer failed to complete in $timeout seconds. Possible interference from a security product?"
        Write-Host $err -ForegroundColor white -BackgroundColor red
        LogMessage $err
        LogMessage $SupportMessage
        throw $ScriptFailed + " " + $err + " " + $SupportMessage
    }
}

# Test that the Huntress agent was able to install, register, and start service correctly
function Test-Installation {
    LogMessage "Verifying installation..."

    # Give the agent a few seconds to start and register.
    Start-Sleep -Seconds 8

    # Get the file locations of some of the Huntress executables
    $HuntressDirectory   = getAgentPath
    $WyUpdaterPath       = Join-Path $HuntressDirectory "wyUpdate.exe"
    $HuntressAgentPath   = Join-Path $HuntressDirectory "HuntressAgent.exe"
    $HuntressUpdaterPath = Join-Path $HuntressDirectory "HuntressUpdater.exe"

    # Get the registry location, and store some strings for use in registry
    $AgentIdKeyValueName = "AgentId"
    $OrganizationKeyValueName = "OrganizationKey"
    $TagsValueName = "Tags"

    # Ensure the critical files were created.
    foreach ( $file in ($HuntressAgentPath, $HuntressUpdaterPath, $WyUpdaterPath) ) {
        if ( ! (Test-Path $file) ) {
            $err = "ERROR: $file did not exist. Check your AV/security software quarantine"
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }
        LogMessage "'$file' is present."
    }

    # Ensure the services are installed and running.
    foreach ( $svc in ($HuntressAgentServiceName, $HuntressUpdaterServiceName) ) {
        # service installed?
        if ( ! (Confirm-ServiceExists($svc)) ) {
            $err = "ERROR: The $svc service is not installed. You may need to reinstall."
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }

        # service running?
        if ( ! (Confirm-ServiceRunning($svc)) ) {
            $err = "ERROR: The $svc service is not running. You may need to manually start it for more info."
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }
        LogMessage "'$svc' is running."
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
    } else {
        LogMessage "Unable to locate log file, thus unable to check if orphaned"
        return $false
    }

    # if the log was found, look through the last 10 lines for the orphaned agent error code
    if ($Path -match 'HuntressAgent.log') {
        $linesFromLog = Get-Content $Path | Select -last 10
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
        $freeSpace = (Get-WmiObject -query "Select * from Win32_LogicalDisk where DeviceID='c:'" | Select FreeSpace).FreeSpace
    } catch {
        LogMessage "WMI issues discovered (free space query), attempting to fix the repository"
        winmgt -verifyrepository
        $drives = get-psdrive
        foreach ($drive in $drives) {
            if ($drive.Name -eq "C") { 
                $freeSpace = $drive.Free
            }
        }
    }
    $freeSpaceNice = $freeSpace.ToString('N0')
    $estimatedSpaceNeeded = 45123456
    if ($freeSpace -lt $estimatedSpaceNeeded) {
        $err = "Low disk space detected, you may have troubles completing this install. Only $($freeSpaceNice) bytes remaining (need about $($estimatedSpaceNeeded.ToString('N0'))."
        Write-Host $err -ForegroundColor white -BackgroundColor red
        LogMessage $err
    } else {
        LogMessage "Free disk space: $($freeSpaceNice)"
    }
}

# determine the path in which Huntress is installed AB
function getAgentPath {
    # Ensure we resolve the correct Huntress directory regardless of operating system or process architecture.
    if (Get-WindowsArchitecture -eq $X64) {
        return (Join-Path $Env:ProgramW6432 "Huntress")  
    } else {
        return (Join-Path $Env:ProgramFiles "Huntress")
    }    
}

# attempt to run a process and log the results AB 
function runProcess ($process, $flags, $name){
    try {
        Start-Process $process $flags | Wait-Process -Timeout $timeout -ErrorAction Stop
        LogMessage "$($name) finished"
    } catch {
        Stop-Process $process -Force
        $err = "ERROR: $($name) failed to complete in $timeout seconds."
        Write-Host $err -ForegroundColor white -BackgroundColor red
        LogMessage $err
        exit 0
    }
}

# Fully uninstall the agent AB 
function uninstallHuntress {
    $agentPath       = getAgentPath
    $updaterPath     = Join-Path $agentPath "HuntressUpdater.exe"
    $exeAgentPath    = Join-Path $agentPath "HuntressAgent.exe"
    $uninstallerPath = Join-Path $agentPath "Uninstall.exe"

    # attempt to use the built in uninstaller, if not found use the uninstallers built into the Agent and Updater
    if (Test-Path $agentPath) {
        # run uninstaller.exe, if not found run the Agent's built in uninstaller and the Updater's built in uninstaller
        if (Test-Path $uninstallerPath) {
            runProcess "$($uninstallerPath)" "/S" "Uninstall.exe"
        } elseif (Test-Path $exeAgentPath) {
            runProcess "$($exeAgentPath)" "/S" "Huntress Agent uninstaller"
        } elseif (Test-Path $updaterPath) {
            runProcess "$($updaterPath)" "/S" "Updater uninstaller"
        } else {

        }
    } else {
        $err = "Note: unable to find Huntress install folder. Attempting to manually uninstall."
        Write-Host $err -ForegroundColor white -BackgroundColor red
        LogMessage $err
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

function main () {
    # gather info on the host for logging purposes
    LogMessage "Script type: '$ScriptType'"
    LogMessage "Script version: '$ScriptVersion'"
    LogMessage "Host name: '$env:computerName'"
    try {
        $os = (get-WMiObject -computername $env:computername -Class win32_operatingSystem).caption.Trim()
    } catch {
        LogMessage "WMI issues discovered (computer name query), attempting to fix the repository"
        winmgt -verifyrepository
        $os = (get-itemproperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ProductName).ProductName
    }
    LogMessage "Host OS: '$os'"
    LogMessage "Host Architecture: '$(Get-WindowsArchitecture)'"
    if ($oldOS) {
        LogMessage "Warning! Older version of PowerShell detected"
    }
    checkFreeDiskSpace
    LogMessage "PowerShell Architecture: '$PowerShellArch'"
    LogMessage "Installer location: '$InstallerPath'"
    LogMessage "Installer log: '$DebugLog'"
    LogMessage "Administrator access: $(testAdministrator)"

    # if run with the uninstall flag, exit so we don't reinstall the agent after
    if ($uninstall) {
        LogMessage "Uninstalling Huntress agent"
        uninstallHuntress
        exit 0
    }

    # if the agent is orphaned, switch to the full uninstall/reinstall (reregister flag)
    if ( !($reregister)) {
        if (isOrphan) {
            $err = 'Huntress Agent is orphaned, unable to use the provided flag. Switching to uninstall/reinstall (reregister flag)'
            Write-Host $err -ForegroundColor white -BackgroundColor red
            LogMessage "$err"
            $reregister = $true
        }
    }

    # trim keys for blanks before use
    $AccountKey = $AccountKey.Trim()
    $OrganizationKey = $OrganizationKey.Trim()

    # check that all the parameters that were passed are valid
    Test-Parameters

    # Hide most of the account key in the logs, keeping the front and tail end for troubleshooting 
    $masked = $AccountKey.Substring(0,4) + "************************" + $AccountKey.SubString(28,4)
    LogMessage "AccountKey: '$masked'"
    LogMessage "OrganizationKey: '$OrganizationKey'"
    LogMessage "Tags: $($Tags)"

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
            exit 0
        }
        StopHuntressServices
    } else {
        LogMessage "Checking for HuntressAgent service..."
        if ( Confirm-ServiceExists($HuntressAgentServiceName) ) {
            $err = "The Huntress Agent is already installed. Exiting with no changes. Suggest using -reregister or -reinstall flags"
            LogMessage "$err"
            Write-Host 'Huntress Agent is already installed. Suggest using the -reregister or -reinstall flags' -ForegroundColor white -BackgroundColor red
            exit 0
        }
    }

    Get-Installer
    Install-Huntress $OrganizationKey
    Test-Installation
    LogMessage "Huntress Agent successfully installed!"
}

try {
    main
} catch {
    $ErrorMessage = $_.Exception.Message
    LogMessage $ErrorMessage
    exit 1
}
