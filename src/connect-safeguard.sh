#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: connect-safeguard.sh [-h]
       connect-safeguard.sh [-a appliance] [-B cabundle] [-v version] [-i provider] [-u user] [-p] [-X]
       connect-safeguard.sh [-a appliance] [-B cabundle] [-v version] -i certificate [-c file] [-k file] [-p] [-X]
       connect-safeguard.sh [-a appliance] [-B cabundle] [-v version] [-i provider] [-u user] [-p] -P [-S] [-X]
       connect-safeguard.sh [-a appliance] [-B cabundle] [-v version] [-i provider] -D [-X]

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
  -D  Use the OAuth 2.0 Device Authorization Grant (RFC 8628) to authenticate
      without launching a local browser. Displays a verification URL and a short
      user code; complete the login from any browser on any device. Recommended
      for headless environments such as Docker containers, SSH sessions, and CI
      runners. Combine with -i to pre-select an identity provider on the rSTS
      login page. Requires Safeguard appliance firmware >= 7.4 with the
      "Device Code" OAuth2 grant type enabled in Appliance Management.
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
DeviceCode=false
SecondaryPass=
StsAccessToken=
AccessToken=
StoreLoginFile=true

. "$ScriptDir/utils/loginfile.sh"
. "$ScriptDir/utils/redact-sensitive.sh"
. "$ScriptDir/utils/common.sh"

