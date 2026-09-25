#!/usr/bin/env zsh

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
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL HUNTRESS LABS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
# OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


# The Huntress installer needs an Account Key and an Organization Key (a user
# specified name or description) which is used to affiliate an Agent with a
# specific Organization within the Huntress Partner's Account. These keys can be
# hard coded below or passed in when the script is run.

# For more details, see our KB article
# https://support.huntress.io/hc/en-us/articles/25013857741331-Critical-Steps-for-Complete-macOS-EDR-Deployment


##############################################################################
## Begin user modified variables
##############################################################################

# Replace __ACCOUNT_KEY__ with your account secret key (from your Huntress portal's "download agent" section)
defaultAccountKey="__ACCOUNT_KEY__"

# If you have a preferred "placeholder" organization name for Mac agents, you can set that below.
# Otherwise, provide the appropriate Organization Key when running the script in your RMM.
defaultOrgKey="Mac Agents"

# Put the name of your RMM below. This helps our support team understand which RMM tools
# are being used to deploy the Huntress macOS Agent. Simply replace the text in quotes below.
rmm="macOS Bash script (Unspecified RMM)"

# Option to install the system extension after the Huntress Agent is installed. In order for this to happen
# without security prompts on the endpoint, permissions need to be applied to the endpoint by an MDM before this script
# is run. See the following KB article for instructions:
# https://support.huntress.io/hc/en-us/articles/21286543756947-Instructions-for-the-MDM-Configuration-for-macOS
install_system_extension=false

# If you want to change the network testers JSON file location, uncomment and change one localJSONtemp variable below to your desired directory. 
# The location must be writable for the user who is running the script! Do not remove any leading or trailing forward slashes "/"
#     Examples and Suggested locations:
# localJSONOverride="/var/root/"
# localJSONOverride="/root/"

##############################################################################
## Do not modify anything below this line
##############################################################################

scriptVersion="September 25, 2026"

version="1.3 - $scriptVersion"
dd=$(date "+%Y-%m-%d  %H:%M:%S")
log_file="/tmp/HuntressInstaller.log"
log_file_location="/Users/Shared/"
install_script="/tmp/HuntressMacInstall.sh"
invalid_key="Invalid account secret key"
pattern="[a-f0-9]{32}"

# Setup some variables for network testing
gitURL='https://raw.githubusercontent.com/huntresslabs/support/refs/heads/main/URLdata.json'
scriptDIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
localJSON="$scriptDIR/URLdata.json"  # from the same working directory as the script
altJSON="/tmp/URLdata.json"          # alternate location if current working directory is inaccessible or is missing the JSON file
countFails=0                         # total number of network tests that failed (including cert fails)
certFailCounter=0                    # total number of certificate tests that failed
gracePeriodForJSON=14                # number of days old the local JSON can be before it's ignored
declare -a testURLs=()               # the URLs to test TCP connectivity
declare -a certURLs=()               # the URLs to test certificate interception
declare -a expIssuer=()              # the expected issuer (owner of the server certificate)
declare -a expSubject=()             # the expected subject (leaf certificate)
declare -a expIssuerName=()          # used for wildcard matching

# Using logger function to provide helpful logs within RMM tools in addition to log file
logger() {
    echo "$dd -- $*";
    echo "$dd -- $*" >> $log_file;
}

# Copies the log from a temp location to /users/shared/  and exits with the given code 
# Using this folder as /tmp/ is wiped on reboot, Huntress folders are protected by TP, and because any user should have access to this folder
copyLog() {
    # capture exit command for script finish-up
    local exitCode="$?"
    # if the network tester created a temp directory, remove it when done
    if [ "$tempDIRCreated" = "true" ]; then
        rm -rf "$localJSONOverrideDIR"
        logger "Cleaning up $localJSONOverrideDIR..."
    fi
    # check if directory exists before writing
    if [ -d "$log_file_location" ]; then
        logger "Copying log file to /Users/Shared/"
        cp "$log_file" "${log_file_location}/HuntressInstaller.log"
    fi
    if [ $exitCode -ne "0" ]; then
        logger "Exit with error, please send ${log_file_location}HuntressInstaller.log to support."
    fi
    exit "$exitCode"
}
trap copyLog EXIT

