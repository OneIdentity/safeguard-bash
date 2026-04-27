#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-a2a-registration.sh [-h]
       get-a2a-registration.sh [-a appliance] [-B cabundle] [-v version] [-t accesstoken]
                               [-i registrationid] [-q filter] [-f fields]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -i  A2A registration ID to get (omit to list all)
  -q  Query filter to pass to the API (SCIM-style, e.g. "AppName eq 'MyApp'")
  -f  Comma-separated list of fields to return (e.g. Id,AppName,CertificateUserId)

List all A2A registrations or get a specific registration by ID. When listing,
use -q and -f to filter and select fields. When getting by ID (-i), filter and
field options are ignored.

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
Filter=
Fields=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
}

while getopts ":a:B:v:t:i:q:f:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    i) RegId=$OPTARG ;;
    q) Filter=$OPTARG ;;
    f) Fields=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

if [ -n "$RegId" ]; then
    RelUrl="A2ARegistrations/$RegId"
else
    QueryParams=""
    if [ -n "$Filter" ]; then
        QueryParams="filter=$(printf '%s' "$Filter" | sed 's/ /%20/g')"
    fi
    if [ -n "$Fields" ]; then
        [ -n "$QueryParams" ] && QueryParams="${QueryParams}&"
        QueryParams="${QueryParams}fields=$Fields"
    fi

    RelUrl="A2ARegistrations"
    if [ -n "$QueryParams" ]; then
        RelUrl="${RelUrl}?${QueryParams}"
    fi
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m GET -U "$RelUrl" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error getting A2A registration(s):"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
