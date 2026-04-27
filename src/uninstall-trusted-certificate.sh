#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: uninstall-trusted-certificate.sh [-h]
       uninstall-trusted-certificate.sh [-a appliance] [-B cabundle] [-v version]
                                        [-t accesstoken] -s thumbprint

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -s  Thumbprint of the certificate to remove (required)

Remove a trusted certificate from Safeguard by its thumbprint.

Requires Appliance Administrator role.

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

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$Thumbprint" ]; then
        read -p "Certificate Thumbprint: " Thumbprint
    fi
}

while getopts ":a:B:v:t:s:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    s) Thumbprint=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m DELETE -U "TrustedCertificates/$Thumbprint" 2>/dev/null)

if [ -n "$Result" ]; then
    Error=$(echo "$Result" | jq .Code 2>/dev/null)
    if [ -n "$Error" -a "$Error" != "null" ]; then
        >&2 echo "Error removing trusted certificate:"
        echo "$Result" | jq . 2>/dev/null || echo "$Result"
        exit 1
    fi
fi
