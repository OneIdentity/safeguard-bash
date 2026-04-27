#!/bin/bash
# Suite: A2A Access Request Broker
# Tests the access request broker lifecycle: get (unconfigured), set, get,
# clear, and verify cleared. Also tests that new-a2a-access-request.sh
# validates inputs correctly (full brokering requires an entitlement/policy
# which is complex to set up in tests).
#
# Requires: PolicyAdmin, AssetAdmin, ApplianceAdmin, UserAdmin roles.
# Creates a RunAdmin user for this purpose.

suite_name()
{
    echo "A2A Access Request Broker"
}

suite_setup()
{
    sg_connect

    # Create full-admin user for this suite
    local admin_result=$("$ScriptDir/../src/new-user.sh" \
        -n "${TestPrefix}_BrokerAdmin" \
        -R "GlobalAdmin,AssetAdmin,PolicyAdmin,UserAdmin,ApplianceAdmin,Auditor,OperationsAdmin" \
        2>/dev/null)
    local admin_id=$(echo "$admin_result" | jq -r '.Id' 2>/dev/null)
    if [ -z "$admin_id" ] || [ "$admin_id" = "null" ]; then
        >&2 echo "Failed to create admin user for broker suite"
        return 1
    fi
    SuiteData[AdminId]="$admin_id"

    sg_invoke -s core -m PUT -U "Users/$admin_id/Password" -b '"BrokerTest1!"' >/dev/null
    sg_disconnect
    echo "BrokerTest1!" | "$ScriptDir/../src/connect-safeguard.sh" \
        -a "$TestAppliance" -i local -u "${TestPrefix}_BrokerAdmin" -v "$TestVersion" -p 2>/dev/null

    # Generate self-signed certificate for A2A
    local cert_dir=$(mktemp -d)
    SuiteData[CertDir]="$cert_dir"
    openssl req -x509 -newkey rsa:2048 -keyout "$cert_dir/key.pem" \
        -out "$cert_dir/cert.pem" -days 1 -nodes \
        -subj "/CN=${TestPrefix}_BrokerCert" 2>/dev/null
    if [ ! -f "$cert_dir/cert.pem" ] || [ ! -f "$cert_dir/key.pem" ]; then
        >&2 echo "Failed to generate self-signed certificate"
        return 1
    fi
    SuiteData[CertFile]="$cert_dir/cert.pem"
    SuiteData[KeyFile]="$cert_dir/key.pem"

    local thumbprint=$(openssl x509 -noout -fingerprint -sha1 -in "$cert_dir/cert.pem" \
        | cut -d= -f2 | tr -d :)
    SuiteData[Thumbprint]="$thumbprint"

    # Install trusted certificate on the appliance
    local cert_data=$(base64 -w 0 "$cert_dir/cert.pem")
    local trust_result=$(sg_invoke -s core -m POST -U "TrustedCertificates" \
        -b "{\"Base64CertificateData\": \"$cert_data\"}")
    local trust_id=$(echo "$trust_result" | jq -r '.Thumbprint' 2>/dev/null)
    if [ -z "$trust_id" ] || [ "$trust_id" = "null" ]; then
        >&2 echo "Failed to install trusted certificate"
        return 1
    fi
    SuiteData[TrustCertId]="$trust_id"
    sg_register_cleanup "Remove trusted certificate" \
        "$ScriptDir/../src/invoke-safeguard-method.sh -s core -m DELETE -U TrustedCertificates/$trust_id 2>/dev/null"

    # Create certificate user linked to the cert thumbprint
    local certuser_result=$("$ScriptDir/../src/new-certificate-user.sh" \
        -n "${TestPrefix}_BrokerCertUser" -s "$thumbprint" 2>/dev/null)
    local certuser_id=$(echo "$certuser_result" | jq -r '.Id' 2>/dev/null)
    if [ -z "$certuser_id" ] || [ "$certuser_id" = "null" ]; then
        >&2 echo "Failed to create certificate user"
        return 1
    fi
    SuiteData[CertUserId]="$certuser_id"
    sg_register_cleanup "Delete certificate user" \
        "$ScriptDir/../src/remove-user.sh -i $certuser_id"

    # Create a regular user to be used as a broker target (ForUser)
    local target_result=$("$ScriptDir/../src/new-user.sh" \
        -n "${TestPrefix}_BrokerTarget" 2>/dev/null)
    local target_id=$(echo "$target_result" | jq -r '.Id' 2>/dev/null)
    if [ -z "$target_id" ] || [ "$target_id" = "null" ]; then
        >&2 echo "Failed to create target user for broker suite"
        return 1
    fi
    SuiteData[TargetUserId]="$target_id"
    sg_register_cleanup "Delete broker target user" \
        "$ScriptDir/../src/remove-user.sh -i $target_id"

    # Pre-cleanup stale A2A registrations
    local stale_regs=$(sg_invoke -s core -m GET -U "A2ARegistrations?filter=AppName%20contains%20'${TestPrefix}_'")
    for id in $(echo "$stale_regs" | jq -r '.[].Id' 2>/dev/null); do
        "$ScriptDir/../src/remove-a2a-registration.sh" -i "$id" 2>/dev/null
    done

    # Create A2A registration for broker tests
    local reg_result=$("$ScriptDir/../src/new-a2a-registration.sh" \
        -n "${TestPrefix}_BrokerReg" -C "$certuser_id" -D "Broker test registration" -V 2>/dev/null)
    local reg_id=$(echo "$reg_result" | jq -r '.Id' 2>/dev/null)
    if [ -z "$reg_id" ] || [ "$reg_id" = "null" ]; then
        >&2 echo "Failed to create A2A registration for broker suite"
        return 1
    fi
    SuiteData[RegId]="$reg_id"
    sg_register_cleanup "Delete A2A registration" \
        "$ScriptDir/../src/remove-a2a-registration.sh -i $reg_id"

    return 0
}

