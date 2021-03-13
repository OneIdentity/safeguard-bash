#!/bin/bash

# This script is meant to be run from within a fresh safeguard-bash Docker container
if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

# Handle script parameters and usage
print_usage()
{
    cat <<EOF
USAGE: sample-event-listener.sh [-h] [-a appliance] [-i provider] [-u username] [-E eventname]

  -a  Network address of the appliance
  -i  Safeguard identity provider, examples: certificate, local, ad<num> (default: local)
  -u  Safeguard user to use (default: Admin)
  -E  Event name to process

EOF
    exit 0
}

while getopts ":a:i:u:E:h" opt; do
    case $opt in
    a)
        Appliance=$OPTARG
        ;;
    i)
        Provider=$OPTARG
        ;;
    u)
        User=$OPTARG
        ;;
    E)
        EventName=$OPTARG
        ;;
    h)
        print_usage
        ;;
    esac
done

# Get the directory of this script while executing
ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get the directory of the rest of safeguard-bash (may be same directory)
if [ -x "$ScriptDir/connect-safeguard.sh" ]; then
    SafeguardDir="$ScriptDir"
elif [ -x "../../../src/connect-safeguard.sh" ]; then
    SafeguardDir="$( cd ../../../src && pwd )"
elif [ -x "/scripts/connect-safeguard.sh" ]; then
    SafeguardDir="$( cd /scripts && pwd )"
else
    cat <<EOF
Unable to find the safeguard-bash scripts.
The best way to run this sample is from a safeguard-bash docker container.
EOF
    exit 1
fi

if [ -z "$Appliance" ]; then
   read -p "Appliance network address: " Appliance 
fi
if [ -z "$Provider" ]; then
    Provider="local"
fi
if [ -z "$User" ]; then
    User="Admin"
fi
if [ -z "$EventName" ]; then
   read -p "Event name: " EventName 
fi

echo "User=$Provider\\$User"
echo "Use Ctrl-C to quit..."
$SafeguardDir/handle-event.sh -a $Appliance -i $Provider -u $User -E $EventName -S $SafeguardDir/../samples/event-handling/generic-event-handling/generic-event-handler.sh

