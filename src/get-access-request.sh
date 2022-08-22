#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-access-request.sh [-h]
       get-access-request.sh [-v version] [-i id] [-F]
       get-access-request.sh [-a appliance] [-t accesstoken] [-v version] [-i id] [-F]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 4 is default
  -i  ID of specific access request
  -F  Full JSON output

Get an access request or all access requests via the Web API.

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
Id=
FullOutput=false

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
}

while getopts ":t:a:v:i:Fh" opt; do
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
        Id=$OPTARG
        ;;
    F)
        FullOutput=true
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

ERRORFILTER='jq .'
if $FullOutput; then
    ATTRFILTER='jq .'
else
    if [ -z "$Id" ]; then
        ATTRFILTER='jq [.[]|{Id,RequesterId,RequesterDisplayName,AssetId,AssetName,AccountId,AccountName,AccessRequestType,State}]'
    else
        ATTRFILTER='jq {Id,RequesterId,RequesterDisplayName,AssetId,AssetName,AccountId,AccountName,AccessRequestType,State}'
    fi
fi

if [ -z "$Id" ]; then
    Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m GET -U "AccessRequests" -N <<<$AccessToken)
else
    Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m GET -U "AccessRequests/$Id" -N <<<$AccessToken)
fi

Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result | $ATTRFILTER
else
    echo $Result | $ERRORFILTER
fi

