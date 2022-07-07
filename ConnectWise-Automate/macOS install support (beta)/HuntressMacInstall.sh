#!/bin/bash

declare account_key
declare organization_key
declare tags
declare api_url
declare eetee_url
declare allow_http=false
declare verbose=0
declare interactive=1
declare -a ARGS
declare portal_url="https://huntress.io"
declare package_file=
ARGS=()

usage() {
    cat <<EOF
Usage: $0 [options...] --account_key <account_key> --organization_key <organization_key>

-a, --account_key      <account_key>      The account key to use for this agent install
-o, --organization_key <organization_key> The org key to use for this agent install
-t, --tags             <tags>             A comma-separated list of agent tags
-v, --verbose                             Print info during install
    --batch_only                          Do not prompt the user for missing info
-h, --help                                Print this message

EOF
}

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        -a|--account_key)
            account_key="$2"
            shift
            shift
            ;;
        --batch_only)
            interactive=0
            shift
            ;;
        -o|--organization_key)
            organization_key="$2"
            shift
            shift
            ;;
        -t|--tags)
            tags="$2"
            shift
            shift
            ;;
        -v|--verbose)
            verbose=1
            shift
            ;;
        -h|--help)
            usage
            exit
            ;;
        # these are more or less hidden options. Only used for debugging
        -f|--package-file)
            package_file="$2"
            shift
            shift
            ;;
        -p|--portal_url|--portal-url)
            portal_url="$2"
            shift
            shift
            ;;
        -u|--api_url|--api-url)
            api_url="$2"
            allow_http=true
            shift
            shift
            ;;
        --eetee_url|--eetee-url)
            eetee_url="$2"
            allow_http=true
            shift
            shift
            ;;
        *)
            ARGS+=($1)
            shift
            ;;
    esac
done

set -- "${ARGS[@]}"

# ask the user for the account key if not passed in and we are
# "interactive" (see --batch_only)
if [[ -z $account_key && $interactive -eq 1 ]]
then
    echo -n "Account Key: "
    read account_key
fi

# ask the user for the organization key if not passed in and we are
# "interactive" (see --batch_only)
if [[ -z $organization_key && $interactive -eq 1 ]]
then
    echo -n "Organization Key: "
    read organization_key
fi

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

rm "$installer_config"
rm "$huntress_pkg"
