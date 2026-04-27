#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: find-event-subscription.sh [-h]
       find-event-subscription.sh [-a appliance] [-B cabundle] [-v version]
                                  [-t accesstoken] [-Q searchtext] [-q filter]
                                  [-f fields]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -Q  Text to search for across all string fields
  -q  Query filter (SCIM-style, e.g. "Type eq 'SignalR'")
  -f  Comma-separated list of fields to return (e.g. Id,Type,Description)

Search for event subscriptions by text or filter. Use -Q for free-text search
across all string fields, or -q for structured SCIM-style filtering.

EXAMPLES:
  find-event-subscription.sh -Q "password"
  find-event-subscription.sh -q "Type eq 'SignalR'" -f "Id,Type,Description"

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
SearchText=
Filter=
Fields=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
}

while getopts ":a:B:v:t:Q:q:f:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    Q) SearchText=$OPTARG ;;
    q) Filter=$OPTARG ;;
    f) Fields=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

Url="EventSubscribers"
QueryParams=""
if [ -n "$SearchText" ]; then
    QueryParams="q=$(printf '%s' "$SearchText" | sed 's/ /%20/g')"
elif [ -n "$Filter" ]; then
    QueryParams="filter=$(printf '%s' "$Filter" | sed 's/ /%20/g')"
fi
if [ -n "$Fields" ]; then
    [ -n "$QueryParams" ] && QueryParams="${QueryParams}&"
    QueryParams="${QueryParams}fields=$Fields"
fi
if [ -n "$QueryParams" ]; then
    Url="${Url}?${QueryParams}"
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m GET -U "$Url" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error searching event subscriptions:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
