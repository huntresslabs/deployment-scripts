#!/bin/zsh

# Checks the system extension status for versions of the agent before 0.14.32
check_legacy_status() {
  output=$(/Applications/Huntress.app/Contents/MacOS/Huntress extensionctl status)

  if [[ $output != *"Extension Status: installed"* ]]; then
    echo "No - Extension Not Installed";
    exit
  fi

  if [[ $output != *"Full Disk Access for Extension: enabled"* ]]; then
    echo "No - Full Disk Access not granted for Extension"
    exit
  fi;

  if [[ $output != *"EDR: enabled"* ]]; then
    echo "No - EDR is not Enabled"
    exit
  fi;

  if [[ $output != *"Preauthorization Status: granted"* ]]; then
    echo "No - Preauthorization not granted"
    exit
  fi

  echo "Yes"
}

# Checks the system extension status for the agent versions 0.14.32 and later
check_status() {
  output=$(/Applications/Huntress.app/Contents/MacOS/Huntress status)

  if ! [[ $output =~ "Extension Status:.*installed" ]]; then
    echo "No - Extension Not Installed";
    exit
  fi

  if ! [[ $output =~ "Full Disk Access for Extension:.*true" ]]; then
    echo "No - Full Disk Access not granted for Extension"
    exit
  fi;

  if ! [[ $output =~ "EDR status:.*enabled" ]]; then
    echo "No - EDR is not Enabled"
    exit
  fi;

  if ! [[ $output =~ "Preauthorization Status:.*granted" ]]; then
    echo "No - Preauthorization not granted"
    exit
  fi

  echo "Yes"
}

agent_version=$(plutil -extract CFBundleVersion raw /Applications/Huntress.app/Contents/Info.plist)
version_fields=( ${(s[.])agent_version} )

if ((
  $version_fields[1] > 0 ||
    $version_fields[2] > 14 ||
    ( $version_fields[2] == 14 && $version_fields[3] >= 32 )
)); then
  check_status
else
  check_legacy_status
fi
