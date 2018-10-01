#!/bin/bash
# This is a script to support calling the a2a service across multiple scripts.
# It shouldn't be called directly.

invoke_a2a_method()
{
    local appliance=$1 ; shift 
    local cabundlearg=$1 ; shift
    local certfile=$1 ; shift 
    local pkeyfile=$1 ; shift 
    local pass=$1 ; shift 
    local apikey=$1 ; shift 
    local method=$1 ; shift 
    method=$(echo "$method" | tr '[:lower:]' '[:upper:]')
    local relurl=$1 ; shift 
    local version=$1 ; shift 
    local body=$1 ; shift 

    if [ $(curl --version | grep "libcurl" | sed -e 's,curl [0-9]*\.\([0-9]*\).* (.*,\1,') -ge 33 ]; then
        http11flag='--http1.1'
    fi
    if [ -z "$body" ]; then
        local response=$(curl -K <(cat <<EOF
-s
$cabundlearg
--key $pkeyfile
--cert $certfile
--pass $pass
-X $method
$http11flag
-H "Accept: application/json"
-H "Authorization: A2A $apikey"
EOF
) "https://$appliance/service/a2a/v$version/$relurl"
        )
        if [ ! -z "$response" -a ! -z "$(echo $response | jq '.Code // empty')" ]; then
            echo "$response"
        else
            # There is a bug in some Debian-based platforms with curl linked to GnuTLS where it doesn't properly
            # ignore certificate errors when using client certificate authentication. This works around that
            # problem by calling OpenSSL directly and manually formulating an HTTP request.
            #   see https://github.com/curl/curl/issues/1411
            response=$(cat <<EOF | openssl s_client -connect $appliance:443 -quiet -crlf -key $pkeyfile -cert $certfile -pass pass:$pass 2>&1
$method /service/a2a/v$version/$relurl HTTP/1.1
Host: $appliance
User-Agent: curl/7.47.0
Authorization: A2A $apikey
Accept: application/json
Connection: close

EOF
            )
            echo "$response" | sed -n '/read:errno/,$p' | sed -e 's/\(.*\)read\:errno\=.*/\1/'
        fi
    else
        local response=$(curl -K <(cat <<EOF
-s
$cabundlearg
--key $pkeyfile
--cert $certfile
--pass $pass
-X $method
$http11flag
-H "Accept: application/json"
-H "Content-type: application/json" -H "Authorization: A2A $apikey"
EOF
) -d @- "https://$appliance/service/a2a/v$version/$relurl" <<EOF
$body
EOF
        )
        if [ -z "$response" ]; then
            body="$(echo -e "${body}" | tr -d '[:space:]')"
            local bodylen=$(echo -n "${body}" | wc -m)
            # There is a bug in some Debian-based platforms with curl linked to GnuTLS where it doesn't properly
            # ignore certificate errors when using client certificate authentication. This works around that
            # problem by calling OpenSSL directly and manually formulating an HTTP request.
            #   see https://github.com/curl/curl/issues/1411
            response=$(cat <<EOF | openssl s_client -connect $appliance:443 -quiet -crlf -key $pkeyfile -cert $certfile -pass pass:$pass 2>&1
POST /service/a2a/v$version/$relurl HTTP/1.1
Host: $appliance
User-Agent: curl/7.47.0
Authorization: A2A $apikey
Accept: application/json
Connection: close
Content-type: application/json
Content-Length: $bodylen

$body
EOF
            )
            echo "$response" | sed -n '/read:errno/,$p' | sed -e 's/\(.*\)read\:errno\=.*/\1/'
        fi
    fi
}

get_a2a_connection_token()
{
    curl -K <(cat <<EOF
-s
$CABundleArg
--key $PKey
--cert $Cert
--pass $Pass
EOF
) "https://$Appliance/service/event/signalr/negotiate?_=$NUM" \
            | sed -n -e 's/\+/%2B/g;s/\//%2F/g;s/.*"ConnectionToken":"\([^"]*\)".*/\1/p'
}

