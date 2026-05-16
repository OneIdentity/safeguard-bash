#!/bin/bash
if [ "$#" -lt 2 ]; then
    >&2 echo "Usage: versionnumber.sh <verNum> <buildId> [tagName] [isTagBuild]"
    exit 1
fi
verNum=$1
buildId=$2
tagName=${3:-""}
isTagBuild=${4:-"False"}

echo "verNum = $verNum"
echo "buildId = $buildId"
echo "tagName = $tagName"
echo "isTagBuild = $isTagBuild"

if [ "$isTagBuild" = "True" ] || [ "$isTagBuild" = "true" ]; then
    # Validate tag format: must be v<major>.<minor>.<patch>
    if ! echo "$tagName" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
        >&2 echo "ERROR: Tag '$tagName' does not match expected format 'v<major>.<minor>.<patch>'. Aborting release build."
        exit 1
    fi
    versionString="${tagName#v}"  # strip v prefix
    releaseTag="$tagName"
    echo "Tag build detected, using tag name as version"
else
    buildNumber=$(expr $buildId - 103500) # shrink shared build number appropriately
    echo "buildNumber = ${buildNumber}"
    versionString="$verNum"
    releaseTag="dev/v${verNum}-pre${buildNumber}"
    echo "Dev build"
fi

echo "VersionString = ${versionString}"
echo "ReleaseTag = ${releaseTag}"

echo "##vso[task.setvariable variable=VersionString;]$versionString"
echo "##vso[task.setvariable variable=ReleaseTag;]$releaseTag"
