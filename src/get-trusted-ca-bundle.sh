#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: get-trusted-ca-bundle.sh [-h]
       get-trusted-ca-bundle.sh [-a appliance] [-t accesstoken] [-v version]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -v  Web API Version: 2 is default

Download trusted certificate authority bundle for the SSL certificate being
served by this appliance.

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
Version=2

. "$ScriptDir/utils/loginfile.sh"

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

require_login_args

Response=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" -v $Version -s appliance -m GET -U "ApplianceStatus" -N)
Error=$(echo $Response | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    ApplianceId=$(echo "$Response" | jq -r .Identity)
    ApplianceName=$(echo "$Response" | jq -r .Name)
    Response=$("$ScriptDir/invoke-safeguard-method.sh" -a "$Appliance" -t "$AccessToken" -v $Version -s core -m GET -U "SslCertificates?filter=Appliances.Id%20eq%20\"$ApplianceId\"" -N)
    Error=$(echo $Response | jq .Code 2> /dev/null)
    if [ -z "$Error" -o "$Error" = "null" ]; then
        SslCert=$(echo $Response | jq -r .[].Base64CertificateData)
        IssuerCerts=$(echo $Response | jq -r '.[].IssuerCertificates | join("")')
        OutFile="$ApplianceName.ca-bundle.crt"
        if [ -z "$IssuerCerts" ]; then
            >&2 echo "Saving self-signed SSL certificate to $OutFile"
            echo "$SslCert" >"$OutFile"
        else
            >&2 echo "Saving SSL certificate issuers to $OutFile"
            echo "$IssuerCerts" >"$OutFile"
        fi
    else
        echo $Response | jq .
    fi
else
    echo $Response | jq .
fi
