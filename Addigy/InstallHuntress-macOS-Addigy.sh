#!/bin/bash
#shellcheck disable=SC2181,SC2295,SC2116

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


#####################################################################################
##
## Begin user modified variables. Modify per documentation before running in Addigy.
##
#####################################################################################


# Replace __ACCOUNT_KEY__ with your account secret key (from your Huntress portal's "download agent" section)
defaultAccountKey="__ACCOUNT_KEY__"

# If the organization key is passed as a parameter, it will be used instead of this defaultOrgKey variable.
# If you have a preferred "placeholder" organization name for Mac agents, you can set that below.
defaultOrgKey="__ORGANIZATION_KEY__"

# Option to install the system extension after the Huntress Agent is installed. In order for this to happen
# without security prompts on the endpoint, permissions need to be applied to the endpoint by Addigy before this script
# is run. See the following KB article for more information:
# https://support.huntress.io/hc/en-us/articles/21286543756947-Instructions-for-the-MDM-Configuration-for-macOS
install_system_extension=true

##############################################################################
## In many multitenant environments, the Top-Level Addigy Policy name
## matches the name of each Organization. If you wish to dynamically use the
## Top-Level policy name as your Organization Name, you can pull the
## $POLICY_PATH environment variable from Addigy's Policy pipeline.
##
## For this method, comment line 51 above and uncomment lines 62-63 below.
##############################################################################

# topLevelPolicy=$(echo ${POLICY_PATH} | awk -F ' \\| ' '{print $1}')
# defaultOrgKey="$topLevelPolicy"

##############################################################################
## Do not modify anything below this line
##############################################################################
dd=$(date "+%Y%m%d-%H%M%S")
log_file="/tmp/HuntressInstaller.log"
install_script="/tmp/HuntressMacInstall.sh"
invalid_key="Invalid account secret key"
pattern="[a-f0-9]{32}"
rmm="Addigy macOS deployment script"
version="1.2 - July 19, 2023"

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

# Log policy path if Addigy policies are being. Useful for troubleshooting
if [ -n "$topLevelPolicy" ]; then
    logger "Policy Path: ${POLICY_PATH}"
    logger "Policy Path (base64): $(echo ${POLICY_PATH} | base64)"
    logger "Top Level Policy: $topLevelPolicy"
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
logger "=========== $rmm | Version: $version ==============="

# VALIDATE OPTIONS PASSED TO SCRIPT
if [ -z "$organization_key" ]; then
    organizationKey=$(echo "$defaultOrgKey" | xargs)
    logger "--organization_key parameter not present, using defaultOrgKey instead: $defaultOrgKey"
  else
    organizationKey=$(echo "$organization_key" | xargs)
    logger "--organization_key parameter present, set to: $organizationKey"
fi

if ! [[ "$account_key" =~ $pattern ]]; then
    logger "Missing --account_key parameter, switching to use defaultAccountKey..."
    accountKey=$(echo "$defaultAccountKey" | xargs)
    if ! [[ $accountKey =~ $pattern ]]; then
        logger "ERROR: Invalid account_key provided. Please check Huntress support documentation."
        exit 1
    fi
    else
        accountKey=$(echo "$account_key" | xargs)
fi

# OPTIONS REQUIRED
if [ -z "$accountKey" ] || [ -z "$organizationKey" ]
then
    logger "Error: --account_key and --organization_key are both required"
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

logger "=============== Begin Installer Logs ==============="
if [ "$install_system_extension" = true ]; then
    install_result="$(/bin/bash "$install_script" -a "$accountKey" -o "$organizationKey" -v --install_system_extension)"
else
    install_result="$(/bin/bash "$install_script" -a "$accountKey" -o "$organizationKey" -v)"
fi

if [ $? != "0" ]; then
    logger "Installer Error: $install_result"
    exit 1
fi

logger "$install_result"
logger "=========== INSTALL FINISHED AT $dd ==============="
exit
