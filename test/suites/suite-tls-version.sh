#!/bin/bash
# Suite: TLS Version
# Exercises the SAFEGUARD_TLS_MIN / SAFEGUARD_TLS_MAX pinning contract against a
# live appliance. A TLS 1.2 ceiling and a TLS 1.2 floor always negotiate. A TLS
# 1.3 floor connects on a 1.3-capable appliance (SPP 9.0) and must fail closed
# (no silent downgrade) on one that only supports TLS 1.2 (8.x). An invalid
# version value is rejected before any network request is attempted.

suite_name()
{
    echo "TLS Version"
}

suite_setup()
{
    sg_disconnect
    SuiteData[Tls13Capable]=false
    if sg_appliance_supports_tls13 "$TestAppliance"; then
        SuiteData[Tls13Capable]=true
    fi
    return 0
}

# Attempt a password connect with the given TLS floor/ceiling and confirm the
# resulting session actually works. Returns 0 on a working session, 1 otherwise.
# Empty min or max leaves that bound unset.
_tls_connect_attempt()
{
    local min="$1"
    local max="$2"
    sg_disconnect
    export SAFEGUARD_TLS_MIN="$min"
    export SAFEGUARD_TLS_MAX="$max"
    local rc=1
    if sg_connect && sg_invoke -s core -m GET -U "Me" >/dev/null 2>&1; then
        rc=0
    fi
    unset SAFEGUARD_TLS_MIN SAFEGUARD_TLS_MAX
    sg_disconnect
    return $rc
}

# Inverse of _tls_connect_attempt: returns 0 only when the connect fails closed.
# Used to assert that a TLS 1.3 floor cannot silently downgrade to TLS 1.2.
_tls_connect_fails_closed()
{
    if _tls_connect_attempt "$1" "$2"; then
        return 1
    fi
    return 0
}

# Returns 0 only when an invalid TLS version is rejected: the connect helper must
# exit non-zero and emit the "Invalid SAFEGUARD_TLS_MIN" message before any
# network request is attempted.
_tls_invalid_value_rejected()
{
    sg_disconnect
    local out rc
    out=$(echo "$TestPassword" | SAFEGUARD_TLS_MIN="9.9" \
        "$ScriptDir/../src/connect-safeguard.sh" \
        -a "$TestAppliance" -i local -u "$TestUser" -v "$TestVersion" -p 2>&1)
    rc=$?
    sg_disconnect
    [ $rc -ne 0 ] && echo "$out" | grep -q "Invalid SAFEGUARD_TLS_MIN"
}

suite_execute()
{
    # A TLS 1.2 ceiling is always negotiable (8.x max; 9.0 also supports 1.2).
    sg_assert "Connect with SAFEGUARD_TLS_MAX=1.2 succeeds" \
        _tls_connect_attempt "" "1.2"

    # A TLS 1.2 floor (1.2-or-higher) is always negotiable.
    sg_assert "Connect with SAFEGUARD_TLS_MIN=1.2 succeeds" \
        _tls_connect_attempt "1.2" ""

    # A TLS 1.3 floor must connect on a 1.3-capable appliance and fail closed on
    # one that only supports TLS 1.2.
    if ${SuiteData[Tls13Capable]}; then
        sg_assert "Connect with SAFEGUARD_TLS_MIN=1.3 succeeds on TLS 1.3 appliance" \
            _tls_connect_attempt "1.3" ""
    else
        sg_assert "Connect with SAFEGUARD_TLS_MIN=1.3 fails closed on TLS 1.2-only appliance" \
            _tls_connect_fails_closed "1.3" ""
    fi

    # An invalid TLS version value must be rejected before any network request.
    sg_assert "Invalid SAFEGUARD_TLS_MIN value is rejected" \
        _tls_invalid_value_rejected
}

suite_cleanup()
{
    unset SAFEGUARD_TLS_MIN SAFEGUARD_TLS_MAX
    sg_disconnect
}
