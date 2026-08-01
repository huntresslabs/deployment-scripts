# Copyright (c) 2026 Huntress Labs, Inc.
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
# Authors: Alan Bishop, Sharon Martin, John Ferrell, Dave Kleinatland, Evan Shewchuk


# The Huntress installer needs an Account Key and an Organization Key (a user specified name or description) which is used to affiliate an Agent with a
# specific Organization within the Huntress Partner's Account. These keys can be hard coded below or passed in when the script is run.
# For more details, see our KB article  https://support.huntress.io/hc/en-us/articles/4404004936339-Deploying-Huntress-with-PowerShell
#
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

##############################################################################################################
##              ---====>> DO NOT REMOVE OR COMMENT OUT ANYTHING IN THIS SCRIPT! <<====---
## Modifications should only be done to the right side of the assignment statements, and in this section only.
## Do not modify any variable names, change variable types, or introduce commenting characters
##
##                            Begin user modified variables section
##############################################################################################################

# Replace __ACCOUNT_KEY__ with your account secret key (from your Huntress portal's "download agent" section)
$AccountKey = '__ACCOUNT_KEY__'

# Replace __ORGANIZATION_KEY__ with a unique identifier for the organization/client (your choice of naming scheme)
$OrganizationKey = '__ORGANIZATION_KEY__'

# Replace __TAGS__ with one or more tags, separated by commas (leave the next line unmodified if you don't want to use Tags)
$TagsKey = '__TAGS__'

# Set to "Continue" to enable verbose logging.
$DebugPreference = 'SilentlyContinue'

# Legacy, spinning HDD, or overloaded machines may require tuning this value. Most modern end points install in 10 seconds
# 3rd party security software (AV/EDR/etc) may significantly slow down the install if Huntress exclusions aren't properly put in!
# Read more about exclusions here https://support.huntress.io/hc/en-us/articles/4404005178771
$timeout = 120         # number of seconds to wait before continuing the install


##############################################################################
##              Do not modify anything below this line
##############################################################################

# These are used by the Huntress support team when troubleshooting.
$ScriptVersion = 'Version 2, major revision 9, 2026 July 13'
$ScriptType = 'PowerShell'

# variables used throughout this script
$X64 = 64
$X86 = 32
$InstallerName = 'HuntressInstaller.exe'
$InstallerPath = Join-Path $Env:TMP $InstallerName
$HuntressKeyPath = 'HKLM:\SOFTWARE\Huntress Labs\Huntress'
$HuntressRegKey = 'HKLM:\SOFTWARE\Huntress Labs'
$SupportMessage = 'Send the error message to support@huntress.com'
$HuntressAgentServiceName = 'HuntressAgent'
$HuntressUpdaterServiceName = 'HuntressUpdater'
$HuntressEDRServiceName = 'HuntressRio'
$Vendor = 'Huntress'
$ScriptInfoName = 'HuntressPoShInstaller.json'

# attempt to use a more central temporary location for the log file rather than the installing users folder
if (Test-Path (Join-Path $env:SystemRoot '\temp')) {
    $DebugLog = Join-Path $env:SystemRoot '\temp\HuntressPoShInstaller.log'
} else {
    $DebugLog = Join-Path $Env:TMP 'HuntressPoShInstaller.log'
}

# Find poorly written code faster with the most stringent setting.
Set-StrictMode -Version Latest

# Pull various software versions for logging purposes
$PoShVersion = $PsVersionTable.PsVersion.Major
$KernelVersion = [System.Environment]::OSVersion.Version

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
    $DownloadURL = 'https://update.huntress.io/legacy_download/' + $AccountKey + '/' + $InstallerName
} else {
    # For Windows 7+, Server 2008 R2+ (PoSh 3+)
    $DownloadURL = 'https://update.huntress.io/download/' + $AccountKey + '/' + $InstallerName
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

# Check for Legacy OS, any kernel below 6.2 cannot run Huntress EDR (so we skip that check)
$services = @($HuntressAgentServiceName, $HuntressUpdaterServiceName, $HuntressEDRServiceName)
if ( ($KernelVersion.major -eq 6 -and $KernelVersion.minor -lt 2) -or ($KernelVersion.major -lt 6) ) {
    $services = @($HuntressAgentServiceName, $HuntressUpdaterServiceName)
}

# Checking to see if Huntress was installed before this script was run
$isHuntressInstalled = $false
if ((Test-Path 'c:\program files\Huntress\HuntressAgent.exe') -or (Test-Path 'c:\program files (x86)\Huntress\HuntressAgent.exe')) {
    $isHuntressInstalled = $true
}

# time stamps for logging purposes
function Get-TimeStamp {
    return '[{0:yyyy/MM/dd} {0:HH:mm:ss}]' -f (Get-Date)
}

# adds time stamp to a message and then writes that to the log file
function Write-LogMessage ($msg) {
    Add-Content $DebugLog "$(Get-TimeStamp) $msg"
    Write-Output "$(Get-TimeStamp) $msg"
}

# test that all required parameters were passed, and that they are in the correct format
function Test-Parameters {
    Write-LogMessage 'Verifying received parameters...'

    # If reregister and reinstall were both flagged, just reregister as it is the more robust option
    if ($reregister -and $reinstall) {
        Write-LogMessage 'Specified -reregister and -reinstall, defaulting to reregister.'
        $reinstall = $false
    }

    # Ensure we have an account key (hard coded or passed params) and that it's in the correct form
    if ($AccountKey -eq '__ACCOUNT_KEY__') {
        Copy-LogAndExt -throwError 'AccountKey not set! Suggest using the -acctkey flag followed by your account key (you can find it in the Downloads section of your Huntress portal).'
    } elseif ($AccountKey.length -ne 32) {
        Copy-LogAndExt -throwError "Invalid AccountKey specified (incorrect length)! Suggest double checking the key was copy/pasted in its entirety. Length = $($AccountKey.length)   expected value = 32"
    } elseif (($AccountKey -match '[^a-zA-Z0-9]')) {
        Copy-LogAndExt -throwError 'Invalid AccountKey specified (invalid characters found)! Suggest double checking the key was copy/pasted fully'
    }

    # Ensure we have an organization key (hard coded or passed params).
    if ($OrganizationKey -eq '__ORGANIZATION_KEY__') {
        Copy-LogAndExt -throwError "OrganizationKey not specified! This is a user defined identifier set by you (usually your customer's organization name)"
    } elseif ($OrganizationKey.length -lt 1) {
        Copy-LogAndExt -throwError 'Invalid OrganizationKey specified (length should be > 0)!'
    }
    Write-LogMessage 'Parameters verified.'
}

# Force kill a process by process name
function Stop-ProcessByName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName
    )

    $processes = Get-Process | Where-Object { $_.ProcessName -eq $ProcessName }
    $processCount = $processes | Measure-Object | Select-Object -ExpandProperty Count

    if ($processCount -eq 0) {
        Write-LogMessage "No processes with the name '$ProcessName' are currently running."
    } else {
        foreach ($process in $processes) {
            try {
                $processID = $process.Id
                Stop-Process -Id $processID -Force
                Write-LogMessage "Killed process '$ProcessName' (ID $processID) successfully."
            } catch {
                Write-LogMessage "Failed to kill process '$ProcessName' (ID $processID): $($_.Exception.Message)"
            }
        }
    }
}

