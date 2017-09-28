#!/bin/bash

# This script is meant to be run from within a fresh safeguard-bash Docker container

#/scripts/utils/new-test-ca.sh
#/scripts/utils/new-test-cert.sh

CaDir=$(find /scripts/utils -maxdepth 1 ! -path /scripts/utils -type d | xargs readlink -f)
IssuingName="issuing-$(basename "$CaDir")"
IssuingDir="$CaDir/$IssuingName"
ClientCertDir="$IssuingDir/certs"
ClientKeyDir="$IssuingDir/private"

ClientCertFile=$(find "$ClientCertDir" ! -path "$ClientCertDir" | grep -v $IssuingName.cert.pem | grep -v ca-chain)
ClientKeyFile=$(find "$ClientKeyDir" ! -path "$ClientKeyDir" | grep -v $IssuingName.key.pem)

UserName=$(basename $ClientCertDir | cut -d. -f1)
Thumbprint=$(openssl x509 -in $ClientCertFile -sha1 -noout -fingerprint)

echo "UserName=$UserName"
echo "ClientCertFile=$ClientCertFile"
echo "ClientKeyFile=$ClientKeyFile"

echo -e "\nLogging into Safeguard as administrator that can create users..."
connect-safeguard.sh

invoke-safeguard-method.sh -s core -m POST -U Users -b "{
    \"PrimaryAuthenticationProviderId\": -2,
    \"UserName\": \"$UserName\",
    \"PrimaryAuthenticationIdentity\": \"$Thumbprint\"
}"

disconnect-safeguard.sh
