#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-event-subscription.sh [-h]
       get-event-subscription.sh [-a appliance] [-B cabundle] [-v version]
                                 [-t accesstoken] [-i subscriptionid] [-q filter]
                                 [-f fields]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -i  Subscription ID for a specific subscription (optional)
  -q  Query filter (SCIM-style, e.g. "Type eq 'SignalR'")
  -f  Comma-separated list of fields to return (e.g. Id,Type,Description)

List all event subscriptions or get a specific one by ID. By default, system-owned
subscriptions are excluded; use -q to override filtering.

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
Filter=
Fields=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
}

while getopts ":a:B:v:t:i:q:f:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    i) SubId=$OPTARG ;;
    q) Filter=$OPTARG ;;
    f) Fields=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

if [ -n "$SubId" ]; then
    Url="EventSubscribers/$SubId"
    if [ -n "$Fields" ]; then
        Url="${Url}?fields=$Fields"
    fi
else
    Url="EventSubscribers"
    QueryParams=""
    # Default: exclude system-owned unless user provides their own filter
    if [ -n "$Filter" ]; then
        QueryParams="filter=$(printf '%s' "$Filter" | sed 's/ /%20/g')"
    else
        QueryParams="filter=IsSystemOwned%20eq%20false"
    fi
    if [ -n "$Fields" ]; then
        [ -n "$QueryParams" ] && QueryParams="${QueryParams}&"
        QueryParams="${QueryParams}fields=$Fields"
    fi
    if [ -n "$QueryParams" ]; then
        Url="${Url}?${QueryParams}"
    fi
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m GET -U "$Url" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error getting event subscription:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