# check to see if the Huntress service exists (agent or updater)
function Confirm-ServiceExists ($service) {
    if ([string]::IsNullOrEmpty($service)) {
        return $false
    }

    if (Get-Service $service -ErrorAction SilentlyContinue) {
        return $true
    }
    return $false
}

# check to see if the Huntress service is running (agent or updater)
function Confirm-ServiceRunning ($service) {
    if ([string]::IsNullOrEmpty($service)) {
        return $false
    }

    $arrService = Get-Service $service -ErrorAction SilentlyContinue
    if ($null -eq $arrService) {
        return $false
    }

    $status = $arrService.Status.ToString()
    if ($status.ToLower() -eq 'running') {
        return $true
    }

    return $false
}

# Check the Windows uninstall registry (Add/Remove Programs) for a Huntress Agent entry.
# This is a more reliable "is it actually installed" signal than leftover files alone -
# a botched uninstall can leave files behind in the Huntress folder without a working agent.
# Checks both the native and Wow6432Node hives since the uninstall entry's location can vary.
function Confirm-UninstallKeyExists {
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $uninstallPaths) {
        $match = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
        Select-Object DisplayName |
        Where-Object { $_.DisplayName -like 'Huntress Agent*' }
        if ($match) {
            return $true
        }
    }
    return $false
}

# Stop the Agent and Updater services
function Stop-HuntressServices {
    Write-LogMessage 'Stopping Huntress services...'
    if (Confirm-ServiceExists($HuntressAgentServiceName)) {
        try {
            Stop-Service -Name "$HuntressAgentServiceName" -ErrorAction SilentlyContinue
        } catch {
            Write-LogMessage 'Unable to stop HuntressAgent, possible Tamper Protection interference.'
        }
    } else {
        Write-LogMessage "$($HuntressAgentServiceName) not found, nothing to stop"
    }
    if (Confirm-ServiceExists($HuntressUpdaterServiceName)) {
        try {
            Stop-Service -Name "$HuntressUpdaterServiceName" -ErrorAction SilentlyContinue
        } catch {
            Write-LogMessage 'Unable to stop HuntressUpdater, possible Tamper Protection interference.'
        }
    } else {
        Write-LogMessage "$($HuntressUpdaterServiceName) not found, nothing to stop"
    }
}

# Ensure the installer was not modified during download by validating the file signature.
function Confirm-InstallerSignature ($file) {
    $varChain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain
    try {
        $varChain.Build((Get-AuthenticodeSignature -FilePath "$file").SignerCertificate) | Out-Null
    } catch [System.Management.Automation.MethodInvocationException] {
        Copy-LogAndExt -throwError "ERROR: '$file' did not contain a valid digital certificate, something may have corrupted the file. Try again and contact Support if the 2nd attempt fails"
    }
}

# Prevent conflicting file from preventing creation of installation directory.
function Assert-AgentPath {
    $path = Get-AgentPath
    if (Test-Path $path -PathType Leaf) {
        $backup = "$path.bak"
        $err = "WARNING: '$path' already exists and is not a directory, renaming to '$backup'."
        Write-LogMessage $err
        Rename-Item -Path $path -NewName $backup -Force
    }
}

# download the Huntress installer
function Get-Installer {
    $msg = "Downloading installer to '$InstallerPath'..."
    Write-LogMessage $msg

    # Ensure a secure TLS version is used.
    $ProtocolsSupported = [enum]::GetValues('Net.SecurityProtocolType')
    if ( ($ProtocolsSupported -contains 'Tls13') -and ($ProtocolsSupported -contains 'Tls12') ) {
        # Use only TLS 1.3 or 1.2
        Write-LogMessage 'Using TLS 1.3 or 1.2...'
        [Net.ServicePointManager]::SecurityProtocol = (
            [Enum]::ToObject([Net.SecurityProtocolType], 12288) -bor [Enum]::ToObject([Net.SecurityProtocolType], 3072)
        )
    } else {
        Write-LogMessage 'Using TLS 1.2...'
        try {
            # In certain .NET 4.0 patch levels, SecurityProtocolType does not have a TLS 1.2 entry.
            # Rather than check for 'Tls12', we force-set TLS 1.2 and catch the error if it's truly unsupported.
            [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
        } catch {
            Copy-LogAndExt -throwError "ERROR: Unable to use a secure version of TLS. Verify Hotfix KB3140245 is installed. Error: ($_.Exception.Message)"
        }
    }

    # Delete stale installer before downloading the most recent installer
    if (Test-Path $InstallerPath -PathType Leaf) {
        $err = "WARNING: '$InstallerPath' already exists, deleting stale Huntress Installer."
        Write-LogMessage $err
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
            $err = "WARNING: Failed to download the Huntress Installer ($attempt/$attempts), retrying in $delay seconds. Error: $_.Exception.Message"
            Write-LogMessage $err
            Start-Sleep -Seconds $delay
        }
    }

    # Ensure the file downloaded correctly, if not, throw error
    if ( ! (Test-Path $InstallerPath) ) {
        Copy-LogAndExt -throwError "ERROR: Failed to download the Huntress Installer. Try accessing $($DownloadURL) from the host where the download failed. Contact support@huntress.io if the problem persists."
    }

    $msg = "Installer downloaded to '$InstallerPath'..."
    Write-LogMessage $msg
}

# check if the agent downloaded, is a valid install file, if those match up then run the installer
function Install-Huntress ($OrganizationKey) {
    # check that the installer downloaded and wasn't quarantined
    Write-LogMessage "Checking for installer '$InstallerPath'..."
    if ( ! (Test-Path $InstallerPath) ) {
        $err = ("ERROR: The installer was unexpectedly removed from $InstallerPath `n" +
            'A security product may have quarantined the installer. Check your security product logs.' +
            'If the issue continues to occur, send the log to the Huntress ' +
            'Team for help at support@huntresslabs.com')
        Write-LogMessage $err
        Copy-LogAndExt -throwError $err
    }

    # verify the installer's integrity
    Confirm-InstallerSignature($InstallerPath)

    Write-LogMessage 'Executing installer...'
    Assert-AgentPath
    # if $Tags value exists install using the provided tags, otherwise no tags
    if (($Tags) -or ($TagsKey -ne '__TAGS__')) {
        $process = Start-Process $InstallerPath "/ACCT_KEY=`"$AccountKey`" /ORG_KEY=`"$OrganizationKey`" /TAGS=`"$TagsKey`" /S" -PassThru
    } else {
        $process = Start-Process $InstallerPath "/ACCT_KEY=`"$AccountKey`" /ORG_KEY=`"$OrganizationKey`" /S" -PassThru
    }

    try {
        $process | Wait-Process -Timeout $timeout -ErrorAction Stop
    } catch {
        $process | Stop-Process -Force
        Copy-LogAndExt -throwError "ERROR: Installer failed to complete in $timeout seconds. Possible interference from a security product?"
    }
}

