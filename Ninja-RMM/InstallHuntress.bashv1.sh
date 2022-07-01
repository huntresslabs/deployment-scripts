#!/bin/sh

# Copyright (c) 2022 Huntress Labs, Inc.
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
# https://support.huntress.io/hc/en-us/articles/4404005189011-Installing-the-Huntress-Agent


##############################################################################
## Begin user modified variables
##############################################################################


# Replace __ACCOUNT_KEY__ with your account secret key (from your Huntress portal's "download agent" section)
accountKey="__ACCOUNT_KEY__"

# If the organization key is passed as a parameter, it will be used instead of this DEFAULT_ORG_KEY variable.
# If you have a preferred "placeholder" organization name, you can set that below.
defaultOrgKey="Mac Agents"


##############################################################################
## Do not modify anything below this line
##############################################################################

ORG_KEY=$1
dd=`date "+%Y%m%d-%H%M%S"`
log_file="/tmp/HuntressInstall.log"
echo "=========== INSTALL START AT $dd ===============" >> "$log_file"

# Check if organization key was passed; if not, use the default organization set above.
if [ -z $ORG_KEY ]
  then
    # remove any trailing spaces
    orgKey=$(echo "$defaultOrgKey" | xargs)
    echo "No Organization Key parameter present, defaulting to $defaultOrgKey" >> "$log_file"
  else
    # remove any trailing spaces
    orgKey=$(echo "$ORG_KEY" | xargs)
    echo "Organization Key parameter present, set to: $ORG_KEY" >> "$log_file"
fi

# Hide most of the account key in the logs, keeping the front and tail end for troubleshooting 
masked="$(echo ${accountKey:0:4})"
masked+="************************"
masked+="$(echo ${accountKey: (-4)})"

echo "Huntress key: $masked" >> "$log_file"
echo "Organization Key: $orgKey" >> "$log_file"

/bin/bash -c "$(curl -L "https://huntress.io/script/darwin/$accountKey")" -- -a "$accountKey" -o "$orgKey"

echo "=========== INSTALL FINISHED AT $dd ===============" >> "$log_file"
