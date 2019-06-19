#!/bin/bash

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Make sure they have docker installed
if [ ! -z "$(which docker)" ]; then
    # Pull latest from oneidentity/safeguard-bash repo
    docker pull oneidentity/safeguard-bash
    # Build an image based on Dockerfile
    docker build --no-cache -t safeguard-eventdemo $ScriptDir
else
    >&2 echo "You must install docker to use this build script"
fi

