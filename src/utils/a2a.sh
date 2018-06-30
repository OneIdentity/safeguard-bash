#!/bin/bash
# This is a script to support calling the a2a service across multiple scripts.
# It shouldn't be called directly.

invoke_a2a_method()
{
    local appliance=$1 ; shift 
    local certfile=$1 ; shift 
    local pkeyfile=$1 ; shift 
    local pass=$1 ; shift 
    local apikey=$1 ; shift 
    local method=$1 ; shift 
    method=$(echo "$method" | tr '[:lower:]' '[:upper:]')
    local relurl=$1 ; shift 
    local version=$1 ; shift 
    local body=$1 ; shift 

    if [ -z "$body" ]; then
        local response=$(curl -s -k --key $pkeyfile --cert $certfile --pass $pass -X $method -H 'Accept: application/json' \
                              -H "Authorization: A2A $apikey" "https://$appliance/service/a2a/v$version/$relurl"
        )
        if [ -z "$reponse" ]; then
            # There is a bug in some Debian-based platforms with curl linked to GnuTLS where it doesn't properly
            # ignore certificate errors when using client certificate authentication. This works around that
            # problem by calling OpenSSL directly and manually formulating an HTTP request.
            response=$(cat <<EOF | openssl s_client -connect $appliance:443 -ign_eof -key $pkeyfile -cert $certfile -pass pass:$pass 2>&1
$method /service/a2a/v$version/$relurl HTTP/1.1
Host: $appliance
User-Agent: curl/7.47.0
Authorization: A2A $apikey
Accept: application/json
Content-Length: 6
 
ignore

Q
EOF
        )
        fi
    else
        local response=$(curl -s -k --key $pkeyfile --cert $certfile --pass $pass -X $method -H 'Accept: application/json' \
                              -H 'Content-type: application/json' -H "Authorization: A2A $apikey" \
                              -d @- "https://$appliance/service/a2a/v$version/$relurl" <<EOF
$body
EOF
        )
        if [ -z "$response" ]; then
            body="$(echo -e "${body}" | tr -d '[:space:]')"
            local bodylen=$(echo -n "${body}" | wc -m)
            # There is a bug in some Debian-based platforms with curl linked to GnuTLS where it doesn't properly
            # ignore certificate errors when using client certificate authentication. This works around that
            # problem by calling OpenSSL directly and manually formulating an HTTP request.
            response=$(cat <<EOF | openssl s_client -connect $appliance:443 -ign_eof -key $pkeyfile -cert $certfile -pass pass:$pass 2>&1
POST /service/a2a/v$version/$relurl HTTP/1.1
Host: $appliance
User-Agent: curl/7.47.0
Authorization: A2A $apikey
Accept: application/json
Content-type: application/json
Content-Length: $bodylen

$body

Q
EOF
              )
        fi
    fi
}
