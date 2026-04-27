#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: new-a2a-access-request.sh [-h]
       new-a2a-access-request.sh [-a appliance] [-B cabundle] [-v version]
                                 [-c certfile] [-k keyfile] [-A apikey]
                                 [-b body] [-O] [-p]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -c  File containing client certificate
  -k  File containing client private key
  -A  A2A broker API key
  -b  JSON body for the access request (required)
  -O  Use openssl s_client instead of curl for TLS client auth problems
  -p  Read certificate private key password from stdin

Broker an access request via the A2A service using certificate authentication.
The A2A registration must have an access request broker configured with an
API key. The broker creates access requests on behalf of other users.

The JSON body specifies the request details. You can use either names or IDs:

  # By name (ForUser is the user on whose behalf the request is made)
  new-a2a-access-request.sh -a 10.0.0.1 -c cert.pem -k key.pem \\
      -A <broker-api-key> -b '{
          "ForUser": "jsmith",
          "AssetName": "linux-server",
          "AccountName": "root",
          "AccessRequestType": "Password"
      }' -p <<< ""

  # By ID with additional options
  new-a2a-access-request.sh -a 10.0.0.1 -c cert.pem -k key.pem \\
      -A <broker-api-key> -b '{
          "ForUserId": 123,
          "AssetId": 456,
          "AccountId": 789,
          "AccessRequestType": "SSH",
          "IsEmergency": true,
          "ReasonComment": "Emergency maintenance",
          "TicketNumber": "INC001234"
      }' -p <<< ""

Supported AccessRequestType values: Password, SSHKey, SSH, RemoteDesktop, Telnet

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundleArg=
CABundle=
Version=4
Cert=
PKey=
ApiKey=
Body=
Pass=
UseOpenSslSclient=false

. "$ScriptDir/utils/loginfile.sh"
. "$ScriptDir/utils/a2a.sh"

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
    if [ -z "$Pass" ]; then
        read -s -p "Private Key Password: " Pass
        >&2 echo
    fi
    if [ -z "$ApiKey" ]; then
        read -p "A2A Broker API Key: " ApiKey
    fi
    if [ -z "$Body" ]; then
        >&2 echo "Error: -b body is required."
        exit 1
    fi
}

while getopts ":a:B:v:c:k:A:b:pOh" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    c) Cert=$OPTARG ;;
    k) PKey=$OPTARG ;;
    A) ApiKey=$OPTARG ;;
    b) Body=$OPTARG ;;
    p) read -s Pass ;;
    O) UseOpenSslSclient=true ;;
    h) print_usage ;;
    esac
done

require_args

ERRORFILTER='cat'
if [ ! -z "$(which jq 2> /dev/null)" ]; then
    ERRORFILTER='jq .'
fi

Result=$(invoke_a2a_method "$Appliance" "$CABundleArg" "$Cert" "$PKey" "$Pass" "$ApiKey" a2a POST "AccessRequests" $Version $UseOpenSslSclient "$Body")
echo $Result | jq . > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo $Result
else
    Error=$(echo $Result | jq .Code 2> /dev/null)
    if [ -z "$Error" -o "$Error" = "null" ]; then
        echo $Result | jq .
    else
        >&2 echo "Error brokering access request:"
        echo $Result | $ERRORFILTER
        exit 1
    fi
fi
