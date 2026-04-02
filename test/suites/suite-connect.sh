#!/bin/bash
# Suite: Connect & Core
# Tests connect-safeguard.sh, disconnect-safeguard.sh, get-logged-in-user.sh,
# invoke-safeguard-method.sh, and get-appliance-status.sh

suite_name()
{
    echo "Connect & Core"
}

suite_setup()
{
    # Ensure we start disconnected
    sg_disconnect
    # Verify the login file does not exist
    rm -f "$HOME/.safeguard_login" 2>/dev/null
    return 0
}

suite_execute()
{
    local LoginFile="$HOME/.safeguard_login"

    # --- Test: Connect to appliance ---
    sg_connect
    sg_assert "connect-safeguard.sh creates login file" test -f "$LoginFile"

    # --- Test: Login file contains appliance address ---
    local stored_appliance=$(grep "^Appliance=" "$LoginFile" 2>/dev/null | cut -d= -f2)
    sg_assert_equal "Login file stores correct appliance" "$stored_appliance" "$TestAppliance"

    # --- Test: Login file contains an access token ---
    local stored_token=$(grep "^AccessToken=" "$LoginFile" 2>/dev/null | cut -d= -f2)
    sg_assert_not_null "Login file contains access token" "$stored_token"

    # --- Test: get-logged-in-user.sh returns user info ---
    local user_result=$("$ScriptDir/../src/get-logged-in-user.sh" 2>/dev/null)
    sg_assert_not_null "get-logged-in-user.sh returns data" "$user_result"

    # Local provider usernames are case-insensitive; normalize for comparison
    local user_name=$(echo "$user_result" | jq -r '.Name' 2>/dev/null | tr '[:upper:]' '[:lower:]')
    local expected_user=$(echo "$TestUser" | tr '[:upper:]' '[:lower:]')
    sg_assert_equal "Logged-in user matches test user" "$user_name" "$expected_user"

    # --- Test: invoke-safeguard-method.sh can call core service ---
    local me_result=$(sg_invoke -s core -m GET -U "Me")
    sg_assert_not_null "invoke-safeguard-method.sh GET Me returns data" "$me_result"

    # --- Test: get-appliance-status.sh returns status ---
    local status_result=$("$ScriptDir/../src/get-appliance-status.sh" 2>/dev/null)
    sg_assert_not_null "get-appliance-status.sh returns data" "$status_result"

    local app_state=$(echo "$status_result" | jq -r '.ApplianceCurrentState' 2>/dev/null)
    sg_assert_equal "Appliance state is Online" "$app_state" "Online"

    # --- Test: Disconnect ---
    sg_disconnect
    sg_assert "disconnect-safeguard.sh removes login file" test ! -f "$LoginFile"
}

suite_cleanup()
{
    # Ensure we leave disconnected regardless of test outcome
    sg_disconnect
}
