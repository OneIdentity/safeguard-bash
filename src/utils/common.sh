#!/bin/bash
# This is a script to add common functionality across multiple scripts
# It shouldn't be called directly.

BackOffWait=1
backoff_wait()
{
    local WaitMax=30
    if [ ! -z "$1" ]; then
        WaitMax=$1
    fi
    sleep $BackOffWait
    if [ $BackOffWait -lt $WaitMax ]; then
        BackOffWait=$((BackOffWait+1))
    fi
}
reset_backoff_wait()
{
    BackOffWait=1
}

# Parse the running curl's major/minor version into _CurlMajor / _CurlMinor.
# The old single-field parse read the MINOR digit (e.g. "5" from curl 8.5.0)
# and wrongly compared it against 33, dropping flags on curl >= 8.x.
_parse_curl_version()
{
    local ver
    ver=$(curl --version 2>/dev/null | sed -n '1s/^curl \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1.\2/p')
    _CurlMajor=${ver%%.*}
    _CurlMinor=${ver##*.}
    : "${_CurlMajor:=0}" "${_CurlMinor:=0}"
}

# curl_version_ge MAJOR MINOR -- returns 0 (true) when curl is at least that version.
curl_version_ge()
{
    _parse_curl_version
    [ "$_CurlMajor" -gt "$1" ] || { [ "$_CurlMajor" -eq "$1" ] && [ "$_CurlMinor" -ge "$2" ]; }
}

# Sets http11flag='--http1.1' when curl supports it (>= 7.33), otherwise empties it.
# Client-certificate auth requires HTTP/1.1: HTTP/2 forbids the TLS post-handshake
# certificate exchange that cert auth relies on, so letting curl negotiate h2 (via
# ALPN, common on curl 8.x against SPP 9.0 / TLS 1.3) breaks cert auth with a 60094.
set_http11_flag()
{
    if curl_version_ge 7 33; then
        http11flag='--http1.1'
    else
        http11flag=''
    fi
}

# Opt-in TLS version pinning driven by SAFEGUARD_TLS_MIN / SAFEGUARD_TLS_MAX
# (values 1.0, 1.1, 1.2, 1.3). Default (both unset) leaves negotiation unchanged.
# Populates the newline-separated $tlsflags for use inside curl -K config blocks.
set_tls_version_flags()
{
    tlsflags=''
    local min="${SAFEGUARD_TLS_MIN:-}"
    local max="${SAFEGUARD_TLS_MAX:-}"
    local flag
    if [ -n "$min" ]; then
        case "$min" in
            1.0) flag='--tlsv1.0' ;;
            1.1) flag='--tlsv1.1' ;;
            1.2) flag='--tlsv1.2' ;;
            1.3) flag='--tlsv1.3' ;;
            *) >&2 echo "Invalid SAFEGUARD_TLS_MIN='$min' (expected 1.0, 1.1, 1.2, or 1.3)"; exit 1 ;;
        esac
        tlsflags="$flag"
    fi
    if [ -n "$max" ]; then
        case "$max" in
            1.0|1.1|1.2|1.3) ;;
            *) >&2 echo "Invalid SAFEGUARD_TLS_MAX='$max' (expected 1.0, 1.1, 1.2, or 1.3)"; exit 1 ;;
        esac
        # curl grew --tls-max in 7.54.0
        if curl_version_ge 7 54; then
            if [ -n "$tlsflags" ]; then
                tlsflags="$tlsflags"$'\n'"--tls-max $max"
            else
                tlsflags="--tls-max $max"
            fi
        else
            >&2 echo "Warning: curl does not support --tls-max (requires >= 7.54); SAFEGUARD_TLS_MAX ignored"
        fi
    fi
}

# Best-effort translation of SAFEGUARD_TLS_MIN / SAFEGUARD_TLS_MAX into openssl
# s_client arguments for the GnuTLS cert-auth fallback paths. Populates the
# OpenSslTlsArgs array (empty when no enforcement is requested).
set_openssl_tls_args()
{
    OpenSslTlsArgs=()
    local min="${SAFEGUARD_TLS_MIN:-}"
    local max="${SAFEGUARD_TLS_MAX:-}"
    if [ -z "$min" ] && [ -z "$max" ]; then
        return 0
    fi
    if openssl s_client -help 2>&1 | grep -q -- '-min_protocol'; then
        if [ -n "$min" ]; then OpenSslTlsArgs+=(-min_protocol "TLSv$min"); fi
        if [ -n "$max" ]; then OpenSslTlsArgs+=(-max_protocol "TLSv$max"); fi
    else
        # Older openssl only exposes exact-version flags (e.g. -tls1_2). Pin to the
        # ceiling when given, otherwise to the floor -- the closest best effort.
        local pin="${max:-$min}"
        OpenSslTlsArgs+=("-tls$(echo "$pin" | tr '.' '_')")
    fi
    return 0
}
