#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: connect-safeguard.sh [-h]
       connect-safeguard.sh [-a appliance] [-B cabundle] [-v version] [-i provider] [-u user] [-p] [-X]
       connect-safeguard.sh [-a appliance] [-B cabundle] [-v version] -i certificate [-c file] [-k file] [-p] [-X]
       connect-safeguard.sh [-a appliance] [-B cabundle] [-v version] [-i provider] [-u user] [-p] -P [-S] [-X]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL trust validation (no checking by default)
  -v  Web API Version: 4 is default
  -i  Safeguard identity provider, examples: certificate, local, ad<num>
  -u  Safeguard user to use
  -c  File containing client certificate
  -k  File containing client private key
  -p  Read Safeguard or certificate password from stdin
  -P  Use PKCE (Proof Key for Code Exchange) non-interactive authentication.
      This programmatically simulates the browser-based OAuth2/PKCE flow without
      launching a browser, which does not require the Resource Owner password grant
      type to be enabled on the appliance.
  -S  Secondary password or MFA code (only used with -P when the identity
      provider requires a second factor, will prompt if not provided)
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
Version=4
Providers=
Provider=
User=
Cert=
PKey=
Pass=
Pkce=false
SecondaryPass=
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

base64url_encode()
{
    openssl enc -base64 -A | tr -d '=' | tr '+/' '-_'
}

