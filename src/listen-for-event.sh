#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: listen_for_event.sh [-h]
       listen_for_event.sh
       listen_for_event.sh [-a appliance] [-t accesstoken] [-T]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token
  -T  Read Safeguard access token from stdin

By default listen-for-events.sh will look for a login file. If one
doesn't exist connect-safeguard.sh will be called to create one. Alternately,
you may pass an appliance address and an access token.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
AccessToken=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
}

get_connection_token()
{
    NUM=`echo $(( ( RANDOM % 1000000000 )  + 1 ))`
    # this call does not require an authorization header
    curl -s -k "https://$Appliance/service/event/signalr/negotiate?_=$NUM" \
        | sed -n -e 's/\+/%2B/g;s/\//%2F/g;s/.*"ConnectionToken":"\([^"]*\)".*/\1/p'
}


if [ ! -z "`which jq`" ]; then
    PRETTYPRINT="jq ."
else
    PRETTYPRINT="cat"
fi

while getopts ":t:a:Th" opt; do
    case $opt in
    t)
        AccessToken=$OPTARG
        ;;
    a)
        Appliance=$OPTARG
        ;;
    T)
        # read AccessToken from stdin before doing anything
        read -s AccessToken
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

ConnectionToken=`get_connection_token`
TID=`echo $(( ( RANDOM % 1000 )  + 1 ))`
Url="https://$Appliance/service/event/signalr/connect"
Params="?transport=serverSentEvents&connectionToken=$ConnectionToken&connectionData=%5b%7b%22name%22%3a%22notificationHub%22%7d%5d&tid=$TID"
stdbuf -o0 -e0 curl -K <(cat <<EOF
-s
-k
-H "Authorization: Bearer $AccessToken"
EOF
) "$Url$Params" | sed -u -e '/^data: initialized/d;/^\s*$/d;s/^data: \(.*\)$/\1/g' | while read line; do echo $line | $PRETTYPRINT ; done