# Test that the Huntress agent was able to install, register, and start service correctly
function Test-Installation {
    # Get the file locations of some of the Huntress executables and setting up some registry related variables
    $HuntressDirectory = Get-AgentPath
    $HuntressAgentPath = Join-Path $HuntressDirectory 'HuntressAgent.exe'
    $HuntressUpdaterPath = Join-Path $HuntressDirectory 'HuntressUpdater.exe'
    $AgentIdKeyValueName = 'AgentId'
    $OrganizationKeyValueName = 'OrganizationKey'
    $TagsValueName = 'Tags'

    Write-LogMessage 'Verifying installation...'

    # 
    # Watch for HuntressAgent.log, checking every 1/4 second until 10 seconds elapsed, if found grab the last 8 lines
    $didAgentRegister = $false
    for ($i = 0; $i -le 40; $i++) {
        if (Test-Path "$($HuntressDirectory)\HuntressAgent.log") {
            $linesFromLog = Get-Content "$($HuntressDirectory)\HuntressAgent.log" | Select-Object -Last 8
            break
        }
        Start-Sleep -Milliseconds 250
    }
    # Write the end of HuntressAgent log to this PoSh deploy log, and note if the agent registered successfully
    if ($NULL -ne $linesFromLog) {
        foreach ($line in $linesFromLog) {
            Write-LogMessage $line
            if ($line -like '*registered agent*') {
                $didAgentRegister = $true
            }
        }
    } else {
        Write-LogMessage 'Warning: HuntressAgent.log not found! This is typically caused by 3rd party interference - AV, EDR, ThreatLocker'
    }
    # If the agent didn't register, log the tail of HuntressAgent.log so Support can see the reason registration failed
    if ( ! $didAgentRegister) {
        $err = 'WARNING: It does not appear the agent has successfully registered. Check 3rd party AV exclusion lists to ensure Huntress is excluded.'
        Write-LogMessage ($err + $SupportMessage)
    } else {
        Write-LogMessage "Agent successfully registered in $($i/4) seconds"
    }

    # Ensure the critical files were created.
    foreach ( $file in ($HuntressAgentPath, $HuntressUpdaterPath) ) {
        if ( ! (Test-Path $file) ) {
            Copy-LogAndExt -throwError "ERROR: $file did not exist. Check your AV/security software quarantine"
        }
        Write-LogMessage "'$file' is present."
    }

    # Check for Legacy OS, any kernel below 6.2 cannot run Huntress EDR (so we skip that check)
    if ( ($KernelVersion.major -eq 6 -and $KernelVersion.minor -lt 2) -or ($KernelVersion.major -lt 6) ) {
        Write-LogMessage 'WARNING: Legacy OS detected, Huntress EDR will not be installed'
    } else {
        Write-LogMessage 'Huntress EDR will be installed automatically in < 24 hours.'
    }

    # Ensure the services are installed and running.
    foreach ($svc in $services) {
        # check if the service is installed
        if ( ! (Confirm-ServiceExists($svc))) {
            # if Huntress was installed before this script started and Rio is missing then we log that, but continue with this script
            if ($svc -eq $HuntressEDRServiceName) {
                if ($isHuntressInstalled) {
                    Write-LogMessage 'Information: Huntress Process Insights (aka Rio) is installed automatically by the Huntress portal. It can take up to 24 hours to show up'
                    Write-LogMessage 'See more about compatibility here: https://support.huntress.io/hc/en-us/articles/4410699983891-Supported-Operating-Systems-System-Requirements-Compatibility'
                } else {
                    Write-LogMessage 'New install detected. It may take 24 hours for Huntress EDR (Rio) to install!'
                }
            } else {
                Copy-LogAndExt -throwError "$($svc) service is missing! + $($SupportMessage)"
            }
        }
        # check if the service is running, attempt to restart if not (only for base agent).
        elseif ( (! (Confirm-ServiceRunning($svc))) -and ($svc -eq $HuntressAgentServiceName)) {
            Start-Service $svc
            # if still not running, log and give up, else inform of success
            if (! (Confirm-ServiceRunning($svc))) {
                Write-LogMessage "ERROR: The $($svc) service is not running. Attempting to restart"
                Start-Service $svc
                if (! (Confirm-ServiceRunning($svc))) {
                    Copy-LogAndExt -throwError "ERROR: restart of service $($svc) failed."
                }
            } else {
                Write-LogMessage "'$svc' is running."
            }
        }
    }


    # look for a condition that prevents checking registry keys, if not then check for registry keys
    if ( ($PowerShellArch -eq $X86) -and ($WindowsArchitecture -eq $X64) ) {
        Write-LogMessage "WARNING: Can't verify registry settings due to 32bit PowerShell on 64bit host. Run PowerShell in 64 bit mode"
    } else {
        # Ensure the Huntress registry key is present.
        if ( ! (Test-Path $HuntressKeyPath) ) {
            Copy-LogAndExt -throwError "ERROR: The registry key '$HuntressKeyPath' did not exist. You may need to reinstall with the -reregister flag"
        }

        # Ensure the Huntress registry values are present.
        $HuntressKeyObject = Get-ItemProperty $HuntressKeyPath
        foreach ( $value in ($AgentIdKeyValueName, $OrganizationKeyValueName, $TagsValueName) ) {
            if ( ! (Get-Member -InputObject $HuntressKeyObject -Name $value -MemberType Properties) ) {
                Copy-LogAndExt -throwError "ERROR: The registry value $value did not exist within $HuntressKeyPath. You may need to reinstall with the -reregister flag"
            }
        }
    }

    # Verify the agent registered (if not blocked by 32/64 bit incompatibilities).
    if ( ($PowerShellArch -eq $X86) -and ($WindowsArchitecture -eq $X64) ) {
        Write-LogMessage "WARNING: Can't verify agent registration due to 32bit PowerShell on 64bit host."
    } else {
        if ($HuntressKeyObject.$AgentIdKeyValueName -eq 0) {
            Copy-LogAndExt -throwError "ERROR: The agent did not register. Check the log (%ProgramFiles%\Huntress\HuntressAgent.log) for errors. Missing $($HuntressKeyObject.$AgentIdKeyValueName)"
        }
        Write-LogMessage 'Agent registered.'
    }
    Write-LogMessage 'Installation verified!'
}

# prepare to reregister by stopping the Huntress service and deleting all the registry keys
function Initialize-Reregister {
    Write-LogMessage 'Preparing to re-register agent...'
    Stop-HuntressServices
    $HuntressKeyPath = 'HKLM:\SOFTWARE\Huntress Labs\Huntress'
    Remove-Item -Path "$HuntressKeyPath" -Recurse -ErrorAction SilentlyContinue
}