urlencode()
{
    if [ ! -z "$(which jq 2> /dev/null)" ]; then
        printf '%s' "$1" | jq -sRr @uri
    else
        local string="$1" encoded="" i c
        for (( i=0; i<${#string}; i++ )); do
            c="${string:$i:1}"
            case "$c" in
                [a-zA-Z0-9.~_-]) encoded+="$c" ;;
                *) encoded+=$(printf '%%%02X' "'$c") ;;
            esac
        done
        printf '%s' "$encoded"
    fi
}

get_rsts_token_with_pkce()
{
    # Generate PKCE code_verifier (60 random bytes, base64url-encoded)
    local CodeVerifier=$(openssl rand 60 | base64url_encode)

    # Generate PKCE code_challenge (SHA256 of verifier, base64url-encoded)
    local CodeChallenge=$(printf '%s' "$CodeVerifier" | openssl dgst -sha256 -binary | base64url_encode)

    # Generate CSRF token (32 random bytes, base64url-encoded)
    local CsrfToken=$(openssl rand 32 | base64url_encode)

    local RedirectUri="urn:InstalledApplication"
    local EncodedRedirectUri=$(urlencode "$RedirectUri")
    local PkceBase="https://$Appliance/RSTS/UserLogin/LoginController?response_type=code&code_challenge_method=S256&code_challenge=$CodeChallenge&redirect_uri=$EncodedRedirectUri&loginRequestStep="

    local FormData="directoryComboBox=$Provider&usernameTextbox=$(urlencode "$User")&passwordTextbox=$(urlencode "$Pass")&csrfTokenTextbox=$CsrfToken"

    local CookieFile=$(mktemp)
    trap "rm -f $CookieFile" RETURN

    # Pre-set CSRF cookie
    local Now=$(date +%s)
    local Expiry=$((Now + 3600))
    printf "%s\tFALSE\t/RSTS\tTRUE\t%s\tCsrfToken\t%s\n" "$Appliance" "$Expiry" "$CsrfToken" > "$CookieFile"

    # Step 1: Initialize rSTS session
    local StepResponse
    StepResponse=$(curl -K <(cat <<EOF
-s
-S
$CABundleArg
-X POST
-H "Accept: application/json"
-H "Content-Type: application/x-www-form-urlencoded"
-b $CookieFile
-c $CookieFile
EOF
) -d "$FormData" "${PkceBase}1")
    if [ $? -ne 0 ]; then
        >&2 echo "PKCE: rSTS initialization failed"
        exit 1
    fi

    # Step 3: Primary authentication
    local PrimaryResponse
    PrimaryResponse=$(curl -K <(cat <<EOF
-s
-S
$CABundleArg
-X POST
-H "Accept: application/json"
-H "Content-Type: application/x-www-form-urlencoded"
-b $CookieFile
-c $CookieFile
EOF
) -d "$FormData" "${PkceBase}3")
    if [ $? -ne 0 ]; then
        >&2 echo "PKCE: rSTS primary authentication failed"
        exit 1
    fi

    # Check for secondary authentication requirement
    local SecondaryProvider
    if [ ! -z "$(which jq 2> /dev/null)" ]; then
        SecondaryProvider=$(echo "$PrimaryResponse" | jq -r '.SecondaryProviderID // empty' 2> /dev/null)
    else
        SecondaryProvider=$(echo "$PrimaryResponse" | sed -n 's/.*"SecondaryProviderID":"\([^"]*\)".*/\1/p')
    fi

    if [ ! -z "$SecondaryProvider" ]; then
        if [ -z "$SecondaryPass" ]; then
            read -s -p "Secondary Password / MFA Code: " SecondaryPass
            >&2 echo
        fi

        # Step 7: Initialize secondary authentication
        local SecondaryInitResponse
        SecondaryInitResponse=$(curl -K <(cat <<EOF
-s
-S
$CABundleArg
-X POST
-H "Accept: application/json"
-H "Content-Type: application/x-www-form-urlencoded"
-b $CookieFile
-c $CookieFile
EOF
) -d "$FormData" "${PkceBase}7")
        if [ $? -ne 0 ]; then
            >&2 echo "PKCE: rSTS secondary initialization failed"
            exit 1
        fi

        local MfaState=""
        if [ ! -z "$(which jq 2> /dev/null)" ]; then
            MfaState=$(echo "$SecondaryInitResponse" | jq -r '.State // empty' 2> /dev/null)
            local MfaMessage=$(echo "$SecondaryInitResponse" | jq -r '.Message // empty' 2> /dev/null)
            if [ ! -z "$MfaMessage" ]; then
                >&2 echo "MFA prompt: $MfaMessage"
            fi
        else
            MfaState=$(echo "$SecondaryInitResponse" | sed -n 's/.*"State":"\([^"]*\)".*/\1/p')
        fi

        # Step 5: Submit secondary credentials
        local MfaFormData="$FormData&secondaryLoginTextbox=$(urlencode "$SecondaryPass")&secondaryAuthenticationStateTextbox=$(urlencode "$MfaState")"
        local MfaResponse MfaHttpCode
        MfaResponse=$(curl -K <(cat <<EOF
-s
-S
$CABundleArg
-X POST
-H "Accept: application/json"
-H "Content-Type: application/x-www-form-urlencoded"
-b $CookieFile
-c $CookieFile
-w "\n%{http_code}"
EOF
) -d "$MfaFormData" "${PkceBase}5")
        MfaHttpCode=$(echo "$MfaResponse" | tail -1)
        MfaResponse=$(echo "$MfaResponse" | sed '$d')
        if [ "$MfaHttpCode" = "203" ]; then
            >&2 echo "PKCE: Secondary authentication failed"
            >&2 echo "$MfaResponse"
            exit 1
        fi
        if [ $? -ne 0 ]; then
            >&2 echo "PKCE: rSTS secondary authentication failed"
            exit 1
        fi
    fi

    # Step 6: Generate claims and get authorization code
    local ClaimsResponse
    ClaimsResponse=$(curl -K <(cat <<EOF
-s
-S
$CABundleArg
-X POST
-H "Accept: application/json"
-H "Content-Type: application/x-www-form-urlencoded"
-b $CookieFile
-c $CookieFile
EOF
) -d "$FormData" "${PkceBase}6")
    if [ $? -ne 0 ]; then
        >&2 echo "PKCE: rSTS claims generation failed"
        exit 1
    fi

    # Extract authorization code from RelyingPartyUrl
    local RelyingPartyUrl AuthorizationCode
    if [ ! -z "$(which jq 2> /dev/null)" ]; then
        RelyingPartyUrl=$(echo "$ClaimsResponse" | jq -r '.RelyingPartyUrl // empty' 2> /dev/null)
    else
        RelyingPartyUrl=$(echo "$ClaimsResponse" | sed -n 's/.*"RelyingPartyUrl":"\([^"]*\)".*/\1/p')
    fi

    if [ -z "$RelyingPartyUrl" ]; then
        >&2 echo "PKCE: rSTS response did not contain a RelyingPartyUrl"
        >&2 echo "$ClaimsResponse"
        exit 1
    fi

    AuthorizationCode=$(echo "$RelyingPartyUrl" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')
    if [ -z "$AuthorizationCode" ]; then
        >&2 echo "PKCE: rSTS response did not contain an authorization code"
        >&2 echo "$RelyingPartyUrl"
        exit 1
    fi

    # Exchange authorization code for RSTS access token
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
    "grant_type": "authorization_code",
    "redirect_uri": "$RedirectUri",
    "code": "$AuthorizationCode",
    "code_verifier": "$CodeVerifier"
}
EOF
    )
    if [ $? -ne 0 ]; then
        >&2 echo "PKCE: Failed to exchange authorization code for RSTS token"
        >&2 echo "$StsResponse"
        exit 1
    fi

    StsAccessToken=$(echo $StsResponse | sed -n 's/.*"access_token":"\([-0-9A-Za-z_\.]*\)",.*/\1/p')
    if [ -z "$StsAccessToken" ]; then
        >&2 echo -e "PKCE: Failed to get access token from RSTS\n$StsResponse"
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


while getopts ":a:B:v:i:u:c:k:phPS:X" opt; do
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
    P)
        Pkce=true
        ;;
    S)
        SecondaryPass=$OPTARG
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

if $Pkce; then
    if [ "$Provider" = "certificate" ]; then
        >&2 echo "PKCE authentication cannot be used with certificate provider"
        exit 1
    fi
    get_rsts_token_with_pkce
else
    get_rsts_token
fi

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
    if $Pkce; then
        cat <<EOF >> $LoginFile
Pkce=true
EOF
    fi
    umask $OldUmask
    >&2 echo "A login file has been created."
else
    echo $AccessToken
fi

