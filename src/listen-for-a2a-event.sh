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
  -O  Use openssl s_client instead of curl for TLS client authentication problems

This script will create a SignalR connection to the A2A service to report
events.

The -O option was added to allow this script to work in certain situations where the
underlying TLS implementation compiled in with curl doesn't properly handle client
certificates.  This has been observed on some versions of macOS, Ubuntu, and other
Debian-based systems.

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

if [ ! -z "$(which gsed)" ]; then
    SED=gsed
else
    SED=sed
fi

if [ $(curl --version | grep "libcurl" | $SED -e 's,curl [0-9]*\.\([0-9]*\).* (.*,\1,') -ge 33 ]; then
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
    # This call does not require an authorization header
    if $UseOpenSslSclient; then
        TokenResponse=$(cat <<EOF | openssl s_client -connect $Appliance:443 -quiet -crlf -key $PKey -cert $Cert -pass pass:$Pass 2>&1
POST /service/a2a/signalr/negotiate?negotiateVersion=1 HTTP/1.1
Host: $Appliance
User-Agent: curl/7.47.0
Authorization: A2A $apikey
Accept: application/json
Connection: close
Content-type: application/json
Content-Length: 0


EOF
)
        echo $TokenResponse | $SED -n -e 's/\+/%2B/g;s/\//%2F/g;s/.*"connectionId":"\([^"]*\)".*/\1/p'
    else
        curl -K <(cat <<EOF
-s
$CABundleArg
--key $PKey
--cert $Cert
--pass $Pass
EOF
) "https://$Appliance/service/a2a/signalr/negotiate?negotiateVersion=1" -d '' \
            | $SED -n -e 's/\+/%2B/g;s/\//%2F/g;s/.*"connectionId":"\([^"]*\)".*/\1/p'
    fi
}

negotiate_connection()
{
    if $UseOpenSslSclient; then
        NegotiateResponse=$(cat <<EOF | openssl s_client -connect $Appliance:443 -quiet -crlf -key $PKey -cert $Cert -pass pass:$Pass 2>&1
POST /service/a2a/signalr$Params HTTP/1.1
Host: $Appliance
User-Agent: curl/7.47.0
Authorization: A2A $ApiKey
Accept: application/json
Connection: close
Content-type: application/json
Content-Length: ${#Body}

$Body
EOF
)
    else
        curl -K <(cat <<EOF
-s
$CABundleArg
--key $PKey
--cert $Cert
--pass $Pass
-H "Authorization: A2A $ApiKey"
EOF
) -d "$Body" "$Url$Params"
    fi
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

# Step 1 -- initialize connection
ConnectionToken=`get_connection_token`

# Step 2 -- negotiate connection
Url="https://$Appliance/service/a2a/signalr"
Params="?id=$ConnectionToken"
Body=$(echo -e "{\"protocol\":\"json\",\"version\":1}\x1E") # \x1E is record separator char
negotiate_connection

# Step 3 -- listen
if $UseOpenSslSclient; then
    if [ -z "$(which stdbuf)" ]; then
        >&2 echo "Using openssl s_client with this script requires the stdbuf utility, please install it."
        exit 1
    fi
    cat <<EOF | stdbuf -o0 -e0 openssl s_client -connect $Appliance:443 -crlf -quiet -key $PKey -cert $Cert -pass pass:$Pass 2>&1 \
        | $SED -u -e '/{.*}/!d' | while read line; do echo $line | $PRETTYPRINT ; done
GET /service/a2a/signalr$Params HTTP/1.1
Host: $Appliance
Authorization: A2A $ApiKey
User-Agent: curl/7.47.0
Accept: text/event-stream


EOF
else
    curl -N -K <(cat <<EOF
-s
$CABundleArg
--key $PKey
--cert $Cert
--pass $Pass
-H "Authorization: A2A $ApiKey"
$http11flag
EOF
) -H 'Accept: text/event-stream' "$Url$Params" | $SED -u -e '/^:.*$/d;/^\s*$/d;s/^data: \(.*\)$/\1/g' |
    while read line; do
        echo $line | $PRETTYPRINT
    done
fi
