#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-a2a-password.sh [-h]
       get-a2a-password.sh [-a appliance] [-v version] [-c file] [-k file] [-A apikey] [-p]

  -h  Show help and exit
  -a  Network address of the appliance
  -v  Web API Version: 2 is default
  -c  File containing client certificate
  -k  File containing client private key
  -A  A2A API token identifying the account
  -p  Read certificate password from stdin

Retrieve a password using the Safeguard A2A service.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


Appliance=
Version=2
Cert=
PKey=
ApiKey=
PassStdin=
Pass=

. "$ScriptDir/utils/a2a.sh"

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
    if [ -z "$Pass" ]; then
        read -s -p "Private Key Password: " Pass
        >&2 echo
    fi
    if [ -z "$ApiKey" ]; then
        read -p "A2A API Key: " ApiKey
    fi
}

while getopts ":a:v:c:k:A:ph" opt; do
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
    p)
        PassStdin="-p"
        ;;
    A)
        ApiKey=$OPTARG
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

Result=$(invoke_a2a_method "$Appliance" "$Cert" "$PKey" "$Pass" "$ApiKey" GET "Credentials?type=Password" $Version "$Body")
Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result | $ATTRFILTER
else
    echo $Result | $ERRORFILTER
fi
