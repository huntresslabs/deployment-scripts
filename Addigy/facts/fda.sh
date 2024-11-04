fda_enabled="kTCCServiceSystemPolicyAllFiles"

out=$(sqlite3 -line "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT * FROM access where client == 'com.huntress.app';" | grep service | awk '{print $3}')
if [[ $out != "kTCCServiceSystemPolicyAllFiles" ]]; then
    echo "No - com.huntress.app does not have Full Disk Access"
    exit
fi

out=$(sqlite3 -line "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT * FROM access where client == 'com.huntress.sysext';" | grep service | awk '{print $3}')
if [[ $out != "kTCCServiceSystemPolicyAllFiles" ]]; then
    echo "No - com.huntress.sysext does not have Full Disk Access"
    exit
fi

echo "Yes"