#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-event-category.sh [-h]
       get-event-category.sh [-a appliance] [-B cabundle] [-v version]
                             [-t accesstoken] [-T objecttype]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -T  Filter by object type (e.g. User, Asset, AssetAccount)

Get the unique categories of subscribable events in Safeguard. Returns a sorted
list of category names. Optionally filter by object type to see only categories
relevant to that type.

EXAMPLES:
  get-event-category.sh
  get-event-category.sh -T AssetAccount

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

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
}

while getopts ":a:B:v:t:T:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    T) ObjectType=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m GET -U "Events?fields=Name,Category,ObjectType" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error retrieving event categories:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

if [ -n "$ObjectType" ]; then
    echo "$Result" | jq -r --arg t "$ObjectType" \
        '[.[] | select(.ObjectType != null and (.ObjectType | ascii_downcase) == ($t | ascii_downcase)) | .Category] | unique | .[]'
else
    echo "$Result" | jq -r '[.[].Category] | unique | .[]'
fi
