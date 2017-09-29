#!/bin/bash

if [ -z "$1" ]; then
    cat <<EOF
USAGE: certificate-login.sh [-h] appliance
  You must specificy the appliance network address
  -h  Show help and exit
EOF
    exit 1
fi

# This script is meant to be run from within a fresh safeguard-bash Docker container
if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

echo -e "${YELLOW}Creating new test CA...${NC}"
/scripts/utils/new-test-ca.sh
echo -e "${YELLOW}Creating new client cert...${NC}"
/scripts/utils/new-test-cert.sh

CaDir=$(find /scripts/utils -maxdepth 1 ! -path /scripts/utils -type d | xargs readlink -f)
IssuingName="issuing-$(basename "$CaDir")"
IssuingDir="$CaDir/$IssuingName"
ClientCertDir="$IssuingDir/certs"
ClientKeyDir="$IssuingDir/private"

CaCertFile="$CaDir/certs/$(basename $CaDir).cert.pem"
IssuingCertFile="$ClientCertDir/$IssuingName.cert.pem"
ClientCertFile=$(find "$ClientCertDir" ! -path "$ClientCertDir" | grep -v $IssuingName.cert.pem | grep -v ca-chain)
ClientKeyFile=$(find "$ClientKeyDir" ! -path "$ClientKeyDir" | grep -v $IssuingName.key.pem)

UserName=$(basename $ClientCertFile | cut -d. -f1)
Thumbprint=$(openssl x509 -in $ClientCertFile -sha1 -noout -fingerprint | cut -d= -f2 | tr -d :)

echo "UserName=$UserName"
echo "Thumbprint=$Thumbprint"
echo "ClientCertFile=$ClientCertFile"
echo "ClientKeyFile=$ClientKeyFile"

echo -e "${YELLOW}\nLogging into Safeguard as bootstrap admin (local/Admin)...${NC}"
connect-safeguard.sh -a $1 -i local -u Admin

echo -e "${YELLOW}\nInstalling trusted root...${NC}"
install-trusted-certificate.sh -C $CaCertFile
echo -e "${YELLOW}\nInstalling intermediate ca...${NC}"
install-trusted-certificate.sh -C $IssuingCertFile

echo -e "${YELLOW}\nAdding certificate user named $UserName...${NC}"
invoke-safeguard-method.sh -s core -m POST -U Users -b "{
    \"PrimaryAuthenticationProviderId\": -2,
    \"UserName\": \"$UserName\",
    \"PrimaryAuthenticationIdentity\": \"$Thumbprint\"
}"

echo -e "${YELLOW}\nLogging out...${NC}"
disconnect-safeguard.sh

echo -e "${YELLOW}\nLogging in as $UserName...${NC}"
connect-safeguard.sh -a $1 -i certificate -c $ClientCertFile -k $ClientKeyFile
echo -e "${YELLOW}\nLogged in user info...${NC}"
get-logged-in-user-info.sh
