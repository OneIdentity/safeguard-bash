#!/bin/bash

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

print_usage()
{
    cat <<EOF
USAGE: run.sh -v volume [-h] [args]

  -h  Show help and exit
  -v  Directory from host to mount into container at /volume
      This is useful for mounting a directory with certificates and private keys
  
      Additional options that will be passed on to 'docker run' command line 
      before the image specification. Using this run.sh script you cannot
      modify the command being run to start the container. You would have to
      do that by calling 'docker run' directly.

This script will create an image (if not already created) and run a container 
based on that image that listens to A2A for password change events and calls
the generic sample script that prints the current password.

You could easily extend this image using the Dockerfile to run a container that
does something much more interesting in your environment.

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

if [ -z "$Volume" ]; then
    >&2 echo "You must specify a directory to mount using the -v option"
    exit 1
fi

# Make sure they have docker installed
if [ ! -z "$(which docker)" ]; then
    # Check to be sure the safeguard-dockerdemo image has been created
    docker images | grep safeguard-dockerdemo
    if [ $? -ne 0 ]; then
        # If not, create it
        $ScriptDir/build.sh
    fi
    # Run a container based on safeguard-dockerdemo and pass additional arguments to it
    docker run -v "$Volume:/volume" "$@" -it safeguard-dockerdemo
else
    >&2 echo "You must install docker to use this script"
    exit 1
fi

