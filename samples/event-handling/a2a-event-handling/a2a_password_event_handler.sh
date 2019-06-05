#!/bin/bash

if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

read -t 0.5 Pass

echo -e "${YELLOW}$0 received Password:${NC} $Pass"

