#!/bin/bash
trap "exit 1" TERM
export TOP_PID=$$

if [ ! -z "$1" ]; then
    Version="${1}"
    DockerVersionStr="${Version}-"
fi

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$(which docker)" ]; then
    >&2 echo "You must install docker to use this build script"
fi

if [ ! -z "$(docker images -q oneidentity/safeguard-bash:${DockerVersionStr}alpine)" ]; then
    echo "Cleaning up the old image: oneidentity/safeguard-bash:${DockerVersionStr}alpine ..."
    docker rmi --force "oneidentity/safeguard-bash:${DockerVersionStr}alpine"
fi
echo "Building a new image: oneidentity/safeguard-bash:${DockerVersionStr}alpine ..."
docker build --no-cache -t "oneidentity/safeguard-bash:${DockerVersionStr}alpine" $ScriptDir

echo "Creating zip file artifact ..."
if [ -z "$Version" ]; then Version=999.999.999; fi
ZipFolderName="safeguard-bash-${Version}"
ZipFileName="$ZipFolderName.zip"
if [ -f "$ZipFileName" ]; then
    echo "Cleaning up the old zip: $ZipFileName ..."
    rm -f $ZipFileName
fi
CurDir=`pwd`
cd $ScriptDir
mkdir $ZipFolderName
cp install-local.sh $ZipFolderName
cp -r src $ZipFolderName
cp -r samples $ZipFolderName
cp -r test $ZipFolderName
zip -r $ZipFileName $ZipFolderName
rm -rf $ZipFolderName
cd $CurDir
