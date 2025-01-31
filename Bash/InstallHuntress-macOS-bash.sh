#!/usr/bin/env zsh

# Copyright (c) 2024 Huntress Labs, Inc.
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
rmm="Unspecified RMM"

# Option to install the system extension after the Huntress Agent is installed. In order for this to happen
# without security prompts on the endpoint, permissions need to be applied to the endpoint by an MDM before this script
# is run. See the following KB article for instructions:
# https://support.huntress.io/hc/en-us/articles/21286543756947-Instructions-for-the-MDM-Configuration-for-macOS
install_system_extension=false

##############################################################################
## Do not modify anything below this line
##############################################################################

scriptVersion="November 22, 2024"

dd=$(date "+%Y-%m-%d %H:%M:%S")
log_file="/tmp/HuntressInstaller.log"
install_script="/tmp/HuntressMacInstall.sh"
invalid_key="Invalid account secret key"
pattern="[a-f0-9]{32}"
version="1.1"

# print help message
usage() {
    cat <<EOF
Usage: $0 [options...] --account_key=<account_key> --organization_key=<organization_key>

-a, --account_key      <account_key>        The account key to use for this agent install
-o, --organization_key <organization_key>   The org key to use for this agent install
-t, --tags             <tags>               A comma-separated list of agent tags
-i, --install_system_extension              If passed, automatically install the system extension
-r, --reregister                            Attempt a clean slate install of Huntress (must also pass account and org keys)
-h, --help                                  Print this message

EOF
}

# Using logger function to provide helpful logs within RMM tools in addition to log file
logger() {
    echo "$dd -- $*";
    echo "$dd -- $*" >> $log_file;
}

# This is for machines where the Huntress install is corrupted, damaged, or missing assets. 
# This will try to fully remove Huntress before attempting a reinstall
reregister() {
    logger "Starting uninstall, please be aware this can take up to a minute"

    countProcesses=$(ps aux | grep "HuntressAgent" -c)
    if [ $countProcesses -le 1 ]; then
        logger "Huntress process not running, System Extension may hang for a minute on uninstall"
    fi
    
    # skip trying to stop the services and file deletes if no assets are found to avoid clogging log with errors
    installCheck=$(checkForAssets)
    if [ $installCheck == 1 ]; then
        uninstall_system_extension
    
        cd "/Library/Application Support/Huntress/HuntressAgent"
        logger "Stopping services"
        /Applications/Huntress.app/Contents/MacOS/HuntressUpdater stop
        /Applications/Huntress.app/Contents/MacOS/HuntressAgent stop
        /Applications/Huntress.app/Contents/MacOS/Huntress daemonctl stop

        logger "Running updater uninstall..."
        /Applications/Huntress.app/Contents/MacOS/HuntressUpdater uninstall

        logger "Running agent uninstall..."
        /Applications/Huntress.app/Contents/MacOS/HuntressAgent uninstall

        logger "Uninstalling GRPC daemon..."
        /Applications/Huntress.app/Contents/MacOS/Huntress daemonctl uninstall

        logger "Removing app directory..."
        rm -rf /Applications/Huntress.app

        logger "Removing support directory..."
        rm -rf "/Library/Application Support/Huntress"
    else 
        logger "Huntress assets not found on disk, no services to stop and no assets to delete. Script continuing..."
    fi

    pkgCheck=$(checkForPkg)     
    if [ $pkgCheck == 1 ]; then
        logger "Forgetting package id..."
        pkgutil --forget com.huntresslabs.pkg.agent 2>/dev/null
    else 
        logger "Huntress pkg not found. Script continuing..."
    fi

    # wait timer for all components to finish uninstall before proceeding with install
    sleep 3
    logger "Uninstall complete, beginning reinstall"
}

# Uninstall the Huntress system extension
uninstall_system_extension() {
    logger "Uninstalling system extension"
    tmp_plist=/tmp/com.apple.system-extensions.admin.plist
    tmp_plist_prev=/tmp/com.apple.system-extensions.admin.prev.plist

    logger "Toggling system authorization settings..."
    security authorizationdb read com.apple.system-extensions.admin > $tmp_plist 
    cp $tmp_plist $tmp_plist_prev

    /usr/libexec/PlistBuddy -c "Set rule:0 is-root" $tmp_plist
    security authorizationdb write com.apple.system-extensions.admin < $tmp_plist

    logger "Uninstalling system extension..."
    /Applications/Huntress.app/Contents/MacOS/Huntress extensionctl uninstall || echo "Uninstalling extension failed: error code $!"

    logger "Restoring system authorization settings..."
    security authorizationdb write com.apple.system-extensions.admin < $tmp_plist_prev 
    rm $tmp_plist $tmp_plist_prev

    logger "Finished uninstalling system extension"
}

# return 1 if an existing Huntress install is detected, otherwise return 0
isHuntressInstalled() {
    installCheck=$(checkForAssets)
    pkgCheck=$(checkForPkg) 
    if [ $installCheck == 1 ]; then 
        echo 1
    elif [ $pkgCheck == 1 ]; then
        echo 1
    else 
        echo 0
    fi
}

# return 1 if Huntress assets are detected on disk, otherwise return 0
checkForAssets() {
    if [ -d "/Library/Application Support/Huntress" ] || [ -d "/Applications/Huntress.app" ]; then 
        echo 1
    else
        echo 0
    fi
}

