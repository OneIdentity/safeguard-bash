#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: disconnect-safeguard.sh [-h]
       disconnect-safeguard.sh [-v version] 
       disconnect-safeguard.sh [-a appliance] [-t accesstoken] [-v version] 

  -h  Show help and exit
  -a  Network address of the appliance
  -v  Web API Version: 2 is default
  -t  Safeguard access token

This will call the logout service on the appliance and remove the login file
that has been stored for the current user. Or, if an appliance and access
token are supplied the access token will be logged out.

EOF
    exit 0
}

Appliance=
AccessToken=
Version=2

LoginFile="$HOME/.safeguard_login"

read_from_login_file()
{
    cat $LoginFile | grep $1 | cut -d \= -f 2
}

while getopts ":t:a:v:h" opt; do
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
    h)
        print_usage
        ;;
    esac
done

if [ ! -z "$Appliance" -a ! -z "$AccessToken" ]; then
    >&2 echo "Ignoring any login file and using specified access token."
elif [[ -r "$LoginFile" && -f "$LoginFile" ]]; then
    Appliance=$(read_from_login_file Appliance)
    Provider=$(read_from_login_file Provider)
    AccessToken=$(read_from_login_file AccessToken)
    if [ "$Provider" = "certificate" ]; then
        Cert=$(read_from_login_file Cert)
        PKey=$(read_from_login_file PKey)
    fi

    >&2 echo "Removing current login file."
    rm -f $LoginFile
else
    >&2 echo "A login file was not found or is not readable!"
    exit 1
fi

>&2 echo "Calling logout service on appliance."
curl -s -S -k -H 'Accept: application/json' -H "Authorization: Bearer $AccessToken" \
     "https://$Appliance/service/core/v$Version/Token/Logout" -d ""