suite_execute()
{
    local reg_id="${SuiteData[RegId]}"
    local target_user_id="${SuiteData[TargetUserId]}"
    local cert_file="${SuiteData[CertFile]}"
    local key_file="${SuiteData[KeyFile]}"

    # --- Test: Get broker before configuration ---
    # Before a broker is configured, the GET returns a broker object with
    # a null ApiKey, or an error. Either way, no valid ApiKey yet.
    local get_before=$("$ScriptDir/../src/get-a2a-access-request-broker.sh" -i "$reg_id" 2>/dev/null)
    local get_before_apikey=$(echo "$get_before" | jq -r '.ApiKey // empty' 2>/dev/null)
    sg_assert_equal "No broker ApiKey before config" "$get_before_apikey" ""

    # --- Test: Set access request broker with a user ---
    local set_body="{\"Users\": [{\"UserId\": $target_user_id}]}"
    local set_result=$("$ScriptDir/../src/set-a2a-access-request-broker.sh" \
        -i "$reg_id" -b "$set_body" 2>/dev/null)
    sg_assert_not_null "Set broker returns data" "$set_result"

    # Verify the broker response has an ApiKey
    local broker_apikey=$(echo "$set_result" | jq -r '.ApiKey' 2>/dev/null)
    sg_assert_not_null "Set broker returns ApiKey" "$broker_apikey"
    sg_assert "Broker ApiKey is not null" test "$broker_apikey" != "null"

    # Verify the broker has the user we configured
    local broker_users=$(echo "$set_result" | jq '.Users | length' 2>/dev/null)
    sg_assert_equal "Broker has 1 user" "$broker_users" "1"

    local broker_user_id=$(echo "$set_result" | jq -r '.Users[0].UserId' 2>/dev/null)
    sg_assert_equal "Broker user ID matches target" "$broker_user_id" "$target_user_id"

    # --- Test: Get broker after configuration ---
    local get_after=$("$ScriptDir/../src/get-a2a-access-request-broker.sh" -i "$reg_id" 2>/dev/null)
    sg_assert_not_null "Get broker after config returns data" "$get_after"

    local get_apikey=$(echo "$get_after" | jq -r '.ApiKey' 2>/dev/null)
    sg_assert_equal "Get broker ApiKey matches set" "$get_apikey" "$broker_apikey"

    local get_users=$(echo "$get_after" | jq '.Users | length' 2>/dev/null)
    sg_assert_equal "Get broker user count matches" "$get_users" "1"

    # --- Test: Update broker with IP restrictions ---
    local update_body="{\"Users\": [{\"UserId\": $target_user_id}], \"IpRestrictions\": [\"10.0.0.99\"]}"
    local update_result=$("$ScriptDir/../src/set-a2a-access-request-broker.sh" \
        -i "$reg_id" -b "$update_body" 2>/dev/null)
    sg_assert_not_null "Update broker with IP restrictions returns data" "$update_result"

    local ip_count=$(echo "$update_result" | jq '.IpRestrictions | length' 2>/dev/null)
    sg_assert_equal "Updated broker has 1 IP restriction" "$ip_count" "1"

    local ip_val=$(echo "$update_result" | jq -r '.IpRestrictions[0]' 2>/dev/null)
    sg_assert_equal "IP restriction value matches" "$ip_val" "10.0.0.99"

    # Readback after update
    local readback=$("$ScriptDir/../src/get-a2a-access-request-broker.sh" -i "$reg_id" 2>/dev/null)
    local rb_ip=$(echo "$readback" | jq -r '.IpRestrictions[0]' 2>/dev/null)
    sg_assert_equal "Readback confirms IP restriction" "$rb_ip" "10.0.0.99"

    # --- Test: Clear access request broker ---
    "$ScriptDir/../src/clear-a2a-access-request-broker.sh" -i "$reg_id" 2>/dev/null
    local clear_exit=$?
    sg_assert_equal "Clear broker exits successfully" "$clear_exit" "0"

    # --- Test: Get broker after clear (should indicate not configured) ---
    local get_cleared=$("$ScriptDir/../src/get-a2a-access-request-broker.sh" -i "$reg_id" 2>/dev/null)
    # After clearing, the API should return an error (no broker) or empty broker
    # Check that the previous broker's ApiKey is no longer present
    local cleared_apikey=$(echo "$get_cleared" | jq -r '.ApiKey' 2>/dev/null)
    # If cleared properly, the ApiKey should differ from the set one (either null/empty/error or new)
    sg_assert "Cleared broker ApiKey differs from original" test "$cleared_apikey" != "$broker_apikey"

    # --- Test: Set broker again to verify re-creation works ---
    local reset_body="{\"Users\": [{\"UserId\": $target_user_id}]}"
    local reset_result=$("$ScriptDir/../src/set-a2a-access-request-broker.sh" \
        -i "$reg_id" -b "$reset_body" 2>/dev/null)
    sg_assert_not_null "Re-set broker returns data" "$reset_result"

    local reset_apikey=$(echo "$reset_result" | jq -r '.ApiKey' 2>/dev/null)
    sg_assert_not_null "Re-set broker returns new ApiKey" "$reset_apikey"
    sg_assert "Re-set broker ApiKey is not null" test "$reset_apikey" != "null"

    # New ApiKey should be different from original (deleted and re-created)
    sg_assert "New ApiKey differs from original" test "$reset_apikey" != "$broker_apikey"

    # --- Test: new-a2a-access-request.sh with invalid body (no ForUser) ---
    # This tests that the script runs and the API returns an error for incomplete body
    local bad_request=$(echo "" | "$ScriptDir/../src/new-a2a-access-request.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" \
        -A "$reset_apikey" -b '{"AccessRequestType": "Password"}' -p 2>/dev/null)
    local bad_code=$(echo "$bad_request" | jq -r '.Code' 2>/dev/null)
    # Should get an API error (not a crash), meaning the script ran correctly
    sg_assert_not_null "Invalid broker request returns API response" "$bad_request"
    sg_assert "Invalid request returns error code" test "$bad_code" != "null"

    # Final cleanup: clear broker before suite cleanup deletes the registration
    "$ScriptDir/../src/clear-a2a-access-request-broker.sh" -i "$reg_id" 2>/dev/null
}

suite_cleanup()
{
    local admin_id="${SuiteData[AdminId]}"
    local cert_dir="${SuiteData[CertDir]}"

    sg_disconnect

    # Reconnect as original user to delete the admin
    echo "$TestPassword" | "$ScriptDir/../src/connect-safeguard.sh" \
        -a "$TestAppliance" -i local -u "$TestUser" -v "$TestVersion" -p 2>/dev/null

    if [ -n "$admin_id" ] && [ "$admin_id" != "null" ]; then
        "$ScriptDir/../src/remove-user.sh" -i "$admin_id" 2>/dev/null
    fi

    # Clean up cert dir
    if [ -n "$cert_dir" ] && [ -d "$cert_dir" ]; then
        rm -rf "$cert_dir"
    fi

    sg_disconnect
}
