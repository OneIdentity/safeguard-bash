#!/bin/bash
# test/suites/suite-security-cred-redaction.sh
#
# Verifies FP-safeguard-bash-002:
#   - argv-leakage: passwords/tokens never appear in `ps -ef` for child
#     curl/openssl processes spawned by connect-safeguard.sh /
#     invoke-safeguard-method.sh / src/utils/a2a.sh.
#   - error-output redaction: src/utils/redact-sensitive.sh masks ONLY
#     SDK auth-plumbing tokens (AccessToken, access_token, refresh_token,
#     id_token, UserToken) and the Authorization/Cookie/Set-Cookie HTTP
#     header values. It MUST NOT touch product response fields like
#     Password, ApiKey, PrivateKey, PasswordRulesPolicyId, ApiKeyName,
#     RequirePasswordChange, etc. -- see triage decision D-013.
#
# This suite is structured so that the unit-level cases (Tests 3, 4, 5)
# run without a Safeguard appliance, and the live-process inspection
# cases (Tests 1, 2) are skipped when TestAppliance is not configured.

suite_name() { echo "security-cred-redaction"; }

suite_setup()
{
    # Locate the helper relative to the suite file regardless of cwd.
    SuiteScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    RedactHelper="$SuiteScriptDir/../../src/utils/redact-sensitive.sh"
    if [ ! -f "$RedactHelper" ]; then
        >&2 echo "redact-sensitive.sh not found at $RedactHelper"
        return 1
    fi
    # shellcheck disable=SC1090
    . "$RedactHelper"
    return 0
}

# Test helper: run a callable and assert its stdout equals an expected
# string. Used by the offline unit cases below.
_sg_assert_stdout_eq()
{
    local description="$1"; shift
    local expected="$1"; shift
    local actual
    actual=$("$@")
    sg_assert_equal "$description" "$actual" "$expected"
}

# Test helper: assert stdout contains a substring.
_sg_assert_stdout_contains()
{
    local description="$1"; shift
    local needle="$1"; shift
    local actual
    actual=$("$@")
    sg_assert_contains "$description" "$actual" "$needle"
}

# Test helper: assert stdout does NOT contain a substring.
_sg_assert_stdout_lacks()
{
    local description="$1"; shift
    local needle="$1"; shift
    local actual
    actual=$("$@")
    if echo "$actual" | grep -q -- "$needle"; then
        _SuiteFail=$((_SuiteFail + 1))
        _SuiteErrors="${_SuiteErrors}    FAIL: ${description} (output unexpectedly contained '${needle}')\n"
        echo -e "    \033[0;31mFAIL\033[0m: $description [output unexpectedly contained '${needle}']"
        return 1
    else
        _SuitePass=$((_SuitePass + 1))
        echo -e "    \033[0;32mPASS\033[0m: $description"
        return 0
    fi
}