# looks at the Huntress log to return true if the agent is orphaned, false if the agent is active AB
function Test-IsOrphan {
    # find the Huntress log file or state that it can't be found
    if (Test-Path 'C:\Program Files\Huntress\HuntressAgent.log') {
        $Path = 'C:\Program Files\Huntress\HuntressAgent.log'
    } elseif (Test-Path 'C:\Program Files (x86)\Huntress\HuntressAgent.log') {
        $Path = 'C:\Program Files (x86)\Huntress\HuntressAgent.log'
    } elseif ($isHuntressInstalled) {
        Write-LogMessage 'Unable to locate log file, thus unable to check if orphaned'
        return $false
    } else {
        Write-LogMessage 'New machine, no need to run through orphan checker'
        return $false
    }

    # if the log was found, look through the last 10 lines for the orphaned agent error code
    if ($Path -match 'HuntressAgent.log') {
        $linesFromLog = Get-Content $Path | Select-Object -Last 10
        foreach ($line in $linesFromLog) {
            if ($line -like '*bad status code: 401*') {
                Write-LogMessage "Agent appears to be orphaned: $($line)"
                return $true
            }
        }
    }
    return $false
}

# Check if the script is being run with admin access AB
function Test-IsAdministrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# Ensure the disk has enough space for the install files + agent, then write results to the log AB
function Get-DiskFreeSpace {
    $freeSpace = (Get-PSDrive C).Free
    if ($freeSpace -lt 200111222) {
        $err = "WARNING: Low disk space detected, you may have troubles completing this install. Only $($freeSpace) bytes remaining (need about $(200111222))."
        Write-LogMessage $err
    } else {
        Write-LogMessage "Free disk space: $($freeSpace) bytes"
    }
}

# Gather information about active network adapters for troubleshooting purposes
function Get-NetworkAdapterInfo {
    # Filter out adapters that are unlikely to be useful to log
    $adapters = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' -and $_.Speed -ge 1 -and $_.Description -ne 'Tunnel' }
    Write-LogMessage 'Adapter Name                            IPv4               DNS                               Gateway'

    foreach ($adapter in $adapters) {
        $ipProps = $adapter.GetIPProperties()
        $ipv4 = $ipProps.UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } | Select-Object -ExpandProperty Address | ForEach-Object { $_.IPAddressToString }
        # Fetch the IP properties and filter out local and empty IPv4 entries
        if ($null -ne $ipv4 -and $ipv4 -ne '') {
            $adapterName = ([string]$adapter.Name).PadRight(36)
            $ipv4 = ([string]$ipv4).PadRight(15)
            $dns = (($ipProps.DnsAddresses | ForEach-Object { $_.IPAddressToString }) -join ', ').PadRight(30)
            $gway = (($ipProps.GatewayAddresses | ForEach-Object { $_.Address.IPAddressToString }) -join ', ').PadRight(30)
            Write-LogMessage "$adaptername    $ipv4    $dns    $gway"
        }
    }
}

# determine the path in which Huntress is installed AB
function Get-AgentPath {
    # Ensure we resolve the correct Huntress directory regardless of operating system or process architecture.
    if ($WindowsArchitecture -eq $X64) {
        return (Join-Path $Env:ProgramW6432 'Huntress')
    } else {
        return (Join-Path $Env:ProgramFiles 'Huntress')
    }
}

# attempt to run a process and log the results AB
function Invoke-RunProcess ($process, $flags, $name) {
    try {
        $proc = Start-Process $process $flags -PassThru
        Wait-Process -Timeout $timeout -ErrorAction Stop -InputObject $proc
        Write-LogMessage "$($name) finished"
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
        Copy-LogAndExt -throwError $err
    }
}

# Fully uninstall the agent AB
function Uninstall-Huntress {
    $agentPath = Get-AgentPath
    $updaterPath = Join-Path $agentPath 'HuntressUpdater.exe'
    $exeAgentPath = Join-Path $agentPath 'HuntressAgent.exe'
    $uninstallerPath = Join-Path $agentPath 'Uninstall.exe'
    $wasUninstallerRun = $false

    # speed this up by stopping services first
    Stop-Service 'huntressrio' -ErrorAction SilentlyContinue
    Stop-Service 'huntressupdater' -ErrorAction SilentlyContinue
    Stop-Service 'huntressagent' -ErrorAction SilentlyContinue

    # Force kill the executables so they're not hangin around
    Stop-ProcessByName 'HuntressAgent.exe'
    Stop-ProcessByName 'HuntressUpdater.exe'
    Stop-ProcessByName 'HuntressRio.exe'

    # attempt to use the built in uninstaller, if not found use the uninstallers built into the Agent and Updater
    if (Test-Path $agentPath) {
        # run uninstaller.exe, if not found run the Agent's built in uninstaller and the Updater's built in uninstaller
        if (Test-Path $uninstallerPath) {
            Invoke-RunProcess "$($uninstallerPath)" '/S' 'Uninstall.exe'
            $wasUninstallerRun = $true
        } elseif (Test-Path $exeAgentPath) {
            Invoke-RunProcess "$($exeAgentPath)" '/S' 'Huntress Agent uninstaller'
            $wasUninstallerRun = $true
        } elseif (Test-Path $updaterPath) {
            Invoke-RunProcess "$($updaterPath)" '/S' 'Updater uninstaller'
            $wasUninstallerRun = $true
        } else {
            Write-LogMessage 'Agent path found but no uninstallers found. Attempting to manually uninstall'
        }
    } else {
        $err = 'Note: unable to find Huntress install folder. Attempting to manually uninstall.'
        Write-LogMessage $err
    }

    # if uninstaller was run, loop until Huntress assets are all successfully removed, or exit & report if timer exceeds 15 seconds
    if ($wasUninstallerRun) {
        for ($i = 0; $i -le 15; $i++) {
            if ((Test-Path $exeAgentPath) -or (Test-Path $HuntressRegKey)) {
                Start-Sleep 1
            } else {
                Write-LogMessage "Agent successfully uninstall in $($i) seconds"
                $i = 100
            }
            if ($i -eq 15) {
                $err = "Uninstall not complete after $($i) seconds"
                Write-LogMessage $err
            }
        }
    }

    # look for the Huntress directory, if found then delete
    if (Test-Path $agentPath) {
        Remove-Item -LiteralPath $agentPath -Force -Recurse -ErrorAction SilentlyContinue
        Write-LogMessage 'Manual cleanup of Huntress folder: success'
    } else {
        Write-LogMessage 'Manual cleanup of Huntress folder: folder not found'
    }

    # look for the registry keys, if exist then delete
    if (Test-Path $HuntressRegKey) {
        Get-Item -Path $HuntressRegKey | Remove-Item -Recurse
        Write-LogMessage 'Manually deleted Huntress registry keys'
    } else {
        Write-LogMessage 'No registry keys found, uninstallation complete'
    }

    # if Huntress services still exist, then delete
    $services = @('HuntressRio', 'HuntressAgent', 'HuntressUpdater', 'Huntmon')
    foreach ($service in $services) {
        if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
            Write-LogMessage "Service $($service) detected post uninstall, attempting to remove"
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            c:\Windows\System32\sc.exe DELETE $service
        }
    }
}

