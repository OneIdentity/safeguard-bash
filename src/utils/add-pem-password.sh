#!/bin/bash

if [[ "$1" == "-h" ]]; then
    cat <<EOF

USAGE: add-pem-password.sh [pemFilePath]

pemFilePath  Provide the path to a PEM-formatted private key file

Running this will read the current PEM file password then rewrite the file
with AES-256 password encryption.

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

openssl rsa  -aes256 -in "$PemFile" -out "$PemFile"