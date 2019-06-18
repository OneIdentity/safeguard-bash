#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-event.sh [-h]
       get-event.sh [-a appliance] [-t accesstoken] [-v version]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 2 is default

List the events that can be used

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which jq)" ]; then
    >&2 echo "This script requires jq for parsing between requests."
    exit 1
fi

Appliance=
AccessToken=
Version=2

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
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

Result=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -s core -m GET -U "Events?fields=Name,Description&orderby=Name" -N)
Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result | jq -r '.[] | "\(.Name) -- \(.Description)"' # display events as flat list
else
    echo $Result | jq . # display error as JSON
fi
