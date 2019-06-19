#!/bin/bash

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ ! -z "$(which docker)" ]; then
    docker pull oneidentity/safeguard-bash
    docker build --no-cache -t safeguard-import-assets-from-tpam $ScriptDir
else
    >&2 echo "You must install docker to use this build script"
fi

