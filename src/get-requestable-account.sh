#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-requestable-account.sh [-h]
       get-requestable-account.sh [-v version]
       get-requestable-account.sh [-a appliance] [-t accesstoken] [-v version]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 4 is default

First call the Me endpoint for requestable Safeguard assets, then call
each in succession to get all accounts for those assets.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq for parsing between requests."
    exit 1
fi

Appliance=
AccessToken=
Version=4

. "$ScriptDir/utils/loginfile.sh"

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

require_login_args

Response=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m GET -U "Me/AccessRequestAssets" -N <<<$AccessToken)
Error=$(echo $Response | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    Ids=$(echo $Response |  jq ".[].Id")
    if [ ! -z "$Ids" ]; then
        Ids=$(echo "$Ids" | tr '\n' ',' | sed 's/,$//')
        Output=""
        $ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m GET -U "Me/RequestEntitlements?assetIds=$Id" -N <<<$AccessToken \
               | jq -c '.[] | {Asset,Account,Policy}' | while IFS= read Obj; do
            AssetId=$(echo $Obj | jq '.Asset.Id')
            NetworkAddress=$(echo $Response | jq ".[] | select(.Id==$AssetId) | {NetworkAddress}")
            Asset=$(echo $Obj | jq '.Asset | .["AssetId"] = .Id | .["AssetName"] = .Name | {AssetId,AssetName,PlatformDisplayName}')
            Account=$(echo $Obj | jq '.Account | .["AccountId"] = .Id | .["AccountDomainName"] = .DomainName |.["AccountName"] = .Name | {AccountId,AccountDomainName,AccountName}')
            RequestType=$(echo $Obj | jq '.Policy | .["AccessRequestType"] = .AccessRequestProperties.AccessRequestType | {AccessRequestType}')
            OutputObj=$(echo "$Asset$NetworkAddress$Account$RequestType" | jq -s add)
            echo $OutputObj
        done | jq -s .
    else
        echo '[]' | jq .
    fi
else
    echo $Response | jq .
fi
