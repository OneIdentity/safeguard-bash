#!/bin/bash

if [ -z "$(which jq)" ]; then
    >&2 echo "This script requires jq for parsing and manipulating responses."
    exit 1
fi

# Handle script parameters and usage
if [ "$1" = "-h" ]; then
    cat <<EOF
USAGE: setup.sh [-h] appliance
  You must specify the appliance network address
  -h  Show help and exit
EOF
    exit 1
fi
if [ -z "$1" ]; then
    read -p "Appliance network address: " Appliance
else
    Appliance=$1
fi

# This script is meant to be run from within a fresh safeguard-bash Docker container
if test -t 1; then
    YELLOW='\033[1;33m'
    CYAN='\033[1;36m'
    NC='\033[0m'
fi

# Get the directory of this script while executing
ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get the directory of the rest of safeguard-bash (may be same directory)
if [ -x "$ScriptDir/connect-safeguard.sh" ]; then
    SafeguardDir="$ScriptDir"
elif [ -x "../../../src/connect-safeguard.sh" ]; then
    SafeguardDir="$( cd ../../../src && pwd )"
else
    cat <<EOF
Unable to find the safeguard-bash scripts.
The best way to run this sample is from a safeguard-bash docker container.
EOF
    exit 1
fi

# Trusted certificates to upload to establish the chain of trust in Safeguard
CaCertFile="$ScriptDir/certs/A2ATestCA.cert.pem"
IssuingCertFile="$ScriptDir/certs/issuing-A2ATestCA.cert.pem"

# Certificiate file and private key file in PEM format
ClientCertFile="$ScriptDir/certs/A2AUser.p12"

# Normally you wouldn't store this certificate password directly in your script file,
# but this is just a sample setup script.
ClientCertPassword="test"

# You can generate your own CAs for a two-level PKI using the new-test-ca.sh script
# in the src/utils directory.  The new-test-cert.sh script will generate certificates
# for client authentication (SSL) or server authentication (SSL).  It will also help
# with generating a certificate for audit log signing.

# Login details for the Safeguard certificate user to create
CertUserName="SampleTestA2AUser"
Thumbprint=$(openssl pkcs12 -in $ClientCertFile -nodes -passin "pass:$ClientCertPassword" | openssl x509 -sha1 -noout -fingerprint | cut -d= -f2 | tr -d :)

# Login details of Setup user to create (deleted after script is run)
SetupUserName="SampleSetupA2AUserDELETEME"
SetupUserPassword="AbcDEF12345qq"

# Test asset and account
AssetName="safeguard-bash-test"
AccountName="a2a"

# Test a2a registration
A2ARegName="safeguard-bash-test-a2a-reg"

echo "ScriptDir=$ScriptDir"
echo "SafeguardDir=$SafeguardDir"
echo "CertUserName=$CertUserName"
echo "Thumbprint=$Thumbprint"
echo "ClientCertFile=$ClientCertFile"

echo -e "${YELLOW}\nLogging into Safeguard as user admin (local/Admin)...${NC}"
$SafeguardDir/connect-safeguard.sh -a $Appliance -i local -u Admin
if [ $? -ne 0 ]; then
    echo "Unable to connect to $Appliance"
    exit 1
fi

echo -e "${YELLOW}\nInstalling trusted root...${NC}"
$SafeguardDir/install-trusted-certificate.sh -C $CaCertFile
echo -e "${YELLOW}\nInstalling intermediate ca...${NC}"
$SafeguardDir/install-trusted-certificate.sh -C $IssuingCertFile

echo -e "${YELLOW}\nAdding certificate user named $CertUserName...${NC}"
Result=$($SafeguardDir/invoke-safeguard-method.sh -s core -m POST -U Users -N -b "{
    \"PrimaryAuthenticationProviderId\": -2,
    \"UserName\": \"$CertUserName\",
    \"PrimaryAuthenticationIdentity\": \"$Thumbprint\"
}")
Error=$(echo $Result | jq .Code 2> /dev/null)
echo $Result | jq .
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result | jq .
    CertUserId=$(echo $Result | jq .Id)
else
    echo "Unable to create certificate user ($CertUserName)"
    exit 1
fi

echo -e "${YELLOW}\nAdding setup user named $SetupUserName...${NC}"
Result=$($SafeguardDir/invoke-safeguard-method.sh -s core -m POST -U Users -N -b "{
    \"PrimaryAuthenticationProviderId\": -1,
    \"UserName\": \"$SetupUserName\",
    \"AdminRoles\": [\"PolicyAdmin\",\"AssetAdmin\"]
}")
Error=$(echo $Result | jq .Code 2> /dev/null)
echo $Result | jq .
if [ -z "$Error" -o "$Error" = "null" ]; then
    UserId=$(echo $Result | jq .Id)
    echo -e "${YELLOW}\nSeting setup user password (if this fails due to policy modify this script)...${NC}"
    $SafeguardDir/invoke-safeguard-method.sh -s core -m PUT -U "Users/$UserId/Password" -b "\"$SetupUserPassword\""
