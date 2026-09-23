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
$AccountKey = "__ACCOUNT_KEY__"

# Replace __ORGANIZATION_KEY__ with a unique identifier for the organization/client (your choice of naming scheme)
$OrganizationKey = "__ORGANIZATION_KEY__"

# Replace __TAGS__ with one or more tags, separated by commas (leave the next line unmodified if you don't want to use Tags)
$TagsKey = "__TAGS__"

# These are used by the Huntress support team when troubleshooting. 
# It's suggested to change $ScriptType to be the name of your automation system deploying this.
$ScriptVersion = "Version 2, major revision 10, 2026 Sept 23"
$ScriptType = "PowerShell"

# Set to "Continue" to enable verbose logging. "SilentlyContinue" is default
$DebugPreference = "SilentlyContinue"

# Legacy, spinning HDD, or overloaded machines may require tuning this value. Most modern end points install in 10 seconds
# 3rd party security software (AV/EDR/etc) may significantly slow down the install if Huntress exclusions aren't properly put in!
# Read more about exclusions here https://support.huntress.io/hc/en-us/articles/4404005178771
$timeout         = 120         # number of seconds to wait before continuing the install

# Currently a fresh install of Huntress + EDR is approximately 100mb, double this for safety as fresh installs can bloat up in size slightly at first
# This can vary based on several factors including process creation rate, if EDR is installed or not, as well as number of users in the c:\users folder
$estimatedSpaceNeeded = 200111222

# If you'd like to use a local JSON file in a specified location, uncomment the below line and change the location if needed
# $alternateLocalJSONFile = "$env:temp\URLdata.json"

##############################################################################
##              Do not modify anything below this line
##############################################################################


# variables used throughout this script
$X64 = 64
$X86 = 32
$InstallerName              = "HuntressInstaller.exe"
$InstallerPath              = Join-Path $Env:TMP $InstallerName
$HuntressKeyPath            = "HKLM:\SOFTWARE\Huntress Labs\Huntress"
$HuntressRegKey             = "HKLM:\SOFTWARE\Huntress Labs"
$SupportMessage             = "Send the error message to support@huntress.com"
$HuntressAgentServiceName   = "HuntressAgent"
$HuntressUpdaterServiceName = "HuntressUpdater"
$HuntressEDRServiceName     = "HuntressRio"
$Vendor                     = "Huntress"
$ScriptInfoName             = "HuntressPoShInstaller.json"

# Setup custom object for network testing
$localJSONLocation = Join-Path $(Split-Path -Parent -Path $MyInvocation.MyCommand.Definition) "URLdata.json"
if ($null -ne $alternateLocalJSONFile) {
    $localJSONLocation = $alternateLocalJSONFile
}
$testURLs      = @()
$certData      = @()
$netDataObject = New-Object -TypeName PSObject -Property @{
    altJSON    = "$env:temp\URLdata.json"
    localJSON  = $localJSONLocation
    countFails = 0
    testURLs   = $testURLs
    certData   = $certData
}

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

# Check for Legacy OS, any kernel below 6.2 cannot run Huntress EDR (so we skip that check)
$services = @($HuntressAgentServiceName, $HuntressUpdaterServiceName, $HuntressEDRServiceName)
if ( ($KernelVersion.major -eq 6 -and $KernelVersion.minor -lt 2) -or ($KernelVersion.major -lt 6) ) {
    $services = @($HuntressAgentServiceName, $HuntressUpdaterServiceName)
}

# Checking to see if Huntress was installed before this script was run
$isHuntressInstalled = $false
if ((test-path "c:\program files\Huntress\HuntressAgent.exe") -OR (test-path "c:\program files (x86)\Huntress\HuntressAgent.exe")){
    $isHuntressInstalled = $true
}

############################################### end initialization #####################################################



# Select a secure TLS protocol for the current PowerShell process. This must occur before any communication.
function setNetworking {
    # Keep "First Run Customize" popup window from blocking the testing (by disabling it)
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main" -Name "DisableFirstRunCustomize" -Value 2

    try {
        $ProtocolsSupported = [System.Enum]::GetValues([System.Net.SecurityProtocolType])
        # Only TLS 1.3 or 1.2 are supported for secure communication with the Huntress portal
        if ( ($ProtocolsSupported -contains 'Tls13') -and ($ProtocolsSupported -contains 'Tls12') ) {
            [System.Net.ServicePointManager]::SecurityProtocol = (
                [System.Enum]::ToObject([System.Net.SecurityProtocolType], 12288) -bOR [System.Enum]::ToObject([System.Net.SecurityProtocolType], 3072)
            )
        } else {
            # In certain .NET 4.0 patch levels, SecurityProtocolType does not have a TLS 1.2 entry.
            # Rather than check for 'Tls12', we force-set TLS 1.2 and catch the error if it's truly unsupported.
            # Note that these legacy systems will also need some manual configuration work before using protocol 3072 (TLS 1.2)
            # See: https://support.microsoft.com/en-us/topic/support-for-tls-system-default-versions-included-in-the-net-framework-2-0-sp2-on-windows-vista-sp2-and-server-2008-sp2-1001add1-103f-0a22-e807-00ee2fc7c75d
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Enum]::ToObject([System.Net.SecurityProtocolType], 3072)
        }
    } catch {
        $msg = $_.Exception.Message
        logger "Failed to enable TLS 1.2, Huntress requires TLS 1.2 or higher for security reasons."
        logger "$msg"
        throw $msg
    }
}

# Helper function to print lengthy error/instructional message
function certFail {
    param ( [Parameter(Mandatory = $true)]
            [string]$cleanURL )
    logger "------------------------------------------------------------------------------------------------------------------------------"
    logger "The Subject/Issuer text above usually identifies if this is a DPI/cert interception issue, or a cert chain issue."
    logger "* If the returned SUBJECT does not contain 'Huntress' or 'Microsoft' in the text this is likely a DPI/cert interception issue."
    logger "      You'll need to add an exclusion for the certificate for this URL in your DPI/cert interception service: $cleanURL"
    logger "* If the returned ISSUER does not contain 'DigiCert', 'Google', or 'Microsoft', this is likely a  DPI/cert interception issue."
    logger "      You'll need to add an exclusion for the certificate for this URL in your DPI/cert interception service: $cleanURL"
    logger "* Otherwise this is likely a missing certificate chain. Check for pending OS updates, reboot, and try again."
    logger "------------------------------------------------------------------------------------------------------------------------------"
    
}

