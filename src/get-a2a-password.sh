#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-a2a-password.sh [-h]
       get-a2a-password.sh [-a appliance] [-B cabundle] [-v version] [-c file] [-k file] [-A apikey] [-p] [-r]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 3 is default
  -c  File containing client certificate
  -k  File containing client private key
  -A  A2A API token identifying the account
  -p  Read certificate password from stdin
  -r  Raw output, i.e. remove quotes from JSON string to get just the password

Retrieve a password using the Safeguard A2A service.

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

while getopts ":a:B:v:c:k:A:prh" opt; do
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
    ATTRFILTER='jq .'
fi

Result=$(invoke_a2a_method "$Appliance" "$CABundleArg" "$Cert" "$PKey" "$Pass" "$ApiKey" GET "Credentials?type=Password" $Version "$Body")
Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    if $Raw; then
        echo $Result | $ATTRFILTER | jq --raw-output .
    else
        echo $Result | $ATTRFILTER
    fi
else
    echo $Result | $ERRORFILTER
fi

