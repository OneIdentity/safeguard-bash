#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: set-account-privatekey.sh [-h]
       set-account-privatekey.sh [-a appliance] [-B cabundle] [-v version]
                                 [-t accesstoken] [-c accountid] [-K keyfile]
                                 [-W passphrase] [-F format]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -c  Account ID (required)
  -K  File containing the SSH private key (required)
  -W  Passphrase for the private key (optional)
  -F  Key format: OpenSsh, Ssh2, or Putty (default: OpenSsh)

Set the SSH private key on an asset account via the Safeguard core API using
token authentication. The private key is read from a file specified with -K.

Requires AssetAdmin role.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq for parsing and manipulating responses."
    exit 1
fi

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
AccountId=
KeyFile=
Passphrase=
KeyFormat=OpenSsh

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$AccountId" ]; then
        read -p "Account ID: " AccountId
    fi
    if [ -z "$KeyFile" ]; then
        read -p "Private Key File: " KeyFile
    fi
}

while getopts ":a:B:v:t:c:K:W:F:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    c) AccountId=$OPTARG ;;
    K) KeyFile=$OPTARG ;;
    W) Passphrase=$OPTARG ;;
    F) KeyFormat=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

if [ ! -f "$KeyFile" ]; then
    >&2 echo "Error: key file '$KeyFile' not found."
    exit 1
fi

KeyData=$(cat "$KeyFile")

# Build JSON body safely using jq
if [ -n "$Passphrase" ]; then
    Body=$(jq -n --arg key "$KeyData" --arg pass "$Passphrase" \
        '{"Passphrase": $pass, "PrivateKey": $key}')
else
    Body=$(jq -n --arg key "$KeyData" \
        '{"PrivateKey": $key}')
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m PUT \
    -U "AssetAccounts/$AccountId/SshKey?keyFormat=$KeyFormat" \
    -b "$Body" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error setting SSH private key:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
