#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-event-property.sh [-h]
       get-event-property.sh [-a appliance] [-B cabundle] [-v version]
                             [-t accesstoken] -n eventname

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -n  Event name (required, e.g. UserCreated, AssetModified)

Get the properties that will be included in notifications for a specific event.
Returns the Properties array from the event definition, showing what data
subscribers will receive when this event fires.

EXAMPLES:
  get-event-property.sh -n UserCreated
  get-event-property.sh -n AssetModified

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq for processing event data."
    exit 1
fi

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
EventName=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$EventName" ]; then
        read -p "Event Name: " EventName
    fi
}

while getopts ":a:B:v:t:n:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    n) EventName=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m GET -U "Events/$EventName" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error retrieving event properties:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result" | jq '[.Properties | sort_by(.Name) | .[] | {Name, Description}]'