# Exit the script with error if a required dependency is missing
function checkDependency {
     tools=("curl" "jq" "openssl" "nc")
     for tool in "${tools[@]}"; do
          if [ -z "$tool" ]; then
               logger "Error retrieving install status of curl, jq, openssl, or nc! $tool"
          else
               if ! command -v $tool &> /dev/null; then
                    logger "Error: $tool is not installed and is required to run this script! You may need to"
                    logger "install this using your package manager. Here are some suggestions:"
                    logger "macOS:               brew install $tool"
                    logger "Debian/Ubuntu:       sudo apt install $tool"
                    logger "CentOS/Fedora/RHEL:  sudo dnf install $tool"
                    if [ "$tool" == "jq" ]; then
                         logger "** Please note the jq tool in CentOS/RHEL may require EPEL first! **"
                    fi
                    logger "SUSE:                sudo zypper install $tool"
                    logger "If the above commands don't work for your distro, please refer to your distro's support team or their documentation."
                    exit 1
               fi
          fi
     done
}

# If the local JSON file exists and was modified less than 14 days ago, skip downloading from github
function getLocalJSON {
     # alternate file location override
     if ! [[ -z "$localJSONOverride" ]]; then
          localJSON="${localJSONOverride}URLdata.json"
     fi

     # Symbolic links could potentially give a user limited access to a directory they normally can't access.
     # The script will exit if it can't find a non-symlink file.
     if [ -L "$localJSON" ]; then
          if [ -L "$altJSON" ]; then
               logger "WARNING: Both JSON files are symbolic links. This is not recommended for security reasons. Exiting!"
               exit 1
          else
               localJSON=$altJSON
               logger "Local JSON is a symbolic link, using alternate location $altJSON."
          fi
     fi

     # look for local JSON file
     if [[ -f "$localJSON" ]]; then
          if [[ $(find "$localJSON" -type f -mtime -"$gracePeriodForJSON" -print) ]]; then
               lastWrite="$(date -r "$localJSON" '+%Y-%m-%d %H:%M:%S %Z')"
               logger "Using $localJSON from $lastWrite"
               getJSON false
          else
               logger "Local JSON file is stale, downloading new version from github"
               getJSON true
          fi
     # if local JSON isn't found, use alternate
     elif [[ -f "$altJSON" ]]; then
          localJSON=$altJSON
          if [[ $(find "$localJSON" -type f -mtime -"$gracePeriodForJSON" -print) ]]; then
               lastWrite="$(date -r "$localJSON" '+%Y-%m-%d %H:%M:%S %Z')"
               logger "Using alternate JSON file ($localJSON) from $lastWrite"
               getJSON false
          else
               logger "Alternate JSON file ($localJSON) too old to safely use, attempting to retrieve from github"
               getJSON true
          fi
     # no existing files found, look for a writable directory
     else 
          # script directory is writable, download fresh copy from github 
          if [[ -w "$scriptDIR" ]]; then
               logger "JSON file not found, using $scriptDIR"
               getJSON true
          # alternate directory is writable, download fresh copy from github to alternate location
          elif [[ -w "/tmp/" ]]; then
               logger "JSON file not found, script directory not writable, using $altJSON"
               localJSON=$altJSON
               getJSON true
          # else exit the script with error
          else
               logger "Unable to write to either local or alternate JSON files:"
               logger "$localJSON"
               logger "$altJSON"
               exit 1
          fi
     fi
}

