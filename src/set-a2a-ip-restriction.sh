#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: set-a2a-ip-restriction.sh [-h]
       set-a2a-ip-restriction.sh [-a appliance] [-B cabundle] [-v version]
                                 [-t accesstoken] [-r registrationid]
                                 [-c accountid] [-I ipaddresses]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -r  A2A registration ID (required)
  -c  Account ID of the credential retrieval (required)
  -I  Comma-separated list of IP addresses to allow (required)
      Example: "10.0.0.1,10.0.0.2,192.168.1.0"

Set IP restrictions on a credential retrieval in an A2A registration.
Only the specified IP addresses will be allowed to retrieve credentials.
Returns the updated IP restrictions array.

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
IpAddresses=

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
    if [ -z "$IpAddresses" ]; then
        read -p "IP Addresses (comma-separated): " IpAddresses
    fi
}

while getopts ":a:B:v:t:r:c:I:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    r) RegId=$OPTARG ;;
    c) AccountId=$OPTARG ;;
    I) IpAddresses=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

# Build JSON array from comma-separated IPs, trimming whitespace and rejecting empties
IpArray=$(echo "$IpAddresses" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')
if [ "$(echo "$IpArray" | jq 'length')" -eq 0 ]; then
    >&2 echo "Error: no valid IP addresses provided."
    exit 1
fi

# GET the current credential retrieval object
Current=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m GET -U "A2ARegistrations/$RegId/RetrievableAccounts/$AccountId" 2>/dev/null)
Error=$(echo "$Current" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error getting credential retrieval:"
    echo "$Current" | jq . 2>/dev/null || echo "$Current"
    exit 1
fi

# Set IpRestrictions on the full object and PUT it back
Updated=$(echo "$Current" | jq --argjson ips "$IpArray" '.IpRestrictions = $ips')

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m PUT -U "A2ARegistrations/$RegId/RetrievableAccounts/$AccountId" \
    -b "$Updated" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error setting IP restrictions:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result" | jq '.IpRestrictions'
