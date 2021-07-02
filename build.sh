#!/bin/bash
trap "exit 1" TERM
export TOP_PID=$$

if [ ! -z "$1" ]; then
    Version="${1}"
    DockerVersionStr="${Version}-"
fi

if [ ! -z "$2" ]; then
    CommitId="${2}"
fi

if [ -z "$Version" ]; then
    Version=999.999.999
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
docker build \
    --no-cache \
    --build-arg BUILD_VERSION=$Version \
    --build-arg COMMIT_ID=$CommitId \
    -t "oneidentity/safeguard-bash:${DockerVersionStr}alpine" \
    $ScriptDir
docker tag "oneidentity/safeguard-bash:${DockerVersionStr}alpine" "oneidentity/safeguard-bash:latest"

echo "Creating zip file artifact ..."
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
