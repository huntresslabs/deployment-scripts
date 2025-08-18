#!/usr/bin/env bash
# Copyright 2025 Huntress Labs, Inc. All rights reserved.
#
# Unauthorized copying of this file, via any medium is strictly prohibited
# without the express written consent of Huntress Labs, Inc.

set -euo pipefail

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
  status_code=$(curl -f -L -o "${HUNTRESS_PKG}" -w "%{http_code}" \
    "${PORTAL_URL}/download/linux/${ACCOUNT_KEY}?arch=${ARCH}")

  if [ $? != 0 ]; then
    if [ "$status_code" = "400" ]; then
      die "Account Key not valid."
    elif [ "$status_code" = "404" ]; then
      die "File not found on S3."
    elif [ "$status_code" = "409" ]; then
      die "The Linux Beta has not been enabled for this account."
    fi
  elif ! [ -f "$HUNTRESS_PKG" ]; then
    die "File download failed."
  fi
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
validate_package
get_user_creds
install_pkg
log_info " ---- Finished Installing Huntress EDR for Linux | script version: ${SCRIPT_VERSION} ---- "
