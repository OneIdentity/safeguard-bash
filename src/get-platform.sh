#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-platform.sh [-h]
       get-platform.sh [-a appliance] [-t accesstoken] [-v version] [-n platformname]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 3 is default

Get all access request favorites for this user via the Web API.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


Appliance=
AccessToken=
Version=3
PlatformName=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
}

while getopts ":t:a:v:n:h" opt; do
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
        PlatformName=$OPTARG
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

# Need a bash function to URL encode in invoke-safeguard-method.sh
PlatformName=$(echo $PlatformName | sed 's/ /%20/g')
if [ -z "$PlatformName" ]; then
    $ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m GET -U "Platforms" -N <<<$AccessToken
else
    $ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m GET \
        -U "Platforms?filter=DisplayName%20ieq%20'$PlatformName'%20or%20Name%20ieq%20'$PlatformName'" -N <<<$AccessToken
fi

