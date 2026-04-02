#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: new-a2a-registration.sh [-h]
       new-a2a-registration.sh [-a appliance] [-B cabundle] [-v version] [-t accesstoken]
                               [-n appname] [-C certuser] [-D description] [-V] [-b]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -n  Application name for the A2A registration (required)
  -C  Certificate user ID (required)
  -D  Description
  -V  Make registration visible to certificate users
  -b  Enable bidirectional (allows setting passwords via A2A, not just reading)

Creates an A2A (Application-to-Application) registration that links a certificate
user to credential retrieval. After creating the registration, use
add-a2a-credential-retrieval.sh to add accounts whose credentials can be retrieved.

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
AppName=
CertUserId=
Description=
Visible=false
Bidirectional=false

. "$ScriptDir/utils/loginfile.sh"

while getopts ":a:B:v:t:n:C:D:Vbh" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    n) AppName=$OPTARG ;;
    C) CertUserId=$OPTARG ;;
    D) Description=$OPTARG ;;
    V) Visible=true ;;
    b) Bidirectional=true ;;
    h) print_usage ;;
    esac
done

if [ -z "$AppName" ]; then
    >&2 echo "Error: -n appname is required."
    exit 1
fi

if [ -z "$CertUserId" ]; then
    >&2 echo "Error: -C certuserid is required."
    exit 1
fi

require_login_args

Body=$(jq -n \
    --arg name "$AppName" \
    --argjson uid "$CertUserId" \
    --argjson vis "$Visible" \
    --argjson bidir "$Bidirectional" \
    '{
        AppName: $name,
        CertificateUserId: $uid,
        VisibleToCertificateUsers: $vis,
        BidirectionalEnabled: $bidir
    }')

if [ -n "$Description" ]; then
    Body=$(echo "$Body" | jq --arg desc "$Description" '.Description = $desc')
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m POST -U "A2ARegistrations" -b "$Body" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error creating A2A registration:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
