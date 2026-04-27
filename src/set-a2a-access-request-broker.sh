#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: set-a2a-access-request-broker.sh [-h]
       set-a2a-access-request-broker.sh [-a appliance] [-B cabundle] [-v version]
                                        [-t accesstoken] [-i registrationid] [-b body]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -i  A2A registration ID (required)
  -b  JSON body for the broker configuration (required)

Configure or update the access request broker for an A2A registration.
There can be only one access request broker per A2A registration.

The JSON body must contain at least one of Users or Groups. Each user is
specified as {"UserId": <id>} and each group as {"GroupId": <id>}.

You may also include IpRestrictions to limit which IP addresses can use
the broker.

Examples:

  # Set broker with specific users
  set-a2a-access-request-broker.sh -i 123 \\
      -b '{"Users": [{"UserId": 45}, {"UserId": 67}]}'

  # Set broker with user groups
  set-a2a-access-request-broker.sh -i 123 \\
      -b '{"Groups": [{"GroupId": 10}]}'

  # Set broker with users, groups, and IP restrictions
  set-a2a-access-request-broker.sh -i 123 \\
      -b '{"Users": [{"UserId": 45}], "Groups": [{"GroupId": 10}], "IpRestrictions": ["10.0.0.1"]}'

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
Body=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$RegId" ]; then
        read -p "A2A Registration ID: " RegId
    fi
    if [ -z "$Body" ]; then
        >&2 echo "Error: -b body is required."
        exit 1
    fi
}

while getopts ":a:B:v:t:i:b:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    i) RegId=$OPTARG ;;
    b) Body=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

# Validate JSON if jq is available
if [ ! -z "$(which jq 2> /dev/null)" ]; then
    echo "$Body" | jq . > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        >&2 echo "Error: -b body is not valid JSON."
        exit 1
    fi
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m PUT -U "A2ARegistrations/$RegId/AccessRequestBroker" \
    -b "$Body" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error setting access request broker configuration:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result" | jq . 2>/dev/null || echo "$Result"
