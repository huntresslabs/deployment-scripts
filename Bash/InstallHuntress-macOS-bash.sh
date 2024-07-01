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
# https://support.huntress.io/hc/en-us/articles/10742964620435-Install-the-Huntress-Agent-for-macOS


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
dd=$(date "+%Y%m%d-%H%M%S")
log_file="/tmp/HuntressInstaller.log"
install_script="/tmp/HuntressMacInstall.sh"
invalid_key="Invalid account secret key"
pattern="[a-f0-9]{32}"
version="1.0"

## Using logger function to provide helpful logs within RMM tools in addition to log file
logger() {
    echo "$dd -- $*";
    echo "$dd -- $*" >> $log_file;
}

# Check for root
if [ $EUID -ne 0 ]; then
    logger "This script must be run as root, exiting..."
    exit 1
fi

# Clean up any old installer scripts.
if [ -f "$install_script" ]; then
    logger "Installer file present in /tmp; deleting."
    rm -f "$install_script"
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
-h, --help                                Print this message

EOF
}

while getopts a:o:h:-: OPT; do
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

logger "=========== INSTALL START AT $dd ==============="
logger "=========== $rmm Deployment Script | Version: $version ==============="

# VALIDATE OPTIONS PASSED TO SCRIPT
if [ -z "$organization_key" ]; then
    organizationKey=$(echo "$defaultOrgKey" | xargs)
    logger "--organization_key parameter not present, using defaultOrgKey instead: $defaultOrgKey"
  else
    organizationKey=$(echo "$organization_key" | xargs)
    logger "--organization_key parameter present, set to: $organizationKey"
fi

if ! [[ "$account_key" =~ $pattern ]]; then
    logger "Invalid --account_key provided, checking defaultAccountKey..."
    accountKey=$(echo "$defaultAccountKey" | xargs)
    if ! [[ $accountKey =~ $pattern ]]; then
        logger "ERROR: Invalid --account_key. Please check Huntress support documentation."
        exit 1
    fi
    else
        accountKey=$(echo "$account_key" | xargs)
fi

# OPTIONS REQUIRED
if [ -z "$accountKey" ] || [ -z "$organizationKey" ]
then
    logger "Error: --account_key and --organization_key are both required" >> $log_file
    echo
    usage
    exit 1
fi

# Hide most of the account key in the logs, keeping the front and tail end for troubleshooting 
masked="$(echo "${accountKey:0:4}")"
masked+="************************"
masked+="$(echo "${accountKey: (-4)}")"

logger "Provided Huntress key: $masked"
logger "Provided Organization Key: $organizationKey"

result=$(curl -w "%{http_code}" -L "https://huntress.io/script/darwin/$accountKey" -o "$install_script")

if [ $? != "0" ]; then
   logger "ERROR: Download failed with error: $result"
   exit 1
fi

if grep -Fq "$invalid_key" "$install_script"; then
   logger "ERROR: --account_key is invalid. You entered: $accountKey"
   exit 1
fi

install_cmd="/bin/zsh $install_script -a $accountKey -o $organizationKey -v"
if [ "$install_system_extension" = true ]; then
    install_cmd+=" --install_system_extension"
fi

install_result=$(eval "${install_cmd}")
logger "=============== Begin Installer Logs ==============="

if [ $? != "0" ]; then
    logger "Installer Error: $install_result"
    exit 1
fi

logger "$install_result"
logger "=========== INSTALL FINISHED AT $dd ==============="
exit
