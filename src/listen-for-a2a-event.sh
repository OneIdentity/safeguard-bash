#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: listen-for-a2a-event.sh [-h]
       listen-for-a2a-event.sh [-a appliance] [-B cabundle] [-c file] [-k file] [-A apikey] [-p] [-O]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -c  File containing client certificate
  -k  File containing client private key
  -A  A2A API token identifying the account
  -p  Read certificate password from stdin
  -O  Use openssl s_client instead of curl for GnuTLS problem

This script will create a SignalR connection to the A2A service to report
events.

The -O option was added to allow this script to work in certain situations where the
underlying TLS implementation compiled in with curl doesn't properly handle client
certificates.  Usually this happens on Ubuntu 16.04 LTS and other Debian-based systems
where curl is compiled against GnuTLS.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundle=
CABundleArg=
Appliance=
Cert=
PKey=
ApiKey=
Pass=
UseOpenSslSclient=false

if [ $(curl --version | grep "libcurl" | sed -e 's,curl [0-9]*\.\([0-9]*\).* (.*,\1,') -ge 33 ]; then
    http11flag='--http1.1'
fi

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    handle_ca_bundle_arg
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
    curl -s $CABundleArg "https://$Appliance/service/a2a/signalr/negotiate?_=$NUM" \
        | sed -n -e 's/\+/%2B/g;s/\//%2F/g;s/.*"ConnectionToken":"\([^"]*\)".*/\1/p'
}


if [ ! -z "`which jq`" ]; then
    PRETTYPRINT="jq ."
else
    PRETTYPRINT="cat"
fi

while getopts ":a:B:c:k:A:pOh" opt; do
    case $opt in
    a)
        Appliance=$OPTARG
        ;;
    B)
        CABundle=$OPTARG
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
    O)
        UseOpenSslSclient=true
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

ConnectionToken=`get_connection_token`
TID=`echo $(( ( RANDOM % 1000 )  + 1 ))`
Url="https://$Appliance/service/a2a/signalr/connect"
Params="?transport=serverSentEvents&connectionToken=$ConnectionToken&connectionData=%5b%7b%22name%22%3a%22notificationHub%22%7d%5d&tid=$TID"
if $UseOpenSslSclient; then
    cat <<EOF | stdbuf -o0 -e0 openssl s_client -connect $Appliance:443 -crlf -quiet -key $PKey -cert $Cert -pass pass:$Pass 2>&1 | sed -u -e '/^data: /!d;/^data: initialized/d;s/^data: \(.*\)$/\1/g' | while read line; do echo $line | $PRETTYPRINT ; done
GET /service/a2a/signalr/connect$Params HTTP/1.1
Host: $Appliance
Authorization: A2A $ApiKey
User-Agent: curl/7.47.0
Accept: application/json


EOF
else
    stdbuf -o0 -e0 curl -K <(cat <<EOF
-s
$CABundleArg
--key $PKey
--cert $Cert
--pass $Pass
-H "Authorization: A2A $ApiKey"
$http11flag
EOF
) "$Url$Params" | sed -u -e '/^data: initialized/d;/^\s*$/d;s/^data: \(.*\)$/\1/g' | while read line; do echo $line | $PRETTYPRINT ; done
fi
