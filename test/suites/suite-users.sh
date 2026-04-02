#!/bin/bash
# Suite: Users
# Tests new-user.sh and remove-user.sh with CRUD validation and readback.

suite_name()
{
    echo "Users"
}

suite_setup()
{
    sg_connect

    # Pre-cleanup: remove stale test users from previous failed runs
    local stale=$(sg_invoke -s core -m GET -U "Users?filter=Name%20contains%20'${TestPrefix}_'")
    local stale_ids=$(echo "$stale" | jq -r '.[].Id' 2>/dev/null)
    for id in $stale_ids; do
        "$ScriptDir/../src/remove-user.sh" -i "$id" 2>/dev/null
    done

    return 0
}

suite_execute()
{
    local TestUserName="${TestPrefix}_User1"
    local TestUserName2="${TestPrefix}_User2"

    # --- Test: Create a basic user ---
    local create_result=$("$ScriptDir/../src/new-user.sh" -n "$TestUserName" -d "Test user for suite" 2>/dev/null)
    sg_assert_not_null "Create user returns data" "$create_result"

    local user_id=$(echo "$create_result" | jq -r '.Id' 2>/dev/null)
    sg_assert_not_null "Created user has an Id" "$user_id"
    SuiteData[UserId]="$user_id"

    sg_register_cleanup "Delete test user $TestUserName" \
        "$ScriptDir/../src/remove-user.sh -i $user_id"

    local created_name=$(echo "$create_result" | jq -r '.Name' 2>/dev/null)
    sg_assert_equal "Created user Name matches" "$created_name" "$TestUserName"

    # --- Test: Readback user by ID ---
    local readback=$(sg_invoke -s core -m GET -U "Users/$user_id")
    sg_assert_not_null "Readback user by ID returns data" "$readback"

    local rb_name=$(echo "$readback" | jq -r '.Name' 2>/dev/null)
    sg_assert_equal "Readback Name matches" "$rb_name" "$TestUserName"

    local rb_desc=$(echo "$readback" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Readback Description matches" "$rb_desc" "Test user for suite"

    local rb_provider=$(echo "$readback" | jq -r '.PrimaryAuthenticationProvider.Name' 2>/dev/null)
    sg_assert_equal "User is local provider" "$rb_provider" "Local"

    # --- Test: Create user with admin roles ---
    local roles_result=$("$ScriptDir/../src/new-user.sh" -n "$TestUserName2" \
        -R "AssetAdmin,PolicyAdmin" 2>/dev/null)
    sg_assert_not_null "Create user with roles returns data" "$roles_result"

    local user2_id=$(echo "$roles_result" | jq -r '.Id' 2>/dev/null)
    SuiteData[User2Id]="$user2_id"

    sg_register_cleanup "Delete test user $TestUserName2" \
        "$ScriptDir/../src/remove-user.sh -i $user2_id"

    # Readback and verify roles
    local roles_readback=$(sg_invoke -s core -m GET -U "Users/$user2_id")
    local has_asset_admin=$(echo "$roles_readback" | jq '[.AdminRoles[] | select(. == "AssetAdmin")] | length' 2>/dev/null)
    sg_assert_equal "User has AssetAdmin role" "$has_asset_admin" "1"

    local has_policy_admin=$(echo "$roles_readback" | jq '[.AdminRoles[] | select(. == "PolicyAdmin")] | length' 2>/dev/null)
    sg_assert_equal "User has PolicyAdmin role" "$has_policy_admin" "1"

    # --- Test: Edit user via PUT ---
    local updated_body=$(echo "$readback" | jq '.Description = "Updated description"')
    local edit_result=$(sg_invoke -s core -m PUT -U "Users/$user_id" -b "$updated_body")
    local edit_desc=$(echo "$edit_result" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Edit user updates Description" "$edit_desc" "Updated description"

    # Readback after edit
    local edit_readback=$(sg_invoke -s core -m GET -U "Users/$user_id")
    local edit_rb_desc=$(echo "$edit_readback" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Readback confirms edited Description" "$edit_rb_desc" "Updated description"

    local edit_rb_name=$(echo "$edit_readback" | jq -r '.Name' 2>/dev/null)
    sg_assert_equal "Name unchanged after edit" "$edit_rb_name" "$TestUserName"

    # --- Test: Find user with filter ---
    local filter_result=$(sg_invoke -s core -m GET -U "Users?filter=Name%20eq%20'${TestUserName}'")
    local filter_count=$(echo "$filter_result" | jq 'length' 2>/dev/null)
    sg_assert_equal "Filter by Name finds exactly 1 user" "$filter_count" "1"

    local filter_name=$(echo "$filter_result" | jq -r '.[0].Name' 2>/dev/null)
    sg_assert_equal "Filtered user Name matches" "$filter_name" "$TestUserName"

    # --- Test: Delete user and verify gone ---
    "$ScriptDir/../src/remove-user.sh" -i "$user2_id" 2>/dev/null
    local gone_result=$(sg_invoke -s core -m GET -U "Users?filter=Name%20eq%20'${TestUserName2}'")
    local gone_count=$(echo "$gone_result" | jq 'length' 2>/dev/null)
    sg_assert_equal "Deleted user no longer found" "$gone_count" "0"

    # Remove from cleanup since we already deleted it
    SuiteData[User2Id]=""
}

suite_cleanup()
{
    sg_disconnect
}
