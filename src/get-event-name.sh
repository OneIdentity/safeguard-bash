#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-event-name.sh [-h]
       get-event-name.sh [-a appliance] [-B cabundle] [-v version]
                         [-t accesstoken] [-T objecttype] [-C category]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -T  Filter by object type (e.g. User, Asset, AssetAccount, A2AService)
  -C  Filter by category (e.g. ObjectHistory, UserAuthentication)

Get the names of subscribable events in Safeguard. Returns a sorted list of
event names that can be used with new-event-subscription.sh or listen-for-event.sh.

Optionally filter by object type (-T) or category (-C) to narrow the results.

EXAMPLES:
  get-event-name.sh
  get-event-name.sh -T User
  get-event-name.sh -C UserAuthentication

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
ObjectType=
Category=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
}

while getopts ":a:B:v:t:T:C:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    T) ObjectType=$OPTARG ;;
    C) Category=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m GET -U "Events?fields=Name,Category,ObjectType" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error retrieving event names:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

if [ -n "$ObjectType" ]; then
    echo "$Result" | jq -r --arg t "$ObjectType" \
        '[.[] | select(.ObjectType != null and (.ObjectType | ascii_downcase) == ($t | ascii_downcase)) | .Name] | sort | .[]'
elif [ -n "$Category" ]; then
    echo "$Result" | jq -r --arg c "$Category" \
        '[.[] | select(.Category != null and (.Category | ascii_downcase) == ($c | ascii_downcase)) | .Name] | sort | .[]'
else
    echo "$Result" | jq -r '[.[].Name] | sort | .[]'
fi
