#!ps 
#timeout=90000

$AccountKey="__ACCOUNT_KEY__"
$OrganizationKey="__ORGANIZATION_KEY__"
# Set to "Continue" to enable verbose logging.
$DebugPreference = "SilentlyContinue"
$timeout = 180 # Seconds

##############################################################################
## The following should not need to be adjusted.
##############################################################################
$reregister = $false
$reinstall = $false
$acctkey = $AccountKey
$orgkey = $OrganizationKey
Set-StrictMode -Version Latest
$ScriptVersion = "Version 1, major revision 1, 2023 Oct 9"
$ScriptType = "PowerShell (ConnectWise Control / ScreenConnect)"
if ( ! [string]::IsNullOrEmpty($acctkey) ) {
    $AccountKey = $acctkey
}
if ( ! [string]::IsNullOrEmpty($orgkey) ) {
    $OrganizationKey = $orgkey
}
$X64 = 64
$X86 = 32
$InstallerName = "HuntressInstaller.exe"
$InstallerPath = Join-Path $Env:TMP $InstallerName
$DebugLog = Join-Path $Env:TMP HuntressInstaller.log
$DownloadURL = "https://update.huntress.io/download/" + $AccountKey + "/" + $InstallerName
$HuntressAgentServiceName = "HuntressAgent"
$HuntressUpdaterServiceName = "HuntressUpdater"

$PowerShellArch = $X86
if ([IntPtr]::size -eq 8) {
   $PowerShellArch = $X64
}
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
    if ($reregister -and $reinstall) {
        $err = "Cannot specify both `-reregister` and `-reinstall` parameters, exiting script!"
        LogMessage $err
        exit 1
    }
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
            [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
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
    Start-Sleep -Seconds 8
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
    $WyUpdaterPath = Join-Path $HuntressDirPath "wyUpdate.exe"
    $HuntressKeyPath = "HKLM:\SOFTWARE\Huntress Labs\Huntress"
    $AgentIdKeyValueName = "AgentId"
    $OrganizationKeyValueName = "OrganizationKey"
    $TagsValueName = "Tags"
    foreach ( $file in ($HuntressAgentPath, $HuntressUpdaterPath, $WyUpdaterPath) ) {
        if ( ! (Test-Path $file) ) {
            $err = "ERROR: $file did not exist."
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }
        LogMessage "'$file' is present."
    }
    foreach ( $svc in ($HuntressAgentServiceName, $HuntressUpdaterServiceName) ) {
        # service installed?
        if ( ! (Confirm-ServiceExists($svc)) ) {
            $err = "ERROR: The $svc service is not installed."
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }
        if ( ! (Confirm-ServiceRunning($svc)) ) {
            $err = "ERROR: The $svc service is not running."
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }
        LogMessage "'$svc' is running."
    }
    if ( ($PowerShellArch -eq $X86) -and ($WindowsArchitecture -eq $X64) ) {
        LogMessage "WARNING: Can't verify registry settings due to 32bit PowerShell on 64bit host."
    } else {
        # Ensure the Huntress registry key is present.
        if ( ! (Test-Path $HuntressKeyPath) ) {
            $err = "ERROR: The registry key '$HuntressKeyPath' did not exist."
            LogMessage $err
            LogMessage $SupportMessage
            throw $ScriptFailed + " " + $err + " " + $SupportMessage
        }

        $HuntressKeyObject = Get-ItemProperty $HuntressKeyPath
        foreach ( $value in ($AgentIdKeyValueName, $OrganizationKeyValueName, $TagsValueName) ) {
            If ( ! (Get-Member -inputobject $HuntressKeyObject -name $value -Membertype Properties) ) {
                $err = "ERROR: The registry value $value did not exist within $HuntressKeyPath."
                LogMessage $err
                LogMessage $SupportMessage
                throw $ScriptFailed + " " + $err + " " + $SupportMessage
            }
        }
    }
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

function StopHuntressServices {
    LogMessage "Stopping Huntress services..."
    Stop-Service -Name "$HuntressAgentServiceName"
    Stop-Service -Name "$HuntressUpdaterServiceName"
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
    $os = (get-WMiObject -computername $env:computername -Class win32_operatingSystem).caption.Trim()
    LogMessage "Host OS: '$os'"
    LogMessage "Host Architecture: '$(Get-WindowsArchitecture)'"
    LogMessage "PowerShell Architecture: '$PowerShellArch'"
    if ($reinstall) {
        LogMessage "Re-install agent: '$reinstall'"
    }
    if ($reregister) {
        LogMessage "Re-register agent: '$reregister'"
    }
    LogMessage "Installer location: '$InstallerPath'"
    LogMessage "Installer log: '$DebugLog'"
    $AccountKey = $AccountKey.Trim()
    $OrganizationKey = $OrganizationKey.Trim()
    Test-Parameters
    $masked = $AccountKey.Substring(0,10) + "XXXXXXXXXXXXXXXXXXXXXXX"
    LogMessage "AccountKey: '$masked'"
    LogMessage "OrganizationKey: '$OrganizationKey'"
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
