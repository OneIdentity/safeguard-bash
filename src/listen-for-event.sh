#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: listen_for_event.sh [-h]
       listen_for_event.sh [-a appliance] [-B cabundle] [-t accesstoken] [-T]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -t  Safeguard access token
  -T  Read Safeguard access token from stdin

By default listen-for-event.sh will look for a login file. If one
doesn't exist connect-safeguard.sh will be called to create one. Alternately,
you may pass an appliance address and an access token.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
AccessToken=
CABundle=
CABundleArg=

. "$ScriptDir/utils/loginfile.sh"

if [ ! -z "$(which gsed)" ]; then
    SED=gsed
else
    SED=sed
fi

get_connection_token()
{
    # this call does not require an authorization header
    curl -s $CABundleArg "https://$Appliance/service/event/signalr/negotiate?negotiateVersion=1" -d '' \
        | $SED -n -e 's/\+/%2B/g;s/\//%2F/g;s/.*"connectionId":"\([^"]*\)".*/\1/p'
}


if [ ! -z "`which jq`" ]; then
    PRETTYPRINT="jq ."
else
    PRETTYPRINT="cat"
fi

while getopts ":t:a:B:Th" opt; do
    case $opt in
    t)
        AccessToken=$OPTARG
        ;;
    a)
        Appliance=$OPTARG
        ;;
    B)
        CABundle=$OPTARG
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

require_login_args

ConnectionToken=`get_connection_token`
Url="https://$Appliance/service/event/signalr"
Params="?id=$ConnectionToken"
Body=$(echo -e "{\"protocol\":\"json\",\"version\":1}\x1E") # \x1E is record separator char
curl -K <(cat <<EOF
-s
$CABundleArg
-H "Authorization: Bearer $AccessToken"
EOF
) -d "$Body" "$Url$Params"

curl -N -K <(cat <<EOF
-s
$CABundleArg
-H "Authorization: Bearer $AccessToken"
EOF
) -H 'Accept: text/event-stream' "$Url$Params" | $SED -u -e '/^:.*$/d;/^\s*$/d;s/^data: \(.*\)$/\1/g' |
    while read line; do
        echo $line | $PRETTYPRINT
    done
