#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: set-a2a-privatekey.sh [-h]
       set-a2a-privatekey.sh [-a appliance] [-B cabundle] [-v version] [-c file] [-k file]
                             [-A apikey] [-K keyfile] [-W passphrase] [-F format] [-O] [-p]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -c  File containing client certificate
  -k  File containing client private key
  -A  A2A API token identifying the account
  -K  File containing the SSH private key to set (required)
  -W  Passphrase for the SSH private key being set (optional)
  -F  Private key format (default: OpenSsh)
      OpenSsh: OpenSSH legacy PEM format
      Ssh2: Tectia format for use with tools from SSH.com
      Putty: Putty format for use with PuTTY tools
  -O  Use openssl s_client instead of curl for TLS client authentication problems
  -p  Read certificate password from stdin

Set an SSH private key using the Safeguard A2A service. This is the bidirectional
counterpart to get-a2a-privatekey.sh — it writes an SSH key to the account instead
of reading one.

The account must be configured for credential retrieval in an A2A registration.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq for constructing the request body."
    exit 1
fi

Appliance=
CABundleArg=
CABundle=
Version=4
Cert=
PKey=
ApiKey=
KeyFile=
KeyPassphrase=
KeyFormat=
PassStdin=
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
        read -p "A2A API Key: " ApiKey
    fi
    if [ -z "$KeyFile" ]; then
        read -p "SSH Private Key File to Set: " KeyFile
    fi
}

while getopts ":a:B:v:c:k:A:K:W:F:pOh" opt; do
    case $opt in
    a)
        Appliance=$OPTARG
        ;;
    B)
        CABundle=$OPTARG
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
    O)
        UseOpenSslSclient=true
        ;;
    K)
        KeyFile=$OPTARG
        ;;
    W)
        KeyPassphrase=$OPTARG
        ;;
    F)
        KeyFormat=$OPTARG
        KeyFormat=$(echo "$KeyFormat" | tr '[:upper:]' '[:lower:]')
        case $KeyFormat in
            openssh|ssh2|putty) ;;
            *) >&2 echo "Must specify a valid key format!"; print_usage ;;
        esac
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

if [ ! -f "$KeyFile" ]; then
    >&2 echo "Error: SSH private key file not found: $KeyFile"
    exit 1
fi

KeyData=$(cat "$KeyFile")
if [ -z "$KeyData" ]; then
    >&2 echo "Error: SSH private key file is empty: $KeyFile"
    exit 1
fi

# Build JSON body safely using jq
if [ -n "$KeyPassphrase" ]; then
    Body=$(jq -n --arg key "$KeyData" --arg pass "$KeyPassphrase" \
        '{Passphrase: $pass, PrivateKey: $key}')
else
    Body=$(jq -n --arg key "$KeyData" '{PrivateKey: $key}')
fi

RelUrl="Credentials/SshKey"
if [ -n "$KeyFormat" ]; then
    # Normalize to API-expected casing
    case $KeyFormat in
        openssh) KeyFormat="OpenSsh" ;;
        ssh2) KeyFormat="Ssh2" ;;
        putty) KeyFormat="Putty" ;;
    esac
    RelUrl="Credentials/SshKey?keyFormat=$KeyFormat"
fi

ERRORFILTER='cat'
if [ ! -z "$(which jq 2> /dev/null)" ]; then
    ERRORFILTER='jq .'
fi

Result=$(invoke_a2a_method "$Appliance" "$CABundleArg" "$Cert" "$PKey" "$Pass" "$ApiKey" a2a PUT "$RelUrl" $Version $UseOpenSslSclient "$Body")
echo "$Result" | jq . > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "$Result"
else
    Error=$(echo "$Result" | jq .Code 2> /dev/null)
    if [ -z "$Error" -o "$Error" = "null" ]; then
        echo "$Result" | jq .
    else
        echo "$Result" | $ERRORFILTER
        exit 1
    fi
fi