get_rsts_token()
{
    if [ "$Provider" = "certificate" ]; then
        set_http11_flag
        StsResponse=$(curl -K <(cat <<EOF
-s
$CABundleArg
$tlsflags
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
            local PassFile
            local PassArgs=()
            if [ -n "$Pass" ]; then
                PassFile=$(write_pass_file "$Pass")
                PassArgs=(-pass "file:$PassFile")
            else
                PassArgs=(-pass "pass:")
            fi
            trap 'rm -f "$PassFile"' RETURN
            StsResponse=$(cat <<EOF | openssl s_client -connect $Appliance:443 -quiet -crlf -key $PKey -cert $Cert "${PassArgs[@]}" "${OpenSslTlsArgs[@]}" 2>&1
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
            rm -f "$PassFile"
            trap - RETURN
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
$tlsflags
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
$tlsflags
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
$tlsflags
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
$tlsflags
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
$tlsflags
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
$tlsflags
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
$tlsflags
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

get_rsts_token_with_device_code()
{
    # OAuth 2.0 Device Authorization Grant (RFC 8628). Mirrors the
    # Get-RstsTokenFromDeviceCode implementation from safeguard-ps.
    #
    # We intentionally send an empty client_id. The RSTS bakes a client_id into
    # the auth-code JWT during the browser-side completion (LoginController),
    # and that side only picks up a client_id from the URL query string. The
    # short verification_uri_complete URL we display does not include client_id,
    # so the JWT ends up signed with the appliance's default ApplicationClientId.
    # The token-poll then compares the cached client_id (what we sent here) to
    # the JWT claim. Sending an empty string lets the appliance normalize both
    # sides to ApplicationClientId, which makes the device flow work whether
    # the user opens verification_uri_complete or types the user_code on the
    # long verification_uri page.
    local DeviceClientId=""
    local DeviceScope="rsts:sts:primaryproviderid:local"

    local DeviceResponseRaw
    DeviceResponseRaw=$(curl -K <(cat <<EOF
-s
-S
$CABundleArg
$tlsflags
-X POST
-H "Accept: application/json"
-H "Content-type: application/json"
-w "\n%{http_code}"
EOF
) -d @- "https://$Appliance/RSTS/oauth2/DeviceLogin" <<EOF
{
    "client_id": "$DeviceClientId",
    "scope": "$DeviceScope"
}
EOF
    )
    local CurlExit=$?
    if [ $CurlExit -ne 0 ]; then
        >&2 echo "Failed to request device authorization from appliance (curl exit $CurlExit)"
        >&2 echo "$DeviceResponseRaw"
        exit 1
    fi

    local DeviceHttpCode=$(echo "$DeviceResponseRaw" | tail -1)
    local DeviceResponse=$(echo "$DeviceResponseRaw" | sed '$d')
    if [ -z "$DeviceHttpCode" ] || [ "${DeviceHttpCode:0:1}" != "2" ]; then
        >&2 echo "Unable to obtain device code from $Appliance (HTTP $DeviceHttpCode)"
        # The appliance returns an HTML error page (rather than a JSON OAuth
        # error body) when the Device Code grant type is disabled or the
        # endpoint is not recognized. Detect that and surface a focused hint
        # instead of dumping the entire HTML page to the terminal. The body
        # may include a UTF-8 BOM and/or an XML prolog before the first '<',
        # so strip leading whitespace and the BOM before checking.
        local DeviceTrimmed=$(printf '%s' "$DeviceResponse" | sed -e 's/^\xef\xbb\xbf//' -e 's/^[[:space:]]*//')
        if [ "${DeviceTrimmed:0:1}" = "<" ]; then
            >&2 echo "Appliance returned an HTML error page rather than an OAuth response."
            >&2 echo "The Device Code OAuth2 grant type may not be enabled on this appliance."
            >&2 echo "Enable it under Appliance Management -> Safeguard Access -> Local Login Control,"
            >&2 echo "or upgrade to Safeguard 7.4 or later."
        else
            >&2 echo "$DeviceResponse"
        fi
        exit 1
    fi
    if [ -z "$DeviceResponse" ]; then
        >&2 echo "Unexpected empty device authorization response from $Appliance"
        exit 1
    fi

    local DeviceCodeValue UserCode VerificationUri VerificationUriComplete ExpiresIn Interval
    if [ ! -z "$(which jq 2> /dev/null)" ]; then
        DeviceCodeValue=$(echo "$DeviceResponse" | jq -r '.device_code // empty' 2> /dev/null)
        UserCode=$(echo "$DeviceResponse" | jq -r '.user_code // empty' 2> /dev/null)
        VerificationUri=$(echo "$DeviceResponse" | jq -r '.verification_uri // empty' 2> /dev/null)
        VerificationUriComplete=$(echo "$DeviceResponse" | jq -r '.verification_uri_complete // empty' 2> /dev/null)
        ExpiresIn=$(echo "$DeviceResponse" | jq -r '.expires_in // empty' 2> /dev/null)
        Interval=$(echo "$DeviceResponse" | jq -r '.interval // empty' 2> /dev/null)
    else
        DeviceCodeValue=$(echo "$DeviceResponse" | sed -n 's/.*"device_code":"\([^"]*\)".*/\1/p')
        UserCode=$(echo "$DeviceResponse" | sed -n 's/.*"user_code":"\([^"]*\)".*/\1/p')
        VerificationUri=$(echo "$DeviceResponse" | sed -n 's/.*"verification_uri":"\([^"]*\)".*/\1/p')
        VerificationUriComplete=$(echo "$DeviceResponse" | sed -n 's/.*"verification_uri_complete":"\([^"]*\)".*/\1/p')
        ExpiresIn=$(echo "$DeviceResponse" | sed -n 's/.*"expires_in":\([0-9]*\).*/\1/p')
        Interval=$(echo "$DeviceResponse" | sed -n 's/.*"interval":\([0-9]*\).*/\1/p')
        # JSON optionally escapes forward slashes as \/. jq -r unescapes those
        # automatically, but our raw sed extraction does not, so undo the most
        # common JSON string escapes that can appear in URIs the user will see.
        VerificationUri=$(printf '%s' "$VerificationUri" | sed -e 's,\\/,/,g')
        VerificationUriComplete=$(printf '%s' "$VerificationUriComplete" | sed -e 's,\\/,/,g')
    fi

    if [ -z "$DeviceCodeValue" ] || [ -z "$UserCode" ]; then
        >&2 echo "Device authorization response from $Appliance is missing required fields"
        >&2 echo "$DeviceResponse"
        exit 1
    fi

    if [ -z "$ExpiresIn" ]; then
        ExpiresIn=300
    fi
    if [ -z "$Interval" ]; then
        Interval=5
    fi

    # Append a provider hint as primaryProviderID so the rSTS skips the
    # provider drop-down and takes the user straight to that provider's
    # login page (Login.cs:601-604 in the appliance).
    if [ ! -z "$Provider" ] && [ "$Provider" != "local" ]; then
        local EncodedProvider=$(urlencode "$Provider")
        if [ ! -z "$VerificationUri" ]; then
            case "$VerificationUri" in
                *\?*) VerificationUri="${VerificationUri}&primaryProviderID=${EncodedProvider}" ;;
                *)    VerificationUri="${VerificationUri}?primaryProviderID=${EncodedProvider}" ;;
            esac
        fi
        if [ ! -z "$VerificationUriComplete" ]; then
            case "$VerificationUriComplete" in
                *\?*) VerificationUriComplete="${VerificationUriComplete}&primaryProviderID=${EncodedProvider}" ;;
                *)    VerificationUriComplete="${VerificationUriComplete}?primaryProviderID=${EncodedProvider}" ;;
            esac
        fi
    fi

    >&2 echo
    >&2 echo "To sign in, use a web browser to open the page:"
    >&2 echo "    $VerificationUri"
    >&2 echo "and enter the code:"
    >&2 echo "    $UserCode"
    if [ ! -z "$VerificationUriComplete" ]; then
        >&2 echo "Or open this URL directly to skip entering the code:"
        >&2 echo "    $VerificationUriComplete"
    fi
    >&2 echo "The code expires in $ExpiresIn seconds. Press Ctrl+C to cancel."
    >&2 echo

    local Now Deadline
    Now=$(date +%s)
    Deadline=$((Now + ExpiresIn))

    while [ "$(date +%s)" -lt "$Deadline" ]; do
        sleep "$Interval"

        local PollResponseRaw PollHttpCode PollBody PollCurlExit
        PollResponseRaw=$(curl -K <(cat <<EOF
-s
-S
$CABundleArg
$tlsflags
-X POST
-H "Accept: application/json"
-H "Content-type: application/json"
-w "\n%{http_code}"
EOF
) -d @- "https://$Appliance/RSTS/oauth2/token" <<EOF
{
    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
    "device_code": "$DeviceCodeValue",
    "client_id": "$DeviceClientId"
}
EOF
        )
        PollCurlExit=$?
        if [ $PollCurlExit -ne 0 ]; then
            >&2 echo "Failed to poll device code token endpoint (curl exit $PollCurlExit)"
            >&2 echo "$PollResponseRaw"
            exit 1
        fi
        PollHttpCode=$(echo "$PollResponseRaw" | tail -1)
        PollBody=$(echo "$PollResponseRaw" | sed '$d')

        if [ "${PollHttpCode:0:1}" = "2" ]; then
            StsAccessToken=$(echo "$PollBody" | sed -n 's/.*"access_token":"\([-0-9A-Za-z_\.]*\)".*/\1/p')
            if [ ! -z "$StsAccessToken" ]; then
                return 0
            fi
            # 2xx without access_token: defensive; keep polling.
            continue
        fi

        local OAuthError
        if [ ! -z "$(which jq 2> /dev/null)" ]; then
            OAuthError=$(echo "$PollBody" | jq -r '.error // empty' 2> /dev/null)
        else
            OAuthError=$(echo "$PollBody" | sed -n 's/.*"error":"\([^"]*\)".*/\1/p')
        fi

        case "$OAuthError" in
            authorization_pending)
                continue
                ;;
            slow_down)
                Interval=$((Interval + 5))
                >&2 echo "Slow down requested by appliance; polling every ${Interval}s"
                continue
                ;;
            access_denied)
                >&2 echo "Device code authentication was denied."
                exit 1
                ;;
            expired_token)
                >&2 echo "Device code has expired. Please try again."
                exit 1
                ;;
            *)
                >&2 echo "Unable to redeem device code (HTTP $PollHttpCode)"
                >&2 echo "$PollBody"
                exit 1
                ;;
        esac
    done

    >&2 echo "Device code expired before user authenticated."
    exit 1
}

