#!/usr/bin/env bash
# Copyright 2025 Huntress Labs, Inc. All rights reserved.
#
# Unauthorized copying of this file, via any medium is strictly prohibited
# without the express written consent of Huntress Labs, Inc.

set -uo pipefail

declare ACCOUNT_KEY=
declare ORG_KEY=
declare TAGS=
declare API_URL=
declare EETEE_URL=
declare INTERACTIVE=1
declare -a ARGS
declare PORTAL_URL="https://huntress.io"
declare PACKAGE_FILE=
declare ARCH=
declare SCRIPT_VERSION=0.0.1
declare CURL_INSTALLED=
declare WGET_INSTALLED=

readonly HUNTRESS_PKG=/tmp/HuntressAgentPackage
# services
readonly huntress_agent_service=huntress-agent
readonly huntress_updater_service=huntress-updater
readonly huntress_agent="/usr/share/huntress/${huntress_agent_service}"
readonly huntress_updater="/usr/share/huntress/${huntress_updater_service}"

ARGS=()

logo() {
  cat <<EOF
⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢸⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠸⣿⣧⣀⠀⢀⣀⣀⣀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⢳⣶⣦⣄⠹⣿⣿⣷⣤⡈⠉⢉⠉⠙⠻⢶⣤⡀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠻⣿⣿⣷⣾⣿⣿⣿⣿⣦⠀⢷⡄⢰⡄⠈⠻⣷⡄⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⢀⣀⣀⣈⣙⠛⠿⠿⣿⣿⣿⣿⡇⢸⣿⣾⣿⣄⣦⠈⢻⣆⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠙⠿⣿⣿⣿⣿⣶⣾⣿⣿⣿⡇⣸⣿⣿⣿⣿⣿⣇⠀⢿⡆⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠚⣀⣠⣤⣭⣭⣭⣭⣿⣿⣿⣷⣿⣿⠉⠳⢦⣤⣤⡄⢸⣧⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠚⠛⠛⠛⠛⢋⣉⣥⢾⣿⣿⠸⣿⣿⡀⢢⣤⣤⠀⡇⠘⣿⡄⠀⠀⠀
⠀⠀⠀⠀⠀⢸⣧⠀⡴⠿⠛⣋⣴⠞⣿⡿⠀⢻⣿⣧⠈⢿⣿⡀⠣⠀⠟⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⢻⣆⠀⠰⠟⠋⣡⣾⠟⢁⣦⡀⠻⣿⡗⢀⣿⣷⠄⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠹⣷⣄⠀⠈⠉⣀⣴⣿⣿⣿⣷⣾⠀⣾⣿⠷⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠈⠛⢷⣦⣄⣀⠀⠉⠛⢿⣿⣿⡄⢹⡟⠁⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠙⠛⠛⠓⠂⠉⢿⣷⠀⠃⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⡆⠀⢰⠀⡆⠀⡆⠀⣦⠀⡆ ⢲⠂⢰⠒⠒⡄⠋⡖⠒ ⢠⡒⠢⠀⣔⠒⠄
⠀⠀⡏⠉⢹⠀⢇⣀⠇⠀⡇⠱⡇⠀⢸⠀⢸⠉⠹⡀ ⣏⣉ ⠠⣈⡱⠀⢄⣉⠆
EOF
}

usage() {
  logo
  echo
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

log_info() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S")
  echo "$ts $*"
}

die() {
  log_info "[x] $*"
  #exit 1
  kill -INT $$
}

# get user configuration
get_user_creds() {
  # ask the user for the account key if not passed in and we are
  # "interactive" (see --batch_only)
  if [[ -z $ACCOUNT_KEY && $INTERACTIVE -eq 1 ]]; then
    echo -n "Account Key: "
    read -r ACCOUNT_KEY
  fi

  # ask the user for the organization key if not passed in and we are
  # "interactive" (see --batch_only)
  if [[ -z $ORG_KEY && $INTERACTIVE -eq 1 ]]; then
    echo -n "Organization Key: "
    read -r ORG_KEY
  fi

  # account key and organization key are required
  if [[ -z $ACCOUNT_KEY || -z $ORG_KEY ]]; then
    echo Error: --account_key and --organization_key are both required
    echo
    usage
    exit 1
  fi
}

# download latest Huntress package from S3
download_latest() {
  local url="${PORTAL_URL}/download/linux/${ACCOUNT_KEY}?arch=${ARCH}"
  local status_code="0"

  # If neither wget or curl exists on the system, then we fail at the previous validation step
  if [ "$CURL_INSTALLED" = true ]; then
    status_code=$(curl -f -L -o "${HUNTRESS_PKG}" -w "%{http_code}" "${url}")
  elif [ "$WGET_INSTALLED" = true ]; then
    # if there is a redirect, get the last http response code
    status_code=$(wget -S -pO "${HUNTRESS_PKG}" "${url}" 2>&1 | grep "HTTP/" | awk '{print $2}' | tail -n 1 | tr -d '[:space:]' )
  fi

  if [ $? != 0 ] || [ "$status_code" != "200" ]; then
    # provide helpful failure message
    if [ "$status_code" = "400" ]; then
      die "Account Key not valid."
    elif [ "$status_code" = "404" ]; then
      die "File not found on S3."
    elif [ "$status_code" = "409" ]; then
      die "The Linux Beta has not been enabled for this account."
    fi

    die "Failed to download installation package"
  fi

  if ! [ -f "$HUNTRESS_PKG" ]; then
    die "File download failed."
  fi

  return 0
}

