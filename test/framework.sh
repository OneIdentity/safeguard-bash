#!/bin/bash
# safeguard-bash test framework
# Modeled after SafeguardPsTestFramework from safeguard-ps
# This file is sourced by test suites and the test runner -- not called directly.

# --- Colors (disabled if not a terminal) ---
if [ -t 1 ]; then
    _CLR_GREEN="\033[0;32m"
    _CLR_RED="\033[0;31m"
    _CLR_YELLOW="\033[0;33m"
    _CLR_CYAN="\033[0;36m"
    _CLR_BOLD="\033[1m"
    _CLR_RESET="\033[0m"
else
    _CLR_GREEN="" _CLR_RED="" _CLR_YELLOW="" _CLR_CYAN="" _CLR_BOLD="" _CLR_RESET=""
fi

# --- Context ---
# Global test context variables
TestAppliance=
TestUser=
TestPassword=
TestVersion=4
TestPrefix="SgBashTest"
TestCABundleArg="-k"

# Per-suite state
_SuiteName=
_SuitePass=0
_SuiteFail=0
_SuiteSkip=0
_SuiteErrors=""

# Global totals
_TotalPass=0
_TotalFail=0
_TotalSkip=0
_TotalSuites=0
_TotalSuitesFailed=0
_SuiteResults=""

# Cleanup stack (LIFO)
_CleanupCount=0
declare -a _CleanupDescriptions
declare -a _CleanupActions

# Per-suite data store (associative array)
declare -A SuiteData

init_test_context()
{
    TestAppliance="$1"
    TestUser="$2"
    TestPassword="$3"
    TestVersion="${4:-4}"
}

reset_suite_state()
{
    _SuiteName=""
    _SuitePass=0
    _SuiteFail=0
    _SuiteSkip=0
    _SuiteErrors=""
    _CleanupCount=0
    _CleanupDescriptions=()
    _CleanupActions=()
    SuiteData=()
}

# --- Assertions ---

# Test an assertion by running a command/function.
# Usage: sg_assert "description" command [args...]
sg_assert()
{
    local description="$1"
    shift
    local start_time=$(date +%s%N 2>/dev/null || date +%s)

    if "$@" >/dev/null 2>&1; then
        _SuitePass=$((_SuitePass + 1))
        echo -e "    ${_CLR_GREEN}PASS${_CLR_RESET}: $description"
        return 0
    else
        _SuiteFail=$((_SuiteFail + 1))
        _SuiteErrors="${_SuiteErrors}    FAIL: ${description}\n"
        echo -e "    ${_CLR_RED}FAIL${_CLR_RESET}: $description"
        return 1
    fi
}

# Assert two values are equal.
# Usage: sg_assert_equal "description" "actual" "expected"
sg_assert_equal()
{
    local description="$1"
    local actual="$2"
    local expected="$3"

    if [ "$actual" = "$expected" ]; then
        _SuitePass=$((_SuitePass + 1))
        echo -e "    ${_CLR_GREEN}PASS${_CLR_RESET}: $description"
        return 0
    else
        _SuiteFail=$((_SuiteFail + 1))
        _SuiteErrors="${_SuiteErrors}    FAIL: ${description} (expected='${expected}', actual='${actual}')\n"
        echo -e "    ${_CLR_RED}FAIL${_CLR_RESET}: $description [expected='${expected}', actual='${actual}']"
        return 1
    fi
}

# Assert a value is not empty.
# Usage: sg_assert_not_null "description" "value"
sg_assert_not_null()
{
    local description="$1"
    local value="$2"

    if [ -n "$value" ]; then
        _SuitePass=$((_SuitePass + 1))
        echo -e "    ${_CLR_GREEN}PASS${_CLR_RESET}: $description"
        return 0
    else
        _SuiteFail=$((_SuiteFail + 1))
        _SuiteErrors="${_SuiteErrors}    FAIL: ${description} (value was empty)\n"
        echo -e "    ${_CLR_RED}FAIL${_CLR_RESET}: $description [value was empty]"
        return 1
    fi
}

# Assert a string contains a substring.
# Usage: sg_assert_contains "description" "haystack" "needle"
sg_assert_contains()
{
    local description="$1"
    local haystack="$2"
    local needle="$3"

    if echo "$haystack" | grep -q "$needle" 2>/dev/null; then
        _SuitePass=$((_SuitePass + 1))
        echo -e "    ${_CLR_GREEN}PASS${_CLR_RESET}: $description"
        return 0
    else
        _SuiteFail=$((_SuiteFail + 1))
        _SuiteErrors="${_SuiteErrors}    FAIL: ${description} (string did not contain '${needle}')\n"
        echo -e "    ${_CLR_RED}FAIL${_CLR_RESET}: $description [string did not contain '${needle}']"
        return 1
    fi
}

