#!/bin/bash

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

# This bundled shell script is intended for use with Datto RMM while utilizing
# the HUNTRESS_ACCOUNT_KEY variable set up as a global variable in Datto RMM.
# https://support.huntress.io/hc/en-us/articles/4404012624147-Deploying-Huntress-with-Datto-RMM-ComStore-

# The CS_PROFILE_NAME variable within Datto RMM will be utilized to generate
# the Organization Name within Huntress. The usage of keys can be found here:
# https://support.huntress.io/hc/en-us/articles/4404012734227-Using-Account-Keys-Organization-Keys-and-Agent-Tags

# Modification of the Datto RMM component below this line is not recommended 
# nor supported. 

declare account_key="$HUNTRESS_ACCOUNT_KEY"
declare organization_key="$CS_PROFILE_NAME"
declare tags
declare api_url
declare eetee_url
declare allow_http=false
declare verbose=1
declare interactive=0
declare portal_url="https://huntress.io"
declare package_file=

# account key and organization key are required
if [[ -z $account_key || -z $organization_key ]]
then
    echo Error: --account_key and --organization_key are both required
    echo
    usage
    exit 1
fi

declare installer_config="/tmp/hagent.yaml"

[[ $verbose -eq 1 ]] && echo creating "$installer_config"...

# create the hagent.yaml file used by the postinstall script to build
# the AgentConfig.plist file
cat >"$installer_config" <<EOF
account_key: $account_key
organization_key: $organization_key
api_url: $api_url
allow_http: $allow_http 
tags: $tags
EOF

if [ -n "$eetee_url" ]; then
    echo "eetee_url: $eetee_url" >>"$installer_config"
fi

huntress_pkg=/tmp/HuntressAgent.pkg

if [ -n "$package_file" ]; then
  if [ -f "$package_file" ]; then
    cp -f "$package_file" "$huntress_pkg"
  else
    echo "$package_file" was not found
    exit 1
  fi
else
  # download the HuntressAgent.pkg file from S3
  status_code=$(curl -f -L -o "$huntress_pkg" -w %{http_code} "$portal_url/download/darwin/$account_key")

  if [ $? != 0 ]; then
    if [ "$status_code" = "400" ]; then
      echo "Account Key not valid."
    elif [ "$status_code" = "404" ]; then
      echo "File not found on S3."
    elif [ "$status_code" = "409" ]; then
      echo "The macOS Beta has not been enabled for this account."
    fi
    exit 1
  elif ! [ -f "$huntress_pkg" ]; then
    echo "File download failed."
    exit 1
  fi
fi

[[ $verbose -eq 1 ]] && echo running the installer...

# run the install
installer -pkg "$huntress_pkg" -target / || echo "Installation failed."

[[ $verbose -eq 1 ]] && echo cleaning up...

rm "$huntress_pkg"
