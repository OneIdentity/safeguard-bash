#!/bin/bash

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

print_usage()
{
    cat <<EOF
USAGE: run.sh [-h] [args]

  -h  Show help and exit

This script will create an image for this sample and run a container 
based on that image.

EOF
    exit 0
}

while getopts ":v:h" opt; do
    case $opt in
    v)
        Volume=$OPTARG
        shift; shift;
        ;;
    h)
        print_usage
        ;;
    ?)
        break
        ;;
    esac
done

if test -t 1; then
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

# Make sure they have docker installed
if [ ! -z "$(which docker)" ]; then
    echo "Rebuilding the image: safeguard-certdemo ..."
    $ScriptDir/build.sh
    # Run a container based on safeguard-certdemo and pass additional arguments to it
    docker run -it safeguard-certdemo "$@"
else
    >&2 echo "You must install docker to use this script"
    exit 1
fi

