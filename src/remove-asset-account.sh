#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: remove-asset-account.sh [-h]
       remove-asset-account.sh [-a appliance] [-B cabundle] [-v version] [-t accesstoken]
                               -i accountid

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -i  Account ID to delete (required)

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
AccountId=

. "$ScriptDir/utils/loginfile.sh"

while getopts ":a:B:v:t:i:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    i) AccountId=$OPTARG ;;
    h) print_usage ;;
    esac
done

if [ -z "$AccountId" ]; then
    >&2 echo "Error: -i accountid is required."
    exit 1
fi

if [ -z "$AccessToken" ]; then
    use_login_file
fi
require_login_args

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m DELETE -U "AssetAccounts/$AccountId" 2>/dev/null)

if [ -n "$Result" ]; then
    Error=$(echo "$Result" | jq .Code 2>/dev/null)
    if [ -n "$Error" -a "$Error" != "null" ]; then
        >&2 echo "Error deleting asset account:"
        echo "$Result" | jq . 2>/dev/null || echo "$Result"
        exit 1
    fi
fi
