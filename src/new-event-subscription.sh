#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: new-event-subscription.sh [-h]
       new-event-subscription.sh [-a appliance] [-B cabundle] [-v version]
                                 [-t accesstoken] [-b body]
       new-event-subscription.sh [-a appliance] [-B cabundle] [-v version]
                                 [-t accesstoken] [-D description] [-e events]
                                 [-T type] [-U userid]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -b  JSON body for the subscription (overrides individual flags)
  -D  Description of the subscription
  -e  Comma-separated list of event names to subscribe to (e.g. "UserCreated,UserDeleted")
  -T  Subscription type: SignalR (default), Email, SNMP, Syslog
  -U  User ID to subscribe (defaults to current user for SignalR)

Create a new event subscription in Safeguard. Event subscriptions configure
notifications when specific events occur.

Subscription types:
  SignalR  - Real-time push via SignalR (use with listen-for-event.sh)
  Email    - Email notifications
  SNMP     - SNMP trap notifications
  Syslog   - Syslog notifications

For advanced configuration (SNMP/Syslog properties, object scoping), use -b
with a full JSON body.

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
Body=
Description=
Events=
Type=SignalR
UserId=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
}

while getopts ":a:B:v:t:b:D:e:T:U:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    b) Body=$OPTARG ;;
    D) Description=$OPTARG ;;
    e) Events=$OPTARG ;;
    T) Type=$OPTARG ;;
    U) UserId=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

if [ -z "$Body" ]; then
    # Build body from individual flags
    Subscriptions="[]"
    if [ -n "$Events" ]; then
        Subscriptions=$(echo "$Events" | tr ',' '\n' | jq -R '.' | jq -s '[ .[] | {Name: .} ]')
    fi
    Body=$(jq -n \
        --arg type "$Type" \
        --argjson subs "$Subscriptions" \
        '{Type: $type, Subscriptions: $subs}')
    if [ -n "$Description" ]; then
        Body=$(echo "$Body" | jq --arg desc "$Description" '.Description = $desc')
    fi
    if [ -n "$UserId" ]; then
        Body=$(echo "$Body" | jq --argjson uid "$UserId" '.UserId = $uid')
    fi
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m POST -U "EventSubscribers" -b "$Body" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error creating event subscription:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
