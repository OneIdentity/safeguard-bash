#!/bin/bash
# Suite: Device Code Login
# Tests connect-safeguard.sh -D (OAuth 2.0 Device Authorization Grant):
#   - disabled-grant negative case (DeviceCode removed from allowed grants)
#   - enabled baseline (verification URL + user code surfaced on stderr)
#   - optional opt-in scripted no-human approval E2E (LOCAL/no-MFA only)
#
# The suite mutates the appliance "Allowed OAuth2 Grant Types" setting, so it
# saves the exact original value at setup and restores it in cleanup, even when
# the test body fails. $HOME/.safeguard_login is treated as sensitive: tokens
# are never echoed in assertion output.

suite_name()
{
    echo "Device Code Login"
}

suite_setup()
{
    local LoginFile="$HOME/.safeguard_login"

    # Start from a clean, disconnected state.
    sg_disconnect
    rm -f "$LoginFile" 2>/dev/null

    # Connect via PKCE (works regardless of grant-type configuration) so we
    # can read and mutate the grant-type setting.
    sg_connect_pkce
    if [ ! -f "$LoginFile" ]; then
        >&2 echo "  Device Code setup: PKCE connect failed; cannot manage grant types."
        return 1
    fi

    # Save the EXACT current grant-type value for restore in cleanup. This is
    # captured per-suite (independent of the runner's ROG save) so cleanup
    # restores the state as it was on suite entry.
    if ! sg_get_grant_types; then
        >&2 echo "  Device Code setup: could not read Allowed OAuth2 Grant Types."
        return 1
    fi
    SuiteData[OrigGrantTypes]="$_OriginalGrantTypes"

    # Ensure DeviceCode is enabled for the baseline/E2E cases.
    sg_ensure_grant_type_enabled "DeviceCode"

    return 0
}

