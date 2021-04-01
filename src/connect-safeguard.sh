#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: connect-safeguard.sh [-h]
       connect-safeguard.sh [-a appliance] [-B cabundle] [-v version] [-i provider] [-u user] [-p] [-X]
       connect-safeguard.sh [-a appliance] [-B cabundle] [-v version] -i certificate [-c file] [-k file] [-p] [-X]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 3 is default
  -i  Safeguard identity provider, examples: certificate, local, ad<num>
  -u  Safeguard user to use
  -c  File containing client certificate
  -k  File containing client private key
  -p  Read Safeguard or certificate password from stdin
  -X  Do NOT generate login file for use in other scripts

The invoke-safeguard-method.sh and listen-for-event.sh scripts will attempt to use
a login file by default. If one is not found this script will be called to generate
one. Subsequent invocations will use that login file until it is removed by calling
logout-safeguard.sh which will also call the logout service on the appliance.

If using -p option make sure you provide all the data you need to run this command or
you will be prompted interactively anyway.

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Appliance=
CABundle=
CABundleArg=
Version=3
Providers=
Provider=
User=
Cert=
PKey=
Pass=
StsAccessToken=
AccessToken=
StoreLoginFile=true

. "$ScriptDir/utils/loginfile.sh"

get_rsts_token()
{
    if [ "$Provider" = "certificate" ]; then
        if [ $(curl --version | grep "libcurl" | sed -e 's,curl [0-9]*\.\([0-9]*\).* (.*,\1,') -ge 33 ]; then
            http11flag='--http1.1'
        fi
        StsResponse=$(curl -K <(cat <<EOF
-s
$CABundleArg
--key $PKey
--cert $Cert
--pass $Pass
$http11flag
-X POST
-H "Accept: application/json"
-H "Content-type: application/json"
EOF
) -d @- "https://$Appliance/RSTS/oauth2/token" <<EOF
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
            #   see https://github.com/curl/curl/issues/1411
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
        StsResponse=$(curl -K <(cat <<EOF
-s
-S
$CABundleArg
-X POST
-H "Accept: application/json"
-H "Content-type: application/json"
EOF
) -d @- "https://$Appliance/RSTS/oauth2/token" <<EOF
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
    StsAccessToken=$(echo $StsResponse | sed -n 's/.*"access_token":"\([-0-9A-Za-z_\.]*\)",.*/\1/p')
    if [ -z "$StsAccessToken" ]; then
        >&2 echo -e "Failed to get access token from appliance\n$StsResponse"
        exit 1
    fi
}

get_safeguard_token()
{
    if [ ! -z "$StsAccessToken" ]; then
        LoginResponse=$(curl -K <(cat <<EOF
-s
-S
$CABundleArg
-X POST
-H "Accept: application/json"
-H "Content-type: application/json"
-H "Authorization: Bearer $StsAccessToken"
EOF
) -d @- "https://$Appliance/service/core/v$Version/Token/LoginResponse" <<EOF
{
    "StsAccessToken": "$StsAccessToken"
}
EOF
        )
        if [ $? -ne 0 ]; then
            >&2 echo -e "Failed to get login response from appliance:\n$LoginResponse"
            exit 1
        fi
        Status=$(echo $LoginResponse | sed -n 's/.*"Status":"\([A-Za-z]*\)",.*/\1/p')
        if [ -z "$Status" ]; then
            >&2 echo -e "Failed to get status from login response:\n$LoginResponse"
            exit 1
        fi
        if [[ $Status =~ .*Success* ]]; then
            AccessToken=$(echo $LoginResponse | sed -n 's/.*"UserToken":"\([-0-9A-Za-z_\.]*\)",.*/\1/p')
            if [ -z "$AccessToken" ]; then
                >&2 echo -e "Failed to get user token from appliance:\n$LoginResponse"
                exit 1
            fi
        elif [[ $Status =~ .*Unauthorized* ]]; then
            >&2 echo -e "Failure result from login response:\n$LoginResponse"
            exit 1
        else
            >&2 echo "Unable to handle status '$(echo $Status | sed -e 's/^.*:.*"\(.*\)",/\1/')'"
            exit 1
        fi
    fi
}


while getopts ":a:B:v:i:u:c:k:phX" opt; do
    case $opt in
    a)
        Appliance=$OPTARG
        ;;
    B)
        CABundle=$OPTARG
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
        # read password from stdin before doing anything
        read -s Pass
        ;;
    X)
        StoreLoginFile=false
        ;;
    h)
        print_usage
        ;;
    esac
done

require_connect_args

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
CABundleArg=$CABundleArg
Provider=$Provider
AccessToken=$AccessToken
EOF
    if [ "$Provider" = "certificate" ]; then
        cat <<EOF >> $LoginFile
Cert=$Cert
PKey=$PKey
EOF
    fi
    umask $OldUmask
    >&2 echo "A login file has been created."
else
    echo $AccessToken
fi

