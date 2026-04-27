#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-trusted-certificate.sh [-h]
       get-trusted-certificate.sh [-a appliance] [-B cabundle] [-v version]
                                  [-t accesstoken] [-s thumbprint] [-q filter]
                                  [-f fields]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -s  Thumbprint of a specific certificate (optional)
  -q  Query filter (SCIM-style, e.g. "Subject contains 'MyCert'")
  -f  Comma-separated list of fields to return (e.g. Thumbprint,Subject)

List all trusted certificates or get a specific one by thumbprint. These are
user-added trusted root and intermediate certificates.

Requires Appliance Administrator or auditor role.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
Thumbprint=
Filter=
Fields=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
}

while getopts ":a:B:v:t:s:q:f:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    s) Thumbprint=$OPTARG ;;
    q) Filter=$OPTARG ;;
    f) Fields=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

if [ -n "$Thumbprint" ]; then
    Url="TrustedCertificates/$Thumbprint"
    if [ -n "$Fields" ]; then
        Url="${Url}?fields=$Fields"
    fi
else
    Url="TrustedCertificates"
    QueryParams=""
    if [ -n "$Filter" ]; then
        QueryParams="filter=$(printf '%s' "$Filter" | sed 's/ /%20/g')"
    fi
    if [ -n "$Fields" ]; then
        [ -n "$QueryParams" ] && QueryParams="${QueryParams}&"
        QueryParams="${QueryParams}fields=$Fields"
    fi
    if [ -n "$QueryParams" ]; then
        Url="${Url}?${QueryParams}"
    fi
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m GET -U "$Url" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error getting trusted certificate:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
