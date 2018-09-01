#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: listen-for-events.sh [-h]
       listen-for-events.sh
       listen-for-events.sh [-a appliance] [-t accesstoken]

  -h  Show help and exit
  -a  Network address of the appliance
  -t  Safeguard access token

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
Cert=
PKey=
Pass=

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
}

get_connection_token()
{
    NUM=`echo $(( ( RANDOM % 1000000000 )  + 1 ))`
    curl -s -k -H "Authorization: Bearer $AccessToken" \
        "https://$Appliance/service/event/signalr/negotiate?_=$NUM" \
        | sed -n -e 's/\+/%2B/g;s/\//%2F/g;s/.*"ConnectionToken":"\([^"]*\)".*/\1/p'
}


if [ ! -z "`which jq`" ]; then
    PRETTYPRINT="jq ."
else
    PRETTYPRINT="cat"
fi

while getopts ":t:a:h" opt; do
    case $opt in
    t)
        AccessToken=$OPTARG
        ;;
    a)
        Appliance=$OPTARG
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
stdbuf -o0 -e0 curl -s -k -H "Authorization: Bearer $AccessToken" "$Url$Params" \
    | sed -u -e '/^data: initialized/d;/^\s*$/d;s/^data: \(.*\)$/\1/g' | while read line; do echo $line | $PRETTYPRINT ; done

