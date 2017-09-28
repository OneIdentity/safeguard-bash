#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: download-support-bundle.sh [-h]
       download-support-bundle.sh [-v version] [-e] [-s]
       download-support-bundle.sh [-a appliance] [-t accesstoken] [-v version] [-e] [-s]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 2 is default
  -e  Include event logs in the support bundle (increases generation time)
  -s  Include session logs in the support bundle (increases generation time)

Download a support bundle from Safeguard. Including event logs will increase
the generation time. Including the session logs will dramatically increase the
generation time. When the progress bar appears, generation is complete and
downloading begins. Support bundle generation generally takes much longer than
the download.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Version=2
Appliance=
AccessToken=
IncludeEvents=false
IncludeSessions=false

. "$ScriptDir/loginfile-utils.sh"

require_args()
{
    require_login_args
}

while getopts ":t:a:v:esh" opt; do
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
    e)
        IncludeEvents=true
        ;;
    s)
        IncludeSessions=true
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

BundleFile="SG-$Appliance-$(date +%Y-%m-%d-%H-%M-%S).zip"
Url="https://$Appliance/service/appliance/v$Version/SupportBundle"
if [ "$IncludeEvents" = "true" ]; then
    Url="$Url?includeEventLogs=true"
else
    Url="$Url?includeEventLogs=false"
fi
if [ "$IncludeSessions" = "true" ]; then
    Url="$Url&includeSessionLogs=true"
else
    Url="$Url&includeSessionLogs=false"
fi

>&2 echo "Generating and downloading support bundle..."
curl -# -k -X GET -H "Accept: application/octet-stream" -H "Authorization: Bearer $AccessToken" $Url > $BundleFile
if [ -r "$BundleFile" ]; then
    BundleSize=$(du "$BundleFile" | cut -f1)
    if [ $BundleSize -gt 0 ]; then
        >&2 echo "File location: $BundleFile"
        exit 0
    fi
fi
>&2 echo "Failed to download support bundle"
exit 1
