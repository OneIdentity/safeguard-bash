#!/bin/bash

# Handle script parameters and usage
if [ "$1" = "-h" ]; then
    cat <<EOF
USAGE: certificate-login.sh [-h] appliance provider username
  You must specify the appliance network address
  You may specify an identity provider for a user admin (default: local)
  You may specify a username for a user admin (default: Admin)
  -h  Show help and exit
EOF
    exit 1
fi
if [ -z "$1" ]; then
    read -p "Appliance network address: " Appliance
else
    Appliance=$1
fi
if [ -z "$2" ]; then
    Provider=local
else
    Provider=$2
fi
if [ -z "$3" ]; then
    AdminUser=Admin
else
    AdminUser=$3
fi

# This script is meant to be run from within a fresh safeguard-bash Docker container
if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

# Get the directory of this script while executing
ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get the directory of the rest of safeguard-bash (may be same directory)
if [ -x "$ScriptDir/connect-safeguard.sh" ]; then
    SafeguardDir="$ScriptDir"
elif [ -x "../../src/connect-safeguard.sh" ]; then
    SafeguardDir="$( cd ../../src && pwd )"
else
    cat <<EOF
Unable to find the safeguard-bash scripts.
The best way to run this sample is from a safeguard-bash docker container.
EOF
    exit 1
fi

# Trusted certificates to upload to establish the chain of trust in Safeguard
CaCertFile="$ScriptDir/LoginTestCA.cert.pem"
IssuingCertFile="$ScriptDir/issuing-LoginTestCA.cert.pem"

# Certificiate file and private key file in PEM format
ClientCertFile="$ScriptDir/UserCert.cert.pem"
ClientKeyFile="$ScriptDir/UserCert.key.pem"

# Normally you wouldn't store this certificate password directly in your script file
# The video accompanying the A2A events sample explains how to handle certificates
# more securely.
ClientCertPassword="login"

# You can generate your own CAs for a two-level PKI using the new-test-ca.sh script
# in the src/utils directory.  The new-test-cert.sh script will generate certificates
# for client authentication (SSL) or server authentication (SSL).  It will also help
# with generating a certificate for audit log signing.

# Login details for the Safeguard certificate user to create
UserName="TestCertUser"
Thumbprint=$(openssl x509 -in $ClientCertFile -sha1 -noout -fingerprint | cut -d= -f2 | tr -d :)

echo "ScriptDir=$ScriptDir"
echo "SafeguardDir=$SafeguardDir"
echo "UserName=$UserName"
echo "Thumbprint=$Thumbprint"
echo "ClientCertFile=$ClientCertFile"
echo "ClientKeyFile=$ClientKeyFile"

echo -e "${YELLOW}\nLogging into Safeguard as user admin ($Provider/$AdminUser)...${NC}"
$SafeguardDir/connect-safeguard.sh -a $Appliance -i $Provider -u $AdminUser
if [ $? -ne 0 ]; then
    echo "Unable to connect to $Appliance"
    exit 1
fi

echo -e "${YELLOW}\nInstalling trusted root...${NC}"
$SafeguardDir/install-trusted-certificate.sh -C $CaCertFile
echo -e "${YELLOW}\nInstalling intermediate ca...${NC}"
$SafeguardDir/install-trusted-certificate.sh -C $IssuingCertFile

echo -e "${YELLOW}\nAdding certificate user named $UserName...${NC}"
$SafeguardDir/invoke-safeguard-method.sh -v 4 -s core -m POST -U Users -b "{
    \"PrimaryAuthenticationProvider\": {\"Id\":-2, \"Identity\":\"$Thumbprint\"},
    \"IdentityProvider\": {\"Id\": -1},
    \"Name\": \"$UserName\"
}"

echo -e "${YELLOW}\nLogging out as user admin ($Provider/$AdminUser)...${NC}"
$SafeguardDir/disconnect-safeguard.sh

echo -e "${YELLOW}\nLogging in as certificate user ($UserName)...${NC}"
$SafeguardDir/connect-safeguard.sh -a $Appliance -i certificate -c $ClientCertFile -k $ClientKeyFile -p <<<"$ClientCertPassword"

echo -e "${YELLOW}\nLogged in user info...${NC}"
$SafeguardDir/get-logged-in-user.sh

echo -e "${YELLOW}\nLogging out as certificate user ($UserName)...${NC}"
$SafeguardDir/disconnect-safeguard.sh