# If the local JSON file exists and was modified less than 14 days ago, skip downloading from github
function getLocalJSON {
    param ( [PSObject]$netDataObject )

    # try to use local JSON first
    if (Test-Path -Path $netDataObject.localJSON) {
        $lastWrite = (Get-Item $netDataObject.localJSON).LastWriteTime
        if ($lastWrite -gt ((Get-Date).AddDays(-14))) {
            logger "Using local URLdata.json from $lastWrite for network testing.`n"
            getJSON $netDataObject
        } else {
            logger "$($netDataObject.localJSON) is stale, downloading new version from github for network testing"
            getJSON $netDataObject -downloadFromGithub
        }
    # try to use alternate JSON location next
    } elseif (Test-Path -Path $netDataObject.altJSON) {
        $netDataObject.localJSON = $netDataObject.altJSON
        $lastWrite = (Get-Item $netDataObject.localJSON).LastWriteTime
        if ($lastWrite -gt ((Get-Date).AddDays(-14))) {
            logger "Using alternate local URLdata.json ($($netDataObject.altJSON)) from $lastWrite `n"
            getJSON $netDataObject
        } else {
            logger "$($netDataObject.localJSON) (alternate location) is stale, downloading new version from github"
            getJSON $netDataObject -downloadFromGithub
        }
    # Otherwise download github to localJSON if writable, alternate otherwise
    } else {
        try {
            New-Item -Path $netDataObject.localJSON -ItemType File
            Remove-Item $netDataObject.localJSON -Force
            logger "$($netDataObject.localJSON) not found, attempting to retrieve from github."
        } catch {
            logger "$($netDataObject.localJSON) is not writeable, attempting to use alternate"
            $netDataObject.localJSON = $netDataObject.altJSON
        }
        getJSON $netDataObject -downloadFromGithub
    }
}

# Pass [bool]true to download a fresh copy of the JSON data, or [bool]false to use a local copy
# Function populates $data array with the resulting file contents
function getJSON {
    param ( [PSObject]$netDataObject,
            [switch]$downloadFromGithub )

    # Attempt to download the JSON from github if prompted by $downloadFromGithub
    if ($downloadFromGithub) {
        try { 
            $URL = 'https://raw.githubusercontent.com/huntresslabs/support/refs/heads/main/URLdata.json'
            Invoke-WebRequest -Uri $URL -OutFile $netDataObject.localJSON -UseBasicParsing -ErrorAction Stop
        } catch {
            logger "Fallback using WebClient (still uses TLS 1.2)"
            $wc = New-Object System.Net.WebClient
            $wc.Headers['User-Agent'] = 'HuntressSupportScript'
            try {
                (New-Object System.Net.WebClient).DownloadFile($URL, $netDataObject.localJSON)
            } catch {
                if (Test-Path -Path $netDataObject.localJSON) {
                    logger "[Warning: Unable to connect to github, using a stale version of the JSON. Test may be inaccurate without fresh data!]"
                } else {
                    logger "[ERROR: Unable to connect to github, unable to find local copy of JSON file!]"
                    logger "Save the file $URL in the same directory as this script to run without needing to open a port to github"
                    throw "Unable to connect to github"
                }
            }
        }
    }

    # Read text lines from file and convert them into a JSON array. Not using ConvertFrom-Json as PowerShell 2.0 doesn't support it.
    [array]$data = @(Get-Content -Path $netDataObject.localJSON -Raw | ConvertFrom-Json)
    #  Note if you really need PoSh 2.0 compatibility you can comment the line above, and uncomment the 4 lines below
    #  You will need TLS 1.2 setup, .NET 3.5, and may need some registry patches to accomplish those. More info here:
    #  https://stackoverflow.com/questions/28077854/powershell-2-0-convertfrom-json-and-convertto-json-implementation
    #  https://knowledge.digicert.com/quovadis/ssl-certificates/ssl-general-topics/how-to-enable-tls-1-2-on-windows-server-2008-r2
    #Add-Type -AssemblyName System.Web.Extensions
    #$jsonString = Get-Content -Path $localJSON -Raw
    #$serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    #[array]$data = $serializer.DeserializeObject($jsonString)

    # process the data from the $data array
    $netDataObject.testURLs = @($data.array1)
    $certURL                = @($data.array2)
    $certArrayTemp          = @($data.array4)
    $expIssuerName          = @($data.array5)

    # array4 contains two different sets of info, even indices are subject, odd indices are issuer
    # The rest of the arrays are single sets of data, enjoy.
    for ($i = 0; $i -lt $certArrayTemp.Count-1; $i = $i + 2) {
        $tempCert = $(($certURL[$i/2] -replace '^https://', '') -replace '/.*', '')

        $netDataObject.certData += New-Object -TypeName PSObject -Property @{
            certURL       = $tempCert
            expIssuerName = $expIssuerName[$($i/2)]
            expSubject    = $certArrayTemp[$i]
            expIssuer     = $certArrayTemp[$i+1]
        }
    }

    # The data on github is purposely over-verbose for future use, so we strip extra characters.
    $netDataObject.testURLs = $netDataObject.testURLs | ForEach-Object { ($_ = ($_ -replace '^https://', '') -replace '/.*', '')}
}

