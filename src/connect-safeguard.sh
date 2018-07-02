#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: connect-safeguard.sh [-h]
       connect-safeguard.sh [-a appliance] [-v version] [-q]
       connect-safeguard.sh [-a appliance] [-v version] [-i provider] [-u user] [-p] [-X]
       connect-safeguard.sh [-a appliance] [-v version] -i certificate [-c file] [-k file] [-p] [-X]

  -h  Show help and exit
  -q  Query list of primary identity providers for appliance
  -a  Network address of the appliance
  -v  Web API Version: 2 is default
  -i  Safeguard identity provider, examples: certificate, local, ad<num>
  -u  Safeguard user to use
  -c  File containing client certificate
  -k  File containing client private key
  -p  Read Safeguard or certificate password from stdin
  -X  Do NOT generate login file for use in other scripts

The invoke-safeguard-method.sh and listen-for-safeguard-events.sh scripts will attempt
to use a login file by default. If one is not found this script will be called to
generate one. Subsequent invocations will use that login file until it is removed by
calling logout-safeguard.sh which will also call the logout service on the appliance.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
Version=2
QueryProviders=false
Providers=
Provider=
User=
Cert=
PKey=
PassStdin=
StsAccessToken=
AccessToken=
StoreLoginFile=true
LoginFile="$HOME/.safeguard_login"

require_args()
{
    if [ -z "$Appliance" ]; then
        read -p "Appliance Network Address: " Appliance
    fi
}

query_providers()
{
    if [ ! -z "$(which jq)" ]; then
        GetPrimaryProvidersRelativeURL="RSTS/UserLogin/LoginController?response_type=token&redirect_uri=urn:InstalledApplication&loginRequestStep=1"
        # certificate provider not returned by default because it is marked as not supporting HTML forms login
        Providers=$(curl -s -k -X POST -H 'Accept: application/x-www-form-urlencoded' "https://$Appliance/$GetPrimaryProvidersRelativeURL" \
                         -d 'RelayState=' | jq '.Providers|.[].Id' | xargs echo -n)
        if [ -z "$Providers" ]; then
            >&2 echo "Unable to obtain list of identity providers, does $Appliance exist?"
            exit 1
        fi
        Providers=$(echo certificate $Providers)
    fi
}

require_auth_args()
{
    query_providers
    if [ -z "$Provider" ]; then
        if [ ! -z "$Providers" ]; then
            read -p "Identity Provider ($Providers): " Provider
        else
            read -p "Identity Provider: " Provider
        fi
    fi
    if [ ! -z "$Providers" ]; then
        if ! [[ $Providers =~ (^|[[:space:]])$Provider($|[[:space:]]) ]]; then
            >&2 echo "Specified provider '$Provider' must be one of: $Providers!"; print_usage
        fi
    fi
    if [ "$Provider" = "certificate" ]; then
        if [ -z "$Cert" ]; then
            read -p "Client Certificate File: " Cert
        fi
        if [ -z "$PKey" ]; then
            read -p "Client Private Key File: " PKey
        fi
    else
        if [ -z "$User" ]; then
            read -p "Appliance Login: " User
        fi
    fi
    if [ -z "$Pass" ]; then
        read -s -p "Password: " Pass
        >&2 echo
    fi 
}

