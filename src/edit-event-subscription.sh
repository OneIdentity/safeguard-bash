#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: edit-event-subscription.sh [-h]
       edit-event-subscription.sh [-a appliance] [-B cabundle] [-v version]
                                  [-t accesstoken] -i subscriptionid [-b body]
       edit-event-subscription.sh [-a appliance] [-B cabundle] [-v version]
                                  [-t accesstoken] -i subscriptionid
                                  [-D description] [-e events] [-T type]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -i  Subscription ID to edit (required)
  -b  Full JSON body to PUT (replaces the entire subscription object)
  -D  Update description
  -e  Replace subscribed events (comma-separated event names)
  -T  Update subscription type (SignalR, Email, SNMP, Syslog)

Edit an existing event subscription using GET-modify-PUT. When using individual
flags, the current subscription is fetched and only the specified fields are
modified. Use -b to replace the entire object.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq for JSON processing."
    exit 1
fi

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
SubId=
Body=
Description=
Events=
Type=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$SubId" ]; then
        read -p "Subscription ID: " SubId
    fi
}

while getopts ":a:B:v:t:i:b:D:e:T:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    i) SubId=$OPTARG ;;
    b) Body=$OPTARG ;;
    D) Description=$OPTARG ;;
    e) Events=$OPTARG ;;
    T) Type=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

if [ -z "$Body" ]; then
    # Fetch current object and modify
    Body=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
        -v "$Version" -s core -m GET -U "EventSubscribers/$SubId" 2>/dev/null)
    Error=$(echo "$Body" | jq .Code 2>/dev/null)
    if [ -n "$Error" -a "$Error" != "null" ]; then
        >&2 echo "Error fetching subscription for edit:"
        echo "$Body" | jq . 2>/dev/null || echo "$Body"
        exit 1
    fi
    if [ -n "$Description" ]; then
        Body=$(echo "$Body" | jq --arg val "$Description" '.Description = $val')
    fi
    if [ -n "$Type" ]; then
        Body=$(echo "$Body" | jq --arg val "$Type" '.Type = $val')
    fi
    if [ -n "$Events" ]; then
        Subscriptions=$(echo "$Events" | tr ',' '\n' | jq -R '.' | jq -s '[ .[] | {Name: .} ]')
        Body=$(echo "$Body" | jq --argjson subs "$Subscriptions" '.Subscriptions = $subs')
    fi
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m PUT -U "EventSubscribers/$SubId" -b "$Body" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error editing event subscription:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
