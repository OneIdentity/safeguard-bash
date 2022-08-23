#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: new-access-request.sh [-h]
       new-access-request.sh [-v version] [-s assetid] [-c accountid] [-y accesstype] [-F]
       new-access-request.sh [-a appliance] [-t accesstoken] [-v version]
                             [-s assetid] [-c accountid] [-y accesstype] [-F]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 4 is default
  -s  Asset Id
  -c  Account Id
  -y  Access type (e.g. password, rdp, ssh)
  -F  Full JSON output

Create a new access request via the Web API. To request a session with your own credentials
pass null in for the Account Id.

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
AssetId=
AccountId=
AccessType=
FullOutput=false

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$AssetId" ]; then
        read -p "Asset ID: " AssetId
    fi
    if [ -z "$AccountId" ]; then
        read -p "Account ID: " AccountId
    fi
    if [ -z "$AccessType" ]; then
        read -p "Access Type (password, rdp, ssh): " AccessType
    fi
    AccessType=$(echo "$AccessType" | tr '[:upper:]' '[:lower:]')
    case $AccessType in
    password) AccessType="Password" ;;
    rdp) AccessType="RemoteDesktop" ;;
    ssh) AccessType="Ssh" ;;
    sshkey) AccessType="SshKey" ;;
    *)
        >&2 echo "Access Type must be one of password, sshkey, rdp, or ssh"
        exit 1
        ;;
    esac
}

while getopts ":t:a:v:s:c:y:Fh" opt; do
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
    s)
        AssetId=$OPTARG
        ;;
    c)
        AccountId=$OPTARG
        ;;
    y)
        AccessType=$OPTARG
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

Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m POST -U "AccessRequests" -N -b "{
    \"AssetId\": $AssetId,
    \"AccountId\": $AccountId,
    \"AccessRequestType\": \"$AccessType\"
}" <<<$AccessToken)

Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result | $ATTRFILTER
else
    echo $Result | $ERRORFILTER
fi

