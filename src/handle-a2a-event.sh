#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: $1 [-h]
       $1 [-a appliance] [-v version] [-c file] [-k file] [-A apikey] [-S script] [-p]

  -h  Show help and exit
  -a  Network address of the appliance
  -v  Web API Version: 2 is default
  -c  File containing client certificate
  -k  File containing client private key
  -A  A2A API token identifying the account
  -S  Script to execute when the password changes
  -p  Read certificate password from stdin

Connect to SignalR using the Safeguard A2A service for a particular account via the apikey
and execute a provided script each time the password changes passing it into stdin

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


Appliance=
Version=2
Cert=
PKey=
ApiKey=
HandlerScript=
PassStdin=
Pass=

#. "$ScriptDir/utils/a2a.sh"

require_args()
{
    if [ -z "$Appliance" ]; then
        read -p "Appliance Network Address: " Appliance
    fi
    if [ -z "$Cert" ]; then
        read -p "Client Certificate File: " Cert
    fi
    if [ -z "$PKey" ]; then
        read -p "Client Private Key File: " PKey
    fi
    if [ -z "$Pass" ]; then
        read -s -p "Private Key Password: " Pass
        >&2 echo
    fi
    if [ -z "$ApiKey" ]; then
        read -p "A2A API Key: " ApiKey
    fi
    if [ -z "$HandlerScript" ]; then
        read -p "Handler Script: " HandlerScript
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
    if [ -z "$listener_PID" ] || kill -0 $listener_PID 2> /dev/null; then
        >&2 echo "Killing coprocess $listener_PID"
        kill $listener_PID
        wait $listener_PID 2> /dev/null
    else
        >&2 echo "Nothing to clean up"
    fi
}

trap cleanup EXIT

while getopts ":a:v:c:k:A:S:ph" opt; do
    case $opt in
    a)
        Appliance=$OPTARG
        ;;
    v)
        Version=$OPTARG
        ;;
    c)
        Cert=$OPTARG
        ;;
    k)
        PKey=$OPTARG
        ;;
    p)
        PassStdin="-p"
        ;;
    A)
        ApiKey=$OPTARG
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
    if [ -z "$listener_PID" ] || kill -0 $listener_PID 2> /dev/null; then
        if [ ! -z "$listener_PID" ]; then
            wait $listener_PID
            unset listener_PID
        fi
        coproc listener { 
            echo "listener script is running..."
            sleep 1
        }
    fi
    unset Output
    IFS= read -t 5 Temp <&"${listener[0]}" && Output="$Temp"
    echo "$Output"
done


#Result=$(invoke_a2a_method "$Appliance" "$Cert" "$PKey" "$Pass" "$ApiKey" GET "Credentials?type=Password" $Version "$Body")
#Error=$(echo $Result | jq .Code 2> /dev/null)
#if [ "$Error" = "null" ]; then
    #echo $Result | $ATTRFILTER
#else
    #echo $Result | $ERRORFILTER
#fi
