#!/bin/bash
# Suite: A2A (Application-to-Application)
# Tests the full A2A workflow: certificate generation, trusted cert install,
# certificate user creation, A2A registration, credential retrieval, and
# end-to-end password retrieval via the A2A service.
#
# Requires: PolicyAdmin, AssetAdmin, ApplianceAdmin, UserAdmin roles.
# Creates a RunAdmin user for this purpose.

suite_name()
{
    echo "A2A"
}

suite_setup()
{
    sg_connect

    # Create full-admin user for this suite
    local admin_result=$("$ScriptDir/../src/new-user.sh" \
        -n "${TestPrefix}_A2AAdmin" \
        -R "GlobalAdmin,AssetAdmin,PolicyAdmin,UserAdmin,ApplianceAdmin,Auditor,OperationsAdmin" \
        2>/dev/null)
    local admin_id=$(echo "$admin_result" | jq -r '.Id' 2>/dev/null)
    if [ -z "$admin_id" ] || [ "$admin_id" = "null" ]; then
        >&2 echo "Failed to create admin user for A2A suite"
        return 1
    fi
    SuiteData[AdminId]="$admin_id"

    sg_invoke -s core -m PUT -U "Users/$admin_id/Password" -b '"A2ATest1!"' >/dev/null
    sg_disconnect
    echo "A2ATest1!" | "$ScriptDir/../src/connect-safeguard.sh" \
        -a "$TestAppliance" -i local -u "${TestPrefix}_A2AAdmin" -v "$TestVersion" -p 2>/dev/null

    # Generate self-signed certificate for A2A
    local cert_dir=$(mktemp -d)
    SuiteData[CertDir]="$cert_dir"
    openssl req -x509 -newkey rsa:2048 -keyout "$cert_dir/key.pem" \
        -out "$cert_dir/cert.pem" -days 1 -nodes \
        -subj "/CN=${TestPrefix}_A2ACert" 2>/dev/null
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
        -n "${TestPrefix}_A2ACertUser" -s "$thumbprint" 2>/dev/null)
    local certuser_id=$(echo "$certuser_result" | jq -r '.Id' 2>/dev/null)
    if [ -z "$certuser_id" ] || [ "$certuser_id" = "null" ]; then
        >&2 echo "Failed to create certificate user"
        return 1
    fi
    SuiteData[CertUserId]="$certuser_id"
    sg_register_cleanup "Delete certificate user" \
        "$ScriptDir/../src/remove-user.sh -i $certuser_id"

    # Create asset and account for A2A credential retrieval
    local asset_result=$("$ScriptDir/../src/new-asset.sh" \
        -n "${TestPrefix}_A2AAsset" -N "10.0.2.100" -P 521 2>/dev/null)
    local asset_id=$(echo "$asset_result" | jq -r '.Id' 2>/dev/null)
    if [ -z "$asset_id" ] || [ "$asset_id" = "null" ]; then
        >&2 echo "Failed to create asset for A2A suite"
        return 1
    fi
    SuiteData[AssetId]="$asset_id"
    sg_register_cleanup "Delete A2A test asset" \
        "$ScriptDir/../src/remove-asset.sh -i $asset_id"

    local acct_result=$("$ScriptDir/../src/new-asset-account.sh" \
        -s "$asset_id" -n "${TestPrefix}_A2AAccount" 2>/dev/null)
    local acct_id=$(echo "$acct_result" | jq -r '.Id' 2>/dev/null)
    if [ -z "$acct_id" ] || [ "$acct_id" = "null" ]; then
        >&2 echo "Failed to create account for A2A suite"
        return 1
    fi
    SuiteData[AccountId]="$acct_id"
    sg_register_cleanup "Delete A2A test account" \
        "$ScriptDir/../src/remove-asset-account.sh -i $acct_id"

    # Set a known password on the account
    sg_invoke -s core -m PUT -U "AssetAccounts/$acct_id/Password" \
        -b '"A2ATestPassw0rd!"' >/dev/null
    SuiteData[KnownPassword]="A2ATestPassw0rd!"

    # Pre-cleanup stale A2A registrations
    local stale_regs=$(sg_invoke -s core -m GET -U "A2ARegistrations?filter=AppName%20contains%20'${TestPrefix}_'")
    for id in $(echo "$stale_regs" | jq -r '.[].Id' 2>/dev/null); do
        "$ScriptDir/../src/remove-a2a-registration.sh" -i "$id" 2>/dev/null
    done

    return 0
}

