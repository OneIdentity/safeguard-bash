#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: new-asset-account.sh [-h]
       new-asset-account.sh [-a appliance] [-B cabundle] [-v version] [-t accesstoken]
                            [-s assetid] [-n accountname] [-D description] [-d domainname]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -s  Asset ID to create the account on (required)
  -n  Account name (required)
  -D  Description
  -d  Domain name

Requires AssetAdmin role.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
AssetId=
AccountName=
Description=
DomainName=

. "$ScriptDir/utils/loginfile.sh"

while getopts ":a:B:v:t:s:n:D:d:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    s) AssetId=$OPTARG ;;
    n) AccountName=$OPTARG ;;
    D) Description=$OPTARG ;;
    d) DomainName=$OPTARG ;;
    h) print_usage ;;
    esac
done

if [ -z "$AssetId" ]; then
    >&2 echo "Error: -s assetid is required."
    exit 1
fi

if [ -z "$AccountName" ]; then
    >&2 echo "Error: -n accountname is required."
    exit 1
fi

if [ -z "$AccessToken" ]; then
    use_login_file
fi
require_login_args

Body=$(jq -n \
    --argjson assetid "$AssetId" \
    --arg name "$AccountName" \
    '{
        Asset: { Id: $assetid },
        Name: $name
    }')

if [ -n "$Description" ]; then
    Body=$(echo "$Body" | jq --arg desc "$Description" '.Description = $desc')
fi

if [ -n "$DomainName" ]; then
    Body=$(echo "$Body" | jq --arg dom "$DomainName" '.DomainName = $dom')
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m POST -U "AssetAccounts" -b "$Body" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error creating asset account:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
