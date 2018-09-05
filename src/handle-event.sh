#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: $1 [-h]
       $1 [-a appliance] [-t accesstoken] [-E eventname] [-S script]
       $1 [-a appliance] [-i provider] [-u user] [-p] [-E eventname] [-S script]
       $1 [-a appliance] -i certificate [-c file] [-k file] [-p] [-E eventname] [-S script]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -i  Safeguard identity provider, examples: certificate, local, ad<num>
  -u  Safeguard user to use
  -c  File containing client certificate
  -k  File containing client private key
  -p  Read Safeguard or certificate password from stdin
  -E  Event name to process
  -S  Script to execute when the password changes

Connect to SignalR using the Safeguard event service via a Safeguard access token
and execute a provided script (handler script) each time an event occurs passing 
the details of the event as a JSON object string to stdin.  The handler script will
actually be passed three lines of text:

    <Appliance Network Address>
    <Access Token>
    <Event Data as JSON string>

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

LoginType=
TokenIsValid=false
TokenIsExpiring=false
TokenExpirationThreshold=0
Appliance=
Version=2
AccessToken=
Provider=
User=
Cert=
PKey=
Pass=
EventName=
HandlerScript=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    if [ ! -z "$AccessToken" ]; then
        LoginType="Token"
        # Use this function to make sure that -a and -t are set
        require_login_args
    elif [ "$Provider" = "certificate" ]; then
        LoginType="Certificate"
        require_connect_args
    else
        LoginType="Password"
        require_connect_args
    fi
    if [ -z "$EventName" ]; then
        read "Event Name: " EventName
    fi
    if [ -z "$HandlerScript" ]; then
        read "Handler Script: " HandlerScript
    fi
}

require_prereqs()
{
    if [ -z "$(which jq)" ]; then
        >&2 echo "This script requires the jq utility for parsing JSON response data from Safeguard"
        exit 1
    fi
    if ! grep -q coproc <(compgen -c); then
        >&2 echo "This script requires a version of bash that supports coproc"
        exit 1
    fi
    if [ ! -x "$HandlerScript" ]; then
        >&2 echo "The handler script passed to -S option must be executable"
        exit 1
    fi
}

check_access_token()
{
    local Url="https://$Appliance/service/core/v$Version/LoginMessage"
    local ResponseCode=$(curl -s -k -o /dev/null -w "%{http_code}" -X GET -H "Accept: application/json" -H "Authorization: Bearer $AccessToken" "$Url")
    if [ $ResponseCode -eq 200 ]; then
        >&2 echo "[$(date '+%x %X')] Access token is still valid."
        TokenIsValid=true
        local Now=$(date +%s)
        local MinutesRemaining=$(curl -s -k -i -X GET -H "Accept: application/json" -H "X-TokenLifetimeRemaining" -H "Authorization: Bearer $AccessToken" "$Url" \
                                     | grep X-TokenLifetimeRemaining | cut -d' ' -f2 | tr -d '\r')
        TokenExpirationThreshold=$(($MinutesRemaining*60+$Now-120))
        >&2 echo "[$(date '+%x %X')] Access token timeout / refresh is set to $((TokenExpirationThreshold-Now)) seconds from now."
    else
        >&2 echo "[$(date '+%x %X')] Access token is NOT valid!"
        TokenIsValid=false
        TokenExpirationThreshold=0
    fi
}

connect()
{
    case $LoginType in
    Token)
        check_access_token
        if ! $AccessTokenIsValid; then
            # can't reconnect
            >&2 echo "[$(date '+%x %X')] Initial login was using an access token.  Cannot reconnect if access token is no longer valid."
            exit 1
        fi
        ;;
    Password)
        AccessToken=$("$ScriptDir/connect-safeguard.sh" -a "$Appliance" -i "$Provider" -u "$User" -p -X <<< "$Pass")
        check_access_token
        if ! $AccessTokenIsValid; then
            >&2 echo "[$(date '+%x %X')] Unable to establish access token using certificate."
            exit 1
        fi
        ;;
    Certificate)
        AccessToken=$("$ScriptDir/connect-safeguard.sh" -a "$Appliance" -i certificate -c "$Cert" -k "$PKey" -p -X <<< "$Pass")
        check_access_token
        if ! $AccessTokenIsValid; then
            >&2 echo "[$(date '+%x %X')] Unable to establish access token using username and password."
            exit 1
        fi
        ;;
    esac
}

cleanup()
{
    if [ ! -z "$listener_PID" ] && kill -0 $listener_PID 2> /dev/null; then
        kill $listener_PID 2> /dev/null
        wait $listener_PID 2> /dev/null
        >&2 echo "[$(date '+%x %X')] Killed listener coprocess PID=$listener_PID"
    fi
}

trap cleanup EXIT

while getopts ":a:t:i:u:c:k:E:S:ph" opt; do
    case $opt in
    a)
        Appliance=$OPTARG
        ;;
    t)
        AccessToken=$OPTARG
        ;;
    i)
        Provider=$OPTARG
        ;;
    u)
        User=$OPTARG
        ;;
    c)
        Cert=$OPTARG
        ;;
    k)
        PKey=$OPTARG
        ;;
    p)
        # read password from stdin before doing anything
        read -s Pass
        ;;
    E)
        EventName=$OPTARG
        ;;
    S)
        HandlerScript=$OPTARG
        ;;
    h)
        print_usage $0
        ;;
    esac
done

require_args
require_prereqs

StartTime=$(date +%s)
while true; do
    Now=$(date +%s)
    if ! $AccessTokenIsValid || [ $Now -gt $TokenExpirationThreshold ]; then
        connect
    fi
    if [ -z "$listener_PID" ] || ! kill -0 $listener_PID 2> /dev/null; then
        if [ ! -z "$listener_PID" ]; then
            wait $listener_PID
            unset listener_PID
        fi
        coproc listener { 
            "$ScriptDir/listen-for-event.sh" -a $Appliance -t $AccessToken | \
                jq --unbuffered -c ".M[]?.A[]? | select(.Name==\"$EventName\") | .Data?"
        }
        >&2 echo "[$(date '+%x %X')] Started listener coprocess PID=$listener_PID."
    fi
# TODO: handle timeouts of not reading anything for a long period and restart coproc
    unset Output
    IFS= read -t 5 Temp <&"${listener[0]}" && Output="$Temp"
    if [ ! -z "$Output" ]; then
        >&2 echo "[$(date '+%x %X')] Calling $HandlerScript with $EventName"
        $HandlerScript <<EOF
$Appliance
$AccessToken
$Output
EOF
    fi
done
