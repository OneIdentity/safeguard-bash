#!/bin/bash

SourceDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TargetDir="$HOME/scripts"

# create scripts directory in your home directory if it doesn't exist
if [ ! -d "$TargetDir" ]; then
    mkdir -p "$TargetDir"
fi

# copy all of safeguard-bash into scripts directory
cp -R $SourceDir/src/* $TargetDir

# find bash profile
if [ -w "$HOME/.bash_profile" ]; then
    BashProfile="$HOME/.bash_profile"
elif [ -w "$HOME/.profile" ]; then
    BashProfile="$HOME/.profile"
else
    >&2 echo "Unable to find writable bash profile, cannot edit PATH"
fi

if [ ! -z "$BashProfile" ]; then
    echo <<EOF >> $BashProfile

# add script directory to PATH
if [[ ":\$PATH:" != *":$TargetDir:"* ]]; then
    PATH="\${PATH:+"\$PATH:"}$TargetDir"
fi

EOF
fi

