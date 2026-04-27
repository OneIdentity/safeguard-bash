#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: handle-a2a-privatekey-event.sh [-h]
       handle-a2a-privatekey-event.sh [-a appliance] [-v version] [-c file] [-k file] [-A apikey] [-O] [-p] [-S script] [-F format]

  -h  Show help and exit
  -a  Network address of the appliance
  -v  Web API Version: 4 is default
  -c  File containing client certificate
  -k  File containing client private key
  -A  A2A API token identifying the account
  -O  Use openssl s_client instead of curl for TLS client authentication problems
  -p  Read certificate password from stdin
  -S  Script to execute when the SSH key changes
  -F  Key format to request: OpenSsh, Ssh2, or Putty (default: OpenSsh)

Connect to SignalR using the Safeguard A2A service via a client certificate and
private key and execute a provided script (handler script) each time an SSH key
changes, passing the new private key via stdin.  The handler script will receive
the private key data on stdin.

The -O option was added to allow this script to work in certain situations where the
underlying TLS implementation compiled in with curl doesn't properly handle client
certificates.  This has been observed on some versions of macOS, Ubuntu, and other
Debian-based systems.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
Version=4
Cert=
PKey=
ApiKey=
Pass=
HandlerScript=
OpenSslSclientFlag=
KeyFormat=

if [ $(curl --version | grep "libcurl" | sed -e 's,curl [0-9]*\.\([0-9]*\).* (.*,\1,') -ge 33 ]; then
    http11flag='--http1.1'
fi

. "$ScriptDir/utils/loginfile.sh"
. "$ScriptDir/utils/common.sh"

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
    if [ -z "$ApiKey" ]; then
        read -p "A2A API Key: " ApiKey
    fi
    if [ -z "$Pass" ]; then
        read -s -p "Password: " Pass
        >&2 echo
    fi
    if [ -z "$HandlerScript" ]; then
        read -p "Handler Script: " HandlerScript
    fi
}

require_prereqs()
{
    if [ -z "$(which jq 2> /dev/null)" ]; then
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
    HandlerScript=$(echo "$(cd "$(dirname "$HandlerScript")"; pwd -P)/$(basename "$HandlerScript")")
}

cleanup()
{
    if [ ! -z "$listener_PID" ] && kill -0 $listener_PID 2> /dev/null; then
        >&2 echo "[$(date '+%x %X')] Killing listener coprocess PID=$listener_PID"
        kill $listener_PID 2> /dev/null
        wait $listener_PID 2> /dev/null
    fi
}

trap cleanup EXIT

while getopts ":a:v:c:k:A:S:F:pOh" opt; do
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
    A)
        ApiKey=$OPTARG
        ;;
    p)
        # read password from stdin before doing anything
        read -s Pass
        ;;
    S)
        HandlerScript=$OPTARG
        ;;
    F)
        KeyFormat=$OPTARG
        ;;
    O)
        OpenSslSclientFlag="-O"
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args
require_prereqs

FormatFlag=
if [ -n "$KeyFormat" ]; then
    FormatFlag="-F $KeyFormat"
fi

AcctKey=$("$ScriptDir/get-a2a-privatekey.sh" -a $Appliance -v $Version -c $Cert -k $PKey -A $ApiKey -p $OpenSslSclientFlag $FormatFlag <<< $Pass | jq -c -r .)
Error=$(echo $AcctKey | jq .Code 2> /dev/null)
if [ ! -z "$Error" -o -z "$AcctKey" ]; then
    >&2 echo "Unable to fetch initial SSH key from A2A service"
    >&2 echo "$AcctKey"
    exit 1
fi
>&2 echo "[$(date '+%x %X')] Calling $HandlerScript with initial SSH key"
$HandlerScript <<EOF
$AcctKey
EOF
unset AcctKey

while true; do
    if [ -z "$listener_PID" ] || ! kill -0 $listener_PID 2> /dev/null; then
        if [ ! -z "$listener_PID" ]; then
            wait $listener_PID
            unset listener_PID
        fi
        coproc listener {
            "$ScriptDir/listen-for-a2a-event.sh" -a $Appliance -c $Cert -k $PKey -A $ApiKey -p $OpenSslSclientFlag <<< $Pass 2> /dev/null | \
                jq --unbuffered -c ".arguments[]? | select(.Data?.EventName==\"AssetAccountSshKeyUpdated\") | .Data?" 2> /dev/null
        }
        >&2 echo "[$(date '+%x %X')] Started listener coprocess PID=$listener_PID."
    fi
# TODO: handle timeouts of not reading anything for a long period and restart coproc
    unset Output
    IFS= read -t 5 Temp <&"${listener[0]}" && Output="$Temp"
    if [ $? -eq 0 -o $? -gt 128 ]; then
        reset_backoff_wait
    else
        >&2 echo "[$(date '+%x %X')] The connection does not appear to be working, waiting to reconnect..."
        backoff_wait
    fi
    if [ ! -z "$Output" ]; then
        AcctKey=$("$ScriptDir/get-a2a-privatekey.sh" -a $Appliance -v $Version -c $Cert -k $PKey -A $ApiKey -p $OpenSslSclientFlag $FormatFlag <<< $Pass | jq -c -r .)
        Error=$(echo $AcctKey | jq .Code 2> /dev/null)
        if [ ! -z "$Error" -o -z "$AcctKey" ]; then
            >&2 echo "Unable to fetch SSH key from A2A service"
            >&2 echo "$AcctKey"
        else
            >&2 echo "[$(date '+%x %X')] Calling $HandlerScript with new SSH key"
            $HandlerScript <<EOF
$AcctKey
EOF
        fi
        unset AcctKey
    fi
done