# grab the currently installed agent version AB
function Get-AgentVersion {
    $exeAgentPath = Join-Path (Get-AgentPath) 'HuntressAgent.exe'
    $agentVersion = (Get-Item $exeAgentPath).VersionInfo.FileVersion
    return $agentVersion
}

# ensure all the Huntress services are running AB
function Repair-Agentt {
    # check that service exists before we attempt to start it
    $HuntressService = Get-Service -Name 'HuntressAgent' -ErrorAction SilentlyContinue
    $UpdaterService = Get-Service -Name 'HuntressUpdater' -ErrorAction SilentlyContinue
    $RioService = Get-Service -Name 'HuntressRio' -ErrorAction SilentlyContinue
    $DidRepairFinish = $true

    # if each service doesn't exist we'll be returning false, else start the service
    if ($null -eq $HuntressService) {
        Write-LogMessage 'Repair was unable to find the HuntressService, this machine will need Huntress uninstalled and reinstalled in order to maintain security'
        $DidRepairFinish = $false
    } else {
        Start-Service 'HuntressAgent'
        Write-LogMessage 'Repair started HuntressAgent service'
    }
    if ($null -eq $UpdaterService) {
        Write-LogMessage 'Repair was unable to find the UpdaterService, this machine will need Huntress uninstalled and reinstalled in order to continue receiving updates.'
        $DidRepairFinish = $false
    } else {
        Start-Service 'HuntressUpdater'
        Write-LogMessage 'Repair started HuntressUpdater service'
    }

    # For Rio/EDR we don't return false as we don't know if it's a fresh install that hasn't received Rio yet, but still attempt to restart service
    if (($null -eq $RioService) -and $isHuntressInstalled) {
        Write-LogMessage 'Repair was unable to find the RioService. If this is a fresh install it may take up to 24 hours for Rio to install. Otherwise contact support to ensure EDR coverage.'
    } elseif ($null -eq $RioService) {
        Write-LogMessage 'Fresh install detected, it can take up to 24 hours for Rio to install.'
    } else {
        Start-Service 'HuntressRio'
        Write-LogMessage 'Repair started HuntressRio service'
    }

    return $DidRepairFinish
}

# Agent will not function when communication is blocked so we exit the script if too many URLs are blocked AB
# Essentially this function tests for port 443 outbound to Huntress URLs, and tests that Huntress certs aren't intercepted.
# Blocking port 443 or intercepting Huntress certs will prevent the agent from functioning, so we exit rather than installing an agent that probably won't function as intended.
function Test-NetworkConnectivity {
    $countFails = 0

    # Avoid "First Run Customize" blocking the testing by disabling it
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main' -Name 'DisableFirstRunCustomize' -Value 2
    # Force TLS 1.2 to avoid compatibility issues and ensure accurate testing (Huntress uses TLS 1.2+ only). Casting 'TLS12' as '3072' for compatibility with legacy OS.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]3072
    } catch {
        Copy-LogAndExt -throwError 'Failed to enable TLS 1.2, Huntress requires TLS 1.2 or higher for security reasons.'
    }

    # retrieve URLs, cert Issuer, and cert Subject from Huntress github
    $URL = 'https://raw.githubusercontent.com/huntresslabs/support/refs/heads/main/URLdata.json'
    # Try the modern set of commands first, then fallback to legacy commands
    try {
        $data = (Invoke-WebRequest -Uri $URL -UseBasicParsing -ErrorAction Stop).Content | ConvertFrom-Json
    } catch {
        Write-LogMessage 'Fallback using WebClient (still uses TLS 1.2)'
        $wc = New-Object System.Net.WebClient
        $wc.Headers['User-Agent'] = 'HuntressSupportScript'
        try {
            $jsonString = $wc.DownloadString($URL)
        } catch {
            Copy-LogAndExt -throwError 'Unable to connect to github, connectivity to raw.githubusercontent.com on port 443 is required for this script to verify the machine is ready for Huntress!'
        }
        try {
            # For PoSh 2 we need to use the legacy .NET JavaScriptSerializer
            [void][Reflection.Assembly]::LoadWithPartialName('System.Web.Extensions')
            # Create the serializer object and parse the string
            $Serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            $data = $Serializer.DeserializeObject($jsonString)
        } catch {
            Copy-LogAndExt -throwError 'Unable to parse JSON from githubusercontent.com'
        }
    }
    # process the data from github
    $testURLs = @($data.array1)
    $certURLs = @($data.array2)
    $certTemp = @($data.array4)
    $expIssuerName = @($data.array5)
    $expSubject = @()
    $expIssuer = @()
    # array4 contains two different sets of info, even indices are subject, odd indices are issuer
    for ($i = 0; $i -lt $certTemp.Count; $i++) {
        if ($i % 2 -eq 0) {
            $expSubject += $certTemp[$i]
        } else {
            $expIssuer += $certTemp[$i]
        }
    }

    # tests that the expected certificates are not intercepted. If the expected cert is not returned the agent will not function.
    Write-LogMessage '-- Testing Certificate Validation --'
    $countFails = 0
    for ($i = 0; $i -lt $certURLs.Count; $i++) {
        $cleanURL = ($certURLs[$i] -replace '^https://', '') -replace '/.*',''
        $uri = ([uri]$cleanURL)
        $tcp = New-Object Net.Sockets.TcpClient
        $tcp.Connect("$uri", 443)
        $ssl = New-Object Net.Security.SslStream($tcp.GetStream(),$false, { $true })
        $ssl.AuthenticateAsClient($uri)
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
        $recSubject = $cert.Subject
        $recIssuer = $cert.Issuer
        # retrieve a hashed/encrypted version of the certificate to log in case troubleshooting is required
        $PEM = @"
-----BEGIN CERTIFICATE-----
$([System.Convert]::ToBase64String($cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert), [System.Base64FormattingOptions]::InsertLineBreaks))
-----END CERTIFICATE-----
"@

        if ($recSubject -eq $expSubject[$i]) {
            Write-LogMessage "[Certificate subject validation successful for $cleanURL]"
        } else {
            Write-LogMessage "[FAILED: Subject validation. Certificate does not match for [$cleanURL] !]"
            Write-LogMessage "Subject that was returned: [$recSubject]"
            Write-LogMessage "Subject that was expected: [$($expSubject[$i])]"
            Write-LogMessage '------------------------------------------------------------------------------------------------------------------------------'
            Write-LogMessage 'The Subject text above usually identifies if this is a DPI/cert interception issue, or a cert chain issue.'
            Write-LogMessage "* If the returned SUBJECT does not contain 'Huntress' or 'Microsoft' in the text this is likely a DPI/cert interception issue."
            Write-LogMessage "      You'll need to add an exclusion for the certificate for this URL in your DPI/cert interception service: $cleanURL"
            Write-LogMessage '* Otherwise this is likely a missing certificate chain. Check for pending OS updates, reboot, and try again.'
            Write-LogMessage '------------------------------------------------------------------------------------------------------------------------------'

            $countFails++
        }

        # Issuer can vary based on the specific server the script reaches. To compensate, we check for exact match then a wildcard match.
        if ($recIssuer -eq $expIssuer[$i]) {
            Write-LogMessage "[Certificate issuer validation successful for $cleanURL]"
        } else {
            # Wildcard match to compensate for big infrastructure having slightly different certificate lines
            if ($recIssuer -like "*$($expIssuerName[$i])*") {
                Write-LogMessage 'Note: this was not an exact match, expected with big infrastructure. As long as the expected and returned Issuer lines are similar you can ignore this.'
                Write-LogMessage "Issuer that was returned: [$recIssuer]"
                Write-LogMessage "Issuer that was expected: [$($expIssuer[$i])]"
            } else { 
                Write-LogMessage "[FAILED: Issuer validation. Certificate does not match for [$cleanURL] !]"
                Write-LogMessage "Issuer that was returned: [$recIssuer]"
                Write-LogMessage "Issuer that was expected: [$($expIssuer[$i])]"
                Write-LogMessage "PEM that was received: $PEM"
                Write-LogMessage '------------------------------------------------------------------------------------------------------------------------------'
                Write-LogMessage 'The Issuer text above usually identifies if this is a DPI/cert interception issue, or a cert chain issue.'
                Write-LogMessage "* If the returned ISSUER does not contain 'DigiCert', 'Google', or 'Microsoft', this is likely a  DPI/cert interception issue."
                Write-LogMessage "      You'll need to add an exclusion for the certificate for this URL in your DPI/cert interception service: $cleanURL"
                Write-LogMessage '* Otherwise this is likely a missing certificate chain. Check for pending OS updates, reboot, and try again.'
                Write-LogMessage '------------------------------------------------------------------------------------------------------------------------------'
                $countFails++
            }
        }
        $ssl.Dispose()
        $tcp.Close()
    }
    Write-LogMessage ''
     
    # test outgoing port 443 connectivity to Huntress URLs
    Write-LogMessage '-- Verifying Huntress services can be reached --'
    foreach ($testURL in $testURLs) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $cleanURL = $($testURL -replace '^https://', '') -replace '/.*',''
            $tcp.connect($cleanURL, 443)
            Write-LogMessage "[Connection to $cleanURL successful]"
        } catch {
            Write-LogMessage "WARNING, connectivity to Huntress URL's is being interrupted. You MUST open port 443 for $cleanURL in order for the Huntress agent to function."
            Write-LogMessage "Error: $($_.Exception.Message)"
            $countFails++
        } finally {
            $tcp.Close()
        }
    }
    Write-LogMessage ''

    if ($countFails -gt 1) {
        Write-LogMessage '[FAILED to connect to all Huntress services]'
        Write-LogMessage '------------------------ FAILED network test ----------------------------------'
        Copy-LogAndExt 'FAILED to connect to all Huntress services'
    } else {
        Write-LogMessage '[Successfully connected to Huntress services]'
    }
}