suite_execute()
{
    local SecretToken='ey-Secret-Token-DO-NOT-LEAK-12345.AAA.BBB'
    local SecretPass='SuperS3cret!Pass'

    # ---- Test 1: connect-safeguard.sh does not leak password via argv ----
    if [ -n "$TestAppliance" ]; then
        echo "  Test 1: connect-safeguard.sh password argv leak"
        # Launch the connect script via the password-on-stdin path. While
        # it is running (will fail because the appliance is unreachable
        # or rejects auth, that's fine -- we only need the child curl/
        # openssl processes to exist during the probe), snapshot the full
        # process table and grep for the secret.
        local probe_out
        probe_out=$(mktemp)
        (
            sleep 0.5
            ps -ef > "$probe_out" 2>/dev/null || ps -W > "$probe_out" 2>/dev/null || true
        ) &
        local probe_pid=$!
        echo "$SecretPass" | timeout 8 "$SuiteScriptDir/../../src/connect-safeguard.sh" \
            -a "$TestAppliance" -i local -u "secrev-bash-probe-user" -p -X \
            >/dev/null 2>&1 || true
        wait $probe_pid 2>/dev/null || true

        if grep -q -F "$SecretPass" "$probe_out" 2>/dev/null; then
            _SuiteFail=$((_SuiteFail + 1))
            _SuiteErrors="${_SuiteErrors}    FAIL: Test 1 connect-safeguard.sh leaked password to ps -ef\n"
            echo -e "    \033[0;31mFAIL\033[0m: Test 1 connect-safeguard.sh leaked password to ps -ef"
        else
            _SuitePass=$((_SuitePass + 1))
            echo -e "    \033[0;32mPASS\033[0m: Test 1 connect-safeguard.sh did not leak password via argv"
        fi
        rm -f "$probe_out"
    else
        sg_skip "Test 1 connect-safeguard.sh argv leak" "TestAppliance not configured (offline run)"
    fi

    # ---- Test 2: invoke-safeguard-method.sh does not leak bearer token ----
    if [ -n "$TestAppliance" ]; then
        echo "  Test 2: invoke-safeguard-method.sh bearer-token argv leak"
        local probe_out
        probe_out=$(mktemp)
        (
            sleep 0.3
            ps -ef > "$probe_out" 2>/dev/null || ps -W > "$probe_out" 2>/dev/null || true
        ) &
        local probe_pid=$!
        timeout 5 "$SuiteScriptDir/../../src/invoke-safeguard-method.sh" \
            -a "$TestAppliance" -t "$SecretToken" -s core -m GET -U "Me" \
            >/dev/null 2>&1 || true
        wait $probe_pid 2>/dev/null || true

        if grep -q -F "$SecretToken" "$probe_out" 2>/dev/null; then
            _SuiteFail=$((_SuiteFail + 1))
            _SuiteErrors="${_SuiteErrors}    FAIL: Test 2 invoke-safeguard-method.sh leaked bearer token to ps -ef\n"
            echo -e "    \033[0;31mFAIL\033[0m: Test 2 invoke-safeguard-method.sh leaked bearer token to ps -ef"
        else
            _SuitePass=$((_SuitePass + 1))
            echo -e "    \033[0;32mPASS\033[0m: Test 2 invoke-safeguard-method.sh did not leak bearer token via argv"
        fi
        rm -f "$probe_out"
    else
        sg_skip "Test 2 invoke-safeguard-method.sh argv leak" "TestAppliance not configured (offline run)"
    fi

    # ---- Test 3: error JSON containing AccessToken is redacted ----
    local err_json='{"Code":400,"Message":"bad request","AccessToken":"ey-secret-token-abc.def.ghi"}'
    local err_out
    err_out=$(echo "$err_json" | redact_sensitive)
    _sg_assert_stdout_lacks \
        "Test 3 redact-sensitive masks AccessToken value in error JSON" \
        "ey-secret-token-abc.def.ghi" \
        echo "$err_out"

    _sg_assert_stdout_contains \
        "Test 3 redact-sensitive emits a REDACTED placeholder" \
        "REDACTED" \
        echo "$err_out"

    # ---- Test 4 (positive plumbing-token): all allowlist keys + headers ----
    local plumb_json='{
        "AccessToken": "AAA-do-not-leak",
        "access_token": "BBB-do-not-leak",
        "refresh_token": "CCC-do-not-leak",
        "id_token": "DDD-do-not-leak",
        "UserToken": "EEE-do-not-leak",
        "NotSensitive": "keep-me"
    }'
    local plumb_out
    plumb_out=$(echo "$plumb_json" | redact_sensitive)
    sg_assert_equal "Test 4 AAA token masked" \
        "$(echo "$plumb_out" | grep -c 'AAA-do-not-leak')" "0"
    sg_assert_equal "Test 4 BBB token masked" \
        "$(echo "$plumb_out" | grep -c 'BBB-do-not-leak')" "0"
    sg_assert_equal "Test 4 CCC token masked" \
        "$(echo "$plumb_out" | grep -c 'CCC-do-not-leak')" "0"
    sg_assert_equal "Test 4 DDD token masked" \
        "$(echo "$plumb_out" | grep -c 'DDD-do-not-leak')" "0"
    sg_assert_equal "Test 4 EEE token masked" \
        "$(echo "$plumb_out" | grep -c 'EEE-do-not-leak')" "0"
    sg_assert_equal "Test 4 non-sensitive value preserved" \
        "$(echo "$plumb_out" | grep -c 'keep-me')" "1"
    # Verify the output is still valid JSON when jq is available.
    if command -v jq >/dev/null 2>&1; then
        if echo "$plumb_out" | jq . >/dev/null 2>&1; then
            _SuitePass=$((_SuitePass + 1))
            echo -e "    \033[0;32mPASS\033[0m: Test 4 redacted output is still valid JSON"
        else
            _SuiteFail=$((_SuiteFail + 1))
            _SuiteErrors="${_SuiteErrors}    FAIL: Test 4 redacted JSON failed jq parse\n"
            echo -e "    \033[0;31mFAIL\033[0m: Test 4 redacted JSON failed jq parse"
        fi
    fi

    # HTTP header redaction (curl trace / openssl s_client output style).
    local header_capture='> GET /service/core/v4/Me HTTP/1.1
