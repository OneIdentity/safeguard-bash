#!/bin/bash

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

if [ ! -z "$(which docker)" ]; then
    docker images | grep safeguard-bash
    if [ $? -ne 0 ]; then
        $ScriptDir/build.sh
    fi
    echo -e "${YELLOW}Running the safeguard-bash container.\n" \
            "You can specify an alternate startup command using arguments to this script.\n" \
            "The default entrypoint is bash, so use the -c argument.\n" \
            "  e.g. run.sh -c /bin/sh${NC}"
    docker run -it safeguard-bash "$@"
else
    >&2 echo "You must install docker to use this script"
fi

