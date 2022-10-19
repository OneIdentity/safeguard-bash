#!/bin/bash

if [[ "$1" == "-h" ]]; then
    cat <<EOF

USAGE: convert-pfx-to-pem.sh [pfxFilePath]

pfxFilePath  Provide the path to a PFX or PKCS#12 file

Running this prompt for the current PFX password if needed then write a PEM-formatted
certificate file and a PEM-formatted private key file (no password).

EOF
    exit 0
fi

set -e

cleanup()
{
    set +e
}

trap cleanup EXIT

if [ -z "$1" ]; then
    read -p "Enter PFX or PKCS#12 file path:" PfxFile
else
    PfxFile=$1
fi
if [ ! -f "$PfxFile" ]; then
    >&2 echo "$PfxFile does not exist"
    exit 1
fi

if [[ "$PfxFile" == *.p12 || "$PfxFile" == *.pfx ]]; then
    PemBase=${PfxFile::-4}
else
    PemBase=$PfxFile
fi

>&2 echo "Extracting the private key to ${PemBase}.key.pem..."
openssl pkcs12 -in "$PfxFile" -nocerts -out "${PemBase}.key.pem" -nodes

>&2 echo "Extracting the certificate to ${PemBase}.cert.pem..."
openssl pkcs12 -in "$PfxFile" -clcerts -nokeys -out "${PemBase}.cert.pem"