# tests that the expected certificates are not intercepted. If the expected cert is not returned the agent will not function.
function certTest {
    param ( [PSObject]$netDataObject )

    logger "-- Testing Certificate Validation --"
    $certFailCounter = 0
    $failURLs    = @()
    # for each URL, establish secure TCP connection and grab the certificate and subject lines to compare with known-good values.
    foreach ($singleCert in $($netDataObject.certData)) {
        $cleanURL = $singleCert.certURL
        $uri = ([uri]($cleanURL))
        $tcp = $null
        $ssl = $null
        try {
            $tcp = New-Object Net.Sockets.TcpClient
            $tcp.Connect("$uri", 443)
            $ssl = New-Object Net.Security.SslStream($tcp.GetStream(),$false,{$true})
            $ssl.AuthenticateAsClient($uri)
            $cert       = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
            $recSubject = $cert.Subject
            $recIssuer  = $cert.Issuer
            # retrieve a hashed/encrypted version of the certificate to log in case troubleshooting is required
            # Note: the 5 lines below must remain at their current indentation!
            $PEM = @"
-----BEGIN CERTIFICATE-----
$([System.Convert]::ToBase64String($cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert), [System.Base64FormattingOptions]::InsertLineBreaks))
-----END CERTIFICATE-----
"@

            # Check for Subject match. No need for wildcards as these should all be static Huntress certs.
            if ($recSubject -eq $($singleCert.expSubject)) {
                logger "[Certificate subject validation successful for $cleanURL]"
            } else {
                logger "[FAILED: Subject validation. Certificate does not match for [$cleanURL] !]"
                logger "Subject that was returned: [$recSubject]"
                logger "Subject that was expected: [$($singleCert.expSubject)]"
                $certFailCounter++
                $netDataObject.countFails++
                $failURLs += $cleanURL
            }

            # Issuer can vary based on the specific server the script reaches. To compensate, we check for exact match then a wildcard match.
            if ($recIssuer -eq $($singleCert.expIssuer)) {
                logger "[Certificate issuer validation successful for $cleanURL]"
            } else {
                # Wildcard match compensates for big infrastructure where the leaf cert's might vary slightly
                if ($recIssuer -like "*$($singleCert.expIssuerName)*") {
                    logger "Please note this was not an exact match, which is expected with big infrastructure."
                    logger "Issuer that was returned: [$recIssuer]"
                    logger "Issuer that was expected: [$($singleCert.expIssuer)]"
                } else { 
                    logger "[FAILED: Issuer validation. Certificate does not match for [$cleanURL] !]"
                    logger "Issuer that was returned: [$recIssuer]"
                    logger "Issuer that was expected: [$($singleCert.expIssuer)]"
                    logger "PEM that was received: $PEM"
                    $certFailCounter++
                    $netDataObject.countFails++
                    $failURLs += $cleanURL
                }
            }
        } catch {
            logger "Error: $($_.Exception.Message)"
            logger "[Error during certificate validation for '$cleanURL'!]"
            $certFailCounter++
            $netDataObject.countFails++
            $failURLs += $cleanURL
        } finally {
            if ($null -ne $ssl) {
                $ssl.Dispose()
            }
            $tcp.Close()
        }
    }
    # If we see any fails, print more info about those failures.
    if ($certFailCounter -gt 0) {
        foreach ($failURL in $failURLs) {
            certFail $failURL
        }
    }
    logger ""
}

# test outgoing port 443 connectivity to Huntress URLs
function tcpTest {
    param ( [PSObject]$netDataObject )

    logger "-- Verifying Huntress services can be reached --"
    foreach ($testURL in $netDataObject.testURLs) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.connect($testURL, 443)
            logger "[Connection to $testURL successful]"
        } catch {
            logger "WARNING, connectivity to Huntress URL's is being interrupted. You MUST open port 443 for $testURL in order for the Huntress agent to function."
            logger "Error: $($_.Exception.Message)"
            $netDataObject.countFails++
        } finally {
            $tcp.Close()
        }
    }
    logger ""
}

# time stamps for logging purposes
function Get-TimeStamp {
    return "[{0:yyyy/MM/dd} {0:HH:mm:ss}]" -f (Get-Date)
}

# adds time stamp to a message and then writes that to the log file
function logger ($msg) {
    Add-Content $DebugLog "$(Get-TimeStamp) $msg"
    Write-Output "$(Get-TimeStamp) $msg"
}

