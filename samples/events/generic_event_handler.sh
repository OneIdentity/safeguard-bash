#!/bin/bash

if [ -z "$(which jq)" ]; then
    >&2 echo "This script requires the jq utility for parsing JSON response data from Safeguard"
    exit 1
fi

if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

read -t 0.5 Appliance
read -t 0.5 AccessToken
read -t 0.5 CABundle
read -t 0.5 EventData

echo -e "${YELLOW}$0 received Appliance:${NC} $Appliance"
echo -e "${YELLOW}$0 received AccessToken:${NC} $AccessToken"
echo -e "${YELLOW}$0 received CABundle file:${NC} $CABundle"
echo -e "${YELLOW}$0 received the following object...${NC}"
echo $EventData | jq .

