#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: new-user.sh [-h]
       new-user.sh [-a appliance] [-B cabundle] [-v version] [-t accesstoken]
                   [-n username] [-N displayname] [-d description] [-R adminroles] [-p]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -n  Username for the new local user (required)
  -N  Display name (defaults to username)
  -d  Description
  -R  Comma-separated admin roles to assign
      Valid roles: GlobalAdmin, Auditor, AssetAdmin, ApplianceAdmin, PolicyAdmin,
                   UserAdmin, HelpdeskAdmin, OperationsAdmin, ApplicationAuditor,
                   SystemAuditor
  -p  Read password for the new user from stdin

The new user is created against the local identity provider (Id: -1).

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundle=
CABundleArg=
Version=4
AccessToken=
UserName=
DisplayName=
Description=
AdminRoles=
Password=

. "$ScriptDir/utils/loginfile.sh"

while getopts ":a:B:v:t:n:N:d:R:ph" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    n) UserName=$OPTARG ;;
    N) DisplayName=$OPTARG ;;
    d) Description=$OPTARG ;;
    R) AdminRoles=$OPTARG ;;
    p)
        read -s Password
        ;;
    h) print_usage ;;
    esac
done

if [ -z "$UserName" ]; then
    >&2 echo "Error: -n username is required."
    exit 1
fi

if [ -z "$AccessToken" ]; then
    use_login_file
fi
require_login_args

if [ -z "$DisplayName" ]; then
    DisplayName="$UserName"
fi

# Build JSON body for user creation
Body="{\"Name\":\"$UserName\",\"DisplayName\":\"$DisplayName\",\"PrimaryAuthenticationProvider\":{\"Id\":-1}"
if [ -n "$Description" ]; then
    Body="$Body,\"Description\":\"$Description\""
fi
if [ -n "$AdminRoles" ]; then
    RolesJson=$(echo "$AdminRoles" | jq -R 'split(",") | map(gsub("^ +| +$";""))' 2>/dev/null)
    if [ -z "$RolesJson" ]; then
        >&2 echo "Error: could not parse admin roles"
        exit 1
    fi
    Body="$Body,\"AdminRoles\":$RolesJson"
fi
Body="$Body}"

# Create user
Result=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
    -v "$Version" -s core -m POST -U "Users" -b "$Body" 2>/dev/null)
Error=$(echo "$Result" | jq .Code 2>/dev/null)
if [ -n "$Error" -a "$Error" != "null" ]; then
    >&2 echo "Error creating user:"
    echo "$Result" | jq . 2>/dev/null || echo "$Result"
    exit 1
fi

UserId=$(echo "$Result" | jq -r '.Id' 2>/dev/null)

# Set password if provided
if [ -n "$Password" ]; then
    PassResult=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" \
        -v "$Version" -s core -m PUT -U "Users/$UserId/Password" \
        -b "\"$Password\"" 2>/dev/null)
    PassError=$(echo "$PassResult" | jq .Code 2>/dev/null)
    if [ -n "$PassError" -a "$PassError" != "null" ]; then
        >&2 echo "Warning: user created but failed to set password:"
        echo "$PassResult" | jq . 2>/dev/null || echo "$PassResult"
    fi
fi

echo "$Result"