get_rsts_token()
{
    if [ "$Provider" = "certificate" ]; then
        StsResponse=$(curl -s -k --key $PKey --cert $Cert --pass $Pass -X POST -H 'Accept: application/json' \
                          -H 'Content-type: application/json' -d @- "https://$Appliance/RSTS/oauth2/token" <<EOF
{
    "grant_type": "client_credentials",
    "scope": "$Scope"
}
EOF
        )
        if [ -z "$StsResponse" ]; then
            # There is a bug in some Debian-based platforms with curl linked to GnuTLS where it doesn't properly
            # ignore certificate errors when using client certificate authentication. This works around that
            # problem by calling OpenSSL directly and manually formulating an HTTP request.
            StsResponse=$(cat <<EOF | openssl s_client -connect $Appliance:443 -quiet -crlf -key $PKey -cert $Cert -pass pass:$Pass 2>&1
POST /RSTS/oauth2/token HTTP/1.1
Host: $Appliance
User-Agent: curl/7.47.0
Accept: application/json
Connection: close
Content-type: application/json
Content-Length: 84

{"grant_type":"client_credentials","scope":"rsts:sts:primaryproviderid:certificate"}
EOF
            )
        fi
        if [ $? -ne 0 ]; then
            >&2 echo "Failed to get access token from appliance token service"
            >&2 echo "$StsResponse"
            exit 1
        fi
    else
        StsResponse=$(curl -s -S -k -X POST -H 'Accept: application/json' -H 'Content-type: application/json' \
                          -d @- "https://$Appliance/RSTS/oauth2/token" <<EOF
{
    "grant_type": "password",
    "username": "$User",
    "password": "$Pass",
    "scope": "$Scope"
}
EOF
        )
        if [ $? -ne 0 ]; then
            >&2 echo "Failed to get access token from appliance token service"
            >&2 echo "$StsResponse"
            exit 1
        fi
    fi
    TokenLine=$(echo $StsResponse | grep -Po '"access_token":.*?[^\\]",')
    if [ $? -ne 0 ]; then
        >&2 echo -e "Failed to get access token from appliance\n$StsResponse"
        exit 1
    fi
    StsAccessToken=$(echo $TokenLine | sed -e 's/^.*:.*"\(.*\)",/\1/')
}

get_safeguard_token()
{
    if [ ! -z "$StsAccessToken" ]; then
        LoginResponse=$(curl -s -S -k -X POST -H 'Accept: application/json' -H 'Content-type: application/json' \
                            -H "Authorization: Bearer $StsAccessToken" -d @- "https://$Appliance/service/core/v$Version/Token/LoginResponse" <<EOF
{
    "StsAccessToken": "$StsAccessToken"
}
EOF
        )
        if [ $? -ne 0 ]; then
            >&2 echo -e "Failed to get login response from appliance:\n$LoginResponse"
            exit 1
        fi
        Status=$(echo $LoginResponse | grep -Po '"Status":.*?[^\\]",')
        if [ $? -ne 0 ]; then
            >&2 echo -e "Failed to get status from login response:\n$LoginResponse"
            exit 1
        fi
        if [[ $Status =~ .*Success* ]]; then
            TokenLine=$(echo $LoginResponse | grep -Po '"UserToken":.*?[^\\]",')
            if [ $? -ne 0 ]; then
                >&2 echo -e "Failed to get user token from appliance:\n$LoginResponse"
                exit 1
            fi
            AccessToken=$(echo $TokenLine | sed -e 's/^.*:.*"\(.*\)",/\1/')
        elif [[ $Status =~ .*Unauthorized* ]]; then
            >&2 echo -e "Failure result from login response:\n$LoginResponse"
            exit 1
        else
            >&2 echo "Unable to handle status '$(echo $Status | sed -e 's/^.*:.*"\(.*\)",/\1/')'"
            exit 1
        fi
    fi
}


while getopts ":a:v:i:u:c:k:pqhX" opt; do
    case $opt in
    a)
        Appliance=$OPTARG
        ;;
    v)
        Version=$OPTARG
        ;;
    i)
        Provider=$OPTARG
        ;;
    u)
        User=$OPTARG
        ;;
    c)
        Cert=$OPTARG
        ;;
    k)
        PKey=$OPTARG
        ;;
    p)
        PassStdin="-p"
        ;;
    q)
        QueryProviders=true
        ;;
    X)
        StoreLoginFile=false
        ;;
    h)
        print_usage
        ;;
    esac
done

require_args

if $QueryProviders; then
    if [ ! -z "$(which jq)" ]; then
        query_providers
        echo $Providers
        exit 0
    else
        >&2 echo "You must install jq to query providers"
        exit 1
    fi
fi

require_auth_args

Scope="rsts:sts:primaryproviderid:$Provider"

get_rsts_token

get_safeguard_token

if [ -z "$AccessToken" ]; then
    >&2 echo "Failed to obtain access token from appliance"
    exit 1
fi

if $StoreLoginFile; then
    OldUmask=$(umask)
    umask 0077
    cat <<EOF > $LoginFile
Appliance=$Appliance
Provider=$Provider
AccessToken=$AccessToken
EOF
    if [ "$Provider" = "certificate" ]; then
        cat <<EOF >> $LoginFile
Cert=$Cert
PKey=$PKey
Pass=$Pass
EOF
    fi
    umask $OldUmask
    >&2 echo "A login file has been created."
else
    echo $AccessToken
fi