# Download a JSON from github to a local file (represented by $localJSON), then process that file into arrays.
function getJSON {
     local downloadFromGithub="${1:?Error: downloadFromGithub variable is required.}"

     # retrieve URLs, cert Issuer, and cert Subject from Huntress github
     if $downloadFromGithub; then
          curl -fsSL --tlsv1.2 -o "$localJSON" "$gitURL"
          if [ $? -ne 0 ]; then
               logger "Unable to connect to github, if you can't allow connections to githubusercontent.com then download this file and save it in same DIR as this script."
               logger "$gitURL"
               exit 1
          else 
               logger "Download successful from github!"
               logger
          fi
     fi
     if ! [ -f "$localJSON" ]; then
          logger "Unable to find $localJSON"
          exit 1
     fi

     # Splitting the JSON file into several arrays
     while IFS= read -r item; do
          [ -z "$item" ] && continue
          testURLs+=($(printf "%s\n" "$item" | sed -e 's|^[^/]*//||' -e 's|/.*$||'))
     done < <(cat "$localJSON" | jq -r '.array1[] | select(length > 0)')
     while IFS= read -r item; do
          [ -z "$item" ] && continue
          certURLs+=($(printf "%s\n" "$item" | sed -e 's|^[^/]*//||' -e 's|/.*$||'))
     done < <(cat "$localJSON" | jq -r '.array2[] | select(length > 0)')
     # even array indices are Subjects, odd are Issuer. 
     count=0    
     while IFS= read -r item; do
          [ -z "$item" ] && continue
          if (( $count % 2 == 0 )); then
               expSubject+=("$(echo "$item" | xargs)")
          else
               expIssuer+=("$(echo "$item" | xargs)")
          fi
          ((count++))
     done < <(cat "$localJSON" | jq -r '.array3[] | select(length > 0)')
     while IFS= read -r item; do
          [ -z "$item" ] && continue
          expIssuerName+=("$item")
     done < <(cat "$localJSON" | jq -r '.array5[] | select(length > 0)')

     # If the data wasn't ingested into the arrays, exit with error (likely a corrupted JSON download)
     if [[ ${#testURLs[@]} -eq 0 || ${#certURLs[@]} -eq 0 || ${#expSubject[@]} -eq 0 || ${#expIssuer[@]} -eq 0 || ${#expIssuerName[@]} -eq 0 ]]; then
          logger "Error reading data from JSON file. Delete the local JSON file and try again."
          exit 1
     fi
}

# tests that the expected certificates are not intercepted. If the expected cert is not returned the agent will not function.
function certTest {
     logger "-- Testing Certificate Validation --"
     declare -a failURLs=()
     for i in "${!certURLs[@]}"; do
          cleanURL=${certURLs[i]}
          # there is no cross-platform timeout command, so attempt to use timeout, perl, or gtimeout before defaulting to no timeout (with warning)
          if command -v timeout >/dev/null 2>&1; then
               s_client=$(timeout 5 openssl s_client -connect "${cleanURL}:443" -servername "${cleanURL}" </dev/null 2>/dev/null)
          elif command -v perl >/dev/null 2>&1; then
               s_client=$(perl -e 'alarm 5; exec @ARGV' openssl s_client -connect "${cleanURL}:443" -servername "${cleanURL}" </dev/null 2>/dev/null)
          elif command -v gtimeout >/dev/null 2>&1; then
               s_client=$(gtimeout 5 openssl s_client -connect "${cleanURL}:443" -servername "${cleanURL}" </dev/null 2>/dev/null)
          else
               logger "Warning: Unable to find an appropriate 'timeout' library. Using openssl without a timer, it's rare but possible for this to hang!"
               s_client=$(printf '\n' | openssl s_client -connect "${cleanURL}:443" -servername "${cleanURL}" 2> /dev/null < /dev/null )
          fi

          PEM=$(printf '%s\n' "$s_client" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p')
          recIssuer=$(printf '%s\n' "$s_client" | openssl x509 -noout -issuer -nameopt compat | cut -d'/' -f2- | xargs)
          recSubject=$(printf '%s\n' "$s_client" | openssl x509 -noout -subject -nameopt compat | cut -d'/' -f2- | xargs)

          # abort install if certificates can't be retrieved
          if [[ -z $recSubject || -z $recIssuer ]]; then
               logger "WARNING: Unable to retrieve certificate data! Exiting."
               exit 1
          fi

          if [[ "$recSubject" == "${expSubject[i]}" ]]; then
               logger "[Certificate subject validation successful for $cleanURL]"
          else
               ((certFailCounter++))
               ((countFails++))
               failURLs+=($cleanURL)
               logger "[FAILED: Subject validation. Certificate does not match for [$cleanURL] !]"
               logger "Subject that was returned: [$recSubject]"
               logger "Subject that was expected: [${expSubject[i]}]"
               logger "PEM that was received: $PEM"
          fi

          # Issuer can vary based on the specific server the script reaches. To compensate, we check for exact match then a wildcard match.
          if [[ "$recIssuer" == "${expIssuer[i]}" ]]; then 
               logger "[Certificate issuer validation successful for $cleanURL]"
          else
               if [[ "$recIssuer" == *"${expIssuerName[i]}"* ]]; then
                    logger "Please note this was not an exact match, which is expected with big infrastructure."
                    logger "Issuer that was returned: [$recIssuer]"
                    logger "Issuer that was expected: [${expIssuer[i]}]"
               else
                    ((certFailCounter++))
                    ((countFails++))
                    failURLs+=($cleanURL)
                    logger "[FAILED: Issuer validation. Certificate does not match for [$cleanURL] !]"
                    logger "Issuer that was returned: [$recIssuer]"
                    logger "Issuer that was expected: [${expIssuer[i]}]"
                    logger "PEM that was received: $PEM"
               fi
          fi
     done
     # list every cert failure so the appropriate DPI system can be adjusted
     if [[ "$certFailCounter" > 0 ]]; then
          for i in "${!failURLs[@]}"; do
               certFail "${failURLs[i]}"
          done
     fi
     logger ""
}

# test outgoing port 443 connectivity to Huntress URLs
function tcpTest {
     logger "-- Verifying Huntress services can be reached --"
     for i in "${!testURLs[@]}"; do
          cleanURL=${testURLs[i]}
          if nc -zvw 5 "$cleanURL" 443 > /dev/null 2>&1; then
              logger "[Connection to $cleanURL successful]"
          else
              logger "[FAILED: Connection to $cleanURL"
               ((countFails++))
          fi
     done
     logger ""
}

# Helper function to print lengthy error/instructional message
function certFail {
    # If $1 parameter is missing, prints the message and exits the script
    local cleanURL="${1:?Error: cleanURL variable is required.}"
    logger "------------------------------------------------------------------------------------------------------------------------------"
    logger "The Subject/Issuer text above usually identifies if this is a DPI/cert interception issue, or a cert chain issue."
    logger "* If the returned SUBJECT does not contain 'Huntress' or 'Microsoft' in the text this is likely a DPI/cert interception issue."
    logger "      You'll need to add an exclusion for the certificate for this URL in your DPI/cert interception service: $cleanURL"
    logger "* If the returned ISSUER does not contain 'DigiCert', 'Google', or 'Microsoft', this is likely a  DPI/cert interception issue."
    logger "      You'll need to add an exclusion for the certificate for this URL in your DPI/cert interception service: $cleanURL"
    logger "* Otherwise this is likely a missing certificate chain. Check for pending OS updates, reboot, and try again."
    logger "------------------------------------------------------------------------------------------------------------------------------"
}

# Get a list of network adapter names, IPv4 address, DNS IP, and gateway IP
function getNetAdapters {
    logger "Network Adapters:"
    while IFS= read -r line; do
        case "$line" in
            "Hardware Port: "*)
                adapter=${line#Hardware Port: }
                ;;
            "Device: "*)
                dev=${line#Device: }

                # Require an active interface with an IPv4 address.
                if ! ifconfig "$dev" 2>/dev/null | grep -q "status: active"; then
                    continue
                fi

                ipv4=$(ifconfig "$dev" 2>/dev/null | awk '$1 == "inet" && $2 != "127.0.0.1" { print $2; exit }')

                [ -n "$ipv4" ] || continue

                dns=$(scutil --dns | awk -v dev="$dev" '
                    /^resolver #[0-9]+/ {
                        dns=""
                        next
                    }
                    $1 ~ /^nameserver\[[0-9]+\]$/ {
                        dns = dns (dns ? ", " : "") $3
                    }
                    $1 == "if_index" && $0 ~ "\\(" dev "\\)" {
                        print dns
                        exit
                    }
                ')

                gateway=$(route -n get default -ifscope "$dev" 2>/dev/null |
                    awk '$1 == "gateway:" { print $2; exit }')

                logger "Adapter: $adapter ($dev)     IPv4: $ipv4     DNS: $dns     Gateway: $gateway" 
                logger 
                ;;
        esac
    done < <(networksetup -listallhardwareports)
}

# validate options passed to or stored in the script
function validateParameters {
    if [ -z "$organization_key" ]; then
        organizationKey=$(echo "$defaultOrgKey" | tr -dc '[:alnum:]- ' | tr ' ' '-' | xargs)
        logger "--organization_key parameter not present, using defaultOrgKey instead: $defaultOrgKey, formatted to $organizationKey "
      else
        organizationKey=$(echo "$organization_key" | tr -dc '[:alnum:]- ' | tr ' ' '-' | xargs)
        logger "--organization_key parameter present, set to: $organization_key, formatted to $organizationKey "
    fi

    if ! [[ "$account_key" =~ $pattern ]]; then
        logger "Invalid --account_key provided, checking defaultAccountKey..."
        accountKey=$(echo "$defaultAccountKey" | xargs)
        if ! [[ $accountKey =~ $pattern ]]; then
            # account key is invalid if script gets to this branch, so write the key unmasked for troubleshooting
            logger "ERROR: Invalid --account_key, $accountKey was provided. Please check Huntress support documentation."
            exit 1
        fi
        else
            accountKey=$(echo "$account_key" | xargs)
    fi

    # Hide most of the account key in the logs, keeping the front and tail for troubleshooting
    masked="$(echo "${accountKey:0:4}")"
    masked+="************************"
    masked+="$(echo "${accountKey: (-4)}")"

    # OPTIONS REQUIRED (account key could be valid in this branch, so mask it)
    if [ -z "$accountKey" ] || [ -z "$organizationKey" ]
    then
        logger "Error: --account_key and --organization_key are both required" >> $log_file
        logger "Account key: $masked and Org Key: $organizationKey were provided"
        echo
        usage
        exit 1
    fi

    logger "Provided Huntress key: $masked"
    logger "Provided Organization Key: $organizationKey"
    if [ -n "$tags" ]; then
      logger "using tags: $tags"
    fi

    if $install_system_extension; then
      logger "automatically installing system extension"
      logger "$install_system_extension"
    fi
}

# After deploy, read the 8 newest lines from HuntressAgent.log to determine registration status
function getRegistrationStatus {
    didAgentRegister=false
    declare -a registrationLines=()
    logLocation="/Library/Application Support/Huntress/HuntressAgent/HuntressAgent.log"
    # Watch for HuntressAgent.log, checking every 1/4 second until 10 seconds elapsed, if found grab the last 8 lines
    for (( i=0; i<40; i++ )); do
        if [[ -f "$logLocation" ]]; then
            break
        fi
        sleep 0.25
    done

    # if the log isn't found at this point, registration failed
    if ! [ -f "$logLocation" ]; then
        logger "WARNING: HuntressAgent.log not found, install failed."
        exit 1
    fi

    # find all registration lines
    regCount=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $line == *registered* ]]; then
            ((regCount++))
            registrationLines+=("$line")
        fi
    done < "$logLocation"

    # look for recent registration
    tailedLog=$(tail -n 8 "$logLocation")
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $line == *registered* ]]; then
            didAgentRegister=true
        fi
    done <<< "$tailedLog"

    logger "Last 8 lines of agent log:"
    logger "$tailedLog"
    logger

    # agent registered recently
    if $didAgentRegister; then
        # recent registration + older registrations found
        if [[ $regCount -gt 1 ]]; then
            logger "Success: Agent registered with Huntress portal. Multiple registration events:"
        # only a recent registration was found
        else
            logger "Success: New agent registered with Huntress portal! Registration event from log:"
        fi
    # no recent agent reg, but older events found
    elif [[ $regCount -gt 0 ]]; then
        logger "Caution: the agent didn't output a registration line in logs, however older registration events were detected."
        logger "Check your Huntress portal for confirmation of registration status, unable to determine via logs. Registration events:"
    else 
        logger "  >>>  WARNING: Agent did not successfully register!  <<<  "
        exit 1
    fi   
    logger $registrationLines
}


