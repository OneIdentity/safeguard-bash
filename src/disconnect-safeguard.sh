#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: disconnect-safeguard.sh [-h]
       disconnect-safeguard.sh [-v version]

  -h  Show help and exit
  -v  Web API Version: 2 is default

This will call the logout service on the appliance and remove the login file
that has been stored for the current user. If no login file exists this script
will do nothing.

EOF
    exit 0
}

Version=2

if [ "$1" = "-h" ]; then
    print_usage
elif [ "$2" = "-v" ]; then
    Version=$3
fi

LoginFile="$HOME/.safeguard_login"

read_from_login_file()
{
    cat $LoginFile | grep $1 | cut -d \= -f 2
}

if [[ -r "$LoginFile" && -f "$LoginFile" ]]; then
    Appliance=$(read_from_login_file Appliance)
    Provider=$(read_from_login_file Provider)
    AccessToken=$(read_from_login_file AccessToken)
    if [ "$Provider" = "certificate" ]; then
        Cert=$(read_from_login_file Cert)
        PKey=$(read_from_login_file PKey)
        Pass=$(read_from_login_file Pass)
    fi
else
    >&2 echo "A login file was not found or is not readable!"
    exit 1
fi

>&2 echo "Removing current login file."
rm -f $LoginFile

>&2 echo "Calling logout service on appliance."
ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ "$Provider" = "certificate" ]; then
    curl -s -S -k -H 'Accept: application/json' -H "Authorization: Bearer $AccessToken" \
        --key $PKey --cert $Cert --pass $Pass "https://$Appliance/service/core/v$Version/Token/Logout" -d ""
else
    curl -s -S -k -H 'Accept: application/json' -H "Authorization: Bearer $AccessToken" \
        "https://$Appliance/service/core/v$Version/Token/Logout" -d ""
fi

