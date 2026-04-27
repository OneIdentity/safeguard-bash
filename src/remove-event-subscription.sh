#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: remove-event-subscription.sh [-h]
       remove-event-subscription.sh [-a appliance] [-B cabundle] [-v version]
                                    [-t accesstoken] -i subscriptionid

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -i  Subscription ID to remove (required)

Remove an event subscription from Safeguard by ID.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
SubId=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$SubId" ]; then
        read -p "Subscription ID: " SubId
    fi
}

while getopts ":a:B:v:t:i:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    i) SubId=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m DELETE -U "EventSubscribers/$SubId" 2>/dev/null)

if [ -n "$Result" ]; then
    Error=$(echo "$Result" | jq .Code 2>/dev/null)
    if [ -n "$Error" -a "$Error" != "null" ]; then
        >&2 echo "Error removing event subscription:"
        echo "$Result" | jq . 2>/dev/null || echo "$Result"
        exit 1
    fi
fi