# Log useful data about the machine for troubleshooting AB
function Write-LogInfo {
    Write-LogMessage '============================== Pre-flight checks and logging =============================='
    Write-LogMessage "Script type: '$ScriptType'"
    Write-LogMessage "Script version: '$ScriptVersion'"
    Write-LogMessage "Script flags:  Reregister=$reregister  Reinstall=$reinstall  Uninstall=$uninstall "
    if ($AccountKey.length -lt 8) {
        Write-LogMessage "Invalid key length, found $($AccountKey.length) (should be 32). Account key value: $AccountKey"
    } else {
        $masked = $AccountKey.Substring(0,4) + '************************' + $AccountKey.SubString($AccountKey.length - 4,4)
        Write-LogMessage "Pre-trim variables: account key=[$masked]  org key=[$OrganizationKey]   (brackets are in place to show trailing/leading spaces)"
    }

    # if Huntress was already installed, pull version info and TP status. This is intentionally a vague check, not intended to definitively show install status!
    Write-LogMessage "Script cursory check, is Huntress installed already: $($isHuntressInstalled)"
    if ($isHuntressInstalled) {
        Write-LogMessage "Agent version $(Get-AgentVersion) found"
    }

    if (Confirm-ServiceRunning $HuntressEDRServiceName) {
        $checkTP = (Confirm-ServiceRunning $HuntressAgentServiceName)
        if ( $null -eq $checkTP ) {
            Write-LogMessage 'Warning: Tamper Protection may be enabled; you may need to disable TP or run this as SYSTEM to repair, upgrade, or reinstall this agent.'
        } else {
            Write-LogMessage 'Pass: Tamper Protection not detected, or this script is running as SYSTEM'
        }
    }

    Write-LogMessage "Administrator access: $(Test-IsAdministrator)"
    $userContext = whoami
    if ($userContext -eq 'nt authority\system') {
        Write-LogMessage 'Pass: Run under the SYSTEM user.'
    } else {
        Write-LogMessage 'Warning: Not run under the SYSTEM user, you may have issues with Huntress Tamper Protection'
    }

    Write-LogMessage "Installing to location: '$InstallerPath'"
    Write-LogMessage "Installer log location: '$DebugLog'"

    Write-LogMessage ''
    Write-LogMessage '============================== Logging machine details =============================='
    # Log OS details
    $patterns = 'Host Name', 'OS Name', 'OS Version', 'OS Configuration', 'Original Install Date', 'System Boot Time', 'System Type', 'Processor(s)', 'Time Zone', 'Total Physical Memory', 'Available Physical Memory', 'Domain', 'Logon Server', 'Network Card(s)', 'Hyper-V Requirements'
    $systemInfo = systeminfo | Out-String
    $systemInfo = (($systemInfo -split "`r`n") | Select-String -Pattern $patterns | Select-Object -ExpandProperty Line)
    Write-LogMessage $($systemInfo -join "`r`n")
    Get-DiskFreeSpace

    # Logging some additional info for a temporary issue with Windows 8.1 and missing Visual C++ dependencies
    Get-LibraryCheck

    # Log status of AD joined and the (in)ability to contact a DC
    $ErrorActionPreference = 'SilentlyContinue'    
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $domainJoined = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
        } else {
            $domainJoined = (Get-WmiObject Win32_ComputerSystem).PartOfDomain
        }
    } catch {
        Write-LogMessage 'Attention: Unable to determine if domain joined (non-stoppage error)'
        $domainJoined = $false
    }
    if ( $domainJoined ) {
        try {
            $secureChannelStatus = Test-ComputerSecureChannel
        } catch {
            Write-LogMessage "Warning, unable to Test-ComputerSecureChannel. If this isn't a DC, then the trust relationship with the DC may be broken"
            $secureChannelStatus = $false
        }
        if ( ! $secureChannelStatus) {
            Write-LogMessage 'Warning, AD joined machine without DC connectivity. Some services may be impacted such as Managed AV and in some rare cases Host Isolation.'
        } else {
            Write-LogMessage 'AD joined and DC connectivity verified!'
        }
    } else {
        Write-LogMessage 'Not AD joined, skipping Test-ComputerSecureChannel'
    }

    # Log architecture and PowerShell details
    Write-LogMessage "Detected Architecture (Windows 32/64 bit): '$($WindowsArchitecture)'"
    Write-LogMessage "PowerShell Architecture (PoSh 32/64 bit): '$PowerShellArch'"
    Write-LogMessage "PowerShell version: $($PoShVersion).$($PSversionTable.PsVersion.Minor)"
    Write-LogMessage "Powershell legacy detected: $($LegacyCommandsRequired)"
    if ($LegacyCommandsRequired) {
        Write-LogMessage 'Warning! Older version of PowerShell detected'
    }

    # Log machine uptime, use -1 to call attention to machines that have issues running the GCIM command
    $uptime = ([Timespan]::FromMilliseconds([Environment]::TickCount)).Days


    if ($uptime -gt 9) {
        Write-LogMessage "Warning, high uptime detected. This machine may need a reboot in order to resolve Windows update-based file locks. $($uptime)`n"
    } else {
        Write-LogMessage "Days of uptime: $($uptime)`n"
    }

    Write-LogMessage '============================== Logging machine networking details =============================='
    # Logging TCP/IP configuration 
    Get-NetworkAdapterInfo
    # Checking connectivity to Huntress servers
    Test-NetworkConnectivity
}

