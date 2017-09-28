#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: invoke-safeguard-method.sh [-h]
       invoke-safeguard-method.sh [-s service] [-m method] [-v version]
                                  [-U relativeurl] [-C contenttype] [-A accept] [-H header] [-b body] [-N]
       invoke-safeguard-method.sh [-a appliance] [-n] [-s service] [-m method] [-v version]
                                  [-U relativeurl] [-C contenttype] [-A accept] [-H header] [-b body] [-N]
       invoke-safeguard-method.sh [-a appliance] [-t accesstoken] [-s service] [-m method] [-v version]
                                  [-U relativeurl] [-C contenttype] [-A accept] [-H header] [-b body] [-N]

  -h  Show help and exit
  -a  Network address of the appliance
  -v  Web API Version: 2 is default
  -n  Anonymous authentication, don't use login file either
  -t  Safeguard access token
  -s  Service: core, appliance, cluster, notification
  -m  HTTP Method: GET, PUT, POST, DELETE
  -U  Relative resource URL (e.g. AccessRequests)
  -C  Content-type header
  -A  Accept header
  -H  Additional header (e.g. 'X-Force-Delete: true')
  -b  Body as JSON string
  -N  Filter out null values (up to three levels--requires jq)

Create a login file using connect-safeguard.sh for convenience. A login file is
required in order to use certificate authentication. If a login file is not used
connect-safeguard.sh will be called to create one. You may also use the -n option for 
anonymous authentication or the -a and -t options to specify an access token.

NOTE: Install jq to get pretty-printed JSON output.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
Provider=
AccessToken=
Cert=
PKey=
Pass=

Version=2
Service=
Method="GET"
RelativeUrl=
ExtraHeader=
Anonymous=false
Accept="application/json"
ContentType="application/json"
Body=
FilterNulls=false

. "$ScriptDir/loginfile-utils.sh"

require_args()
{
    $Anonymous
    if [[ $? -ne 0 && -z "$Appliance" && -z "$AccessToken" ]]; then
        use_login_file
    else
        if [ -z "$Appliance" ]; then
            read -p "Appliance network address: " Appliance
        fi
        if ! $Anonymous; then
            if [ -z "$AccessToken" ]; then
                AccessToken=$($ScriptDir/connect-safeguard.sh -a $Appliance -X)
            fi
        fi
    fi
    if [ -z "$Service" ]; then
        read -p "Service [core,appliance,cluster,notification]: " Service
    fi
    Service=$(echo "$Service" | tr '[:upper:]' '[:lower:]')
    case $Service in
        core|appliance|cluster|notification) ;;
        *) >&2 echo "Must specify a valid Safeguard service name!"; print_usage ;;
    esac
    if [ -z "$Method" ]; then
        read -p "HTTP method: " Method
    fi
    Method=$(echo "$Method" | tr '[:lower:]' '[:upper:]')
    case $Method in
        GET|PUT|POST|DELETE) ;;
        *) >&2 echo "Must specify a valid HTTP method!"; print_usage ;;
    esac
    if ! [[ $Version =~ ^[0-9]+$ ]]; then
        >&2 echo "Version must be a number!"; print_usage
    fi
    if [ -z "$RelativeUrl" ]; then
        read -p "Relative resource URL: " RelativeUrl
    fi
}

while getopts ":t:na:v:s:m:U:C:A:H:b:Nh" opt; do
    case $opt in
    t)
        if $Anonymous; then
            >&2 echo "You cannot specify anonymous (-n) with a token (-t)!"; print_usage
        fi
		AccessToken=$OPTARG
        ;;
    n)
        if [ ! -z "$AccessToken" ]; then
            >&2 echo "You cannot specify anonymous (-n) with a token (-t)!"; print_usage
        fi
        Anonymous=true
        ;;
    a)
        Appliance=$OPTARG
        ;;
    v)
        Version=$OPTARG
        ;;
    s)
        Service=$OPTARG
        ;;
    m)
        Method=$OPTARG
        ;;
    U)
        RelativeUrl=$OPTARG
        ;;
    C)
        ContentType=$OPTARG
        ;;
    A)
        Accept=$OPTARG
        ;;
    H)
        ExtraHeader=(-H "$OPTARG")
        ;;
    b)
        Body=$OPTARG
        ;;
    N)
        FilterNulls=true
        ;;
    h)
        print_usage
        ;;
    esac
done

PRETTYPRINT='cat'
if [ "$Accept" = "application/json" ]; then
    if [ ! -z "$(which jq)" ]; then
        if $FilterNulls; then
            # If we had walk we could replace everything recursively with
            #   walk( if type == "object" then with_entries(select(.value != null)) else . end)
            # The real problem just comes down to quoting and using $PRETTYPRINT to also work for cat
            PRETTYPRINT='jq del(.[]?|nulls)|del(.[]?[]?|nulls)|del(.[]?[]?[]?|nulls)|del(.[]?[]?[]?[]?|nulls)'
        else
            PRETTYPRINT='jq .'
        fi
    fi
fi

require_args

Url="https://$Appliance/service/$Service/v$Version/$RelativeUrl"
case $Method in
    GET|DELETE)
        curl -s -k -X $Method "${ExtraHeader[@]}" -H "Accept: $Accept" -H "Authorization: Bearer $AccessToken" $Url | $PRETTYPRINT
    ;;
    PUT|POST)
        curl -s -k -X $Method "${ExtraHeader[@]}" -H "Accept: $Accept" -H "Content-type: $ContentType" \
             -H "Authorization: Bearer $AccessToken" -d @- $Url <<EOF | $PRETTYPRINT
            $Body
EOF
    ;;
esac
