#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-a2a-credential-retrieval.sh [-h]
       get-a2a-credential-retrieval.sh [-a appliance] [-B cabundle] [-v version]
                                       [-t accesstoken] [-r registrationid]
                                       [-c accountid] [-q filter] [-f fields]
                                       [-o orderby]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -r  A2A registration ID (required)
  -c  Account ID for a single credential retrieval (optional)
  -q  Query filter to pass to the API (SCIM-style, e.g. "AccountName eq 'root'")
  -f  Comma-separated list of fields to return (e.g. AccountName,AccountId)
  -o  Comma-separated list of fields to order by (e.g. AccountName)

List credential retrieval configurations for an A2A registration. Returns all
retrievable accounts by default, or a single account if -c is specified.

The -q, -f, and -o options only apply when listing all accounts (no -c).

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
Filter=
Fields=
OrderBy=

. "$ScriptDir/utils/loginfile.sh"

while getopts ":a:B:v:t:r:c:q:f:o:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    r) RegId=$OPTARG ;;
    c) AccountId=$OPTARG ;;
    q) Filter=$OPTARG ;;
    f) Fields=$OPTARG ;;
    o) OrderBy=$OPTARG ;;
    h) print_usage ;;
    esac
done

if [ -z "$RegId" ]; then
    >&2 echo "Error: -r registrationid is required."
    exit 1
fi

require_login_args

if [ -n "$AccountId" ]; then
    # Get a single credential retrieval by account ID
    Url="A2ARegistrations/$RegId/RetrievableAccounts/$AccountId"
else
    # List all credential retrievals with optional query params
    Url="A2ARegistrations/$RegId/RetrievableAccounts"
    QueryParams=""
    if [ -n "$Filter" ]; then
        QueryParams="filter=$(printf '%s' "$Filter" | sed 's/ /%20/g')"
    fi
    if [ -n "$Fields" ]; then
        [ -n "$QueryParams" ] && QueryParams="${QueryParams}&"
        QueryParams="${QueryParams}fields=$Fields"
    fi
    if [ -n "$OrderBy" ]; then
        [ -n "$QueryParams" ] && QueryParams="${QueryParams}&"
        QueryParams="${QueryParams}orderby=$OrderBy"
    fi
    if [ -n "$QueryParams" ]; then
        Url="${Url}?${QueryParams}"
    fi
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m GET -U "$Url" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error getting credential retrieval:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
