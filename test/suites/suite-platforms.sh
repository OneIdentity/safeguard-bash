#!/bin/bash
# Suite: Platforms
# Tests get-platform.sh and invoke-safeguard-method.sh against known
# built-in platforms that exist on every Safeguard appliance.

suite_name()
{
    echo "Platforms"
}

suite_setup()
{
    sg_connect
    return $?
}

suite_execute()
{
    # --- Test: List all platforms returns non-empty array ---
    local all_platforms=$("$ScriptDir/../src/get-platform.sh" 2>/dev/null)
    sg_assert_not_null "get-platform.sh returns data" "$all_platforms"

    local platform_count=$(echo "$all_platforms" | jq 'length' 2>/dev/null)
    sg_assert "Platform list has entries" test "$platform_count" -gt 0

    # --- Test: All platforms are system-owned built-ins ---
    local non_system=$(echo "$all_platforms" | jq '[.[] | select(.IsSystemOwned != true)] | length' 2>/dev/null)
    # There may be custom platforms, but built-ins should dominate -- skip this as informational

    # --- Test: Windows Server platform exists with known properties ---
    local win_server=$("$ScriptDir/../src/get-platform.sh" -n "Windows Server" 2>/dev/null)
    sg_assert_not_null "get-platform.sh -n 'Windows Server' returns data" "$win_server"

    local win_name=$(echo "$win_server" | jq -r '.[0].Name' 2>/dev/null)
    sg_assert_equal "Windows Server Name field" "$win_name" "Windows Server"

    local win_type=$(echo "$win_server" | jq -r '.[0].PlatformType' 2>/dev/null)
    sg_assert_equal "Windows Server PlatformType is Windows" "$win_type" "Windows"

    local win_family=$(echo "$win_server" | jq -r '.[0].PlatformFamily' 2>/dev/null)
    sg_assert_equal "Windows Server PlatformFamily is Windows" "$win_family" "Windows"

    local win_owned=$(echo "$win_server" | jq -r '.[0].IsSystemOwned' 2>/dev/null)
    sg_assert_equal "Windows Server is system-owned" "$win_owned" "true"

    # --- Test: Linux platform exists with known properties ---
    local linux_plat=$("$ScriptDir/../src/get-platform.sh" -n "Linux" 2>/dev/null)
    sg_assert_not_null "get-platform.sh -n 'Linux' returns data" "$linux_plat"

    local linux_name=$(echo "$linux_plat" | jq -r '.[0].Name' 2>/dev/null)
    sg_assert_equal "Linux Name field" "$linux_name" "Linux"

    local linux_type=$(echo "$linux_plat" | jq -r '.[0].PlatformType' 2>/dev/null)
    sg_assert_equal "Linux PlatformType is LinuxOther" "$linux_type" "LinuxOther"

    local linux_family=$(echo "$linux_plat" | jq -r '.[0].PlatformFamily' 2>/dev/null)
    sg_assert_equal "Linux PlatformFamily is Linux" "$linux_family" "Linux"

    # --- Test: Windows Desktop platform exists with known properties ---
    local win_desktop=$("$ScriptDir/../src/get-platform.sh" -n "Windows Desktop" 2>/dev/null)
    sg_assert_not_null "get-platform.sh -n 'Windows Desktop' returns data" "$win_desktop"

    local desk_name=$(echo "$win_desktop" | jq -r '.[0].Name' 2>/dev/null)
    sg_assert_equal "Windows Desktop Name field" "$desk_name" "Windows Desktop"

    local desk_family=$(echo "$win_desktop" | jq -r '.[0].PlatformFamily' 2>/dev/null)
    sg_assert_equal "Windows Desktop PlatformFamily is Windows" "$desk_family" "Windows"

    # --- Test: invoke-safeguard-method.sh can query platforms with filter ---
    local filtered=$(sg_invoke -s core -m GET -U "Platforms?filter=PlatformFamily%20eq%20'Linux'")
    sg_assert_not_null "Filtered platform query returns data" "$filtered"

    local filtered_count=$(echo "$filtered" | jq 'length' 2>/dev/null)
    sg_assert "Linux family filter returns at least 1 platform" test "$filtered_count" -gt 0

    local all_linux=$(echo "$filtered" | jq '[.[] | select(.PlatformFamily != "Linux")] | length' 2>/dev/null)
    sg_assert_equal "All filtered results are Linux family" "$all_linux" "0"
}

suite_cleanup()
{
    sg_disconnect
}
