#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: start-access-request-ssh-session.sh [-h]
       start-access-request-ssh-session.sh [-v version] [-i requestid]
       start-access-request-ssh-session.sh [-a appliance] [-t accesstoken] [-v version] [-i requestid]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 4 is default
  -i  Request Id

Start an SSH session of an access request via the Web API.

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
Action=InitializeSession

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$RequestId" ]; then
        read -p "Request ID: " RequestId
    fi
}

while getopts ":t:a:v:i:h" opt; do
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
    h)
        print_usage
        ;;
    esac
done

require_args

ERRORFILTER='jq .'
ATTRFILTER='jq .'


Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m GET -U "AccessRequests/$RequestId" -N <<<$AccessToken)
Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    Type=$(echo $Result | jq --raw-output '.AccessRequestType')
    LType=$(echo $Type | tr '[:upper:]' '[:lower:]')
    case $LType in
    ssh)
        Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m POST -U "AccessRequests/$RequestId/$Action" -N <<<$AccessToken)
        Error=$(echo $Result | jq .Code 2> /dev/null)
        if [ -z "$Error" -o "$Error" = "null" ]; then
            SshUri=$(echo $Result | jq --raw-output '.ConnectionUri')
            >&2 echo "Opening SSH connection..."
            ssh $SshUri
        else
            echo $Result | $ERRORFILTER
        fi
        ;;
    *)
        >&2 echo "Unable to launch SSH session for access request type '$Type'"
        exit 1
        ;;
    esac

else
    echo $Result | $ERRORFILTER
    exit 1
fi
