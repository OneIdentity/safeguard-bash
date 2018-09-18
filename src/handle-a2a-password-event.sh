#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: handle-a2a-password-event.sh [-h]
       handle-a2a-password-event.sh [-a appliance] [-c file] [-k file] [-A apikey] [-O] [-p] [-S script]

  -h  Show help and exit
  -a  Network address of the appliance
  -c  File containing client certificate
  -k  File containing client private key
  -A  A2A API token identifying the account
  -O  Use openssl s_client instead of curl for GnuTLS problem
  -p  Read certificate password from stdin
  -S  Script to execute when the password changes

Connect to SignalR using the Safeguard a2a service via a client certificate and
private key and execute a provided script (handler script) each time a password
changes, passing the new password via stdin.  The handler script will be passed
only one line of text:

    <New Password>

The -O option was added to allow this script to work in certain situations where the
underlying TLS implementation compiled in with curl doesn't properly handle client
certificates.  Usually this happens on Ubuntu 16.04 LTS and other Debian-based systems
where curl is compiled against GnuTLS.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
Cert=
PKey=
ApiKey=
Pass=
HandlerScript=
OpenSslSclientFlag=

if [ $(curl --version | grep "libcurl" | sed -e 's,curl [0-9]*\.\([0-9]*\).* (.*,\1,') -ge 33 ]; then
    http11flag='--http1.1'
fi

. "$ScriptDir/utils/loginfile.sh"

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

cleanup()
{
    if [ ! -z "$listener_PID" ] && kill -0 $listener_PID 2> /dev/null; then
        >&2 echo "[$(date '+%x %X')] Killing listener coprocess PID=$listener_PID"
        kill $listener_PID 2> /dev/null
        wait $listener_PID 2> /dev/null
    fi
}

trap cleanup EXIT

while getopts ":a:c:k:A:S:pOh" opt; do
    case $opt in
    a)
        Appliance=$OPTARG
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


AcctPass=$("$ScriptDir/get-a2a-password.sh" -a $Appliance -c $Cert -k $PKey -A $ApiKey -p <<< $Pass | jq -r .)
if [ -z "$AcctPass" ]; then
    >&2 echo "Unable to fetch initial password from A2A service"
    exit 1
fi
>&2 echo "[$(date '+%x %X')] Calling $HandlerScript with initial password"
$HandlerScript <<EOF
$AcctPass
EOF
unset AcctPass

while true; do
    if [ -z "$listener_PID" ] || ! kill -0 $listener_PID 2> /dev/null; then
        if [ ! -z "$listener_PID" ]; then
            wait $listener_PID
            unset listener_PID
        fi
        coproc listener { 
            "$ScriptDir/listen-for-a2a-event.sh" -a $Appliance -c $Cert -k $PKey -A $ApiKey -p $OpenSslSclientFlag <<< $Pass | \
                jq --unbuffered -c ".M[]?.A[]? | select(.Data?.EventName==\"AssetAccountPasswordUpdated\") | .Data?"
        }
        >&2 echo "[$(date '+%x %X')] Started listener coprocess PID=$listener_PID."
    fi
# TODO: handle timeouts of not reading anything for a long period and restart coproc
    unset Output
    IFS= read -t 5 Temp <&"${listener[0]}" && Output="$Temp"
    if [ ! -z "$Output" ]; then
        AcctPass=$("$ScriptDir/get-a2a-password.sh" -a $Appliance -c $Cert -k $PKey -A $ApiKey -p <<< $Pass | jq -r .)
        >&2 echo "[$(date '+%x %X')] Calling $HandlerScript with new password"
        $HandlerScript <<EOF
$AcctPass
EOF
        unset AcctPass
    fi
done
