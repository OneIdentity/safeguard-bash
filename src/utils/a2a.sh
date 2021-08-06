#!/bin/bash
# This is a script to support calling the a2a service across multiple scripts.
# It shouldn't be called directly.
invoke_a2a_method()
{
    local appliance=$1 ; shift       #1
    local cabundlearg=$1 ; shift     #2
    local certfile=$1 ; shift        #3
    local pkeyfile=$1 ; shift        #4
    local pass=$1 ; shift            #5
    local apikey=$1 ; shift          #6
    local service=$1 ; shift         #7
    local method=$1 ; shift          #8
    method=$(echo "$method" | tr '[:lower:]' '[:upper:]')
    local relurl=$1 ; shift          #9
    local version=$1 ; shift         #10
    local usesclient=$1 ; shift      #11

    local apikeyflag="-H \"Authorization: A2A $apikey\""
    local response=""
    local error=""

    if ! $usesclient; then
        if [ $(curl --version | grep "libcurl" | sed -e 's,curl [0-9]*\.\([0-9]*\).* (.*,\1,') -ge 33 ]; then
            http11flag='--http1.1'
        fi
        response=$(curl -K <(cat <<EOF
-s
$cabundlearg
--key $pkeyfile
--cert $certfile
--pass $pass
-X $method
$http11flag
-H "Accept: application/json"
$apikeyflag
EOF
) "https://$appliance/service/$service/v$version/$relurl"
       )
        if [ -z "$(which jq 2> /dev/null)" ]; then
            error=$(echo $response | grep ".Code")
        else
            error=$(echo $response | jq .Code 2> /dev/null)
        fi
    fi
    if [ ! -z "$response" ] && [ -z "$error" -o "$error" = "null" ]; then
        echo "$response"
    else
        # There is a bug in some Debian-based platforms with curl linked to GnuTLS where it doesn't properly
        # ignore certificate errors when using client certificate authentication. This works around that
        # problem by calling OpenSSL directly and manually formulating an HTTP request.
        #   see https://github.com/curl/curl/issues/1411
        IFS=$'\n' read -d '' -r -a response < <(cat <<EOF | openssl s_client -connect $appliance:443 -quiet -crlf -key $pkeyfile -cert $certfile -pass pass:$pass 2>&1
$method /service/$service/v$version/$relurl HTTP/1.1
Host: $appliance
User-Agent: curl/7.47.0
Authorization: A2A $apikey
Accept: application/json
Connection: close

EOF
            )
        local noclose=true
        local noempty=true
        local length=
        local body=
        for line in "${response[@]}"; do
            line=$(echo $line | tr -d '\r')
            if $noclose; then
                # need to find the connection close marker
                if [ "$line" = "Connection: close" ]; then
                    noclose=false
                fi
            elif $noempty; then
                # after close there should be an empty line
                if [ "$line" = "" ]; then
                    noempty=false
                fi
            elif [ -z "$length" ]; then
                # after empty line should be the length of the HTTP payload
                (( 16#$line )) 2> /dev/null
                if [ $? -eq 0 ]; then
                    length=$line
                fi
            elif [ -z "$body" ]; then
                # after length should be the body
                body=$line
            else
                # after body should just be garbage
                echo $line > /dev/null
            fi
        done
        if [ -z "$body" ]; then
            # Coalesce all the output into a string, see if it matches other types of output, or dump error
            output=$(printf '%s\n' "${response[@]}")
            if grep -q "read:errno=0" <<< $output; then
                echo "$output" | sed -n '/read:errno/,$p' | sed -e 's/\(.*\)read\:errno\=.*/\1/'
            else
                echo $output
            fi
        else
            echo "$body"
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

