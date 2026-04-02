#!/bin/bash
# Suite: Asset Accounts
# Tests new-asset-account.sh, remove-asset-account.sh, and set-account-password.sh
# with CRUD validation and readback.
# Requires AssetAdmin role -- creates a RunAdmin user for this purpose.

suite_name()
{
    echo "Asset Accounts"
}

suite_setup()
{
    sg_connect

    # Create a full-admin user since built-in Admin lacks AssetAdmin
    local admin_result=$("$ScriptDir/../src/new-user.sh" \
        -n "${TestPrefix}_AcctAdmin" \
        -R "GlobalAdmin,AssetAdmin,PolicyAdmin,UserAdmin,ApplianceAdmin,Auditor,OperationsAdmin" \
        2>/dev/null)
    local admin_id=$(echo "$admin_result" | jq -r '.Id' 2>/dev/null)
    if [ -z "$admin_id" ] || [ "$admin_id" = "null" ]; then
        >&2 echo "Failed to create admin user for Asset Accounts suite"
        return 1
    fi
    SuiteData[AdminId]="$admin_id"

    sg_invoke -s core -m PUT -U "Users/$admin_id/Password" -b '"AcctTest1!"' >/dev/null
    sg_disconnect
    echo "AcctTest1!" | "$ScriptDir/../src/connect-safeguard.sh" \
        -a "$TestAppliance" -i local -u "${TestPrefix}_AcctAdmin" -v "$TestVersion" -p 2>/dev/null

    # Pre-cleanup stale objects (accounts before assets due to dependency)
    local stale_accts=$(sg_invoke -s core -m GET -U "AssetAccounts?filter=Name%20contains%20'${TestPrefix}_'")
    for id in $(echo "$stale_accts" | jq -r '.[].Id' 2>/dev/null); do
        "$ScriptDir/../src/remove-asset-account.sh" -i "$id" 2>/dev/null
    done
    local stale_assets=$(sg_invoke -s core -m GET -U "Assets?filter=Name%20contains%20'${TestPrefix}_'")
    for id in $(echo "$stale_assets" | jq -r '.[].Id' 2>/dev/null); do
        "$ScriptDir/../src/remove-asset.sh" -i "$id" 2>/dev/null
    done

    # Create parent asset for account tests
    local asset_result=$("$ScriptDir/../src/new-asset.sh" \
        -n "${TestPrefix}_AcctAsset" -N "10.0.1.100" -P 521 2>/dev/null)
    local asset_id=$(echo "$asset_result" | jq -r '.Id' 2>/dev/null)
    if [ -z "$asset_id" ] || [ "$asset_id" = "null" ]; then
        >&2 echo "Failed to create parent asset for Asset Accounts suite"
        return 1
    fi
    SuiteData[AssetId]="$asset_id"
    sg_register_cleanup "Delete parent asset ${TestPrefix}_AcctAsset" \
        "$ScriptDir/../src/remove-asset.sh -i $asset_id"

    return 0
}

