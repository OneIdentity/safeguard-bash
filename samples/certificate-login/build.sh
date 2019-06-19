#!/bin/bash

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Make sure they have docker installed
if [ ! -z "$(which docker)" ]; then
    # Build an image based on Dockerfile
    docker build -t safeguard-certdemo $ScriptDir
else
    >&2 echo "You must install docker to use this build script"
fi

