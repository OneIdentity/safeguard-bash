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
if [ ! -r "/volume/$SG_CERTFILE" ]; then
    >&2 echo "$SG_CERTFILE certificate file not found in /volume/"
    exit 1
fi
if [ ! -r "/volume/$SG_KEYFILE" ]; then
    >&2 echo "$SG_KEYFILE certificate file not found in /volume/"
    exit 1
fi
echo "Executing a2a event listener..."
/scripts/handle-a2a-password-event.sh -a $SG_APPLIANCE -c /volume/$SG_CERTFILE -k /volume/$SG_KEYFILE -A $SG_APIKEY -O -S /samples/events/a2a_password_event_handler.sh -p <<<$SG_KEYFILE_PASSWORD
