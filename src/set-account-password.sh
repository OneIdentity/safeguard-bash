#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: set-account-password.sh [-h]
       set-account-password.sh [-v version] [-c accountid] [-p]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 3 is default
  -c  Account Id
  -p  Read new password from stdin

Create a new access request via the Web API. To request a session with your own credentials
pass null in for the Account Id.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq)" ]; then
    >&2 echo "This script requires jq for parsing and manipulating responses."
    exit 1
fi

Appliance=
AccessToken=
Version=3
AccountId=
Pass=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$AccountId" ]; then
        read -p "Account ID: " AccountId
    fi
    if [ -z "$Pass" ]; then
        read -s -p "New Password: " Pass
        >&2 echo
    fi
}

while getopts ":t:a:v:c:ph" opt; do
    case $opt in
    t)
        AccessToken=$OPTARG
        ;;
    a)
        Appliance=$OPTARG
        ;;
    v)
        Version=$OPTARG
        ;;
    c)
        AccountId=$OPTARG
        ;;
    p)
        # read password from stdin before doing anything
        read -s Pass
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

$ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m PUT -U "AssetAccounts/$AccountId/Password" -N -b "\"$Pass\"" <<<$AccessToken | jq .