# Skip a test with a reason.
# Usage: sg_skip "description" "reason"
sg_skip()
{
    local description="$1"
    local reason="${2:-no reason given}"

    _SuiteSkip=$((_SuiteSkip + 1))
    echo -e "    ${_CLR_YELLOW}SKIP${_CLR_RESET}: $description ($reason)"
}

# --- Cleanup Registration ---

# Register a cleanup action to run after the suite completes (LIFO order).
# Usage: sg_register_cleanup "description" "command or function"
sg_register_cleanup()
{
    local description="$1"
    local action="$2"

    _CleanupDescriptions[$_CleanupCount]="$description"
    _CleanupActions[$_CleanupCount]="$action"
    _CleanupCount=$((_CleanupCount + 1))
}

# Execute all registered cleanup actions in LIFO order.
run_registered_cleanups()
{
    if [ $_CleanupCount -eq 0 ]; then
        return
    fi

    echo -e "  ${_CLR_CYAN}Running registered cleanups...${_CLR_RESET}"
    local i
    for (( i = _CleanupCount - 1; i >= 0; i-- )); do
        echo "    Cleanup: ${_CleanupDescriptions[$i]}"
        timeout 15 bash -c "${_CleanupActions[$i]}" 2>/dev/null || true
    done
}

# --- Suite Runner ---

# Run a test suite script. The suite script must define these functions:
#   suite_name()    - echo the suite name
#   suite_setup()   - setup phase (optional)
#   suite_execute() - test execution phase
#   suite_cleanup() - cleanup phase (optional)
#
# Usage: run_suite /path/to/suite-file.sh
run_suite()
{
    local suite_file="$1"
    local suite_basename=$(basename "$suite_file" .sh)

    reset_suite_state

    # Source the suite to load its functions
    . "$suite_file"

    # Get suite name
    if type suite_name >/dev/null 2>&1; then
        _SuiteName=$(suite_name)
    else
        _SuiteName="$suite_basename"
    fi

    _TotalSuites=$((_TotalSuites + 1))
    echo ""
    echo -e "${_CLR_BOLD}=== Suite: ${_SuiteName} ===${_CLR_RESET}"

    # Setup phase
    local setup_ok=true
    if type suite_setup >/dev/null 2>&1; then
        echo -e "  ${_CLR_CYAN}Setup...${_CLR_RESET}"
        if ! suite_setup; then
            echo -e "  ${_CLR_RED}Setup FAILED -- skipping Execute phase${_CLR_RESET}"
            setup_ok=false
        fi
    fi

    # Execute phase (only if setup succeeded)
    if [ "$setup_ok" = true ]; then
        echo -e "  ${_CLR_CYAN}Execute...${_CLR_RESET}"
        if type suite_execute >/dev/null 2>&1; then
            suite_execute
        fi
    fi

    # Registered cleanup actions run first (while session is still active)
    run_registered_cleanups

    # Suite cleanup runs last (restores session state for next suite)
    if type suite_cleanup >/dev/null 2>&1; then
        echo -e "  ${_CLR_CYAN}Cleanup...${_CLR_RESET}"
        suite_cleanup 2>/dev/null || true
    fi

    # Unset suite functions so they don't leak into next suite
    unset -f suite_name suite_setup suite_execute suite_cleanup 2>/dev/null

    # Record results
    local suite_status="PASS"
    if [ $_SuiteFail -gt 0 ]; then
        suite_status="FAIL"
        _TotalSuitesFailed=$((_TotalSuitesFailed + 1))
    fi

    _TotalPass=$((_TotalPass + _SuitePass))
    _TotalFail=$((_TotalFail + _SuiteFail))
    _TotalSkip=$((_TotalSkip + _SuiteSkip))

    _SuiteResults="${_SuiteResults}  ${suite_status}: ${_SuiteName} (pass=${_SuitePass}, fail=${_SuiteFail}, skip=${_SuiteSkip})\n"

    echo -e "  ${_CLR_BOLD}Result: ${_SuitePass} passed, ${_SuiteFail} failed, ${_SuiteSkip} skipped${_CLR_RESET}"
}

# --- Reporting ---

print_test_report()
{
    echo ""
    echo -e "${_CLR_BOLD}============================================${_CLR_RESET}"
    echo -e "${_CLR_BOLD}  Test Report${_CLR_RESET}"
    echo -e "${_CLR_BOLD}============================================${_CLR_RESET}"
    echo -e "$_SuiteResults"
    echo -e "${_CLR_BOLD}--------------------------------------------${_CLR_RESET}"
    echo -e "${_CLR_BOLD}  Suites: ${_TotalSuites} (${_TotalSuitesFailed} failed)${_CLR_RESET}"
    echo -e "${_CLR_BOLD}  Tests:  ${_TotalPass} passed, ${_TotalFail} failed, ${_TotalSkip} skipped${_CLR_RESET}"
    echo -e "${_CLR_BOLD}============================================${_CLR_RESET}"

    if [ $_TotalFail -gt 0 ]; then
        echo ""
        echo -e "${_CLR_RED}${_CLR_BOLD}FAILURES:${_CLR_RESET}"
        echo -e "$_SuiteErrors"
    fi
}

