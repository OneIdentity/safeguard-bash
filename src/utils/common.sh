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


# validate_appliance_host -- F-bash-006 (FP-safeguard-bash-005)
#
# Verify that the appliance hostname/IP supplied via -a (or read at the
# prompt) refers to an external endpoint, not a host on this network or
# this machine. This blocks accidental and adversarial SSRF where a
# crafted address makes the SDK shovel a bearer token at a local
# metadata service, neighbour container, etc.
#
# Usage:
#   validate_appliance_host [--allow-localhost] HOST
#     0 if HOST passes
#     1 otherwise (with explanatory message on stderr)
#
# Rejected by default:
#   - syntactically invalid input (shell metacharacters, slashes,
#     spaces, zero-length, raw integers, IPv4 octets out of range)
#   - IPv4 loopback (127.0.0.0/8)
#   - IPv4 link-local (169.254.0.0/16)
#   - IPv4 RFC1918 private (10/8, 172.16/12, 192.168/16)
#   - IPv6 loopback (::1)
#   - IPv6 link-local (fe80::/10)
#   - IPv6 unique-local (fc00::/7)
#   - the literal hostname "localhost"
#
# Accept-by-name is intentional (DNS resolution to a private range is
# out of scope here; that is a deeper network-control concern).
validate_appliance_host()
{
    local allow_local=false
    if [ "$1" = "--allow-localhost" ]; then
        allow_local=true
        shift
    fi
    local host="${1:-}"
    if [ -z "$host" ]; then
        >&2 echo "validate_appliance_host: empty appliance host."
        return 1
    fi
    # Reject shell metacharacters and other host-impossible characters
    # outright.
    case "$host" in
        *[\ \"\'\\\$\;\&\|\<\>\(\)\`\!\?\*\{\}\[\]\/]*)
            >&2 echo "validate_appliance_host: '$host' contains characters that are not valid in a host."
            return 1
            ;;
    esac
    # Loopback by name.
    case "$host" in
        localhost|localhost.localdomain)
            if $allow_local; then return 0; fi
            >&2 echo "validate_appliance_host: '$host' is the local machine; pass --allow-localhost to override."
            return 1
            ;;
    esac
    # IPv4 dotted-quad?
    if [[ "$host" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}" o3="${BASH_REMATCH[3]}" o4="${BASH_REMATCH[4]}"
        local octet
        for octet in "$o1" "$o2" "$o3" "$o4"; do
            if [ "$octet" -gt 255 ] 2>/dev/null; then
                >&2 echo "validate_appliance_host: '$host' has an IPv4 octet out of range."
                return 1
            fi
        done
        if [ "$o1" -eq 127 ]; then
            $allow_local && return 0
            >&2 echo "validate_appliance_host: '$host' is loopback (127.0.0.0/8); pass --allow-localhost to override."
            return 1
        fi
        if [ "$o1" -eq 169 ] && [ "$o2" -eq 254 ]; then
            $allow_local && return 0
            >&2 echo "validate_appliance_host: '$host' is link-local (169.254.0.0/16); pass --allow-localhost to override."
            return 1
        fi
        if [ "$o1" -eq 10 ]; then
            $allow_local && return 0
            >&2 echo "validate_appliance_host: '$host' is RFC1918 private (10.0.0.0/8); pass --allow-localhost to override."
            return 1
        fi
        if [ "$o1" -eq 192 ] && [ "$o2" -eq 168 ]; then
            $allow_local && return 0
            >&2 echo "validate_appliance_host: '$host' is RFC1918 private (192.168.0.0/16); pass --allow-localhost to override."
            return 1
        fi
        if [ "$o1" -eq 172 ] && [ "$o2" -ge 16 ] && [ "$o2" -le 31 ]; then
            $allow_local && return 0
            >&2 echo "validate_appliance_host: '$host' is RFC1918 private (172.16.0.0/12); pass --allow-localhost to override."
            return 1
        fi
        return 0
    fi
    # Bare integer (e.g. "2130706433" == 127.0.0.1)? Reject as
    # ambiguous; we will not normalize it.
    if [[ "$host" =~ ^[0-9]+$ ]]; then
        >&2 echo "validate_appliance_host: '$host' is a bare integer; supply a dotted-quad IPv4, an IPv6 address, or a hostname."
        return 1
    fi
    # IPv6 literal?
    if [[ "$host" =~ : ]]; then
        # Strip RFC 6874 zone id and brackets for matching, but reject
        # anything that is not roughly colon-hex.
        local h6="${host#[}"; h6="${h6%]}"; h6="${h6%%%*}"
        if ! [[ "$h6" =~ ^[0-9A-Fa-f:]+$ ]]; then
            >&2 echo "validate_appliance_host: '$host' is not a valid IPv6 address."
            return 1
        fi
        # ::1 loopback
        if [ "$h6" = "::1" ]; then
            $allow_local && return 0
            >&2 echo "validate_appliance_host: '$host' is IPv6 loopback (::1); pass --allow-localhost to override."
            return 1
        fi
        # link-local fe80::/10
        local lower
        lower=$(printf '%s' "$h6" | tr '[:upper:]' '[:lower:]')
        case "$lower" in
            fe8?:*|fe9?:*|fea?:*|feb?:*)
                $allow_local && return 0
                >&2 echo "validate_appliance_host: '$host' is IPv6 link-local (fe80::/10); pass --allow-localhost to override."
                return 1
                ;;
            fc??:*|fd??:*|fc?:*|fd?:*)
                $allow_local && return 0
                >&2 echo "validate_appliance_host: '$host' is IPv6 unique-local (fc00::/7); pass --allow-localhost to override."
                return 1
                ;;
        esac
        return 0
    fi
    # Hostname: letters, digits, hyphens, dots; labels 1..63 chars; no
    # leading/trailing hyphen. Must contain at least one alphabetic
    # character to disambiguate from malformed IPv4 like "192.168.1".
    if [[ "$host" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]] \
       && [[ "$host" =~ [A-Za-z] ]]; then
        return 0
    fi
    >&2 echo "validate_appliance_host: '$host' is not a valid hostname, IPv4, or IPv6 literal."
    return 1
}