else
    echo "Unable to create setup user (local/$SetupUserName)"
    exit 1
fi

echo -e "${YELLOW}\nLogging out as user admin (local/Admin)...${NC}"
$SafeguardDir/disconnect-safeguard.sh

echo -e "${YELLOW}\nLogging into Safeguard as setup user (local/$SetupUserName)...${NC}"
$SafeguardDir/connect-safeguard.sh -a $Appliance -i local -u $SetupUserName -p <<<$SetupUserPassword
if [ $? -ne 0 ]; then
    echo "Unable to connect to $Appliance"
    exit 1
fi

echo -e "${YELLOW}\nCreating a test asset ($AssetName)...${NC}"
Result=$($SafeguardDir/invoke-safeguard-method.sh -s core -m POST -U Assets -N -b "{
    \"AssetPartitionId\": -1,
    \"PlatformId\": 190,
    \"Name\": \"$AssetName\",
    \"Description\": \"This should be deleted\"
}")
Error=$(echo $Result | jq .Code 2> /dev/null)
echo $Result | jq .
if [ -z "$Error" -o "$Error" = "null" ]; then
    AssetId=$(echo $Result | jq .Id)
    echo -e "${YELLOW}\nCreating a test account ($AccountName)...${NC}"
    Result=$($SafeguardDir/invoke-safeguard-method.sh -s core -m POST -U AssetAccounts -N -b "{
        \"AssetId\": $AssetId,
        \"Name\": \"$AccountName\",
        \"Description\": \"This should be deleted\"
    }")
    Error=$(echo $Result | jq .Code 2> /dev/null)
    echo $Result | jq .
    if [ -z "$Error" -o "$Error" = "null" ]; then
        AccountId=$(echo $Result | jq .Id)
        echo -e "${YELLOW}\nCreating a test a2a registration ($A2ARegName)...${NC}"
        Result=$($SafeguardDir/invoke-safeguard-method.sh -s core -m POST -U A2ARegistrations -N -b "{
            \"CertificateUserId\": $CertUserId,
            \"AppName\": \"$A2ARegName\",
            \"Description\": \"This should be deleted\"
        }")
        Error=$(echo $Result | jq .Code 2> /dev/null)
        echo $Result | jq .
        if [ -z "$Error" -o "$Error" = "null" ]; then
            A2ARegId=$(echo $Result | jq .Id)
            Result=$($SafeguardDir/invoke-safeguard-method.sh -s core -m POST -U "A2ARegistrations/$A2ARegId/RetrievableAccounts" -N -b "{
                \"SystemId\": $AssetId,
                \"AccountId\": $AccountId
            }")
            Error=$(echo $Result | jq .Code 2> /dev/null)
            echo $Result | jq .
            if [ -z "$Error" -o "$Error" = "null" ]; then
                ApiKey=$(echo $Result | jq .ApiKey)
            else
                echo "Unable to create test a2a registration account retrieval"
            fi
        else
            echo "Unable to create test a2a registration ($A2ARegName)"
        fi
    else
        echo "Unable to create test account ($AssetName/$AccountName)"
    fi
else
    echo "Unable to create test asset ($AssetName)"
fi

echo -e "${YELLOW}\nLogging out as setup user ($SetupUserName)...${NC}"
$SafeguardDir/disconnect-safeguard.sh

echo -e "${YELLOW}\nLogging into Safeguard as user admin (local/Admin)...${NC}"
$SafeguardDir/connect-safeguard.sh -a $Appliance -i local -u Admin
if [ $? -ne 0 ]; then
    echo "Unable to connect to $Appliance"
    exit 1
fi

echo -e "${YELLOW}\nDeleting setup user (local/$SetupUserName)...${NC}"
$SafeguardDir/invoke-safeguard-method.sh -s core -m DELETE -U "Users/$UserId"

echo -e "${YELLOW}\nLogging out as user admin (local/Admin)...${NC}"
$SafeguardDir/disconnect-safeguard.sh

if [ -z "$ApiKey" ]; then
    echo "Something has gone wrong and you need to clean up and try to run this script again."
    exit 1
else
    echo -e "${YELLOW}Thumbprint${NC}=${CYAN}$Thumbprint${NC}"
    echo -e "${YELLOW}ApiKey${NC}=${CYAN}$ApiKey${NC}"
fi
