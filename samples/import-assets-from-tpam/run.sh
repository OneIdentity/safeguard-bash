#!/bin/bash

if [ ! -f "$1" ]; then
    >&2 echo "You must specify an existing keyfile to access TPAM"
    >&2 echo "USAGE: run.sh keyfile"
    exit 1
fi

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

if [ ! -z "$(which docker)" ]; then
    $ScriptDir/build.sh
    echo -e "${YELLOW}Running the safeguard-import-assets-from-tpam container.\n" \
            "The keyfile you specified will automatically be copied to /tpam_id.${NC}"
    Id=$(docker run -it -d safeguard-import-assets-from-tpam -c /bin/bash)
    docker cp $1 "$Id:/tpam_id"
    echo -e "${YELLOW}Press any key...${NC}"
    docker attach $Id
else
    >&2 echo "You must install docker to use this script"
fi

