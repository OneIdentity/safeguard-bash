#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-access-request-privatekey.sh [-h]
       get-access-request-privatekey.sh [-v version] [-i requestid] [-F format] [-r]
       get-access-request-privatekey.sh [-a appliance] [-t accesstoken] [-v version] [-i requestid] [-F format] [-r]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 4 is default
  -i  Request Id
  -r  Raw output, i.e. remove quotes from JSON string to get just the password
  -F  Private key format (default: OpenSsh)
      OpenSsh: OpenSSH legacy PEM format
      Ssh2: Tectia format for use with tools from SSH.com
      Putty: Putty format for use with PuTTY tools

Check out an SSH private key of an access request via the Web API.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq for parsing and manipulating responses."
    exit 1
fi

Appliance=
AccessToken=
Version=4
RequestId=
Action=CheckOutSshKey
Raw=false
KeyFormat=OpenSsh

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$RequestId" ]; then
        read -p "Request ID: " RequestId
    fi
}

while getopts ":t:a:v:i:hF:r" opt; do
    case $opt in
    t)
        AccessToken=$OPTARG
        ;;
    a)
        Appliance=$OPTARG
        ;;
    v)
        Version=$OPTARG
        ;;
    i)
        RequestId=$OPTARG
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

ERRORFILTER='jq .'
if $Raw; then
    ATTRFILTER='jq --raw-output .PrivateKey'
else
    ATTRFILTER='jq .'
fi


Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m POST -U "AccessRequests/$RequestId/$Action?keyFormat=$KeyFormat" -N <<<$AccessToken)
Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result | $ATTRFILTER
else
    echo $Result | $ERRORFILTER
    exit 1
fi
