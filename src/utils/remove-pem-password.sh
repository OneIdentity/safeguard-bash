#!/bin/bash

if [[ "$1" == "-h" ]]; then
    cat <<EOF

USAGE: remove-pem-password.sh [pemFilePath]

pemFilePath  Provide the path to a PEM-formatted private key file

Running this prompt for the current PEM file password then rewrite the file
without password encryption.

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
    read -p "Enter PEM private key file path:" PemFile
else
    PemFile=$1
fi
if [ ! -f "$PemFile" ]; then
    >&2 echo "$PemFile does not exist"
    exit 1
fi

openssl rsa -in "$PemFile" -out "$PemFile"