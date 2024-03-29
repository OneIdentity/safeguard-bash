#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: install-ssl-certificate.sh [-h]
       install-ssl-certificate.sh [-v version] [-C certificatefile] [-P password]
       install-ssl-certificate.sh [-a appliance] [-t accesstoken] [-v version] [-C certificatefile] [-P password]

  -h  Show help and exit
  -a  Network address of the appliance
  -v  Web API Version: 4 is default
  -t  Safeguard access token
  -C  File containing certificate (PKCS#12 format, ie p12 or pfx file)
  -P  Password to decrypt the certificate (otherwise you will be prompted)

Upload a certificate file to Safeguard for use as an SSL certificate.  This script will upload the
certificate to the cluster and immediately configure it for use with this appliance.

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
SSLCertificateFile=
SSLCertificatePassword=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$SSLCertificateFile" ]; then
        read -p "Certificate file: " SSLCertificateFile
    fi
    if [ -z "$SSLCertificatePassword" ]; then
        read -s -p "Certificate file password: " SSLCertificatePassword
        >&2 echo
    fi
    if [ ! -r "$SSLCertificateFile" ]; then
        >&2 echo "Unable to read certificate file '$SSLCertificateFile'"
        exit 1
    fi
}

while getopts ":t:a:v:C:P:h" opt; do
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
    C)
        SSLCertificateFile=$OPTARG
        ;;
    P)
        SSLCertificatePassword=$OPTARG
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

echo "Uploading '$SSLCertificateFile'..."
Response=$($ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -v $Version -s core -m POST -U SslCertificates -N -b "{
    \"Base64CertificateData\": \"$(base64 $SSLCertificateFile)\",
    \"Passphrase\": \"$SSLCertificatePassword\"
}" <<<$AccessToken)
echo $Response | jq .
if [ -z "$Response" ]; then
    >&2 echo "Invalid response while trying to upload certificate file"
    exit 1
fi
Thumbprint=$(echo $Response | jq -r .Thumbprint)

ApplianceId=$($ScriptDir/get-appliance-status.sh -a "$Appliance" | jq .ApplianceId)
if [ -z "$ApplianceId" ]; then
    >&2 echo "Unable to determine appliance ID from notification service"
    exit 1
fi

echo "Setting '$Thumbprint' as SSL certificate for '$Appliance', ID='$ApplianceId'..."
$ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -T -s core -m PUT -U "SslCertificates/$Thumbprint/Appliances" -N -b "[
    {
        \"Id\": $ApplianceId
    }
]" <<<$AccessToken

