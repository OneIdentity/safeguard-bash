#!/bin/bash

if [ -z "$(which jq)" ]; then
    >&2 echo "This script requires the jq utility for parsing JSON response data from Safeguard"
    exit 1
fi

if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

read line
echo -e "${YELLOW}$0 received the following object...${NC}"
echo $line | jq .
