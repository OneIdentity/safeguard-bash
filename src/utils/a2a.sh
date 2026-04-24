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
    local body=${1:-}                 #12 (optional request body)

    local apikeyflag="-H \"Authorization: A2A $apikey\""
    local contenttypeflag=""
    if [ -n "$body" ]; then
        contenttypeflag="-H \"Content-Type: application/json\""
    fi
    local response=""
    local error=""

    if ! $usesclient; then
        if [ $(curl --version | grep "libcurl" | sed -e 's,curl [0-9]*\.\([0-9]*\).* (.*,\1,') -ge 33 ]; then
            http11flag='--http1.1'
        fi
        local bodyargs=()
        if [ -n "$body" ]; then
            bodyargs=(-d "$body")
        fi
        response=$(curl -K <(cat <<EOF
-s
-S
$cabundlearg
--key $pkeyfile
--cert $certfile
--pass $pass
-X $method
$http11flag
-H "Accept: application/json"
$contenttypeflag
$apikeyflag
EOF
) "${bodyargs[@]}" "https://$appliance/service/$service/v$version/$relurl" 2>"${TMPDIR:-/tmp}/.a2a_curl_err.$$"
       )
        local curlerr=$?
        if [ $curlerr -ne 0 ] && [ -z "$response" ]; then
            >&2 cat "${TMPDIR:-/tmp}/.a2a_curl_err.$$"
            rm -f "${TMPDIR:-/tmp}/.a2a_curl_err.$$"
            return 1
        fi
        rm -f "${TMPDIR:-/tmp}/.a2a_curl_err.$$"
        if [ -z "$(which jq 2> /dev/null)" ]; then
            error=$(echo $response | grep '"Code":60108')
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
        local contentlengthheader=""
        local contenttypeheader=""
        local bodydata=""
        if [ -n "$body" ]; then
            contenttypeheader="Content-Type: application/json"
            contentlengthheader="Content-Length: ${#body}"
            bodydata="$body"
        fi
        IFS=$'\n' read -d '' -r -a response < <(cat <<EOF | openssl s_client -connect $appliance:443 -quiet -crlf -key $pkeyfile -cert $certfile -pass pass:$pass 2>"${TMPDIR:-/tmp}/.a2a_sclient_err.$$"
$method /service/$service/v$version/$relurl HTTP/1.1
Host: $appliance
User-Agent: curl/7.47.0
Authorization: A2A $apikey
Accept: application/json
${contenttypeheader:+$contenttypeheader
}${contentlengthheader:+$contentlengthheader
}Connection: close

$bodydata
EOF
            )
        local noclose=true
        local noempty=true
        local contentlength=
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
                # capture Content-Length from remaining headers
                local clval=$(echo "$line" | sed -n 's/^Content-Length: *\([0-9][0-9]*\).*/\1/p')
                if [ ! -z "$clval" ]; then
                    contentlength=$clval
                fi
                # after close there should be an empty line separating headers from body
                if [ "$line" = "" ]; then
                    noempty=false
                fi
            elif [ -z "$body" ]; then
                if [ -z "$length" ]; then
                    # check if this is a hex chunk length (chunked transfer encoding)
                    (( 16#$line )) 2> /dev/null
                    if [ $? -eq 0 ]; then
                        length=$line
                    else
                        # not chunked -- this line is the body (Content-Length response)
                        body=$line
                    fi
                else
                    # had chunk length, this line is the body
                    body=$line
                fi
            fi
        done
        if [ ! -z "$body" ]; then
            # trim body to Content-Length to remove any trailing SSL errors
            if [ ! -z "$contentlength" ]; then
                body=${body:0:$contentlength}
            fi
            rm -f "${TMPDIR:-/tmp}/.a2a_sclient_err.$$"
            echo "$body"
        else
            # No HTTP body found -- report captured stderr if available
            if [ -s "${TMPDIR:-/tmp}/.a2a_sclient_err.$$" ]; then
                >&2 cat "${TMPDIR:-/tmp}/.a2a_sclient_err.$$"
            fi
            rm -f "${TMPDIR:-/tmp}/.a2a_sclient_err.$$"
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

