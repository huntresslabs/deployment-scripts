# Check system extension status
output=$(/Applications/Huntress.app/Contents/MacOS/Huntress extensionctl status)

# If this is not working as expected, you may need to prepend sudo. Delete the above and uncomment the following line
#output=$(sudo /Applications/Huntress.app/Contents/MacOS/Huntress extensionctl status)

# Check if extension installed
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
