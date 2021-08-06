#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: install-license.sh [-h]
       install-license.sh [-v version] [-L licensefile]
       install-license.sh [-a appliance] [-t accesstoken] [-v version] [-L licensefile]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 3 is default
  -L  License file

Upload a license file to Safeguard.  This script will stage the license file then
immediately install it via the Web API.

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
Version=3
LicenseFile=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$LicenseFile" ]; then
        read -p "License file: " LicenseFile
    fi
    if [ ! -r "$LicenseFile" ]; then
        >&2 echo "Unable to read license file '$LicenseFile'"
        exit 1
    fi
}

while getopts ":t:a:v:L:h" opt; do
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
    L)
        LicenseFile=$OPTARG
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

echo "Staging license file..."
Response=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m POST -U Licenses -N -b "{
    \"Base64Data\": \"$(base64 $LicenseFile)\"
}" <<<$AccessToken)
echo $Response | jq .
if [ -z "$Response" ]; then
    >&2 echo "Invalid response while trying to stage license file"
    exit 1
fi
Key=$(echo $Response | jq -r '.Key')

echo "Installing license '$Key'..."
$ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -s core -m POST -U "Licenses/$Key/Install" -N -b "" <<<$AccessToken

