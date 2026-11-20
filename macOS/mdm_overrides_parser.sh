#!/usr/bin/env zsh

bundle_ids=("com.huntress.app" "com.huntress.sysext" "com.huntress.HuntressAgent") # bundle_ids=("bundle_id_1" "bundle_id_2")

## Using logger function to provide helpful logs within RMM tools in addition to log file
logger() {
    echo "$dd -- $*";
    echo "$dd -- $*" >> $log_file;
}

dd=$(date "+%Y%m%d-%H%M%S")
version_date="March 28, 2025"
version="1.0"
log_file="/tmp/overrides_parser.log"

logger "Script last updated $version_date"

#Check for root
if [ $EUID -ne 0 ]; then
    logger "This script must be run as root, exiting..."
    exit 1
fi


logger "======== SCRIPT START AT $dd ============"
logger "======== Script | Version: $version ============"


plistbuddy_helper() {
	# Helper function to interact with plists.
	# All options utilize the "-c" option (non-interactive mode).
	# All options except a file path to be passed _except_ for the action "print_stdin"
	# Arguments
	# $1 = (str) action to perform on the plist; Supported options are:
		# "print_xml" - returns xml formatted text
		# "print_stdin" - expects to work with xml formatted text (passed to PlistBuddy via stdin)
		# "print" - returns PlistBuddy's standard descriptive text format, optionally provide a key
		# "read" - returns the specified key's value
		# "add" - add or set values for a specified key, optionally provide a the key's type
		# "delete" - delete the specified key/value pair
		# "clear" - clear the value for a specified key
	# $2 = (str) Path to plist or generated xml
	# $3 = (str) Key or key path to read
	# $4 = (str) Type that will be used for the value
	# $5 = (str) Value to be set to the passed key
	local action="${1}"
	local plist="${2}"
	local key="${3}"
	local type="${4}"
	local value="${5}"

	case "${action}" in
		"print_xml" )
			# Dump plist file as XML
			/usr/libexec/PlistBuddy -x -c "Print" "${plist}"
		;;
		"print_stdin" )
			# Read plist "str" (as a heredoc) and print the passed key
			/usr/libexec/PlistBuddy -c "Print :${key}" /dev/stdin <<< "${plist}" 2> /dev/null || \
			/usr/libexec/PlistBuddy -c "Print" /dev/stdin <<< "${plist}" 2> /dev/null
		;;
		"print" )
			# Read a key (leaving for previous function revision support)
			/usr/libexec/PlistBuddy -c "Print :'${key}'" "${plist}" 2> /dev/null || \
			# Print the entire plist file
			/usr/libexec/PlistBuddy -c "Print" "${plist}"
		;;
		"read" )
			# Read a key
			/usr/libexec/PlistBuddy -c "Print :'${key}'" "${plist}" 2> /dev/null
		;;
		"add" )
			# Configure values
			/usr/libexec/PlistBuddy -c "Add :${key} ${type} ${value}" "${plist}" > /dev/null 2>&1 \
			|| /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "${plist}" > /dev/null 2>&1
		;;
		"delete" )
			# Delete a key
			/usr/libexec/PlistBuddy -c "Delete :${key} ${type}" "${plist}" > /dev/null 2>&1
		;;
		"clear" )
			# Clear a key's value
			/usr/libexec/PlistBuddy -c "clear ${type}" "${plist}" > /dev/null 2>&1
		;;
	esac
}

parse_mdm_overrides() {

	if [[ -z "${bundle_ids}" ]]; then
    logger "No Bundle ID provided. Please provide as array on line 3" 
    exit 1
  fi

	mdm_overrides_path="/Library/Application Support/com.apple.TCC/MDMOverrides.plist"

	if [[ -e "${mdm_overrides_path}" ]]
	then
		tcc_mdm_db=$( plistbuddy_helper "print_xml" \
		"/Library/Application Support/com.apple.TCC/MDMOverrides.plist" )

		for id in "${bundle_ids[@]}"
		do
			mdm_fda_enabled=$( plistbuddy_helper "print_stdin" "${tcc_mdm_db}" \
				"${id}:kTCCServiceSystemPolicyAllFiles:Allowed" )

			if [ "${mdm_fda_enabled}" = "true" ]; then
				result="Approved"
			elif [ "${mdm_fda_enabled}" = "false" ]; then
				result="Denied"
			else
				logger "$id: Unknown Bundle ID"
				continue
			fi

			logger "Bundle ID: $id"
			logger "Status: $result"
		done

	else
		logger "===========  No MDMOverrides - Check TCC database for permissions not provisioned by an MDM ==========="
	fi
}

parse_mdm_overrides

logger "======== SCRIPT FINISHED AT $dd ============"
exit
