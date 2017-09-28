#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: install-trusted-certificate.sh [-h]
       install-trusted-certificate.sh [-v version] [-C certificatefile] [-P password]
       install-trusted-certificate.sh [-a appliance] [-t accesstoken] [-v version] [-C certificatefile]

  -h  Show help and exit
  -a  Network address of the appliance
  -v  Web API Version: 2 is default
  -t  Safeguard access token
  -C  File containing certificate (PEM format, or DER-encoded)

Upload a certificate file to Safeguard for use as trusted root certificate.  This script will upload
the certificate to the cluster and immediately configure it for use with the entire cluster.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
AccessToken=
Version=2
RootCertificateFile=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    if [ -z "$RootCertificateFile" ]; then
        read -p "Certificate file: " RootCertificateFile
    fi
}

while getopts ":t:a:v:C:h" opt; do
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
        RootCertificateFile=$OPTARG
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

if [ ! -r "$RootCertificateFile" ]; then
    >&2 echo "Unable to read certificate file '$RootCertificateFile'"
    exit 1
fi

echo "Uploading '$RootCertificateFile'..."
$ScriptDir/invoke-safeguard-method.sh -a "$Appliance" -t "$AccessToken" -v $Version -s core -m POST -U TrustedCertificates -N -b "{
    \"Base64CertificateData\": \"$(base64 "$RootCertificateFile")\"
}"

