#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-actionable-request.sh [-h]
       get-actionable-request.sh [-v version] [-r requestrole] [-F]
       get-actionable-request.sh [-a appliance] [-t accesstoken] [-v version] [-r requestrole] [-F]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 3 is default
  -r  Request role (e.g. Admin, Approver, Requester, Reviewer)
  -F  Full JSON output

Get an access request or all access requests via the Web API that are open that
the user can interact with using edit-access-request.sh.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


Appliance=
AccessToken=
Version=3
RequestRole=
FullOutput=false

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ ! -z "$RequestRole" ]; then
        RequestRole=$(echo "$RequestRole" | tr '[:upper:]' '[:lower:]')
        case $RequestRole in
        admin) RequestRole="Admin" ;;
        approver) RequestRole="Approver" ;;
        requester) RequestRole="Requester" ;;
        reviewer) RequestRole="Reviewer" ;;
        *)
            >&2 echo "Request role needs to be one of Admin, Approver, Requester, or Reviewer"
            exit 1
            ;;
        esac
    fi
}

while getopts ":t:a:v:r:Fh" opt; do
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
    r)
        RequestRole=$OPTARG
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
if [ ! -z "$(which jq 2> /dev/null)" ]; then
    ERRORFILTER='jq .'
    if $FullOutput; then
        ATTRFILTER='jq .'
    else
        ArrayFilter='[.[]|{Id,AssetId,AssetName,AccountId,AccountName,State}]'
        if [ -z "$RequestRole" ]; then
            ATTRFILTER="jq with_entries(.value|=$ArrayFilter)"
        else
            ATTRFILTER="jq $ArrayFilter"
        fi
    fi
fi

if [ -z "$RequestRole" ]; then
    Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m GET -U "Me/ActionableRequests" -N <<<$AccessToken)
else
    Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m GET -U "Me/ActionableRequests/$RequestRole" -N <<<$AccessToken)
fi

Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result | $ATTRFILTER
else
    echo $Result | $ERRORFILTER
fi