# --- Helpers ---

# Connect to the test appliance and create a login file.
# Uses the global TestAppliance, TestUser, TestPassword, TestVersion.
sg_connect()
{
    echo "$TestPassword" | "$ScriptDir/../src/connect-safeguard.sh" \
        -a "$TestAppliance" -i local -u "$TestUser" -v "$TestVersion" -p 2>/dev/null
}

# Connect to the test appliance using PKCE and create a login file.
# Uses the global TestAppliance, TestUser, TestPassword, TestVersion.
sg_connect_pkce()
{
    echo "$TestPassword" | "$ScriptDir/../src/connect-safeguard.sh" \
        -a "$TestAppliance" -i local -u "$TestUser" -v "$TestVersion" -P -p 2>/dev/null
}

# Disconnect from the test appliance.
sg_disconnect()
{
    "$ScriptDir/../src/disconnect-safeguard.sh" 2>/dev/null || true
}

# Invoke a Safeguard API method using the login file.
# Usage: sg_invoke -s service -m method -U url [-b body]
sg_invoke()
{
    "$ScriptDir/../src/invoke-safeguard-method.sh" "$@" 2>/dev/null
}

# --- Resource Owner Grant (ROG) Management ---
# The Safeguard "Allowed OAuth2 Grant Types" setting controls whether
# password-based (Resource Owner) login is permitted. Tests that use
# sg_connect (password auth) require ROG to be enabled. These helpers
# detect, enable, and restore the setting so the test runner works even
# when ROG is off by default.

_OriginalGrantTypes=""
_RogWasDisabled=false
_GrantTypeSettingName="Allowed OAuth2 Grant Types"
_GrantTypeSettingUrl="Settings/Allowed%20OAuth2%20Grant%20Types"

# Query the current allowed grant types from the appliance.
# Requires an active login session. Sets _OriginalGrantTypes.
sg_get_grant_types()
{
    local settings
    settings=$(sg_invoke -s core -m GET -U "Settings")
    if [ -z "$settings" ]; then
        >&2 echo "Warning: Failed to read appliance Settings"
        return 1
    fi
    local setting_exists
    setting_exists=$(echo "$settings" | jq -r ".[] | select(.Name==\"$_GrantTypeSettingName\") | .Name" 2>/dev/null)
    if [ -z "$setting_exists" ]; then
        >&2 echo "Warning: Could not find '$_GrantTypeSettingName' in Settings"
        return 1
    fi
    _OriginalGrantTypes=$(echo "$settings" | jq -r ".[] | select(.Name==\"$_GrantTypeSettingName\") | .Value" 2>/dev/null)
}

# Ensure Resource Owner grant type is enabled. Must be called while
# connected (login file exists). Saves original state for later restore.
sg_ensure_rog_enabled()
{
    sg_get_grant_types || return 1

    if echo "$_OriginalGrantTypes" | grep -qi "ResourceOwner"; then
        echo "  Resource Owner grant is already enabled."
        _RogWasDisabled=false
        return 0
    fi

    echo "  Resource Owner grant is DISABLED -- enabling for tests..."
    _RogWasDisabled=true

    local NewValue
    if [ -z "$_OriginalGrantTypes" ]; then
        NewValue="ResourceOwner"
    else
        NewValue="$_OriginalGrantTypes, ResourceOwner"
    fi
    local Body
    Body=$(jq -n --arg v "$NewValue" '{"Value": $v}')
    local Result
    Result=$(sg_invoke -s core -m PUT -U "$_GrantTypeSettingUrl" -b "$Body")
    if [ -z "$Result" ]; then
        >&2 echo "Error: Failed to enable Resource Owner grant type"
        return 1
    fi

    echo "  Resource Owner grant enabled successfully."
}

# Restore the original grant type setting. Connects via PKCE (since ROG
# may have just been disabled) and PUTs the original value back.
sg_restore_rog()
{
    if [ "$_RogWasDisabled" != true ]; then
        return 0
    fi

    echo ""
    echo "Restoring original grant type setting..."

    # Reconnect via PKCE for the restore (ROG-independent)
    sg_disconnect
    sg_connect_pkce

    local Body
    Body=$(jq -n --arg v "$_OriginalGrantTypes" '{"Value": $v}')
    local Result
    Result=$(sg_invoke -s core -m PUT -U "$_GrantTypeSettingUrl" -b "$Body")
    if [ -z "$Result" ]; then
        >&2 echo "Warning: Failed to restore original grant type setting"
    else
        echo "  Grant types restored to: $_OriginalGrantTypes"
    fi

    sg_disconnect
}
