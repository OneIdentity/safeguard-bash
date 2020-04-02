#!/bin/bash
trap "exit 1" TERM
export TOP_PID=$$

if [ ! -z "$1" ]; then
    Version="${1}-"
fi

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which docker)" ]; then
    >&2 echo "You must install docker to use this build script"
fi

if [ ! -z "$(docker images -q oneidentity/safeguard-bash:${Version}alpine)" ]; then
    echo "Cleaning up the old image: oneidentity/safeguard-bash:${Version}alpine ..."
    docker rmi --force "oneidentity/safeguard-bash:${Version}alpine"
fi
echo "Building a new image: oneidentity/safeguard-bash:${Version}alpine ..."
docker build --no-cache -t "oneidentity/safeguard-bash:$Version$ImageType" $ScriptDir

