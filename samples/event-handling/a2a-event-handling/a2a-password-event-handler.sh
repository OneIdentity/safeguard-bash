#!/bin/bash

# This is just a very simple a2a password handler script that just prints
# the new password every time it is called.

if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

# This read timeout is important to prevent hanging your event pipeline
read -t 1 Pass

echo -e "${YELLOW}$0 received Password:${NC} $Pass"

# The above functionality could easily be replaced to do something more
# useful with the password such as modify configuration or restart a service.

