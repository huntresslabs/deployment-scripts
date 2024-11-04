#!/bin/zsh
declare -a HuntressDaemons=("HuntressAgent" "HuntressUpdater" "Huntress")

for i in "${HuntressDaemons[@]}"; do 
  pgrep -x "$i" >/dev/null
  daemon_status=$?
  if [ "$daemon_status" != "0" ]; then
    echo "No - Service $i is not running"
    exit
  fi
done;

if [ ! -d "/Library/Application Support/Huntress" ]; then
    echo "No - App Support Dir missing"
    exit
fi

echo "Yes"