logger "============================= Pre-Flight Checks at $dd ==================================="
# Check for root
if [ $EUID -ne 0 ]; then
    logger "WARNING: This script must be run as root, exiting..."
    exit 1
fi

# Clean up any old installer scripts.
if [ -f "$install_script" ]; then
    logger "Installer file present in /tmp; deleting."
    rm -f "$install_script"
fi

# Cursory check for existing install
if [ -f "/Applications/Huntress.app/Contents/Macos/HuntressAgent" ]; then
    isInstalled=true
else
    isInstalled=false
fi

##
## This section handles the assigning `=` character for options.
## Since most RMMs treat spaces as delimiters in Mac Scripting,
## we have to use `=` to assign the option value, but must remove
## it because, well, bash. https://stackoverflow.com/a/28466267/519360
##

usage() {
    cat <<EOF
Usage: $0 [options...] --account_key=<account_key> --organization_key=<organization_key>

-a, --account_key      <account_key>      The account key to use for this agent install
-o, --organization_key <organization_key> The org key to use for this agent install
-t, --tags             <tags>             A comma-separated list of agent tags to use for this agent install
-r, --reinstall                           If passed, attempt to reinstall on top of existing Huntress agent
-i, --install_system_extension            If passed, automatically install the system extension
-n, --noNetTest                           If prompted by Huntress staff, use this flag to temporarily bypass network testing
-h, --help                                Print this message

EOF
}