suite_execute()
{
    local certuser_id="${SuiteData[CertUserId]}"
    local acct_id="${SuiteData[AccountId]}"
    local cert_file="${SuiteData[CertFile]}"
    local key_file="${SuiteData[KeyFile]}"
    local known_pw="${SuiteData[KnownPassword]}"

    # --- Test: Create A2A registration ---
    local reg_result=$("$ScriptDir/../src/new-a2a-registration.sh" \
        -n "${TestPrefix}_A2AReg" -C "$certuser_id" -D "Test A2A registration" 2>/dev/null)
    sg_assert_not_null "Create A2A registration returns data" "$reg_result"

    local reg_id=$(echo "$reg_result" | jq -r '.Id' 2>/dev/null)
    sg_assert_not_null "Registration has an Id" "$reg_id"
    SuiteData[RegId]="$reg_id"

    sg_register_cleanup "Delete A2A registration" \
        "$ScriptDir/../src/remove-a2a-registration.sh -i $reg_id"

    local reg_name=$(echo "$reg_result" | jq -r '.AppName' 2>/dev/null)
    sg_assert_equal "Registration AppName matches" "$reg_name" "${TestPrefix}_A2AReg"

    local reg_certuser=$(echo "$reg_result" | jq -r '.CertificateUserId' 2>/dev/null)
    sg_assert_equal "Registration CertificateUserId matches" "$reg_certuser" "$certuser_id"

    local reg_desc=$(echo "$reg_result" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Registration Description matches" "$reg_desc" "Test A2A registration"

    # --- Test: Readback registration ---
    local reg_readback=$(sg_invoke -s core -m GET -U "A2ARegistrations/$reg_id")
    sg_assert_not_null "Readback registration returns data" "$reg_readback"

    local rb_name=$(echo "$reg_readback" | jq -r '.AppName' 2>/dev/null)
    sg_assert_equal "Readback AppName matches" "$rb_name" "${TestPrefix}_A2AReg"

    local rb_disabled=$(echo "$reg_readback" | jq -r '.Disabled' 2>/dev/null)
    sg_assert_equal "Registration is not disabled" "$rb_disabled" "false"

    # --- Test: Add credential retrieval ---
    local cred_result=$("$ScriptDir/../src/add-a2a-credential-retrieval.sh" \
        -r "$reg_id" -c "$acct_id" 2>/dev/null)
    sg_assert_not_null "Add credential retrieval returns data" "$cred_result"

    local api_key=$(echo "$cred_result" | jq -r '.ApiKey' 2>/dev/null)
    sg_assert_not_null "Credential retrieval returns ApiKey" "$api_key"
    SuiteData[ApiKey]="$api_key"

    local cred_acct_id=$(echo "$cred_result" | jq -r '.AccountId' 2>/dev/null)
    sg_assert_equal "Credential retrieval AccountId matches" "$cred_acct_id" "$acct_id"

    # --- Test: List retrievable accounts via API ---
    local retrievable=$(sg_invoke -s core -m GET -U "A2ARegistrations/$reg_id/RetrievableAccounts")
    sg_assert_not_null "List retrievable accounts returns data" "$retrievable"

    local retr_count=$(echo "$retrievable" | jq 'length' 2>/dev/null)
    sg_assert_equal "Exactly 1 retrievable account" "$retr_count" "1"

    local retr_acct=$(echo "$retrievable" | jq -r '.[0].AccountId' 2>/dev/null)
    sg_assert_equal "Retrievable AccountId matches" "$retr_acct" "$acct_id"

    # --- Test: Retrieve password via A2A service ---
    local a2a_pw=$(echo "" | "$ScriptDir/../src/get-a2a-password.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" \
        -A "$api_key" -r 2>/dev/null)
    sg_assert_not_null "A2A password retrieval returns data" "$a2a_pw"
    sg_assert_equal "Retrieved password matches known password" "$a2a_pw" "$known_pw"

    # --- Test: Remove credential retrieval and verify ---
    "$ScriptDir/../src/remove-a2a-credential-retrieval.sh" \
        -r "$reg_id" -c "$acct_id" 2>/dev/null
    local after_remove=$(sg_invoke -s core -m GET -U "A2ARegistrations/$reg_id/RetrievableAccounts")
    local after_count=$(echo "$after_remove" | jq 'length' 2>/dev/null)
    sg_assert_equal "No retrievable accounts after removal" "$after_count" "0"

    # --- Test: Delete A2A registration and verify ---
    "$ScriptDir/../src/remove-a2a-registration.sh" -i "$reg_id" 2>/dev/null
    SuiteData[RegId]=""

    local gone_result=$(sg_invoke -s core -m GET -U "A2ARegistrations?filter=AppName%20eq%20'${TestPrefix}_A2AReg'")
    local gone_count=$(echo "$gone_result" | jq 'length' 2>/dev/null)
    sg_assert_equal "Deleted registration no longer found" "$gone_count" "0"
}

suite_cleanup()
{
    # Clean up temp cert files
    local cert_dir="${SuiteData[CertDir]}"
    if [ -n "$cert_dir" ] && [ -d "$cert_dir" ]; then
        rm -rf "$cert_dir"
    fi

    # Reconnect as original user to delete the suite admin
    sg_disconnect
    sg_connect
    local admin_id="${SuiteData[AdminId]}"
    if [ -n "$admin_id" ]; then
        "$ScriptDir/../src/remove-user.sh" -i "$admin_id" 2>/dev/null
    fi
    sg_disconnect
}
