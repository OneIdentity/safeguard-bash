#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: edit-access-request.sh [-h]
       edit-access-request.sh [-v version] [-i requestid] [-m method] [-c comment] [-F]
       edit-access-request.sh [-a appliance] [-t accesstoken] [-v version]
                              [-i requestid] [-m method] [-c comment] [-F]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 2 is default
  -i  Request Id
  -m  Action to perform (Approve, Deny, Review, Cancel, Close, CheckIn,
                         CheckOutPassword, InitializeSession, Acknowledge)
  -c  Comment, sometimes required for an action
  -F  Full JSON output

Update an access request via the Web API.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


Appliance=
AccessToken=
Version=2
RequestId=
Action=
Comment=
FullOutput=false

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$RequestId" ]; then
        read -p "Request ID: " RequestId
    fi
    if [ -z "$Action" ]; then
        >&2 echo "Possible actions (Approve, Deny, Review, Cancel, Close, CheckIn, CheckOutPassword, InitializeSession, Acknowledge)"
        read -p "Action: " Action
    fi
    Action=$(echo "$Action" | tr '[:upper:]' '[:lower:]')
    case $Action in
    approve) Action="Approve" ;;
    deny) Action="Deny" ;;
    review) Action="Review" ;;
    cancel) Action="Cancel" ;;
    close) Action="Close" ;;
    checkin) Action="CheckIn" ;;
    checkoutpassword) Action="CheckOutPassword" ;;
    initializesession) Action="InitializeSession" ;;
    acknowledge) Action="Acknowledge" ;;
    *)
        >&2 echo -e "Action must be one of Approve, Deny, Review, Cancel, Close, CheckIn,\n  CheckOutPassword, InitializeSession, Acknowledge"
        exit 1
        ;;
    esac
}

while getopts ":t:a:v:i:m:c:h" opt; do
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
    m)
        Action=$OPTARG
        ;;
    c)
        Comment=$OPTARG
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

ATTRFILTER='cat'
ERRORFILTER='cat'
if [ ! -z "$(which jq)" ]; then
    ERRORFILTER='jq .'
    if $FullOutput; then
        ATTRFILTER='jq .'
    else
        ATTRFILTER='jq {Id,AssetId,AssetName,AccountId,AccountName,State}'
    fi
    case $Action in
        CheckOutPassword) ATTRFILTER='jq .' ;;
        InitializeSession) ATTRFILTER='jq .' ;;
    esac
fi

Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -t "$AccessToken" -v $Version -s core -m POST -U "AccessRequests/$RequestId/$Action" -N -b "$Comment")
Error=$(echo $Result | jq .Code 2> /dev/null)
if [ "$Error" = "null" ]; then
    echo $Result | $ATTRFILTER
else
    echo $Result | $ERRORFILTER
fi