# This function copies the Huntress DebugLog to a more permanent location as it's incredibly helpful for troubleshooting. AB
# Exits with a code 0 if $throwError wasn't passed, otherwise throws the error contained in the $throwError string
function Copy-LogAndExt {
    param (
        [string]$throwError
    )
    if ( [string]::IsNullOrEmpty($throwError) ) { $throwError = '0' }

    # log the error message first
    if ($throwError -ne '0') {
        Write-LogMessage "WARNING: Script errors detected, operation may not have completed! $throwError `n$SupportMessage"
    }

    # sleep to ensure file operations have completed
    Start-Sleep 1
    $agentPath = Get-AgentPath
    $logLocation = Join-Path $agentPath 'HuntressPoShInstaller.log'

    # If this is an unistall, we'll leave the log in the C:\temp dir, otherwise copy the log to the huntress directory
    if (!$uninstall) {
        if (!(Test-Path -Path $agentPath)) { New-Item $agentPath -Type Directory }
        try {
            Copy-Item -Path $DebugLog -Destination $logLocation -Force -ErrorAction SilentlyContinue
            Write-Output "'$($DebugLog)' copied to '$logLocation'."
        } catch {
            Write-Output 'Unable to copy Installer log, possible Tamper Protection interference. Look in \Windows\temp\ for HuntressPoShInstaller.log'
        }
    }

    # if no error was passed, exit gracefully, otherwise throw an error and exit
    if ($throwError -eq '0') {
        Write-Output 'Script complete!'
        exit 0
    } else {
        Write-Output "WARNING: Script errors detected, operation may not have completed! Error: [$throwError]"
        throw $throwError
    }
}

# Sometimes previous installs can be stuck with services in the Disabled state, this function attempts to set the state to Automatic.
# Services in the Disabled state cannot be manually started, and TP will stop partners from fixing this themselves. AB
function Invoke-FixServices {
    $servicesOnInstall = @($HuntressAgentServiceName, $HuntressUpdaterServiceName)
    # Ensure the services are installed before repairing the state
    foreach ($svc in $servicesOnInstall) {
        if (  (Confirm-ServiceExists($svc))) {
            # repairing service state
            if ( $(Get-Service $svc).StartType -ne 'automatic') {
                Write-LogMessage "Disabled service $svc detected, attempting to set startup type to automatic."
                Set-Service -Name $svc -StartupType Automatic
            }
        }
    }
}

function Get-ScriptInfoPath {
    $results = Get-AgentPath
    return Join-Path -Path $results -ChildPath $ScriptInfoName
}

# Get the hash of this currently running PowerShell script file
function Get-Sha256Hash {
    try {
        # Get the hash of this file
        return (Get-FileHash -Path $PSCommandPath -Algorithm SHA256).Hash
    } catch {
        # catch failures in this function and return an empty hash
        $ErrorMessage = $_.Exception.Message
        return '', "Unable to retrieve script hash: $ErrorMessage"
    }
}

# Get the operation we running for this script
function Get-ScriptOperation {
    $operation = 'Install'
    if ($reregister -eq $true) {
        $operation = 'Reregister'
    } elseif ($reinstall -eq $true) {
        $operation = 'Reinstall'
    }

    return $operation
}

function Write-InstallScriptInfo {
    $hold = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    try {
        if ($uninstall) {
            # No need to track installation on an uninstall
            Write-LogMessage 'No script information will be saved for uninstall'
            return
        }

        [array]$hashResult = Get-Sha256Hash
        if ($hashResult.Count -eq 2) {
            Write-LogMessage $hashResult[1]
        }
        # Write the values to a json file in the Huntress install directory (not using built in JSON methods to ensure maximum PoSh version compatibility)
        $json = "{`"vendor`":`"$Vendor`",`"sha256`":`"$($hashResult[0])`",`"operation`":`"$(Get-ScriptOperation)`"}"
        Set-Content -Path $(Get-ScriptInfoPath) -Value $json
    } catch {
        $ErrorMessage = $_.Exception.Message
        Write-LogMessage "Unable to save installation script information: $ErrorMessage"
    }

    $ErrorActionPreference = $hold
}

