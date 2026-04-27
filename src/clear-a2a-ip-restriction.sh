#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: clear-a2a-ip-restriction.sh [-h]
       clear-a2a-ip-restriction.sh [-a appliance] [-B cabundle] [-v version]
                                   [-t accesstoken] [-r registrationid]
                                   [-c accountid]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -r  A2A registration ID (required)
  -c  Account ID of the credential retrieval (required)

Clear all IP restrictions from a credential retrieval in an A2A registration.
After clearing, any IP address will be allowed to retrieve credentials.

Requires PolicyAdmin role.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq for parsing JSON responses."
    exit 1
fi

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
RegId=
AccountId=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$RegId" ]; then
        read -p "A2A Registration ID: " RegId
    fi
    if [ -z "$AccountId" ]; then
        read -p "Account ID: " AccountId
    fi
}

while getopts ":a:B:v:t:r:c:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    r) RegId=$OPTARG ;;
    c) AccountId=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

# GET the current credential retrieval object
Current=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m GET -U "A2ARegistrations/$RegId/RetrievableAccounts/$AccountId" 2>/dev/null)
Error=$(echo "$Current" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error getting credential retrieval:"
    echo "$Current" | jq . 2>/dev/null || echo "$Current"
    exit 1
fi

# Set IpRestrictions to null and PUT the full object back
Updated=$(echo "$Current" | jq '.IpRestrictions = null')

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m PUT -U "A2ARegistrations/$RegId/RetrievableAccounts/$AccountId" \
    -b "$Updated" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error clearing IP restrictions:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result" | jq '.IpRestrictions'