reinstall=false
skipNetTest=false
while getopts "a:o:t:ihrn-:" OPT; do
    if [ "$OPT" = "-" ]; then
        OPT="${OPTARG%%=*}"       # extract long option name
        OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
        OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
    else
        # the user used a short option, but we still want to strip the assigning `=`
        OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
    fi
    case "$OPT" in
        a | account_key)
            account_key="$OPTARG"
            ;;
        o | organization_key)
            organization_key="$OPTARG"
            ;;
        t | tags)
            tags="$OPTARG"
            ;;
        i | install_system_extension)
            logger "Running with System Extension immediate install option"
            install_system_extension=true
            ;;
        r | reinstall)
            logger "Running with the -reinstall flag"
            reinstall=true
            ;;
        n | noNetTest)
            logger "=======> Skipping network test! <======="
            skipNetTest=true
            ;;
        h | help)
            usage
            exit 0
            ;;
        ??*)
            logger "Illegal option --$OPT"
                exit 2
            ;;  # bad long option
        \? )
                exit 2
            ;;  # bad short option (error reported via getopts)
    esac
done
shift $((OPTIND-1)) # remove parsed options and args from $@ list

logger "Huntress install script $scriptVersion, install source: $rmm"
logger "Script flags: Reinstall:$reinstall  System Extension:$install_system_extension  Network testing skip:$skipNetTest"
validateParameters
logger "Script cursory check, is Huntress installed already: $isInstalled"

