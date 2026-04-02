#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: add-a2a-credential-retrieval.sh [-h]
       add-a2a-credential-retrieval.sh [-a appliance] [-B cabundle] [-v version]
                                       [-t accesstoken] [-r registrationid] [-c accountid]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -r  A2A registration ID (required)
  -c  Account ID to make retrievable (required)

Adds an asset account to an A2A registration for credential retrieval. The response
includes the ApiKey needed for the A2A credential retrieval scripts
(get-a2a-password.sh, get-a2a-privatekey.sh, get-a2a-apikeysecret.sh).

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
AccountId=

. "$ScriptDir/utils/loginfile.sh"

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

if [ -z "$RegId" ]; then
    >&2 echo "Error: -r registrationid is required."
    exit 1
fi

if [ -z "$AccountId" ]; then
    >&2 echo "Error: -c accountid is required."
    exit 1
fi

require_login_args

Body=$(jq -n --argjson id "$AccountId" '{AccountId: $id}')

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m POST -U "A2ARegistrations/$RegId/RetrievableAccounts" \
    -b "$Body" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error adding credential retrieval:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
