#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-requestable-accounts.sh [-h]
       get-requestable-accounts.sh [-v version]
       get-requestable-accounts.sh [-a appliance] [-t accesstoken] [-v version]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 2 is default

First call the Me endpoint for requestable Safeguard assets, then call
each in succession to get all accounts for those assets.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq)" ]; then
    >&2 echo "This script requires jq for parsing between requests."
    exit 1
fi

Appliance=
AccessToken=
Version=2
LicenseFile=

. "$ScriptDir/loginfile-utils.sh"

require_args()
{
    require_login_args
    if [ -z "$LicenseFile" ]; then
        read -p "License file: " LicenseFile
    fi
}

while getopts ":t:a:v:h" opt; do
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
    h)
        print_usage
        ;;
    esac
done


Response=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -t "$AccessToken" -v $Version -s core -m GET -U "Me/RequestableAssets" -N)
Error=$(echo $Response | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    Ids=$(echo $Response |  jq ".[].Id")
    if [ ! -z "$Ids" ]; then
        Objs=""
        for Id in $Ids; do
            Accounts=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -t "$AccessToken" -v $Version -s core -m GET -U "Me/RequestableAssets/$Id/Accounts" -N \
                       | jq '.[] | {Id,Name,AccountRequestTypes}' | jq -s .)
            Asset=$(echo $Response | jq --argjson accounts "$Accounts" \
                    ".[] | select(.Id == $Id) | {Id,Name,NetworkAddress,PlatformDisplayName,AccountRequestTypes,Accounts} | .Accounts |= \$accounts")
            Objs="$Objs$Asset"
        done
        echo "$Objs" | jq -s .
    else
        echo '[]' | jq .
    fi
else
    echo $Response | jq .
fi

