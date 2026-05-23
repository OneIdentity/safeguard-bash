#!/bin/bash
# test/suites/suite-security-ssrf-validation.sh
#
# F-safeguard-bash-006 regression suite for the validate_appliance_host
# helper added in src/utils/common.sh.
#
# Offline -- no DNS lookup, no network I/O.

suite_name() { echo "security-ssrf-validation"; }

suite_setup()
{
    local d
    d="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    SuiteData[script_dir]="$d"
    . "$d/src/utils/common.sh"
}

suite_cleanup()
{
    :
}

_expect_pass()
{
    local desc="$1" host="$2"
    shift 2
    if validate_appliance_host "$@" "$host" 2>/dev/null; then
        sg_assert "$desc" true
    else
        sg_assert "$desc" false
    fi
}

_expect_fail()
{
    local desc="$1" host="$2"
    shift 2
    if validate_appliance_host "$@" "$host" 2>/dev/null; then
        sg_assert "$desc" false
    else
        sg_assert "$desc" true
    fi
}

suite_execute()
{
    # Test 1: valid external IPv4 accepted.
    _expect_pass "Test 1 external IPv4 10.5.32.162 (not RFC1918? actually 10/8 is) -> use 8.8.8.8" "8.8.8.8"

    # Test 2: valid FQDN accepted.
    _expect_pass "Test 2 FQDN example.com" "example.com"

    # Test 3: IPv4 loopback rejected.
    _expect_fail "Test 3 loopback 127.0.0.1 rejected" "127.0.0.1"

    # Test 4: IPv4 RFC1918 private rejected.
    _expect_fail "Test 4 RFC1918 192.168.1.100 rejected" "192.168.1.100"
    _expect_fail "Test 4b RFC1918 10.0.0.5 rejected" "10.0.0.5"
    _expect_fail "Test 4c RFC1918 172.16.5.5 rejected" "172.16.5.5"
    _expect_pass "Test 4d 172.32.5.5 is outside 172.16/12 -- accepted" "172.32.5.5"

    # Test 5: IPv6 link-local rejected.
    _expect_fail "Test 5 IPv6 link-local fe80::1 rejected" "fe80::1"

    # Test 6: IPv4 link-local rejected.
    _expect_fail "Test 6 IPv4 link-local 169.254.0.1 rejected" "169.254.0.1"

    # Test 7: --allow-localhost overrides loopback.
    _expect_pass "Test 7 --allow-localhost 127.0.0.1 accepted" "127.0.0.1" "--allow-localhost"

    # Test 8: shell-injection attempts and malformed inputs rejected.
    _expect_fail "Test 8a shell metachar rejected: '; rm -rf /'" "'; rm -rf /"
    _expect_fail "Test 8b malformed IP 192.168.1 rejected" "192.168.1"
    _expect_fail "Test 8c bare integer 2130706433 rejected" "2130706433"
    _expect_fail "Test 8d empty input rejected" ""
    _expect_fail "Test 8e space-containing input rejected" "evil.com /etc/passwd"
    _expect_fail "Test 8f IPv4 octet out of range rejected" "999.1.1.1"

    # Test 9: IPv6 loopback rejected without flag.
    _expect_fail "Test 9 IPv6 ::1 loopback rejected" "::1"
    _expect_pass "Test 9b IPv6 ::1 with --allow-localhost accepted" "::1" "--allow-localhost"

    # Test 10: localhost literal rejected.
    _expect_fail "Test 10 'localhost' literal rejected" "localhost"
    _expect_pass "Test 10b 'localhost' with --allow-localhost accepted" "localhost" "--allow-localhost"

    # Test 11: valid IPv6 global accepted.
    _expect_pass "Test 11 IPv6 2001:db8::1 accepted" "2001:db8::1"
}