#return 1 if Huntress pkg is registered, otherwise return 0
checkForPkg() {
    pkgCheck=$(pkgutil --pkgs | grep "Huntress" -i)
    if [[ -n $pkgCheck ]]; then 
        echo 1
    else
        echo 0
    fi
}

# logging details about the machine for troubleshooting purposes
getMachineInfo() {
    # uptime, free disk space, and OS version
    logger "================================================================="
    logger "============= Extra logging for troubleshooting ================="
    logger $"Uptime: $(uptime)"
    dfLines=$(df -H)
    for df in dfLines; do
        logger "$(df)"
    done
    logger "$(sw_vers)"

    # get network connectivity data
    logger "============================================================"
    logger "============= Testing network connectivity ================="
    for hostn in "update.huntress.io" "huntress.io" "eetee.huntress.io" "huntress-installers.s3.amazonaws.com" "huntress-updates.s3.amazonaws.com" "huntress-uploads.s3.us-west-2.amazonaws.com" "huntress-user-uploads.s3.amazonaws.com" "huntress-rio.s3.amazonaws.com" "huntress-survey-results.s3.amazonaws.com"; do 
        logger $(nc -z -v $hostn 443 2>&1)
    done
}




# ====================================================================================
# =================================== Begin 'main' ===================================
# ====================================================================================

# Logging machine and script info for troubleshooting
getMachineInfo

# Check for root
if [ $EUID -ne 0 ]; then
    logger "This script must be run as root, exiting..."
    exit 1
fi

# Clean up any old installer scripts.
if [ -f "$install_script" ]; then
    logger "Installer script present in /tmp; deleting to ensure newest version is being used."
    rm -f "$install_script"
fi

## This section handles the assigning `=` character for options. Since most RMMs treat spaces as delimiters in Mac Scripting,
## we have to use `=` to assign the option value, but must remove it because, well, bash. https://stackoverflow.com/a/28466267/519360
while getopts a:o:h:t:-:i:r OPT; do
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
        install_system_extension=true
        ;;
    r | reregister)
        reregister=true
        ;;
    h | help)
        usage
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

logger "============= INSTALL START AT $dd      ================="
logger "============= $rmm  | Version: $version ================="
logger "============= Script last updated $scriptVersion ============="

# if the reregister flag is passed perform a full wipe and fresh install
if [ $reregister ]; then
    logger "Reregister flag passed, attempting a clean install:"
    if [ assetCheck == 1 ]; then
        logger "Current contents of Huntress.app folder: $(ls '/Applications/Huntress.app/Contents/MacOS')"
        logger "Current contents of Application Support folder: $(ls '/Library/Application Support/Huntress/HuntressAgent')"
    fi
    reregister
fi

# if Huntress is detected on the machine, exit the script with error
# reregister flag above should fully remove Huntress (for installing on top of an existing install)
assetCheck=$(isHuntressInstalled)
if [ $assetCheck == 1 ]; then
    logger "Cannot proceed while Huntress is installed, suggest using the reregister flag"
    exit 2
fi

# validate options passed to script, remove all invalid characters except spaces are converted to dash
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

if [ -n "$tags" ]; then
  logger "using tags: $tags"
fi

if [ "$install_system_extension" = true ]; then
  logger "automatically installing system extension"
fi

# Hide most of the account key in the logs, keeping the front and tail end for troubleshooting
masked="$(echo "${accountKey:0:4}")"
masked+="************************"
masked+="$(echo "${accountKey: (-4)}")"

# OPTIONS REQUIRED (account key could be invalid in this branch, so mask it)
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

logger "==========================================================="
logger "============= Downloading agent installer ================="

result=$(curl -w "%{http_code}" -L "https://huntress.io/script/darwin/$accountKey" -o "$install_script")

if [ $? != "0" ]; then
   logger "ERROR: Download failed with error: $result"
   exit 1
fi

if grep -Fq "$invalid_key" "$install_script"; then
   logger "ERROR: --account_key is invalid. You entered: $accountKey"
   exit 1
fi

if [ "$install_system_extension" = true ]; then
    install_result="$(/bin/bash "$install_script" -a "$accountKey" -o "$organizationKey" -t "$tags" -v --install_system_extension)"
else
    install_result="$(/bin/bash "$install_script" -a "$accountKey" -o "$organizationKey" -t "$tags" -v)"
fi

logger "========================================================"
logger "================= Begin Installer Logs ================="

if [ $? != "0" ]; then
    logger "Installer Error: $install_result"
    exit 1
fi
logger "$install_result"

registrationStatus=$(sudo cat "/Library/Application Support/Huntress/HuntressAgent/HuntressAgent.log" | head -n 2 | grep "Huntress agent registered" -i)
if [[ -n $registrationStatus ]]; then
    echo "Agent successfully registered:"
    echo $registrationStatus
else
    logger "The agent wasn't able to register. Please check these articles and reach out to support if you get stuck"
    logger "https://support.huntress.io/hc/en-us/articles/4411751045267-Network-Connectivity-and-Troubleshooting-Errors-Caused-by-Firewalls"
    logger "https://support.huntress.io/hc/en-us/articles/4404005178771-Allow-List-Huntress-in-Third-Party-Security-Software-AV-NGAV-DR"
fi

logger "======================================================="
logger "============= INSTALL FINISHED AT $dd ================="
exit
