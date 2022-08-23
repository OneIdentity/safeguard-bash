#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: close-access-request.sh [-h]
       close-access-request.sh [-v version] [-i requestid]
       close-access-request.sh [-a appliance] [-t accesstoken] [-v version] [-i requestid]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 4 is default
  -i  Request Id

Close an access request via the Web API. This performs the appropriate action depending on
the state of the access request, e.g. cancel when password was never released, or check-in
after password was released, or acknowledge for an expired password.

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
FullOutput=false

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$RequestId" ]; then
        read -p "Request ID: " RequestId
    fi
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
        RequestId=$OPTARG
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
    ATTRFILTER='jq {Id,RequesterId,RequesterDisplayName,AssetId,AssetName,AccountId,AccountName,AccessRequestType,State}'
fi


Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m GET -U "AccessRequests/$RequestId" -N <<<$AccessToken)
Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    State=$(echo $Result | jq --raw-output '.State')
    LState=$(echo $State | tr '[:upper:]' '[:lower:]')
    if [ "$LState" = "new" -o "$LState" = "pendingapproval" -o "$LState" = "approved" -o "$LState" = "pendingtimerequested" -o "$LState" = "requestavailable" -o "$LState" = "pendingaccountrestored" ]; then
        Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m POST -U "AccessRequests/$RequestId/Cancel" -N <<<$AccessToken)
    elif [ "$LState" = "passwordcheckedout" -o "$LState" = "sshkeycheckedout" -o "$LState" = "sessioninitialized" ]; then
        Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m POST -U "AccessRequests/$RequestId/CheckIn" -N <<<$AccessToken)
    elif [ "$LState" = "requestcheckedin" -o "$LState" = "terminated" -o "$LState" = "pendingreview" -o "$LState" = "pendingaccountsuspended" ]; then
        Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m POST -U "AccessRequests/$RequestId/Close" -N <<<$AccessToken)
    elif [ "$LState" = "expired" -o "$LState" = "pendingacknowledgement" ]; then
        Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m POST -U "AccessRequests/$RequestId/Acknowledge" -N <<<$AccessToken)
    elif [ "$LState" = "closed" -o "$LState" = "complete" -o "$LState" = "reclaimed" -o "$LState" = "pendingpasswordreset" ]; then
        >&2 echo "Doing nothing for state '$State'"
    else
        >&2 echo "Unrecognized access request state '$State'"
        exit 1
    fi
    Error=$(echo $Result | jq .Code 2> /dev/null)
    if [ -z "$Error" -o "$Error" = "null" ]; then
        echo $Result | $ATTRFILTER
    else
        echo $Result | $ERRORFILTER
        exit 1
    fi
else
    echo $Result | $ERRORFILTER
    exit 1
fi

