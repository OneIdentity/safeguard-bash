#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: new-certificate-user.sh [-h]
       new-certificate-user.sh [-a appliance] [-t accesstoken] [-v version] [-n name] [-C file] [-s sha1]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 4 is default
  -n  Name for new user
  -C  User certificate file (used to obtain SHA-1 thumbprint)
  -s  SHA-1 thumbprint as a string

Create a certificate user in Safeguard that can be used to log in or to set up A2A.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq for parsing between requests."
    exit 1
fi

Appliance=
AccessToken=
Version=4
NewUserName=
NewUserThumbprint=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$NewUserName" ]; then
        read -p "New User Name: " NewUserName
    fi
    if [ -z "$NewUserThumbprint" ]; then
        read -p "New User SHA-1 Certificate Thumbprint: " NewUserThumbprint
    fi
}

while getopts ":t:a:v:n:C:s:h" opt; do
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
    n)
        NewUserName=$OPTARG
        ;;
    C)
        NewUserCert=$OPTARG
        if [ ! -r "$NewUserCert" ]; then
            >&2 echo "Unable to read certificate file '$NewUserCert'"
            exit 1
        fi
        set -e
        NewUserThumbprint=$(openssl x509 -noout -fingerprint -sha1 -in "$NewUserCert" | cut -d= -f2 | tr -d :)
        set +e
        ;;
    s)
        NewUserThumbprint=$OPTARG
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

if [ $Version -eq 4 ]; then
        $ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m POST -U "Users" -N -b "
{ \"Name\":\"$NewUserName\", \"IdentityProvider\": {\"Id\": -1}, \"PrimaryAuthenticationProvider\": {\"Id\":-2, \"Identity\":\"$NewUserThumbprint\"} }" <<<$AccessToken
else
        $ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m POST -U "Users" -N -b "
{ \"UserName\":\"$NewUserName\", \"IdentityProviderId\":-1, \"PrimaryAuthenticationProviderId\":-2, \"PrimaryAuthenticationIdentity\":\"$NewUserThumbprint\" }" <<<$AccessToken
fi

