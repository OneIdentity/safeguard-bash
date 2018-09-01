#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: $1 [-h]
       $1 [-a appliance] [-t accesstoken] [-E eventname] [-S script]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -E  Event name to process
  -S  Script to execute when the password changes

Connect to SignalR using the Safeguard event service via a Safeguard access token
and execute a provided script each time an event occurs passing the details of the
event as an object stdin

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


Appliance=
AccessToken=
EventName=
HandlerScript=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
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

cleanup()
{
    if [ ! -z "$listener_PID" ] && kill -0 $listener_PID 2> /dev/null; then
        >&2 echo "Killing coprocess $listener_PID"
        kill $listener_PID
        wait $listener_PID 2> /dev/null
    fi
}

trap cleanup EXIT

while getopts ":a:t:E:S:ph" opt; do
    case $opt in
    a)
        Appliance=$OPTARG
        ;;
    t)
        AccessToken=$OPTARG
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
        coproc listener { 
            "$ScriptDir/listen-for-event.sh" -a $Appliance -t $AccessToken | \
                jq --unbuffered -c ".M[]?.A[]? | select(.Name==\"$EventName\") | .Data?"
        }
    fi
    unset Output
    IFS= read -t 5 Temp <&"${listener[0]}" && Output="$Temp"
    if [ ! -z "$Output" ]; then
        $HandlerScript <<< "$Output"
    fi
done
