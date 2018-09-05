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
        >&2 echo "The handler script passed to -S option must be executable and receive password as stdin"
        exit 1
    fi
}

check_access_token()
{
    local Url="https://$Appliance/service/core/v$Version/LoginMessage"
    local ResponseCode=$(curl -s -k -o /dev/null -w "%{http_code}" -X GET -H "Accept: application/json" -H "Authorization: Bearer $AccessToken" "$Url")
    if [ $ResponseCode -eq 200 ]; then
        TokenIsValid=true
    else
        TokenIsValid=false
    fi
}

connect()
{
    case $LoginType in
    Token)
        # can't reconnect
        >&2 echo "Initial login was using an access token.  Cannot reconnect if access token is no longer valid."
        exit 1
        ;;
    Certificate)
        AccessToken=$("$ScriptDir/connect-safeguard.sh" -a "$Appliance" -i "$Provider" -u "$User" -p -X <<< "$Pass")
        ;;
    Password)
        AccessToken=$("$ScriptDir/connect-safeguard.sh" -a "$Appliance" -i certificate -c "$Cert" -k "$PKey" -p -X <<< "$Pass")
        ;;
    esac
}

cleanup()
{
    if [ ! -z "$listener_PID" ] && kill -0 $listener_PID 2> /dev/null; then
        >&2 echo "Killing coprocess $listener_PID"
        kill $listener_PID
        wait $listener_PID 2> /dev/null
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

while true; do
    if [ -z "$listener_PID" ] || ! kill -0 $listener_PID 2> /dev/null; then
        if [ ! -z "$listener_PID" ]; then
            wait $listener_PID
            unset listener_PID
        fi
        if [ -z "$AccessToken" ]; then
            check_access_token
        fi
        if ! $AccessTokenIsValid; then
            connect
        fi
        coproc listener { 
            "$ScriptDir/listen-for-event.sh" -a $Appliance -t $AccessToken | \
                jq --unbuffered -c ".M[]?.A[]? | select(.Name==\"$EventName\") | .Data?"
        }
    fi
# TODO: handle timeouts of not reading anything for a long period and restart coproc
# TODO: check the access token and fetch a new one if it is running out of time
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
