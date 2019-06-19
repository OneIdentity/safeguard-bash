#!/bin/bash
echo "Checking for environment information"
if [ -z "$SG_APPLIANCE" -o -z "$SG_CERTFILE" -o -z "$SG_KEYFILE" -o -z "$SG_APIKEY" -o -z "$SG_KEYFILE_PASSWORD" ]; then
    >&2 cat <<EOF
All environment variables are not set
    SG_APPLIANCE=$SG_APPLIANCE
    SG_CERTFILE=$SG_CERTFILE
    SG_KEYFILE=$SG_KEYFILE
    SG_APIKEY=<length ${#SG_APIKEY}>
    SG_KEYFILE_PASSWORD=<length ${#SG_KEYFILE_PASSWORD}>
EOF
    exit 1
fi

# Get the directory of this script while executing
ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get the directory of the rest of safeguard-bash (may be same directory)
if [ -x "$ScriptDir/connect-safeguard.sh" ]; then
    SafeguardDir="$ScriptDir"
elif [ -x "../../../src/connect-safeguard.sh" ]; then
    SafeguardDir="$( cd ../../../src && pwd )"
else
    cat <<EOF
Unable to find the safeguard-bash scripts.
The best way to run this sample is from a safeguard-bash docker container.
EOF
    exit 1
fi

# Get the volume directory (may be the same directory when not running in container)
if [ -r "$ScriptDir/certs/$SG_CERTFILE" ]; then
    VolumeDir="$ScriptDir/certs"
elif [ -r "/volume/$SG_CERTFILE" ]; then
    VolumeDir="/volume"
else
    >&2 echo "$SG_CERTFILE certificate file not found in /volume/"
    exit 1
fi
if [ ! -r "$VolumeDir/$SG_KEYFILE" ]; then
    >&2 echo "$SG_KEYFILE certificate file not found in $VolumeDir"
    exit 1
fi

echo "Executing a2a event listener..."
SampleHandlerScript=$SafeguardDir/../samples/event-handling/a2a-event-handling/a2a-password-event-handler.sh
>&2 echo "SampleHandlerScript=$SampleHandlerScript"
$SafeguardDir/handle-a2a-password-event.sh -a $SG_APPLIANCE -c $VolumeDir/$SG_CERTFILE -k $VolumeDir/$SG_KEYFILE -A $SG_APIKEY -O -S $SampleHandlerScript -p <<<$SG_KEYFILE_PASSWORD