> Host: appliance.example
> Authorization: Bearer ey-leak-this.AAA.BBB
> Cookie: SessionId=leak-this-cookie
< HTTP/1.1 401 Unauthorized
< Set-Cookie: SafeguardToken=leak-this-too; Path=/
'
    local header_out
    header_out=$(echo "$header_capture" | redact_sensitive)
    _sg_assert_stdout_lacks \
        "Test 4 Authorization header value redacted" \
        "ey-leak-this.AAA.BBB" \
        echo "$header_out"
    _sg_assert_stdout_lacks \
        "Test 4 Cookie header value redacted" \
        "leak-this-cookie" \
        echo "$header_out"
    _sg_assert_stdout_lacks \
        "Test 4 Set-Cookie header value redacted" \
        "leak-this-too" \
        echo "$header_out"

    # ---- Test 5 (D-013 NEGATIVE tripwire): product fields pass through ----
    # These field names are LEGITIMATE Safeguard API payload data. Per the
    # D-013 redaction-scope doctrine recorded in security-triage.md, the
    # SDK MUST NOT touch them. If a future change adds substring matching
    # or expands the allowlist, this test will fail loudly.
    local product_json='{
        "Password": "p@ss",
        "ApiKey": "xyz",
        "PrivateKey": "-----BEGIN PRIVATE KEY-----abcdef-----END PRIVATE KEY-----",
        "PasswordRulesPolicyId": "abc-123",
        "ApiKeyName": "ServiceAcct-Prod",
        "RequirePasswordChange": true,
        "PasswordHistoryDepth": 5,
        "NewPasswordValidUntil": "2030-01-01T00:00:00Z",
        "AccountPasswordRule": "DefaultRule",
        "SshHostKey": "ssh-rsa AAAA...",
        "AccessTokenLifetime": 3600,
        "ApiKeySecret": "secret-value-keep"
    }'
    local product_out
    product_out=$(echo "$product_json" | redact_sensitive)

    # Every value must survive untouched.
    sg_assert_equal "Test 5 (TRIPWIRE) Password value preserved" \
        "$(echo "$product_out" | grep -c '"p@ss"')" "1"
    sg_assert_equal "Test 5 (TRIPWIRE) ApiKey value preserved" \
        "$(echo "$product_out" | grep -c '"xyz"')" "1"
    sg_assert_equal "Test 5 (TRIPWIRE) PrivateKey value preserved" \
        "$(echo "$product_out" | grep -c 'BEGIN PRIVATE KEY')" "1"
    sg_assert_equal "Test 5 (TRIPWIRE) PasswordRulesPolicyId value preserved" \
        "$(echo "$product_out" | grep -c '"abc-123"')" "1"
    sg_assert_equal "Test 5 (TRIPWIRE) ApiKeyName value preserved" \
        "$(echo "$product_out" | grep -c '"ServiceAcct-Prod"')" "1"
    sg_assert_equal "Test 5 (TRIPWIRE) RequirePasswordChange value preserved" \
        "$(echo "$product_out" | grep -c 'true')" "1"
    sg_assert_equal "Test 5 (TRIPWIRE) PasswordHistoryDepth value preserved" \
        "$(echo "$product_out" | grep -c '\b5\b')" "1"
    sg_assert_equal "Test 5 (TRIPWIRE) NewPasswordValidUntil value preserved" \
        "$(echo "$product_out" | grep -c '2030-01-01T00:00:00Z')" "1"
    sg_assert_equal "Test 5 (TRIPWIRE) AccountPasswordRule value preserved" \
        "$(echo "$product_out" | grep -c '"DefaultRule"')" "1"
    sg_assert_equal "Test 5 (TRIPWIRE) SshHostKey value preserved" \
        "$(echo "$product_out" | grep -c 'ssh-rsa AAAA')" "1"
    sg_assert_equal "Test 5 (TRIPWIRE) AccessTokenLifetime value preserved (not AccessToken)" \
        "$(echo "$product_out" | grep -c '3600')" "1"
    sg_assert_equal "Test 5 (TRIPWIRE) ApiKeySecret value preserved (not ApiKey)" \
        "$(echo "$product_out" | grep -c '"secret-value-keep"')" "1"

    # And no REDACTED marker should appear anywhere in the product output.
    _sg_assert_stdout_lacks \
        "Test 5 (TRIPWIRE) no REDACTED marker in product-field-only JSON" \
        "REDACTED" \
        echo "$product_out"
}