# test that all required parameters were passed, and that they are in the correct format
function Test-Parameters {
    logger "Verifying received parameters..."

    # If reregister and reinstall were both flagged, just reregister as it is the more robust option
    if ($reregister -and $reinstall) {
        logger "Specified -reregister and -reinstall, defaulting to reregister."
        $reinstall = $false
    }

    # Ensure we have an account key (hard coded or passed params) and that it's in the correct form
    if ($AccountKey -eq "__ACCOUNT_KEY__") {
        copyLogAndExit -throwError "AccountKey not set! Suggest using the -acctkey flag followed by your account key (you can find it in the Downloads section of your Huntress portal)."
    } elseif ($AccountKey.length -ne 32) {
        copyLogAndExit -throwError "Invalid AccountKey specified (incorrect length)! Suggest double checking the key was copy/pasted in its entirety. Length = $($AccountKey.length)   expected value = 32"
    } elseif (($AccountKey -match '[^a-zA-Z0-9]')) {
        copyLogAndExit -throwError "Invalid AccountKey specified (invalid characters found)! Suggest double checking the key was copy/pasted fully"
    }

    # Ensure we have an organization key (hard coded or passed params).
    if ($OrganizationKey -eq "__ORGANIZATION_KEY__") {
        copyLogAndExit -throwError "OrganizationKey not specified! This is a user defined identifier set by you (usually your customer's organization name)"
    } elseif ($OrganizationKey.length -lt 1) {
        copyLogAndExit -throwError "Invalid OrganizationKey specified (length should be > 0)!"
    }
    logger "Parameters verified."
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
        logger "No processes with the name '$ProcessName' are currently running."
    }
    else {
        foreach ($process in $processes) {
            try {
                $processID = $process.Id
                Stop-Process -Id $processID -Force
                logger "Killed process '$ProcessName' (ID $processID) successfully."
            }
            catch {
                logger "Failed to kill process '$ProcessName' (ID $processID): $($_.Exception.Message)"
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

# Stop the Agent and Updater services
function StopHuntressServices {
    logger "Stopping Huntress services..."
    if (Confirm-ServiceExists($HuntressAgentServiceName)) {
        try {
            Stop-Service -Name "$HuntressAgentServiceName" -ErrorAction SilentlyContinue
        } catch {
             logger "Unable to stop HuntressAgent, possible Tamper Protection interference."
        }
    } else {
        logger "$($HuntressAgentServiceName) not found, nothing to stop"
    }
    if (Confirm-ServiceExists($HuntressUpdaterServiceName)) {
        try {
            Stop-Service -Name "$HuntressUpdaterServiceName" -ErrorAction SilentlyContinue
        } catch {
            logger "Unable to stop HuntressUpdater, possible Tamper Protection interference."
        }
    } else {
        logger "$($HuntressUpdaterServiceName) not found, nothing to stop"
    }
}

# Ensure the installer was not modified during download by validating the file signature.
function verifyInstaller ($file) {
    $varChain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain
    try {
        $varChain.Build((Get-AuthenticodeSignature -FilePath "$file").SignerCertificate) | out-null
    } catch [System.Management.Automation.MethodInvocationException] {
        copyLogAndExit -throwError "ERROR: '$file' did not contain a valid digital certificate, something may have corrupted the file. Try again and contact Support if the 2nd attempt fails"
    }
}

# Prevent conflicting file from preventing creation of installation directory.
function prepareAgentPath {
    $path = getAgentPath
    if (Test-Path $path -PathType Leaf) {
        $backup = "$path.bak"
        $err = "WARNING: '$path' already exists and is not a directory, renaming to '$backup'."
        logger $err
        Rename-Item -Path $path -NewName $backup -Force
    }
}

# download the Huntress installer
function Get-Installer {
    $msg = "Downloading installer to '$InstallerPath'..."
    logger $msg

    # Ensure a secure TLS version is used.
    $ProtocolsSupported = [enum]::GetValues('Net.SecurityProtocolType')
    if ( ($ProtocolsSupported -contains 'Tls13') -and ($ProtocolsSupported -contains 'Tls12') ) {
        # Use only TLS 1.3 or 1.2
        logger "Using TLS 1.3 or 1.2..."
        [Net.ServicePointManager]::SecurityProtocol = (
            [Enum]::ToObject([Net.SecurityProtocolType], 12288) -bOR [Enum]::ToObject([Net.SecurityProtocolType], 3072)
        )
    } else {
        logger "Using TLS 1.2..."
        try {
            # In certain .NET 4.0 patch levels, SecurityProtocolType does not have a TLS 1.2 entry.
            # Rather than check for 'Tls12', we force-set TLS 1.2 and catch the error if it's truly unsupported.
            [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
        } catch {
            copyLogAndExit -throwError "ERROR: Unable to use a secure version of TLS. Verify Hotfix KB3140245 is installed. Error: ($_.Exception.Message)"
        }
    }

    # Delete stale installer before downloading the most recent installer
    if (Test-Path $InstallerPath -PathType Leaf) {
        $err = "WARNING: '$InstallerPath' already exists, deleting stale Huntress Installer."
        logger $err
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
            logger $err
            Start-Sleep -Seconds $delay
        }
    }

    # Ensure the file downloaded correctly, if not, throw error
    if ( ! (Test-Path $InstallerPath) ) {
        copyLogAndExit -throwError "ERROR: Failed to download the Huntress Installer. Try accessing $($DownloadURL) from the host where the download failed. Contact support@huntress.io if the problem persists."
    }

    $msg = "Installer downloaded to '$InstallerPath'..."
    logger $msg
}

# check if the agent downloaded, is a valid install file, if those match up then run the installer
function Install-Huntress ($OrganizationKey) {
    # check that the installer downloaded and wasn't quarantined
    logger "Checking for installer '$InstallerPath'..."
    if ( ! (Test-Path $InstallerPath) ) {
        $err = ("ERROR: The installer was unexpectedly removed from $InstallerPath `n"+
            "A security product may have quarantined the installer. Check your security product logs." +
            "If the issue continues to occur, send the log to the Huntress " +
            "Team for help at support@huntresslabs.com")
        logger $err
        copyLogAndExit -throwError $err
    }

    # verify the installer's integrity
    verifyInstaller($InstallerPath)

    logger "Executing installer..."
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
        copyLogAndExit -throwError "ERROR: Installer failed to complete in $timeout seconds. Possible interference from a security product?"
    }
}

# Test that the Huntress agent was able to install, register, and start service correctly
function Test-Installation {
    # Get the file locations of some of the Huntress executables and setting up some registry related variables
    $HuntressDirectory        = getAgentPath
    $HuntressAgentPath        = Join-Path $HuntressDirectory "HuntressAgent.exe"
    $HuntressUpdaterPath      = Join-Path $HuntressDirectory "HuntressUpdater.exe"
    $AgentIdKeyValueName      = "AgentId"
    $OrganizationKeyValueName = "OrganizationKey"
    $TagsValueName            = "Tags"

    logger "Verifying installation..."

    # Watch for HuntressAgent.log, checking every 1/4 second until 10 seconds elapsed, if found grab the last 8 lines
    $didAgentRegister = $false
    for ($i = 0; $i -le 40; $i++) {
        if (Test-Path "$($HuntressDirectory)\HuntressAgent.log") {
            $linesFromLog = Get-Content "$($HuntressDirectory)\HuntressAgent.log" | Select-Object -last 8
            break
        }
        Start-Sleep -Milliseconds 250
    }
    # Write the end of HuntressAgent log to this PoSh deploy log, and note if the agent registered successfully
    if ($NULL -ne $linesFromLog) {
        logger "VVV  Excerpt from HuntressAgent.log  VVV"
        foreach ($line in $linesFromLog) {
            logger $line
            if ($line -like "*registered agent*") {
                $didAgentRegister = $true
            }
        }
    } else {
        logger "Warning: HuntressAgent.log not found! This is typically caused by 3rd party interference - AV, EDR, ThreatLocker"
    }
    # If the agent didn't register throw an error, otherwise note how long registration took
    if ( ! $didAgentRegister) {
        $err = "WARNING: It does not appear the agent has successfully registered. Check 3rd party AV exclusion lists to ensure Huntress is excluded."
        logger ($err + $SupportMessage)
    } else {
        logger "Agent successfully registered in $($i/4) seconds"
    }

    # Ensure the critical files were created.
    foreach ( $file in ($HuntressAgentPath, $HuntressUpdaterPath) ) {
        if ( ! (Test-Path $file) ) {
            copyLogAndExit -throwError "ERROR: $file did not exist. Check your AV/security software quarantine"
        }
        logger "'$file' is present."
    }

    # Check for Legacy OS, any kernel below 6.2 cannot run Huntress EDR (so we skip that check)
    if ( ($KernelVersion.major -eq 6 -and $KernelVersion.minor -lt 2) -or ($KernelVersion.major -lt 6) ) {
        logger "WARNING: Legacy OS detected, Huntress EDR will not be installed"
    } else {
        logger "Huntress EDR will be installed automatically in < 24 hours."
    }

    # Ensure the services are installed and running.
    foreach ($svc in $services) {
        # check if the service is installed
        if ( ! (Confirm-ServiceExists($svc))) {
            # if Huntress was installed before this script started and Rio is missing then we log that, but continue with this script
            if ($svc -eq $HuntressEDRServiceName) {
                if ($isHuntressInstalled) {
                    logger "Information: Huntress Process Insights (aka Rio) is installed automatically by the Huntress portal. It can take up to 24 hours to show up"
                    logger "See more about compatibility here: https://support.huntress.io/hc/en-us/articles/4410699983891-Supported-Operating-Systems-System-Requirements-Compatibility"
                } else {
                    logger "New install detected. It may take 24 hours for Huntress EDR (Rio) to install!"
                }
            } else {
                copyLogAndExit -throwError "$($svc) service is missing! + $($SupportMessage)"
            }
        }
        # check if the service is running, attempt to restart if not (only for base agent).
        elseif ( (! (Confirm-ServiceRunning($svc))) -AND ($svc -eq $HuntressAgentServiceName)) {
            Start-Service $svc
            # if still not running, log and give up, else inform of success
            if (! (Confirm-ServiceRunning($svc))) {
                logger "ERROR: The $($svc) service is not running. Attempting to restart"
                Start-Service $svc
                if (! (Confirm-ServiceRunning($svc))) {
                    copyLogAndExit -throwError "ERROR: restart of service $($svc) failed."
                }
            } else {
                logger "'$svc' is running."
            }
        }
    }


    # look for a condition that prevents checking registry keys, if not then check for registry keys
    if ( ($PowerShellArch -eq $X86) -and ($WindowsArchitecture -eq $X64) ) {
        logger "WARNING: Can't verify registry settings due to 32bit PowerShell on 64bit host. Run PowerShell in 64 bit mode"
    } else {
        # Ensure the Huntress registry key is present.
        if ( ! (Test-Path $HuntressKeyPath) ) {
            copyLogAndExit -throwError "ERROR: The registry key '$HuntressKeyPath' did not exist. You may need to reinstall with the -reregister flag"
        }

        # Ensure the Huntress registry values are present.
        $HuntressKeyObject = Get-ItemProperty $HuntressKeyPath
        foreach ( $value in ($AgentIdKeyValueName, $OrganizationKeyValueName, $TagsValueName) ) {
            If ( ! (Get-Member -inputobject $HuntressKeyObject -name $value -Membertype Properties) ) {
                copyLogAndExit -throwError "ERROR: The registry value $value did not exist within $HuntressKeyPath. You may need to reinstall with the -reregister flag"
            }
        }
    }

    # Verify the agent registered (if not blocked by 32/64 bit incompatibilities).
    if ( ($PowerShellArch -eq $X86) -and ($WindowsArchitecture -eq $X64) ) {
        logger "WARNING: Can't verify agent registration due to 32bit PowerShell on 64bit host."
    } else {
        If ($HuntressKeyObject.$AgentIdKeyValueName -eq 0) {
            copyLogAndExit -throwError "ERROR: The agent did not register. Check the log (%ProgramFiles%\Huntress\HuntressAgent.log) for errors. Missing $($HuntressKeyObject.$AgentIdKeyValueName)"
        }
        logger "Agent registered."
    }
    logger "Installation verified!"
}

# prepare to reregister by stopping the Huntress service and deleting all the registry keys
function PrepReregister {
    logger "Preparing to re-register agent..."
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
        logger "Unable to locate log file, thus unable to check if orphaned"
        return $false
    } else {
        logger "New machine, no need to run through orphan checker"
        return $false
    }

    # if the log was found, look through the last 10 lines for the orphaned agent error code
    if ($Path -match 'HuntressAgent.log') {
        $linesFromLog = Get-Content $Path | Select-Object -last 10
        ForEach ($line in $linesFromLog)    {
            if ($line -like "*bad status code: 401*") {
                logger "Agent appears to be orphaned: $($line)"
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
function getDiskFreeSpace {
    $freeSpace = (Get-PSDrive C).Free
    if ($freeSpace -lt 200111222) {
        $err = "WARNING: Low disk space detected, you may have troubles completing this install. Only $($freeSpace) bytes remaining (need about $(200111222))."
        logger $err
    } else {
        logger "Free disk space: $($freeSpace) bytes"
    }
}

# Gather information about active network adapters for troubleshooting purposes
function getNetworkAdapterInfo {
    # Filter out adapters that are unlikely to be useful to log
    $adapters = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' -and $_.Speed -ge 1 -and $_.Description -ne 'Tunnel'}
    logger "Adapter Name                            IPv4               DNS                               Gateway"

    foreach ($adapter in $adapters) {
        $ipProps = $adapter.GetIPProperties()
        $ipv4 = $ipProps.UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } | Select-Object -ExpandProperty Address | ForEach-Object { $_.IPAddressToString }
        # Fetch the IP properties and filter out local and empty IPv4 entries
        if ($null -ne $ipv4 -and $ipv4 -ne "") {
            $adapterName = ([string]$adapter.Name).PadRight(36)
            $ipv4 = ([string]$ipv4).PadRight(15)
            $dns  = (($ipProps.DnsAddresses | ForEach-Object { $_.IPAddressToString }) -join ', ').PadRight(30)
            $gway = (($ipProps.GatewayAddresses | ForEach-Object { $_.Address.IPAddressToString }) -join ', ').PadRight(30)
            logger "$adaptername    $ipv4    $dns    $gway"
        }
    }
    logger ""
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
        logger "$($name) finished"
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
        copyLogAndExit -throwError $err
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
            logger "Agent path found but no uninstallers found. Attempting to manually uninstall"
        }
    } else {
        $err = "Note: unable to find Huntress install folder. Attempting to manually uninstall."
        logger $err
    }

    # if uninstaller was run, loop until Huntress assets are all successfully removed, or exit & report if timer exceeds 15 seconds
    if ($wasUninstallerRun) {
        for ($i = 0; $i -le 15; $i++) {
            if ((Test-Path $exeAgentPath) -OR (Test-Path $HuntressRegKey)){
                Start-Sleep 1
             } else {
                logger "Agent successfully uninstall in $($i) seconds"
                $i = 100
            }
            if ($i -eq 15) {
                $err = "Uninstall not complete after $($i) seconds"
                logger $err
            }
        }
    }

    # look for the Huntress directory, if found then delete
    if (Test-Path $agentPath) {
        Remove-Item -LiteralPath $agentPath -Force -Recurse -ErrorAction SilentlyContinue
        logger "Manual cleanup of Huntress folder: success"
    } else {
        logger "Manual cleanup of Huntress folder: folder not found"
    }

    # look for the registry keys, if exist then delete
    if (Test-Path $HuntressRegKey) {
        Get-Item -path $HuntressRegKey | Remove-Item -recurse
        logger "Manually deleted Huntress registry keys"
    } else {
        logger "No registry keys found, uninstallation complete"
    }

    # if Huntress services still exist, then delete
    $services = @("HuntressRio", "HuntressAgent", "HuntressUpdater", "Huntmon")
    foreach ($service in $services) {
        if (Get-Service -name $service -ErrorAction SilentlyContinue) {
            logger "Service $($service) detected post uninstall, attempting to remove"
            c:\Windows\System32\sc.exe STOP $service
            c:\Windows\System32\sc.exe DELETE $service
        }
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
        logger "Repair was unable to find the HuntressService, this machine will need Huntress uninstalled and reinstalled in order to maintain security"
        $DidRepairFinish = $false
    } else {
        Start-Service HuntressAgent
        logger "Repair started HuntressAgent service"
    }
    if ($null -eq $UpdaterService){
        logger "Repair was unable to find the UpdaterService, this machine will need Huntress uninstalled and reinstalled in order to continue receiving updates."
        $DidRepairFinish = $false
    } else {
        Start-Service HuntressUpdater
        logger "Repair started HuntressUpdater service"
    }

    # For Rio/EDR we don't return false as we don't know if it's a fresh install that hasn't received Rio yet, but still attempt to restart service
    if (($null -eq $RioService) -AND $isHuntressInstalled){
        logger "Repair was unable to find the RioService. If this is a fresh install it may take up to 24 hours for Rio to install. Otherwise contact support to ensure EDR coverage."
    } elseif ($null -eq $RioService) {
        logger "Fresh install detected, it can take up to 24 hours for Rio to install."
    } else {
        Start-Service HuntressRio
        logger "Repair started HuntressRio service"
    }

    return $DidRepairFinish
}

# Log useful data about the machine for troubleshooting AB
function logInfo {
    param ( [PSObject]$netDataObject )

    logger "============================== Pre-flight checks and logging =============================="
    logger "Script type: '$ScriptType'"
    logger "Script version: '$ScriptVersion'"
    logger "Script flags:  Reregister=$reregister  Reinstall=$reinstall  Uninstall=$uninstall "
    if ($AccountKey.length -lt 8) {
        logger "Invalid key length, found $($AccountKey.length) (should be 32). Account key value: $AccountKey"
    } else {
        $masked = $AccountKey.Substring(0,4) + "************************" + $AccountKey.SubString($AccountKey.length-4,4)
        logger "Pre-trim variables: account key=[$masked]  org key=[$OrganizationKey]   (brackets are in place to show trailing/leading spaces)"
    }

    # if Huntress was already installed, pull version info and TP status. This is intentionally a vague check, not intended to definitively show install status!
    logger "Script cursory check, is Huntress installed already: $($isHuntressInstalled)"
    if ($isHuntressInstalled){
        logger "Agent version $(getAgentVersion) found"
    }

    if (Confirm-ServiceRunning $HuntressEDRServiceName){
        $checkTP = (Confirm-ServiceRunning $HuntressAgentServiceName)
        if ( $null -eq $checkTP ) {
            logger "Warning: Tamper Protection may be enabled; you may need to disable TP or run this as SYSTEM to repair, upgrade, or reinstall this agent."
        } else {
            logger "Pass: Tamper Protection not detected, or this script is running as SYSTEM"
        }
    }

    logger "Administrator access: $(testAdministrator)"
    $userContext = whoami
    if ($userContext -eq "nt authority\system") {
        logger "Pass: Run under the SYSTEM user."
    } else {
        logger "Warning: Not run under the SYSTEM user, you may have issues with Huntress Tamper Protection"
    }

    logger "Installing to location: '$InstallerPath'"
    logger "Installer log location: '$DebugLog'"

    logger ""
    logger "============================== Logging machine details =============================="
    # Log OS details
    $patterns = "Host Name", "OS Name", "OS Version", "OS Configuration", "Original Install Date", "System Boot Time", "System Type", "Processor(s)", "Time Zone", "Total Physical Memory", "Available Physical Memory", "Domain", "Logon Server", "Network Card(s)", "Hyper-V Requirements"
    $systemInfo = systeminfo | Out-String
    $systemInfo = (($systemInfo -split "`r`n") | Select-String -Pattern $patterns | Select-Object -ExpandProperty Line)
    logger $($systemInfo -join "`r`n")
    getDiskFreeSpace

    # Logging some additional info for a temporary issue with Windows 8.1 and missing Visual C++ dependencies
    libraryCheck

    # Log status of AD joined and the (in)ability to contact a DC
    $ErrorActionPreference = 'SilentlyContinue'    
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $domainJoined = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
        } else {
            $domainJoined = (Get-WmiObject Win32_ComputerSystem).PartOfDomain
        }
    } catch {
        logger "Attention: Unable to determine if domain joined (non-stoppage error)"
        $domainJoined = $false
    }
    if ( $domainJoined ) {
        try {
            $secureChannelStatus = Test-ComputerSecureChannel
        } catch {
            logger "Warning, unable to Test-ComputerSecureChannel. If this isn't a DC, then the trust relationship with the DC may be broken"
            $secureChannelStatus = $false
        }
        if ( ! $secureChannelStatus) {
            logger "Warning, AD joined machine without DC connectivity. Some services may be impacted such as Managed AV and in some rare cases Host Isolation."
        } else {
            logger "AD joined and DC connectivity verified!"
        }
    } else {
        logger "Not AD joined, skipping Test-ComputerSecureChannel"
    }

    # Log architecture and PowerShell details
    logger "Detected Architecture (Windows 32/64 bit): '$($WindowsArchitecture)'"
    logger "PowerShell Architecture (PoSh 32/64 bit): '$PowerShellArch'"
    logger "PowerShell version: $($PoShVersion).$($PSversionTable.PsVersion.Minor)"
    logger "Powershell legacy detected: $($LegacyCommandsRequired)"
    if ($LegacyCommandsRequired) {
        logger "Warning! Older version of PowerShell detected"
    }

    # Log machine uptime, use -1 to call attention to machines that have issues running the GCIM command
    $uptime = ([Timespan]::FromMilliseconds([Environment]::TickCount)).Days


    if ($uptime -gt 9) {
        logger "Warning, high uptime detected. This machine may need a reboot in order to resolve Windows update-based file locks. $($uptime)`n"
    } else {
        logger "Days of uptime: $($uptime)`n"
    }

    logger "============================== Logging machine networking details =============================="
    # Logging TCP/IP configuration 
    getNetworkAdapterInfo
    
    # Checking connectivity to Huntress servers 
    getLocalJSON $netDataObject
    tcpTest $netDataObject
    certTest $netDataObject
    if ($netDataObject.countFails -gt 0) {
        $errorText = "[FAILED to connect to all Huntress services, aborting deploy! Read the errors above for more info.]"
        copyLogAndExit $errorText
    }
}