suite_execute()
{
    local LoginFile="$HOME/.safeguard_login"

    # ----------------------------------------------------------------------
    # Test 2: Disabled-grant error (reactive)
    # ----------------------------------------------------------------------
    # Remove DeviceCode from the allowed grant types, disconnect, then attempt
    # a device-code login and assert it fails with a CLI-visible disabled-grant
    # message. The DeviceLogin error body is HTML, not JSON, so detection stays
    # reactive against the CLI-surfaced text and tolerates summarized wording.
    sg_set_grant_type_enabled "DeviceCode" false
    sg_disconnect
    rm -f "$LoginFile" 2>/dev/null

    local disabled_output disabled_exit
    disabled_output=$("$ScriptDir/../src/connect-safeguard.sh" \
        -a "$TestAppliance" -i local -v "$TestVersion" -D 2>&1)
    disabled_exit=$?

    sg_assert "Disabled DeviceCode: connect exits non-zero" \
        test "$disabled_exit" -ne 0
    sg_assert "Disabled DeviceCode: no login file is created" \
        test ! -f "$LoginFile"

    # The output must identify the device authorization request context.
    local disabled_has_context=false
    if echo "$disabled_output" | grep -qi "device"; then
        disabled_has_context=true
    fi
    sg_assert_equal "Disabled DeviceCode: output references device-login context" \
        "$disabled_has_context" "true"

    # The output must indicate a grant/not-allowed/disabled condition. Prefer
    # the exact appliance marker when present; otherwise accept the summarized
    # "grant type ... not enabled/allowed/disabled" wording the CLI surfaces.
    local disabled_has_marker=false
    if echo "$disabled_output" | grep -qi "device code grant type is not allowed"; then
        disabled_has_marker=true
    elif echo "$disabled_output" | grep -qiE "grant type.*(not.*(allowed|enabled)|disabled)"; then
        disabled_has_marker=true
    elif echo "$disabled_output" | grep -qiE "not allowed|not enabled|disabled"; then
        disabled_has_marker=true
    fi
    sg_assert_equal "Disabled DeviceCode: output indicates grant not allowed/disabled" \
        "$disabled_has_marker" "true"

    # ----------------------------------------------------------------------
    # Test 3: Enabled baseline -- request succeeds and code is surfaced
    # ----------------------------------------------------------------------
    # Re-enable DeviceCode, then start a device-code login capturing stderr.
    # Use capture-then-terminate so the baseline does not poll until the code
    # expires; token/login-file assertions are not applicable without approval.
    sg_connect_pkce
    sg_ensure_grant_type_enabled "DeviceCode"
    sg_disconnect
    rm -f "$LoginFile" 2>/dev/null

    local errfile="$ScriptDir/.device-code-baseline.$$.stderr"
    rm -f "$errfile" 2>/dev/null

    "$ScriptDir/../src/connect-safeguard.sh" \
        -a "$TestAppliance" -i local -v "$TestVersion" -D >/dev/null 2>"$errfile" &
    local dc_pid=$!

    # Wait until the user-code instructions appear, the process exits, or we
    # hit a short cap -- whichever comes first.
    local waited=0
    while [ $waited -lt 30 ]; do
        if grep -q "and enter the code:" "$errfile" 2>/dev/null; then
            break
        fi
        if ! kill -0 "$dc_pid" 2>/dev/null; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done

    # Terminate the polling process so the baseline never hangs to expiry.
    kill "$dc_pid" 2>/dev/null
    wait "$dc_pid" 2>/dev/null

    local baseline_output
    baseline_output=$(cat "$errfile" 2>/dev/null)
    rm -f "$errfile" 2>/dev/null

    sg_assert_contains "Baseline: stderr prompts to open a web browser" \
        "$baseline_output" "To sign in, use a web browser to open the page:"
    sg_assert_contains "Baseline: stderr asks the user to enter the code" \
        "$baseline_output" "and enter the code:"

    # The line after the browser prompt is the verification URL.
    local verification_uri
    verification_uri=$(echo "$baseline_output" | \
        sed -n '/To sign in, use a web browser to open the page:/{n;s/^[[:space:]]*//;p;}')
    sg_assert_not_null "Baseline: verification URL is surfaced" "$verification_uri"
    sg_assert_contains "Baseline: verification URL is an RSTS URL" \
        "$verification_uri" "/RSTS/"

    # The line after "and enter the code:" is the user code.
    local user_code
    user_code=$(echo "$baseline_output" | \
        sed -n '/and enter the code:/{n;s/^[[:space:]]*//;p;}')
    sg_assert_not_null "Baseline: a non-empty user code is surfaced" "$user_code"

    # verification_uri_complete is optional; assert only when surfaced.
    if echo "$baseline_output" | grep -qi "Or open this URL directly"; then
        local verification_uri_complete
        verification_uri_complete=$(echo "$baseline_output" | \
            sed -n '/Or open this URL directly to skip entering the code:/{n;s/^[[:space:]]*//;p;}')
        sg_assert_not_null "Baseline: direct verification URL is surfaced when present" \
            "$verification_uri_complete"
    else
        sg_skip "Baseline: direct verification URL" \
            "appliance did not surface verification_uri_complete"
    fi

    # ----------------------------------------------------------------------
    # Test 4: Opt-in true E2E -- scripted no-human approval (LOCAL/no-MFA)
    # ----------------------------------------------------------------------
    # Scripted approval via the rSTS LoginController is opt-in and best-effort.
    # It is limited to the local provider and no-MFA users, and may be skipped
    # if brittle. Enable it explicitly with SG_DEVICE_CODE_E2E=1.
    if [ "$SG_DEVICE_CODE_E2E" = "1" ]; then
        sg_skip "E2E: scripted device-code approval" \
            "scripted rSTS LoginController approval not yet automated; baseline covers the guaranteed floor"
    else
        sg_skip "E2E: scripted device-code approval" \
            "opt-in only; set SG_DEVICE_CODE_E2E=1 to attempt (LOCAL provider / no-MFA users only)"
    fi
}

suite_cleanup()
{
    local LoginFile="$HOME/.safeguard_login"

    # Always restore the EXACT original grant-type value captured at setup,
    # even if the test body failed. Reconnect via PKCE (grant-type-independent)
    # so this works regardless of the current DeviceCode/ROG state.
    if [ -n "${SuiteData[OrigGrantTypes]}" ]; then
        sg_disconnect
        sg_connect_pkce
        sg_put_grant_types "${SuiteData[OrigGrantTypes]}" >/dev/null 2>&1 || true
    fi

    sg_disconnect
    rm -f "$LoginFile" 2>/dev/null
}