# Logging Visual C++ info for a Windows 8.1 specific issue
function Get-LibraryCheck {
    # Since this issue only affects Win 8.1, check the OS version before logging.
    if ( (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName -notlike '*Windows 8.1*' ) {
        Write-LogMessage 'Windows 8.1 not detected, not checking for missing dependencies'
        return
    }

    # Fleet Health Check: UCRT + VC Redistributables
    $Results = [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        KB2919355    = 'Missing, install KB2919355 https://www.microsoft.com/en-us/download/details.aspx?id=42327'
        KB2999226    = 'Missing, install KB2999226 https://www.microsoft.com/en-ie/download/details.aspx?id=51109'
        UCRT_Version = 'None, install Universal CRT https://support.microsoft.com/en-us/topic/update-for-universal-c-runtime-in-windows-c0514201-7fe6-95a3-b0a5-287930f3560c'
        VCRedist_x64 = 'Not Found, install x64 Visual C++ Redistributable v14 https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170#visual-c-redistributable-v14'
        VCRedist_x86 = 'Not Found, install x86 Visual C++ Redistributable v14 https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170#visual-c-redistributable-v14'
    }

    # 1. Check for KBs
    $Hotfixes = Get-HotFix | Select-Object -ExpandProperty HotFixID
    if ($Hotfixes -contains 'KB2919355') { $Results.KB2919355 = "Installed`n" }
    if ($Hotfixes -contains 'KB2999226') { $Results.KB2999226 = "Installed`n" }

    # 2. Check for UCRT DLL Version
    if (Test-Path "$env:windir\System32\ucrtbase.dll") {
        $Results.UCRT_Version = "$((Get-Item "$env:windir\System32\ucrtbase.dll").VersionInfo.ProductVersion)  (version 10.0.14393+ is recommended)"
    }

    # 3. Check for VC Redist 2015-2022 via Registry (Fastest for Fleet)
    $UninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty $UninstallKeys | Where-Object { $_.psobject.Properties['DisplayName'] } | Where-Object { $_.DisplayName -like '*Visual C++*' } | ForEach-Object {
        if ($_.DisplayName -like '*x64*') { $Results.VCRedist_x64 = "$($_.DisplayVersion)  (version 14+ is recommended)" }
        if ($_.DisplayName -like '*x86*') { $Results.VCRedist_x86 = "$($_.DisplayVersion)  (version 14+ is recommended)" }
    }

    # Save each of the name and property values on a new line in the installer log
    foreach ($property in $Results.PSObject.Properties) {
        if ($null -ne $property) { Write-LogMessage "$($property.Name) - $($property.Value)" }
    }
}


#########################################################################################
#                                  begin main function                                  #
#########################################################################################
function Start-Main () {
    # Start the script with logging to capture useful data for troubleshooting. All your logging are belong to us, Zero Wang.
    Write-LogInfo

    # if run with the uninstall flag, exit afterward so we don't reinstall the agent after
    if ($uninstall) {
        Write-LogMessage 'Uninstalling Huntress agent'
        Uninstall-Huntress
        Copy-LogAndExt
    }

    Write-LogMessage ''
    Write-LogMessage '============================== Starting Install =============================='
    # if the agent is orphaned, switch to the full uninstall/reinstall (reregister flag)
    if ( !($reregister)) {
        $orphanStatus = Test-IsOrphan
        if ( $orphanStatus -eq $true ) {
            $err = 'Huntress Agent is orphaned, unable to use the provided flag. Switching to uninstall/reinstall (reregister flag)'
            Write-LogMessage "$err"
            $reregister = $true
        }
    }

    # if run with no flags and no account key print usage and exit
    if (!$reregister -and !$uninstall -and !$reinstall -and ($AccountKey -eq '__ACCOUNT_KEY__')) {
        Write-LogMessage 'No flags or account key found! Exiting.'
        Write-LogMessage 'Usage (remove brackets [] and substitute <variable> for your value):'
        Write-LogMessage "powershell -executionpolicy bypass -f ./InstallHuntress.powershellv2.ps1 [-acctkey <account_key>] [-orgkey <organization_key>] [-tags <tags>] [-reregister] [-reinstall] [-uninstall] `n"
        Write-LogMessage 'Example:'
        Write-LogMessage 'powershell -executionpolicy bypass -f ./InstallHuntress.powershellv2.ps1 -acctkey "0b8a694b2eb7b642069" -orgkey "Buzzword Company Name" -tags "production,US West" '
        Copy-LogAndExt -throwError 'No flags or account key found! Exiting.'
    }


    # trim keys for blanks before use
    $AccountKey = $AccountKey.Trim()
    $OrganizationKey = $OrganizationKey.Trim()

    # check that all the parameters that were passed are valid
    Test-Parameters

    # Hide most of the account key in the logs, keeping the front and tail end for troubleshooting
    if ($AccountKey -ne '__Account_Key__') {
        $masked = $AccountKey.Substring(0,4) + '************************' + $AccountKey.SubString($AccountKey.length - 4,4)
        Write-LogMessage "AccountKey: '$masked'"
        Write-LogMessage "OrganizationKey: '$OrganizationKey'"
        Write-LogMessage "Tags: $($Tags)"
    }

    # reregister > reinstall > uninstall > install (in decreasing order of impact)
    # reregister = reinstall + delete registry keys
    # reinstall  = stop Huntress service + reinstall
    $agentPath = Get-AgentPath
    $agentFilesPresent = (Test-Path $agentPath) -and ((Get-ChildItem -Path $agentPath -File | Measure-Object).count -gt 1)
    # Files alone aren't proof of a working install - a prior uninstall can leave remnants behind
    # (locked files, Tamper Protection interference, etc). Only trust "already installed" if
    # Add/Remove Programs agrees; otherwise route through the same cleanup path as -reinstall.
    $huntressUninstallKeyExists = Confirm-UninstallKeyExists

    if ($reregister) {
        Write-LogMessage "Re-register agent: '$reregister'"
        if ( !(Confirm-ServiceExists($HuntressAgentServiceName))) {
            Write-LogMessage "Run with the -reregister flag but the service wasn't found. Attempting to install...."
        }
        Initialize-Reregister
    } elseif ($reinstall -or ($agentFilesPresent -and (-not $huntressUninstallKeyExists))) {
        if (-not $reinstall) {
            Write-LogMessage "Huntress files found in $agentPath but no matching uninstall registry entry was found. Treating this as remnants from an incomplete removal and reinstalling."
        }
        Write-LogMessage "Re-install agent: '$reinstall'"
        if ( !(Confirm-ServiceExists($HuntressAgentServiceName)) ) {
            $err = "Script was run w/ reinstall flag but there's nothing to reinstall. Attempting to clean remnants, then install the agent fresh."
            Write-LogMessage "$err"
            Uninstall-Huntress
        }
        Stop-HuntressServices
    } else {
        Write-LogMessage 'Checking for HuntressAgent install...'
        if ($agentFilesPresent) {
            $assetCount = (Get-ChildItem -Path $agentPath -File | Measure-Object).count
            # to avoid issues with a single file blocking installs, only exit script if multiple files are found and script not run with -reregister or -reinstall
            Copy-LogAndExt -throwError "The Huntress Agent is already installed in $agentPath. Exiting with no changes. Suggest using -reregister or -reinstall flags. Asset count = $assetCount"
        }
    }

    Get-Installer
    Install-Huntress $OrganizationKey
    Invoke-FixServices
    Test-Installation
    Write-LogMessage 'Huntress Agent successfully installed!'
}

try {
    Start-Main
    Write-InstallScriptInfo
} catch {
    Copy-LogAndExt -throwError $_.Exception.Message
}

Write-LogMessage 'Script Complete'
Copy-LogAndExt