# This function copies the Huntress DebugLog to a more permanent location as it's incredibly helpful for troubleshooting. AB
# Exits with a code 0 if $throwError wasn't passed, otherwise throws the error contained in the $throwError string
function copyLogAndExit {
    param (
        [string]$throwError
    )
    if ( [string]::IsNullOrEmpty($throwError) ) { $throwError="0" }

    # log the error message first
    if ($throwError -ne "0") {
        logger "WARNING: Script errors detected, operation may not have completed! $throwError `n$SupportMessage"
    }

    # sleep to ensure file operations have completed
    Start-Sleep 1
    $agentPath = getAgentPath
    $logLocation = Join-Path $agentPath "HuntressPoShInstaller.log"

    # If this is an unistall, we'll leave the log in the C:\temp dir, otherwise copy the log to the huntress directory
    if (!$uninstall){
        if (!(Test-Path -path $agentPath)) {New-Item $agentPath -Type Directory}
        try {
           Copy-Item -Path $DebugLog -Destination $logLocation -Force -ErrorAction SilentlyContinue
           Write-Output "'$($DebugLog)' copied to '$logLocation'."
       } catch {
           Write-Output "Unable to copy Installer log. Using \Windows\temp\ for HuntressPoShInstaller.log instead."
       }
    }

    # if no error was passed, exit gracefully, otherwise throw an error and exit
    if ($throwError -eq "0") {
         Write-Output "Script complete!"
         exit 0
    } else {
        Write-Output "WARNING: Script errors detected, operation may not have completed! Error: [$throwError]"
        throw $throwError
    }
}

