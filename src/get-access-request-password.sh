#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-access-request-password.sh [-h]
       get-access-request-password.sh [-v version] [-i requestid] [-r]
       get-access-request-password.sh [-a appliance] [-t accesstoken] [-v version] [-i requestid] [-r]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 4 is default
  -i  Request Id
  -r  Raw output, i.e. remove quotes from JSON string to get just the password

Check out a password of an access request via the Web API.

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
Action=CheckOutPassword
Raw=false

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$RequestId" ]; then
        read -p "Request ID: " RequestId
    fi
}

while getopts ":t:a:v:i:hr" opt; do
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
    h)
        print_usage
        ;;
    esac
done

require_args

ERRORFILTER='jq .'
if $Raw; then
    ATTRFILTER='jq --raw-output .'
else
    ATTRFILTER='jq .'
fi


Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m POST -U "AccessRequests/$RequestId/$Action" -N <<<$AccessToken)
Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result | $ATTRFILTER
else
    echo $Result | $ERRORFILTER
fi
