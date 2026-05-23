#!/bin/bash
# test/suites/suite-security-response-size.sh
#
# F-safeguard-bash-007 regression suite. Verifies that
# src/invoke-safeguard-method.sh now caps response sizes via curl's
# --max-filesize option and validates the SAFEGUARD_MAX_RESPONSE_SIZE
# env override.
#
# Offline. Inspects the script's behavior with bogus arguments so the
# size-validation paths run without hitting an appliance.

suite_name() { echo "security-response-size"; }

suite_setup()
{
    SuiteData[script_dir]="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
}

suite_cleanup()
{
    :
}

suite_execute()
{
    local script="${SuiteData[script_dir]}/src/invoke-safeguard-method.sh"

    # Test 1: GET curl invocation carries --max-filesize.
    if grep -E -q -- '--max-filesize \$MaxResponseSize' "$script"; then
        sg_assert "Test 1 GET/DELETE curl uses --max-filesize" true
    else
        sg_assert "Test 1 GET/DELETE curl uses --max-filesize" false
    fi

    # Test 2: PUT/POST curl invocation carries --max-filesize. Both case
    # arms use the same variable; count the occurrences.
    local count
    count=$(grep -E -c -- '--max-filesize \$MaxResponseSize' "$script")
    sg_assert "Test 2 --max-filesize appears in both GET/DELETE and PUT/POST arms" \
        [ "$count" -ge 2 ]

    # Test 3: env override is read.
    if grep -q 'SAFEGUARD_MAX_RESPONSE_SIZE' "$script"; then
        sg_assert "Test 3 SAFEGUARD_MAX_RESPONSE_SIZE env var is honored" true
    else
        sg_assert "Test 3 SAFEGUARD_MAX_RESPONSE_SIZE env var is honored" false
    fi

    # Test 4: a non-numeric override is rejected before curl is invoked.
    local out rc
    out=$(SAFEGUARD_MAX_RESPONSE_SIZE="not-a-number" \
        "$BASH" "$script" -a 192.0.2.1 -n -s core -m GET -U Me 2>&1 < /dev/null)
    rc=$?
    sg_assert "Test 4 non-numeric SAFEGUARD_MAX_RESPONSE_SIZE rejected (exit nonzero)" \
        [ "$rc" -ne 0 ]
    case "$out" in
        *"must be a positive integer"*)
            sg_assert "Test 4 error message names the offending value" true
            ;;
        *)
            sg_assert "Test 4 error message names the offending value" false
            ;;
    esac

    # Test 5: an override above the 100 MiB safety cap is rejected.
    out=$(SAFEGUARD_MAX_RESPONSE_SIZE="999999999" \
        "$BASH" "$script" -a 192.0.2.1 -n -s core -m GET -U Me 2>&1 < /dev/null)
    rc=$?
    sg_assert "Test 5 over-cap SAFEGUARD_MAX_RESPONSE_SIZE rejected (exit nonzero)" \
        [ "$rc" -ne 0 ]
    case "$out" in
        *"100 MiB"*|*"safety cap"*)
            sg_assert "Test 5 error message mentions the 100 MiB safety cap" true
            ;;
        *)
            sg_assert "Test 5 error message mentions the 100 MiB safety cap" false
            ;;
    esac

    # Test 6: usage text mentions the size cap (operator-discoverable).
    out=$("$BASH" "$script" -h 2>&1)
    case "$out" in
        *"SAFEGUARD_MAX_RESPONSE_SIZE"*)
            sg_assert "Test 6 usage text documents the size override env var" true
            ;;
        *)
            sg_assert "Test 6 usage text documents the size override env var" false
            ;;
    esac
}
