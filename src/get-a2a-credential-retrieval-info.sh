#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-a2a-credential-retrieval-info.sh [-h]
       get-a2a-credential-retrieval-info.sh [-a appliance] [-B cabundle] [-v version]
                                            [-t accesstoken] [-n assetname]
                                            [-N accountname] [-d domainname]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -n  Filter by asset name (case-insensitive)
  -N  Filter by account name (case-insensitive)
  -d  Filter by domain name (case-insensitive)

Get summary information of all A2A credential retrievals across all registrations.
Returns a flat list with AppName, Description, CertificateUserThumbPrint, ApiKey,
AssetName, AccountName, and DomainName for each retrievable account.

Requires PolicyAdmin role.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq for JSON processing."
    exit 1
fi

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
AssetName=
AccountName=
DomainName=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
}

while getopts ":a:B:v:t:n:N:d:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    n) AssetName=$OPTARG ;;
    N) AccountName=$OPTARG ;;
    d) DomainName=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

# Get all A2A registrations
Registrations=$("$ScriptDir/get-a2a-registration.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" 2>/dev/null)
Error=$(echo "$Registrations" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error getting A2A registrations:"
    echo "$Registrations" | jq .
    exit 1
fi

# Build flattened summary by iterating registrations and their retrievable accounts
Result="[]"
for RegId in $(echo "$Registrations" | jq -r '.[].Id' 2>/dev/null); do
    RegInfo=$(echo "$Registrations" | jq ".[] | select(.Id == $RegId)")
    AppName=$(echo "$RegInfo" | jq -r '.AppName')
    Description=$(echo "$RegInfo" | jq -r '.Description')
    CertThumbPrint=$(echo "$RegInfo" | jq -r '.CertificateUserThumbPrint')

    Accounts=$("$ScriptDir/get-a2a-credential-retrieval.sh" -a "$Appliance" -t "$AccessToken" \
        -v "$Version" -r "$RegId" 2>/dev/null)
    AcctError=$(echo "$Accounts" | jq .Code 2>/dev/null)
    if [ -n "$AcctError" -a "$AcctError" != "null" ]; then
        continue
    fi

    Entries=$(echo "$Accounts" | jq --arg app "$AppName" --arg desc "$Description" \
        --arg thumbprint "$CertThumbPrint" \
        '[ .[] | {
            AppName: $app,
            Description: $desc,
            CertificateUserThumbPrint: $thumbprint,
            ApiKey: .ApiKey,
            AssetName: .AssetName,
            AccountName: .AccountName,
            DomainName: .DomainName
        } ]')
    Result=$(echo "$Result" "$Entries" | jq -s '.[0] + .[1]')
done

# Apply client-side filters (case-insensitive)
if [ -n "$AssetName" ]; then
    Result=$(echo "$Result" | jq --arg name "$AssetName" \
        '[ .[] | select(.AssetName | ascii_downcase == ($name | ascii_downcase)) ]')
fi
if [ -n "$AccountName" ]; then
    Result=$(echo "$Result" | jq --arg name "$AccountName" \
        '[ .[] | select(.AccountName | ascii_downcase == ($name | ascii_downcase)) ]')
fi
if [ -n "$DomainName" ]; then
    Result=$(echo "$Result" | jq --arg name "$DomainName" \
        '[ .[] | select(.DomainName | ascii_downcase == ($name | ascii_downcase)) ]')
fi

echo "$Result"
