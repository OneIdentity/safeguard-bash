#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: enable-a2a-service.sh [-h]
       enable-a2a-service.sh [-a appliance] [-B cabundle] [-v version] [-t accesstoken]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token

Enable the A2A service on the appliance. Once enabled, A2A credential retrieval
and access request brokering become available.

Requires ApplianceAdmin role.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=

. "$ScriptDir/utils/loginfile.sh"

while getopts ":a:B:v:t:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_login_args

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s appliance -m POST -U "A2AService/Enable" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error enabling A2A service:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
