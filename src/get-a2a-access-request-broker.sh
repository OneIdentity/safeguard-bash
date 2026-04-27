#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-a2a-access-request-broker.sh [-h]
       get-a2a-access-request-broker.sh [-a appliance] [-B cabundle] [-v version]
                                        [-t accesstoken] [-i registrationid]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -i  A2A registration ID (required)

Get the access request broker configuration for an A2A registration.
Returns the broker configuration including authorized users, groups,
IP restrictions, and the broker API key.

If no broker is configured for the registration, the API returns an error.

Requires PolicyAdmin role.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
RegId=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$RegId" ]; then
        read -p "A2A Registration ID: " RegId
    fi
}

while getopts ":a:B:v:t:i:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    i) RegId=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m GET -U "A2ARegistrations/$RegId/AccessRequestBroker" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error getting access request broker configuration:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result" | jq . 2>/dev/null || echo "$Result"
