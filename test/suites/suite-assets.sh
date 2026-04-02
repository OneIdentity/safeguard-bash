#!/bin/bash
# Suite: Assets
# Tests new-asset.sh and remove-asset.sh with CRUD validation and readback.
# Requires AssetAdmin role -- creates a RunAdmin user for this purpose.

suite_name()
{
    echo "Assets"
}

suite_setup()
{
    sg_connect

    # Create a full-admin user since built-in Admin lacks AssetAdmin
    local admin_result=$("$ScriptDir/../src/new-user.sh" \
        -n "${TestPrefix}_AssetAdmin" \
        -R "GlobalAdmin,AssetAdmin,PolicyAdmin,UserAdmin,ApplianceAdmin,Auditor,OperationsAdmin" \
        2>/dev/null)
    local admin_id=$(echo "$admin_result" | jq -r '.Id' 2>/dev/null)
    if [ -z "$admin_id" ] || [ "$admin_id" = "null" ]; then
        >&2 echo "Failed to create admin user for Assets suite"
        return 1
    fi
    SuiteData[AdminId]="$admin_id"

    # Set password and reconnect as the full admin
    sg_invoke -s core -m PUT -U "Users/$admin_id/Password" -b '"AssetTest1!"' >/dev/null
    sg_disconnect
    echo "AssetTest1!" | "$ScriptDir/../src/connect-safeguard.sh" \
        -a "$TestAppliance" -i local -u "${TestPrefix}_AssetAdmin" -v "$TestVersion" -p 2>/dev/null

    # Pre-cleanup stale assets
    local stale=$(sg_invoke -s core -m GET -U "Assets?filter=Name%20contains%20'${TestPrefix}_'")
    local stale_ids=$(echo "$stale" | jq -r '.[].Id' 2>/dev/null)
    for id in $stale_ids; do
        "$ScriptDir/../src/remove-asset.sh" -i "$id" 2>/dev/null
    done

    return 0
}

suite_execute()
{
    local TestAssetName="${TestPrefix}_Asset1"

    # --- Test: Create asset ---
    local create_result=$("$ScriptDir/../src/new-asset.sh" \
        -n "$TestAssetName" -N "10.0.0.100" -P 521 -D "Test Linux asset" 2>/dev/null)
    sg_assert_not_null "Create asset returns data" "$create_result"

    local asset_id=$(echo "$create_result" | jq -r '.Id' 2>/dev/null)
    sg_assert_not_null "Created asset has an Id" "$asset_id"
    SuiteData[AssetId]="$asset_id"

    sg_register_cleanup "Delete test asset $TestAssetName" \
        "$ScriptDir/../src/remove-asset.sh -i $asset_id"

    local created_name=$(echo "$create_result" | jq -r '.Name' 2>/dev/null)
    sg_assert_equal "Created asset Name matches" "$created_name" "$TestAssetName"

    local created_platform=$(echo "$create_result" | jq -r '.PlatformDisplayName' 2>/dev/null)
    sg_assert_equal "Created asset platform is Linux" "$created_platform" "Linux"

    # --- Test: Readback by ID ---
    local readback=$(sg_invoke -s core -m GET -U "Assets/$asset_id")
    sg_assert_not_null "Readback asset by ID returns data" "$readback"

    local rb_name=$(echo "$readback" | jq -r '.Name' 2>/dev/null)
    sg_assert_equal "Readback Name matches" "$rb_name" "$TestAssetName"

    local rb_addr=$(echo "$readback" | jq -r '.NetworkAddress' 2>/dev/null)
    sg_assert_equal "Readback NetworkAddress matches" "$rb_addr" "10.0.0.100"

    local rb_desc=$(echo "$readback" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Readback Description matches" "$rb_desc" "Test Linux asset"

    local rb_partition=$(echo "$readback" | jq -r '.AssetPartitionName' 2>/dev/null)
    sg_assert_equal "Asset is in Default Partition" "$rb_partition" "Default Partition"

    # --- Test: Edit asset via PUT ---
    local updated=$(echo "$readback" | jq '.Description = "Updated asset" | .NetworkAddress = "10.0.0.101"')
    local edit_result=$(sg_invoke -s core -m PUT -U "Assets/$asset_id" -b "$updated")

    local edit_desc=$(echo "$edit_result" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Edit updates Description" "$edit_desc" "Updated asset"

    local edit_addr=$(echo "$edit_result" | jq -r '.NetworkAddress' 2>/dev/null)
    sg_assert_equal "Edit updates NetworkAddress" "$edit_addr" "10.0.0.101"

    # Readback after edit
    local edit_readback=$(sg_invoke -s core -m GET -U "Assets/$asset_id")
    local edit_rb_desc=$(echo "$edit_readback" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Readback confirms edited Description" "$edit_rb_desc" "Updated asset"

    local edit_rb_name=$(echo "$edit_readback" | jq -r '.Name' 2>/dev/null)
    sg_assert_equal "Name unchanged after edit" "$edit_rb_name" "$TestAssetName"

    # --- Test: Find asset with filter ---
    local filter_result=$(sg_invoke -s core -m GET -U "Assets?filter=Name%20eq%20'${TestAssetName}'")
    local filter_count=$(echo "$filter_result" | jq 'length' 2>/dev/null)
    sg_assert_equal "Filter by Name finds exactly 1 asset" "$filter_count" "1"

    # --- Test: Create a second asset (Windows) and verify platform ---
    local TestAsset2="${TestPrefix}_Asset2"
    local win_result=$("$ScriptDir/../src/new-asset.sh" \
        -n "$TestAsset2" -N "10.0.0.200" -P 547 -D "Test Windows asset" 2>/dev/null)
    local win_id=$(echo "$win_result" | jq -r '.Id' 2>/dev/null)
    sg_assert_not_null "Create Windows asset returns Id" "$win_id"
    SuiteData[Asset2Id]="$win_id"

    sg_register_cleanup "Delete test asset $TestAsset2" \
        "$ScriptDir/../src/remove-asset.sh -i $win_id"

    local win_platform=$(echo "$win_result" | jq -r '.PlatformDisplayName' 2>/dev/null)
    sg_assert_equal "Windows asset platform is Windows Server" "$win_platform" "Windows Server"

    # --- Test: Delete asset and verify gone ---
    "$ScriptDir/../src/remove-asset.sh" -i "$win_id" 2>/dev/null
    local gone_result=$(sg_invoke -s core -m GET -U "Assets?filter=Name%20eq%20'${TestAsset2}'")
    local gone_count=$(echo "$gone_result" | jq 'length' 2>/dev/null)
    sg_assert_equal "Deleted asset no longer found" "$gone_count" "0"

    SuiteData[Asset2Id]=""
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