# determine arch type
get_host_info() {
  local arch

  arch="$(uname -m)"
  case "${arch}" in
  x86_64)
    ARCH="amd64"
    ;;
  aarch64)
    ARCH="arm64"
    ;;
  *) die "unknown arch: ${arch}" ;;
  esac
}

# check if package file was provided
validate_package() {
  if [ -n "$PACKAGE_FILE" ]; then
    log_info "[+] Validating package"
    if [ -f "$PACKAGE_FILE" ]; then
      cp -f "$PACKAGE_FILE" "$HUNTRESS_PKG"
    else
      die "$PACKAGE_FILE was not found"
    fi
  else
    log_info "[+] Downloading latest package"
    download_latest
  fi
}

test_url() {
  # use curl if installed
  if [ "$CURL_INSTALLED" = true ]; then
    if curl -s -o /dev/null "$1"; then
      return 0 # success
    fi
  elif [ "$WGET_INSTALLED" = true ]; then
    wget --spider --quiet "$1" || local exit_code=$?
    exit_code=${exit_code:-0}

    # return code 8 connection succeeded, but the server returned a non-200 status
    if [ $exit_code -eq 0 ] || [ $exit_code -eq 8 ]; then
      return 0 # success
    fi
  fi

  die "CONNECTION FAILURE: Unable to reach $1"
}

# Check minimum requirements
validate_requirements() {
  log_info "[+] Validating requirements"

  # Kernel version must be 5.14 or higher
  version_check() {
      return "$(uname -r | awk -F '.' '{ if ($1 < 5) { print 1; } else if ($1 == 5) { if ($2 < 14) { print 1; } else { print 0; } } else { print 0; } }')"
  }
  if ! version_check; then
    die "REQUIREMENT FAILURE: Huntress requires a Linux kernel version of 5.14 or higher"
  fi

  # Systemd
  if [ "$(ps -p 1 -o comm=)" != "systemd" ]; then
    die "REQUIREMENT FAILURE: Systemd is required for the Huntress Agent"
  fi

  # Curl or wget
  CURL_INSTALLED=false
  WGET_INSTALLED=false
  if [ "$(which curl)" ]; then
    CURL_INSTALLED=true
  fi
  if [ "$(which wget)" ]; then
    WGET_INSTALLED=true
  fi
  if [ "$CURL_INSTALLED" = false ] && [ "$WGET_INSTALLED" = false ]; then
    die "REQUIREMENT FAILURE: curl or wget needs to be installed"
  fi

  test_url "https://huntress.io"
  test_url "https://s3.amazonaws.com"
  test_url "https://huntresscdn.com"
  test_url "https://bugsnag.com"
}

# Install
install_pkg() {
  log_info "[+] Unpacking installer"
  tar -zxf "${HUNTRESS_PKG}" -C / || die "Failed to unpack tar"

  # configure the agent
  $huntress_agent configure \
    -account-key "${ACCOUNT_KEY}" \
    -organization-key "${ORG_KEY}" \
    -tags "${TAGS}" \
    -api-url "${API_URL}" \
    -eetee-url "${EETEE_URL}" || die "Configuration Failed."
  log_info "[+] Configured agent with given settings"

  # install the services
  log_info "[+] Installing Huntress Services"
  $huntress_agent install || die "Failed installing huntress-agent service"
  $huntress_updater install || die "Failed installing huntress-updater service"

  # start the services
  log_info "[+] Starting Huntress Services"
  $huntress_agent start || die "Failed to start huntress-agent service"
  $huntress_updater start || die "Failed to start huntress-updater service"
}

if [ $# -eq 0 ]; then
  usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
  -a | --account_key)
    ACCOUNT_KEY="$2"
    shift
    shift
    ;;
  --batch_only)
    INTERACTIVE=0
    shift
    ;;
  -o | --organization_key)
    ORG_KEY="$2"
    shift
    shift
    ;;
  -t | --tags)
    TAGS="$2"
    shift
    shift
    ;;
  -h | --help)
    usage
    exit
    ;;
  # these are more or less hidden options. Only used for debugging
  -f | --package-file)
    PACKAGE_FILE="$2"
    shift
    shift
    ;;
  -p | --portal_url | --portal-url)
    PORTAL_URL="$2"
    shift
    shift
    ;;
  -u | --api_url | --api-url)
    API_URL="$2"
    shift
    shift
    ;;
  --eetee_url | --eetee-url)
    EETEE_URL="$2"
    shift
    shift
    ;;
  *)
    ARGS+=("$1")
    shift
    ;;
  esac
done

set -- "${ARGS[@]}"

log_info " ---- Installing Huntress EDR for Linux | script version: ${SCRIPT_VERSION} ---- "
get_host_info
validate_requirements
validate_package
get_user_creds
install_pkg
log_info " ---- Finished Installing Huntress EDR for Linux | script version: ${SCRIPT_VERSION} ---- "