# Sometimes previous installs can be stuck with services in the Disabled state, this function attempts to set the state to Automatic.
# Services in the Disabled state cannot be manually started, and TP will stop partners from fixing this themselves. AB
function fixServices {
    $servicesOnInstall = @($HuntressAgentServiceName, $HuntressUpdaterServiceName)
    # Ensure the services are installed before repairing the state
    foreach ($svc in $servicesOnInstall) {
        if (  (Confirm-ServiceExists($svc))) {
            # repairing service state
            if ( $(Get-Service $svc).StartType -ne "automatic") {
                logger "Disabled service $svc detected, attempting to set startup type to automatic."
                c:\Windows\System32\sc.exe config $svc start=auto
            }
        }
    }
}

function Get-ScriptInfoPath {
    $results = getAgentPath
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
        return "", "Unable to retrieve script hash: $ErrorMessage"
    }
}

# Get the operation we running for this script
function Get-ScriptOperation {
    $operation = "Install"
    if ($reregister -eq $true) {
        $operation = "Reregister"
    } elseif ($reinstall -eq $true) {
        $operation = "Reinstall"
    }

    return $operation
}

function Write-InstallScriptInfo {
    $hold = $ErrorActionPreference
    $ErrorActionPreference = "Stop"

    try {
        if ($uninstall) {
            # No need to track installation on an uninstall
            logger "No script information will be saved for uninstall"
            return
        }

        [array]$hashResult = Get-Sha256Hash
        if ($hashResult.Count -eq 2) {
            logger $hashResult[1]
        }
        # Write the values to a json file in the Huntress install directory (not using built in JSON methods to ensure maximum PoSh version compatibility)
        $json="{`"vendor`":`"$Vendor`",`"sha256`":`"$($hashResult[0])`",`"operation`":`"$(Get-ScriptOperation)`"}"
        Set-Content -Path $(Get-ScriptInfoPath) -Value $json
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        logger "Unable to save installation script information: $ErrorMessage"
    }

    $ErrorActionPreference = $hold
}