suite_execute()
{
    local asset_id="${SuiteData[AssetId]}"
    local TestAcctName="${TestPrefix}_Account1"

    # --- Test: Create account ---
    local create_result=$("$ScriptDir/../src/new-asset-account.sh" \
        -s "$asset_id" -n "$TestAcctName" -D "Test account" 2>/dev/null)
    sg_assert_not_null "Create account returns data" "$create_result"

    local acct_id=$(echo "$create_result" | jq -r '.Id' 2>/dev/null)
    sg_assert_not_null "Created account has an Id" "$acct_id"
    SuiteData[AccountId]="$acct_id"

    sg_register_cleanup "Delete test account $TestAcctName" \
        "$ScriptDir/../src/remove-asset-account.sh -i $acct_id"

    local created_name=$(echo "$create_result" | jq -r '.Name' 2>/dev/null)
    sg_assert_equal "Created account Name matches" "$created_name" "$TestAcctName"

    local created_asset_id=$(echo "$create_result" | jq -r '.Asset.Id' 2>/dev/null)
    sg_assert_equal "Created account belongs to correct asset" "$created_asset_id" "$asset_id"

    # --- Test: Readback by ID ---
    local readback=$(sg_invoke -s core -m GET -U "AssetAccounts/$acct_id")
    sg_assert_not_null "Readback account by ID returns data" "$readback"

    local rb_name=$(echo "$readback" | jq -r '.Name' 2>/dev/null)
    sg_assert_equal "Readback Name matches" "$rb_name" "$TestAcctName"

    local rb_desc=$(echo "$readback" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Readback Description matches" "$rb_desc" "Test account"

    local rb_has_pw=$(echo "$readback" | jq -r '.HasPassword' 2>/dev/null)
    sg_assert_equal "Account has no password initially" "$rb_has_pw" "false"

    local rb_platform=$(echo "$readback" | jq -r '.Platform.PlatformFamily' 2>/dev/null)
    sg_assert_equal "Account inherits Linux platform" "$rb_platform" "Linux"

    # --- Test: Set password ---
    sg_invoke -s core -m PUT -U "AssetAccounts/$acct_id/Password" -b '"TestPass99!"' >/dev/null
    local pw_readback=$(sg_invoke -s core -m GET -U "AssetAccounts/$acct_id")
    local has_pw=$(echo "$pw_readback" | jq -r '.HasPassword' 2>/dev/null)
    sg_assert_equal "Account has password after set" "$has_pw" "true"

    # --- Test: Edit account via PUT ---
    local updated=$(echo "$readback" | jq '.Description = "Updated account"')
    local edit_result=$(sg_invoke -s core -m PUT -U "AssetAccounts/$acct_id" -b "$updated")
    local edit_desc=$(echo "$edit_result" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Edit updates Description" "$edit_desc" "Updated account"

    # Readback after edit
    local edit_readback=$(sg_invoke -s core -m GET -U "AssetAccounts/$acct_id")
    local edit_rb_desc=$(echo "$edit_readback" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Readback confirms edited Description" "$edit_rb_desc" "Updated account"

    local edit_rb_name=$(echo "$edit_readback" | jq -r '.Name' 2>/dev/null)
    sg_assert_equal "Name unchanged after edit" "$edit_rb_name" "$TestAcctName"

    local edit_rb_pw=$(echo "$edit_readback" | jq -r '.HasPassword' 2>/dev/null)
    sg_assert_equal "Password still set after edit" "$edit_rb_pw" "true"

    # --- Test: Create second account and verify filter ---
    local TestAcct2="${TestPrefix}_Account2"
    local acct2_result=$("$ScriptDir/../src/new-asset-account.sh" \
        -s "$asset_id" -n "$TestAcct2" 2>/dev/null)
    local acct2_id=$(echo "$acct2_result" | jq -r '.Id' 2>/dev/null)
    sg_assert_not_null "Create second account returns Id" "$acct2_id"
    SuiteData[Account2Id]="$acct2_id"

    sg_register_cleanup "Delete test account $TestAcct2" \
        "$ScriptDir/../src/remove-asset-account.sh -i $acct2_id"

    local filter_result=$(sg_invoke -s core -m GET -U "AssetAccounts?filter=Name%20eq%20'${TestAcctName}'")
    local filter_count=$(echo "$filter_result" | jq 'length' 2>/dev/null)
    sg_assert_equal "Filter by Name finds exactly 1 account" "$filter_count" "1"

    # --- Test: Delete account and verify gone ---
    "$ScriptDir/../src/remove-asset-account.sh" -i "$acct2_id" 2>/dev/null
    local gone_result=$(sg_invoke -s core -m GET -U "AssetAccounts?filter=Name%20eq%20'${TestAcct2}'")
    local gone_count=$(echo "$gone_result" | jq 'length' 2>/dev/null)
    sg_assert_equal "Deleted account no longer found" "$gone_count" "0"

    SuiteData[Account2Id]=""
}

suite_cleanup()
{
    # Reconnect as original user to delete the suite admin
    sg_disconnect
    sg_connect
    local admin_id="${SuiteData[AdminId]}"
    if [ -n "$admin_id" ]; then
        "$ScriptDir/../src/remove-user.sh" -i "$admin_id" 2>/dev/null
    fi
    sg_disconnect
}