# Check for existing Huntress install, if already installed exit with error. Bypass if using the reinstall flag.
if ! $reinstall; then
    if $isInstalled; then
        logger "Huntress assets found, checking for running processes"
        numServicesStopped=0
        for HuntressProcess in "HuntressAgent" "HuntressUpdater"; do
            if [ $(pgrep "$HuntressProcess" > /dev/null) ]; then
                logger "Warning: process $HuntressProcess is stopped"
                ((numServicesStopped++))
            else
                logger "Process $HuntressProcess is running"
            fi
        done
        if [ $numServicesStopped -gt 0 ]; then
            logger "Installation appears damaged, suggest running with the -reinstall flag"
        else
            logger "Installation found and processes are running. If you suspect this agent is damaged try running this script with the -reinstall flag"
        fi
        exit 1
    fi
fi

logger "============================== Logging Machine Details at $dd ==================================="
logger "Machine name: $(scutil --get ComputerName)"
logger "macOS version: $(sw_vers --ProductVersion)"
logger "System uptime: $(uptime)"
logger "CPU: $(sysctl -n machdep.cpu.brand_string)"
logger "Free disk space: "$(df -Pk . | sed 1d | grep -v used | awk '{ print $4 "\t" }')
logger $(top -l 1 | head -n 7 | tail -n 1)    # memory usage
logger $(top -l 1 | head -n 3 | tail -n 1)    # CPU load average
logger "Time Zone: $(date +%Z)"


logger "========================= Logging Machine Networking Details at $dd ============================="
getNetAdapters

# Perform a network test. Verifying port 443 connectivity to Huntress URL's and that Huntress certificates are not intercepted.
if ! $skipNetTest; then
    logger "Scanning for endpoint network readiness:"
    checkDependency
    getLocalJSON
    tcpTest
    certTest
    if [[ $countFails -gt 0 ]]; then
        logger "WARNING: Network testing failed, aborting deploy since the endpoint is not ready for Huntress yet."
        exit 1
    fi
else
    logger "Warning: Skipping network testing, the Huntress agent may not operate without a valid network setup!"
fi

logger "======================== Downloading and Installing at $dd ==============================="
result=$(curl -w "%{http_code}" -L "https://huntress.io/script/darwin/$accountKey" -o "$install_script")

if [ $? != "0" ]; then
   logger "ERROR: Download failed with error: $result"
   exit 1
else
    logger "Download successful. Installing..."
fi

if grep -Fq "$invalid_key" "$install_script"; then
   logger "ERROR: --account_key is invalid. You entered: $accountKey"
   exit 1
fi

if $install_system_extension; then
    install_result="$(/bin/bash "$install_script" -a "$accountKey" -o "$organizationKey" -t "$tags" -v --install_system_extension)"
else
    install_result="$(/bin/bash "$install_script" -a "$accountKey" -o "$organizationKey" -t "$tags" -v)"
fi

if [ $? != "0" ]; then
    logger "Installer Error: $install_result"
    exit 1
fi
logger "$install_result"

getRegistrationStatus

logger "============================ INSTALL FINISHED AT $dd ====================================="

exit 0