# Logging Visual C++ info for a Windows 8.1 specific issue
function libraryCheck {
    # Since this issue only affects Win 8.1, check the OS version before logging.
    if ( (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName -notlike "*Windows 8.1*" ) {
        logger "Windows 8.1 not detected, not checking for missing dependencies"
        return
    }

    # Fleet Health Check: UCRT + VC Redistributables
    $Results = [PSCustomObject]@{
        ComputerName  = $env:COMPUTERNAME
        KB2919355     = "Missing, install KB2919355 https://www.microsoft.com/en-us/download/details.aspx?id=42327"
        KB2999226     = "Missing, install KB2999226 https://www.microsoft.com/en-ie/download/details.aspx?id=51109"
        UCRT_Version  = "None, install Universal CRT https://support.microsoft.com/en-us/topic/update-for-universal-c-runtime-in-windows-c0514201-7fe6-95a3-b0a5-287930f3560c"
        VCRedist_x64  = "Not Found, install x64 Visual C++ Redistributable v14 https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170#visual-c-redistributable-v14"
        VCRedist_x86  = "Not Found, install x86 Visual C++ Redistributable v14 https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170#visual-c-redistributable-v14"
    }

    # 1. Check for KBs
    $Hotfixes = Get-HotFix | Select-Object -ExpandProperty HotFixID
    if ($Hotfixes -contains "KB2919355") { $Results.KB2919355 = "Installed`n" }
    if ($Hotfixes -contains "KB2999226") { $Results.KB2999226 = "Installed`n" }

    # 2. Check for UCRT DLL Version
    if (Test-Path "$env:windir\System32\ucrtbase.dll") {
        $Results.UCRT_Version = "$((Get-Item "$env:windir\System32\ucrtbase.dll").VersionInfo.ProductVersion)  (version 10.0.14393+ is recommended)"
    }

    # 3. Check for VC Redist 2015-2022 via Registry (Fastest for Fleet)
    $UninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    Get-ItemProperty $UninstallKeys | Where-Object { $_.psobject.Properties["DisplayName"] } | Where-Object { $_.DisplayName -like "*Visual C++*" } | ForEach-Object {
        if ($_.DisplayName -like "*x64*") { $Results.VCRedist_x64 = "$($_.DisplayVersion)  (version 14+ is recommended)" }
        if ($_.DisplayName -like "*x86*") { $Results.VCRedist_x86 = "$($_.DisplayVersion)  (version 14+ is recommended)" }
    }

    # Save each of the name and property values on a new line in the installer log
    foreach ($property in $Results.PSObject.Properties) {
		if ($null -ne $property) { logger "$($property.Name) - $($property.Value)" }
    }
}


#########################################################################################
#                                  begin main function                                  #
#########################################################################################
function main () {
    # Set TLS protocol and IE first run
    setNetworking

    # Start the script with logging to capture useful data for troubleshooting. All your logging are belong to us, Zero Wang.
    logInfo $netDataObject

    # if run with the uninstall flag, exit afterward so we don't reinstall the agent after
    if ($uninstall) {
        logger "Uninstalling Huntress agent"
        uninstallHuntress
        copyLogAndExit
    }

    logger ""
    logger "============================== Starting Install =============================="
    # if the agent is orphaned, switch to the full uninstall/reinstall (reregister flag)
    if ( !($reregister)) {
        $orphanStatus = isOrphan
        if ( $orphanStatus -eq $true ) {
            $err = 'Huntress Agent is orphaned, unable to use the provided flag. Switching to uninstall/reinstall (reregister flag)'
            logger "$err"
            $reregister = $true
        }
    }

    # if run with no flags and no account key print usage and exit
    if (!$reregister -and !$uninstall -and !$reinstall -and ($AccountKey -eq "__ACCOUNT_KEY__")) {
        logger "No flags or account key found! Exiting."
        logger "Usage (remove brackets [] and substitute <variable> for your value):"
        logger "powershell -executionpolicy bypass -f ./InstallHuntress.powershellv2.ps1 [-acctkey <account_key>] [-orgkey <organization_key>] [-tags <tags>] [-reregister] [-reinstall] [-uninstall] `n"
        logger "Example:"
        logger 'powershell -executionpolicy bypass -f ./InstallHuntress.powershellv2.ps1 -acctkey "0b8a694b2eb7b642069" -orgkey "Buzzword Company Name" -tags "production,US West" '
        copyLogAndExit -throwError "No flags or account key found! Exiting."
    }

    # trim keys for blanks before use
    $AccountKey = $AccountKey.Trim()
    $OrganizationKey = $OrganizationKey.Trim()

    # check that all the parameters that were passed are valid
    Test-Parameters

    # Hide most of the account key in the logs, keeping the front and tail end for troubleshooting
    if ($AccountKey -ne "__Account_Key__") {
        $masked = $AccountKey.Substring(0,4) + "************************" + $AccountKey.SubString($AccountKey.length-4,4)
        logger "AccountKey: '$masked'"
        logger "OrganizationKey: '$OrganizationKey'"
        logger "Tags: $($Tags)"
    }

    # reregister > reinstall > uninstall > install (in decreasing order of impact)
    # reregister = reinstall + delete registry keys
    # reinstall  = stop Huntress service + reinstall
    if ($reregister) {
        logger "Re-register agent: '$reregister'"
        if ( !(Confirm-ServiceExists($HuntressAgentServiceName))) {
            logger "Run with the -reregister flag but the service wasn't found. Attempting to install...."
        }
        PrepReregister
    } elseif ($reinstall) {
        logger "Re-install agent: '$reinstall'"
        if ( !(Confirm-ServiceExists($HuntressAgentServiceName)) ) {
            $err = "Script was run w/ reinstall flag but there's nothing to reinstall. Attempting to clean remnants, then install the agent fresh."
            logger "$err"
            uninstallHuntress
        }
        StopHuntressServices
    } else {
        logger "Checking for HuntressAgent install..."
        $agentPath = getAgentPath
        if ( (Test-Path $agentPath) -eq $true) {
            $assetCount = (Get-ChildItem -Path $agentPath -File | Measure-Object).count
            # to avoid issues with a single file blocking installs, only exit script if multiple files are found and script not run with -reregister or -reinstall
            if ($assetCount -gt 1) {
              copyLogAndExit -throwError "The Huntress Agent is already installed in $agentPath. Exiting with no changes. Suggest using -reregister or -reinstall flags. Asset count = $assetCount"
            }
        }
    }

    Get-Installer
    Install-Huntress $OrganizationKey
    fixServices
    Test-Installation
    logger "Huntress Agent successfully installed!"
}

try {
    main
    Write-InstallScriptInfo
} catch {
    copyLogAndExit -throwError $_.Exception.Message
}

logger "Script Complete"
copyLogAndExit