get_safeguard_token()
{
    if [ ! -z "$StsAccessToken" ]; then
        LoginResponse=$(curl -K <(cat <<EOF
-s
-S
$CABundleArg
$tlsflags
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


while getopts ":a:B:v:i:u:c:k:phPDS:X" opt; do
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
    D)
        DeviceCode=true
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

if $DeviceCode; then
    if $Pkce; then
        >&2 echo "DeviceCode (-D) and PKCE (-P) cannot be combined"
        exit 1
    fi
    if [ "$Provider" = "certificate" ]; then
        >&2 echo "DeviceCode authentication cannot be used with certificate provider"
        exit 1
    fi
    if [ ! -z "$Cert" ] || [ ! -z "$PKey" ]; then
        >&2 echo "Client certificate options (-c/-k) are not valid with DeviceCode authentication"
        exit 1
    fi
    if [ ! -z "$Pass" ]; then
        >&2 echo "Warning: password input is ignored when using DeviceCode (-D)"
        Pass=
    fi
    require_device_code_connect_args
else
    require_connect_args
fi

Scope="rsts:sts:primaryproviderid:$Provider"

set_tls_version_flags
set_openssl_tls_args

if $DeviceCode; then
    get_rsts_token_with_device_code
elif $Pkce; then
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
    if $DeviceCode; then
        cat <<EOF >> $LoginFile
DeviceCode=true
EOF
    fi
    umask $OldUmask
    >&2 echo "A login file has been created."
else
    echo $AccessToken
fi

