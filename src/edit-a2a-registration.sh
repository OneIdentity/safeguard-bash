#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: edit-a2a-registration.sh [-h]
       edit-a2a-registration.sh [-a appliance] [-B cabundle] [-v version] [-t accesstoken]
                                -i registrationid [-b body]
       edit-a2a-registration.sh [-a appliance] [-B cabundle] [-v version] [-t accesstoken]
                                -i registrationid [-n appname] [-D description] [-C certuserid] [-V|-W]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -i  A2A registration ID to edit (required)
  -b  JSON body for the PUT request (overrides individual attribute flags)
  -n  New application name
  -D  New description
  -C  New certificate user ID
  -V  Make registration visible to certificate users
  -W  Make registration NOT visible to certificate users

Edit an existing A2A registration. You can either provide a full JSON body with -b,
or use individual flags (-n, -D, -C, -V/-W) to update specific attributes. When using
individual flags, the script fetches the current registration, applies changes, and
PUTs the updated object back.

Requires PolicyAdmin role.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq for parsing and manipulating responses."
    exit 1
fi

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
RegId=
Body=
AppName=
Description=
CertUserId=
Visible=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$RegId" ]; then
        read -p "Registration ID: " RegId
    fi
}

while getopts ":a:B:v:t:i:b:n:D:C:VWh" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    i) RegId=$OPTARG ;;
    b) Body=$OPTARG ;;
    n) AppName=$OPTARG ;;
    D) Description=$OPTARG ;;
    C) CertUserId=$OPTARG ;;
    V) Visible=true ;;
    W) Visible=false ;;
    h) print_usage ;;
    esac
done

require_args

if [ -z "$Body" ]; then
    # Fetch current registration and apply individual attribute changes
    Body=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
        -v "$Version" -s core -m GET -U "A2ARegistrations/$RegId" 2>/dev/null)
    Error=$(echo "$Body" | jq .Code 2>/dev/null)
    if [ -n "$Error" -a "$Error" != "null" ]; then
        >&2 echo "Error fetching A2A registration for edit:"
        echo "$Body" | jq . 2>/dev/null || echo "$Body"
        exit 1
    fi

    if [ -n "$AppName" ]; then
        Body=$(echo "$Body" | jq --arg v "$AppName" '.AppName = $v')
    fi
    if [ -n "$Description" ]; then
        Body=$(echo "$Body" | jq --arg v "$Description" '.Description = $v')
    fi
    if [ -n "$CertUserId" ]; then
        Body=$(echo "$Body" | jq --argjson v "$CertUserId" '.CertificateUserId = $v')
    fi
    if [ -n "$Visible" ]; then
        Body=$(echo "$Body" | jq --argjson v "$Visible" '.VisibleToCertificateUsers = $v')
    fi
fi

Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m PUT -U "A2ARegistrations/$RegId" -b "$Body" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error editing A2A registration:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

echo "$Result"
