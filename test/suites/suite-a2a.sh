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
        -n "${TestPrefix}_A2AReg" -C "$certuser_id" -D "Test A2A registration" -V 2>/dev/null)
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

    # --- Test: get-a2a-registration.sh get by ID ---
    local get_single=$("$ScriptDir/../src/get-a2a-registration.sh" -i "$reg_id" 2>/dev/null)
    sg_assert_not_null "get-a2a-registration by ID returns data" "$get_single"

    local get_single_name=$(echo "$get_single" | jq -r '.AppName' 2>/dev/null)
    sg_assert_equal "get-a2a-registration by ID AppName matches" "$get_single_name" "${TestPrefix}_A2AReg"

    local get_single_certuser=$(echo "$get_single" | jq -r '.CertificateUserId' 2>/dev/null)
    sg_assert_equal "get-a2a-registration by ID CertificateUserId matches" "$get_single_certuser" "$certuser_id"

    # --- Test: get-a2a-registration.sh list all ---
    local get_all=$("$ScriptDir/../src/get-a2a-registration.sh" 2>/dev/null)
    sg_assert_not_null "get-a2a-registration list all returns data" "$get_all"

    local get_all_count=$(echo "$get_all" | jq 'length' 2>/dev/null)
    sg_assert "get-a2a-registration list returns at least 1" test "$get_all_count" -ge 1

    # --- Test: get-a2a-registration.sh with filter ---
    local get_filtered=$("$ScriptDir/../src/get-a2a-registration.sh" \
        -q "AppName eq '${TestPrefix}_A2AReg'" 2>/dev/null)
    sg_assert_not_null "get-a2a-registration filter returns data" "$get_filtered"

    local get_filt_count=$(echo "$get_filtered" | jq 'length' 2>/dev/null)
    sg_assert_equal "get-a2a-registration filter returns 1 result" "$get_filt_count" "1"

    local get_filt_name=$(echo "$get_filtered" | jq -r '.[0].AppName' 2>/dev/null)
    sg_assert_equal "get-a2a-registration filtered AppName matches" "$get_filt_name" "${TestPrefix}_A2AReg"

    # --- Test: get-a2a-registration.sh with non-matching filter ---
    local get_nomatch=$("$ScriptDir/../src/get-a2a-registration.sh" \
        -q "AppName eq 'NonExistent_ZZZ_999'" 2>/dev/null)
    local get_nomatch_count=$(echo "$get_nomatch" | jq 'length' 2>/dev/null)
    sg_assert_equal "get-a2a-registration non-matching filter returns empty" "$get_nomatch_count" "0"

    # --- Test: get-a2a-registration.sh with fields ---
    local get_fields=$("$ScriptDir/../src/get-a2a-registration.sh" \
        -f "Id,AppName" 2>/dev/null)
    sg_assert_not_null "get-a2a-registration fields returns data" "$get_fields"

    local get_fields_name=$(echo "$get_fields" | jq -r '.[0].AppName' 2>/dev/null)
    sg_assert_not_null "get-a2a-registration fields includes AppName" "$get_fields_name"

    # --- Test: edit-a2a-registration.sh with individual flags ---
    local edit_result=$("$ScriptDir/../src/edit-a2a-registration.sh" \
        -i "$reg_id" -n "${TestPrefix}_A2ARegEdited" -D "Edited description" 2>/dev/null)
    sg_assert_not_null "edit-a2a-registration returns data" "$edit_result"

    local edit_name=$(echo "$edit_result" | jq -r '.AppName' 2>/dev/null)
    sg_assert_equal "edit-a2a-registration AppName updated" "$edit_name" "${TestPrefix}_A2ARegEdited"

    local edit_desc=$(echo "$edit_result" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "edit-a2a-registration Description updated" "$edit_desc" "Edited description"

    # Readback after edit to confirm persistence
    local edit_rb=$("$ScriptDir/../src/get-a2a-registration.sh" -i "$reg_id" 2>/dev/null)
    local edit_rb_name=$(echo "$edit_rb" | jq -r '.AppName' 2>/dev/null)
    sg_assert_equal "edit-a2a-registration readback AppName matches" "$edit_rb_name" "${TestPrefix}_A2ARegEdited"

    local edit_rb_desc=$(echo "$edit_rb" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "edit-a2a-registration readback Description matches" "$edit_rb_desc" "Edited description"

    # Verify CertificateUserId was not changed by the edit
    local edit_rb_certuser=$(echo "$edit_rb" | jq -r '.CertificateUserId' 2>/dev/null)
    sg_assert_equal "edit-a2a-registration CertificateUserId unchanged" "$edit_rb_certuser" "$certuser_id"

    # --- Test: edit-a2a-registration.sh with -V (visible) flag ---
    local edit_vis=$("$ScriptDir/../src/edit-a2a-registration.sh" \
        -i "$reg_id" -V 2>/dev/null)
    local edit_vis_val=$(echo "$edit_vis" | jq -r '.VisibleToCertificateUsers' 2>/dev/null)
    sg_assert_equal "edit-a2a-registration -V sets visible to true" "$edit_vis_val" "true"

    # --- Test: edit-a2a-registration.sh with -W (not visible) flag ---
    local edit_invis=$("$ScriptDir/../src/edit-a2a-registration.sh" \
        -i "$reg_id" -W 2>/dev/null)
    local edit_invis_val=$(echo "$edit_invis" | jq -r '.VisibleToCertificateUsers' 2>/dev/null)
    sg_assert_equal "edit-a2a-registration -W sets visible to false" "$edit_invis_val" "false"

    # --- Test: edit-a2a-registration.sh with JSON body ---
    local edit_body_json=$(echo "$edit_rb" | jq '.AppName = "'"${TestPrefix}_A2AReg"'" | .Description = "Test A2A registration"')
    local edit_body_result=$("$ScriptDir/../src/edit-a2a-registration.sh" \
        -i "$reg_id" -b "$edit_body_json" 2>/dev/null)
    sg_assert_not_null "edit-a2a-registration with JSON body returns data" "$edit_body_result"

    local edit_body_name=$(echo "$edit_body_result" | jq -r '.AppName' 2>/dev/null)
    sg_assert_equal "edit-a2a-registration JSON body restored AppName" "$edit_body_name" "${TestPrefix}_A2AReg"

    local edit_body_desc=$(echo "$edit_body_result" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "edit-a2a-registration JSON body restored Description" "$edit_body_desc" "Test A2A registration"

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

    # --- Test: get-a2a-credential-retrieval.sh list all ---
    local gcr_all=$("$ScriptDir/../src/get-a2a-credential-retrieval.sh" \
        -r "$reg_id" 2>/dev/null)
    sg_assert_not_null "get-a2a-credential-retrieval list all returns data" "$gcr_all"

    local gcr_all_count=$(echo "$gcr_all" | jq 'length' 2>/dev/null)
    sg_assert_equal "get-a2a-credential-retrieval list returns 1 account" "$gcr_all_count" "1"

    local gcr_all_acct=$(echo "$gcr_all" | jq -r '.[0].AccountId' 2>/dev/null)
    sg_assert_equal "get-a2a-credential-retrieval list AccountId matches" "$gcr_all_acct" "$acct_id"

    # --- Test: get-a2a-credential-retrieval.sh get single by account ID ---
    local gcr_single=$("$ScriptDir/../src/get-a2a-credential-retrieval.sh" \
        -r "$reg_id" -c "$acct_id" 2>/dev/null)
    sg_assert_not_null "get-a2a-credential-retrieval single returns data" "$gcr_single"

    local gcr_single_acct=$(echo "$gcr_single" | jq -r '.AccountId' 2>/dev/null)
    sg_assert_equal "get-a2a-credential-retrieval single AccountId matches" "$gcr_single_acct" "$acct_id"

    local gcr_single_apikey=$(echo "$gcr_single" | jq -r '.ApiKey' 2>/dev/null)
    sg_assert_not_null "get-a2a-credential-retrieval single has ApiKey" "$gcr_single_apikey"

    # --- Test: get-a2a-credential-retrieval.sh with filter ---
    local gcr_filter=$("$ScriptDir/../src/get-a2a-credential-retrieval.sh" \
        -r "$reg_id" -q "AccountName eq '${TestPrefix}_A2AAccount'" 2>/dev/null)
    sg_assert_not_null "get-a2a-credential-retrieval filter returns data" "$gcr_filter"

    local gcr_filter_count=$(echo "$gcr_filter" | jq 'length' 2>/dev/null)
    sg_assert_equal "get-a2a-credential-retrieval filter returns 1 result" "$gcr_filter_count" "1"

    # --- Test: get-a2a-credential-retrieval.sh with non-matching filter ---
    local gcr_nomatch=$("$ScriptDir/../src/get-a2a-credential-retrieval.sh" \
        -r "$reg_id" -q "AccountName eq 'NonExistent_ZZZ_999'" 2>/dev/null)
    local gcr_nomatch_count=$(echo "$gcr_nomatch" | jq 'length' 2>/dev/null)
    sg_assert_equal "get-a2a-credential-retrieval non-matching filter returns empty" "$gcr_nomatch_count" "0"

    # --- Test: get-a2a-credential-retrieval.sh with fields ---
    local gcr_fields=$("$ScriptDir/../src/get-a2a-credential-retrieval.sh" \
        -r "$reg_id" -f "AccountName,AccountId" 2>/dev/null)
    sg_assert_not_null "get-a2a-credential-retrieval fields returns data" "$gcr_fields"

    local gcr_fields_name=$(echo "$gcr_fields" | jq -r '.[0].AccountName' 2>/dev/null)
    sg_assert_not_null "get-a2a-credential-retrieval fields includes AccountName" "$gcr_fields_name"

    # --- Test: get-a2a-credential-retrieval.sh with orderby ---
    local gcr_order=$("$ScriptDir/../src/get-a2a-credential-retrieval.sh" \
        -r "$reg_id" -o "AccountName" 2>/dev/null)
    sg_assert_not_null "get-a2a-credential-retrieval orderby returns data" "$gcr_order"

    # --- Test: get-a2a-apikey.sh ---
    local get_apikey=$("$ScriptDir/../src/get-a2a-apikey.sh" \
        -r "$reg_id" -c "$acct_id" 2>/dev/null)
    sg_assert_not_null "get-a2a-apikey returns data" "$get_apikey"

    # The API returns the key as a bare JSON string (quoted)
    local get_apikey_val=$(echo "$get_apikey" | jq -r '.' 2>/dev/null)
    sg_assert_equal "get-a2a-apikey matches original key" "$get_apikey_val" "$api_key"

    # --- Test: reset-a2a-apikey.sh ---
    local reset_apikey=$("$ScriptDir/../src/reset-a2a-apikey.sh" \
        -r "$reg_id" -c "$acct_id" 2>/dev/null)
    sg_assert_not_null "reset-a2a-apikey returns data" "$reset_apikey"

    local new_apikey=$(echo "$reset_apikey" | jq -r '.' 2>/dev/null)
    sg_assert_not_null "reset-a2a-apikey returns new key" "$new_apikey"

    # Verify the new key is different from the original
    if [ "$new_apikey" != "$api_key" ]; then
        sg_assert "reset-a2a-apikey generated a different key" true
    else
        sg_assert "reset-a2a-apikey generated a different key" false
    fi

    # Verify get-a2a-apikey now returns the new key
    local verify_apikey=$("$ScriptDir/../src/get-a2a-apikey.sh" \
        -r "$reg_id" -c "$acct_id" 2>/dev/null)
    local verify_apikey_val=$(echo "$verify_apikey" | jq -r '.' 2>/dev/null)
    sg_assert_equal "get-a2a-apikey returns new key after reset" "$verify_apikey_val" "$new_apikey"

    # Update stored API key for subsequent tests
    api_key="$new_apikey"
    SuiteData[ApiKey]="$api_key"

    # --- Test: Retrieve password via A2A service ---
    local a2a_pw=$(echo "" | "$ScriptDir/../src/get-a2a-password.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" \
        -A "$api_key" -r 2>/dev/null)
    sg_assert_not_null "A2A password retrieval returns data" "$a2a_pw"
    sg_assert_equal "Retrieved password matches known password" "$a2a_pw" "$known_pw"

    # --- Test: set-a2a-password.sh (bidirectional) ---
    # Enable bidirectional on the registration
    "$ScriptDir/../src/edit-a2a-registration.sh" -i "$reg_id" -b \
        "$(sg_invoke -s core -m GET -U "A2ARegistrations/$reg_id" | jq '.BidirectionalEnabled = true')" \
        >/dev/null 2>/dev/null

    # Set a new password via A2A
    local new_pw="A2ANewPassw0rd!"
    local set_result=$(printf '%s\n%s\n' "" "\"$new_pw\"" | "$ScriptDir/../src/set-a2a-password.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" \
        -A "$api_key" 2>/dev/null)
    # set-a2a-password returns empty on success
    sg_assert_equal "set-a2a-password returns empty on success" "$set_result" ""

    # Verify the new password by retrieving it
    local verify_pw=$(echo "" | "$ScriptDir/../src/get-a2a-password.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" \
        -A "$api_key" -r 2>/dev/null)
    sg_assert_equal "Password was changed by set-a2a-password" "$verify_pw" "$new_pw"

    # Restore original password
    printf '%s\n%s\n' "" "\"$known_pw\"" | "$ScriptDir/../src/set-a2a-password.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" \
        -A "$api_key" 2>/dev/null

    # Verify restore
    local restore_pw=$(echo "" | "$ScriptDir/../src/get-a2a-password.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" \
        -A "$api_key" -r 2>/dev/null)
    sg_assert_equal "Password restored after set-a2a-password" "$restore_pw" "$known_pw"

    # --- Test: set-a2a-privatekey.sh (bidirectional) ---
    # Generate a test SSH key to set
    local test_ssh_key="$cert_dir/test_ssh_key"
    ssh-keygen -t rsa -b 2048 -f "$test_ssh_key" -N "" -q 2>/dev/null

    if [ -f "$test_ssh_key" ]; then
        # Set the SSH key via A2A
        local set_key_result=$(echo "" | "$ScriptDir/../src/set-a2a-privatekey.sh" \
            -a "$TestAppliance" -c "$cert_file" -k "$key_file" \
            -A "$api_key" -K "$test_ssh_key" -p 2>/dev/null)
        # set-a2a-privatekey returns empty on success
        sg_assert_equal "set-a2a-privatekey returns empty on success" "$set_key_result" ""

        # Verify by retrieving the key
        local get_key_result=$(echo "" | "$ScriptDir/../src/get-a2a-privatekey.sh" \
            -a "$TestAppliance" -c "$cert_file" -k "$key_file" \
            -A "$api_key" -r -p 2>/dev/null)
        sg_assert_not_null "get-a2a-privatekey returns data after set" "$get_key_result"

        # Set with explicit format
        local set_key_fmt=$(echo "" | "$ScriptDir/../src/set-a2a-privatekey.sh" \
            -a "$TestAppliance" -c "$cert_file" -k "$key_file" \
            -A "$api_key" -K "$test_ssh_key" -F OpenSsh -p 2>/dev/null)
        sg_assert_equal "set-a2a-privatekey with format returns empty on success" "$set_key_fmt" ""
    else
        sg_skip "set-a2a-privatekey tests" "ssh-keygen not available"
    fi

    # --- Test: get-a2a-retrievable-account.sh list all (no filter) ---
    local all_result=$(echo "" | "$ScriptDir/../src/get-a2a-retrievable-account.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" -p 2>/dev/null)
    sg_assert_not_null "get-a2a-retrievable-account list all returns data" "$all_result"

    local all_count=$(echo "$all_result" | jq 'length' 2>/dev/null)
    sg_assert_equal "List all returns 1 account" "$all_count" "1"

    local all_acct_name=$(echo "$all_result" | jq -r '.[0].AccountName' 2>/dev/null)
    sg_assert_not_null "List all includes AccountName" "$all_acct_name"

    # --- Test: get-a2a-retrievable-account.sh with matching QueryFilter ---
    local filter_result=$(echo "" | "$ScriptDir/../src/get-a2a-retrievable-account.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" -p \
        -q "AccountName eq '${TestPrefix}_A2AAccount'" 2>/dev/null)
    sg_assert_not_null "Matching QueryFilter returns data" "$filter_result"

    local filter_count=$(echo "$filter_result" | jq 'length' 2>/dev/null)
    sg_assert_equal "Matching QueryFilter returns 1 result" "$filter_count" "1"

    local filter_name=$(echo "$filter_result" | jq -r '.[0].AccountName' 2>/dev/null)
    sg_assert_equal "Filtered AccountName matches" "$filter_name" "${TestPrefix}_A2AAccount"

    # --- Test: get-a2a-retrievable-account.sh with non-matching QueryFilter ---
    local nomatch_result=$(echo "" | "$ScriptDir/../src/get-a2a-retrievable-account.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" -p \
        -q "AccountName eq 'NonExistent_ZZZ_999'" 2>/dev/null)
    local nomatch_count=$(echo "$nomatch_result" | jq 'length' 2>/dev/null)
    sg_assert_equal "Non-matching QueryFilter returns empty" "$nomatch_count" "0"

    # --- Test: get-a2a-retrievable-account.sh with Fields ---
    local fields_result=$(echo "" | "$ScriptDir/../src/get-a2a-retrievable-account.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" -p \
        -f "AccountName,AccountId" 2>/dev/null)
    sg_assert_not_null "Fields filter returns data" "$fields_result"

    local fields_acct=$(echo "$fields_result" | jq -r '.[0].AccountName' 2>/dev/null)
    sg_assert_not_null "Fields result includes AccountName" "$fields_acct"

    local fields_id=$(echo "$fields_result" | jq -r '.[0].AccountId' 2>/dev/null)
    sg_assert_not_null "Fields result includes AccountId" "$fields_id"

    # --- Test: get-a2a-retrievable-account.sh with OrderBy ---
    local orderby_result=$(echo "" | "$ScriptDir/../src/get-a2a-retrievable-account.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" -p \
        -o "AccountName" 2>/dev/null)
    sg_assert_not_null "OrderBy returns data" "$orderby_result"

    # --- Test: get-a2a-retrievable-account.sh with QueryFilter and Fields combined ---
    local combined_result=$(echo "" | "$ScriptDir/../src/get-a2a-retrievable-account.sh" \
        -a "$TestAppliance" -c "$cert_file" -k "$key_file" -p \
        -q "AccountName eq '${TestPrefix}_A2AAccount'" -f "AccountName" 2>/dev/null)
    sg_assert_not_null "QueryFilter with Fields combined returns data" "$combined_result"

    local combined_name=$(echo "$combined_result" | jq -r '.[0].AccountName' 2>/dev/null)
    sg_assert_equal "Combined filter+fields AccountName matches" "$combined_name" "${TestPrefix}_A2AAccount"

    # --- Test: A2A service status/enable/disable ---
    local svc_status=$("$ScriptDir/../src/get-a2a-service-status.sh" 2>/dev/null)
    sg_assert_not_null "get-a2a-service-status returns data" "$svc_status"

    # Save original state to restore later
    local orig_a2a_enabled=$(echo "$svc_status" | jq -r '.IsEnabled // .Enabled // empty' 2>/dev/null)
    if [ -z "$orig_a2a_enabled" ]; then
        # Status might be a simple string; check raw output
        orig_a2a_enabled="$svc_status"
    fi

    # Enable the service
    "$ScriptDir/../src/enable-a2a-service.sh" 2>/dev/null
    local after_enable=$("$ScriptDir/../src/get-a2a-service-status.sh" 2>/dev/null)
    sg_assert_not_null "Status after enable returns data" "$after_enable"

    # Disable the service
    "$ScriptDir/../src/disable-a2a-service.sh" 2>/dev/null
    local after_disable=$("$ScriptDir/../src/get-a2a-service-status.sh" 2>/dev/null)
    sg_assert_not_null "Status after disable returns data" "$after_disable"

    # Verify status changed between enable and disable
    sg_assert "Enable and disable produce different status" \
        test "$after_enable" != "$after_disable"

    # Restore original state
    if echo "$orig_a2a_enabled" | grep -qi "true\|enabled"; then
        "$ScriptDir/../src/enable-a2a-service.sh" 2>/dev/null
    else
        "$ScriptDir/../src/disable-a2a-service.sh" 2>/dev/null
    fi

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
