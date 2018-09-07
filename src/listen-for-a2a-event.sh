#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: $1 [-h]
       $1 [-a appliance] [-c file] [-k file] [-A apikey] [-p]

  -h  Show help and exit
  -a  Network address of the appliance
  -c  File containing client certificate
  -k  File containing client private key
  -A  A2A API token identifying the account
  -p  Read certificate password from stdin

This script will create a SignalR connection to the A2A service to report
events.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
AccessToken=
Appliance=
Cert=
PKey=
ApiKey=
Pass=

if [ $(curl --version | grep "libcurl" | sed -e 's,curl [0-9]*\.\([0-9]*\).* (.*,\1,') -ge 33 ]; then
    http11flag='--http1.1'
fi

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
}

get_connection_token()
{
    NUM=`echo $(( ( RANDOM % 1000000000 )  + 1 ))`
    # This call does not require an authorization header
    curl -s -k "https://$Appliance/service/a2a/signalr/negotiate?_=$NUM" \
        | sed -n -e 's/\+/%2B/g;s/\//%2F/g;s/.*"ConnectionToken":"\([^"]*\)".*/\1/p'
}


if [ ! -z "`which jq`" ]; then
    PRETTYPRINT="jq ."
else
    PRETTYPRINT="cat"
fi

while getopts ":a:c:k:A:ph" opt; do
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
    h)
        print_usage $0
        ;;
    esac
done

require_args

ConnectionToken=`get_connection_token`
TID=`echo $(( ( RANDOM % 1000 )  + 1 ))`
Url="https://$Appliance/service/a2a/signalr/connect"
Params="?transport=serverSentEvents&connectionToken=$ConnectionToken&connectionData=%5b%7b%22name%22%3a%22notificationHub%22%7d%5d&tid=$TID"
stdbuf -o0 -e0 curl -K <(cat <<EOF
-s
-k
--key $PKey
--cert $Cert
--pass $Pass
-H "Authorization: A2A $ApiKey"
$http11flag
EOF
) "$Url$Params" | sed -u -e '/^data: initialized/d;/^\s*$/d;s/^data: \(.*\)$/\1/g' | while read line; do echo $line | $PRETTYPRINT ; done

