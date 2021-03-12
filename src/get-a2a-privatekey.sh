#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-a2a-privatekey.sh [-h]
       get-a2a-privatekey.sh [-a appliance] [-B cabundle] [-v version] [-c file] [-k file] [-A apikey] [-F format] [-p] [-r]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 3 is default
  -c  File containing client certificate
  -k  File containing client private key
  -A  A2A API token identifying the account
  -p  Read certificate password from stdin
  -r  Raw output, i.e. remove quotes & interpret escape chars from JSON string to get just the private key
  -F  Private key format (default: OpenSsh)
      OpenSsh: OpenSSH legacy PEM format
      Ssh2: Tectia format for use with tools from SSH.com
      Putty: Putty format for use with PuTTY tools

Retrieve a private key using the Safeguard A2A service.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


Appliance=
CABundleArg=
CABundle=
Version=3
Cert=
PKey=
ApiKey=
Raw=false
KeyFormat=OpenSsh
PassStdin=
Pass=

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
}

while getopts ":a:B:v:c:k:A:F:prh" opt; do
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
    r)
        Raw=true
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

ATTRFILTER='cat'
ERRORFILTER='cat'
if [ ! -z "$(which jq)" ]; then
    ERRORFILTER='jq .'
    if $Raw; then
        ATTRFILTER='jq --raw-output .'
    else
        ATTRFILTER='jq .'
    fi
fi

Result=$(invoke_a2a_method "$Appliance" "$CABundleArg" "$Cert" "$PKey" "$Pass" "$ApiKey" a2a GET "Credentials?type=PrivateKey&keyFormat=$KeyFormat" $Version)
echo $Result | jq . > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo $Result
else
    Error=$(echo $Result | jq .Code 2> /dev/null)
    if [ -z "$Error" -o "$Error" = "null" ]; then
        echo $Result | $ATTRFILTER
    else
        echo $Result | $ERRORFILTER
    fi
fi
