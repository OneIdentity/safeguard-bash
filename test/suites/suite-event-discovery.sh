#!/bin/bash
# Test suite for event discovery scripts:
#   get-event-name.sh, get-event-category.sh, get-event-property.sh, find-event.sh

suite_name()
{
    echo "Event Discovery"
}

suite_setup()
{
    sg_connect
    return 0
}

suite_execute()
{
    # --- Test: get-event-name.sh (all names) ---
    local all_names=$("$ScriptDir/../src/get-event-name.sh" 2>/dev/null)
    sg_assert_not_null "get-event-name returns data" "$all_names"

    local name_count=$(echo "$all_names" | wc -l)
    sg_assert "Event name count is large" test "$name_count" -gt 100

    # Verify output is sorted (first and last should be alphabetical)
    local first_name=$(echo "$all_names" | head -1)
    local second_name=$(echo "$all_names" | head -2 | tail -1)
    local sorted_names=$(echo "$all_names" | sort)
    local sorted_first=$(echo "$sorted_names" | head -1)
    sg_assert_equal "Names are sorted" "$first_name" "$sorted_first"

    # Verify known event names appear
    local has_user_created=$(echo "$all_names" | grep -c "^UserCreated$")
    sg_assert_equal "UserCreated event exists" "$has_user_created" "1"

    # --- Test: get-event-name.sh filtered by object type ---
    local user_names=$("$ScriptDir/../src/get-event-name.sh" -T User 2>/dev/null)
    sg_assert_not_null "get-event-name -T User returns data" "$user_names"

    local user_name_count=$(echo "$user_names" | wc -l)
    sg_assert "User event names fewer than all" test "$user_name_count" -lt "$name_count"

    local has_user_created2=$(echo "$user_names" | grep -c "^UserCreated$")
    sg_assert_equal "UserCreated in User type filter" "$has_user_created2" "1"

    # --- Test: get-event-name.sh filtered by category ---
    local auth_names=$("$ScriptDir/../src/get-event-name.sh" -C UserAuthentication 2>/dev/null)
    sg_assert_not_null "get-event-name -C UserAuthentication returns data" "$auth_names"

    local has_user_auth=$(echo "$auth_names" | grep -c "^UserAuthenticated$")
    sg_assert_equal "UserAuthenticated in auth category" "$has_user_auth" "1"

    # --- Test: get-event-category.sh (all categories) ---
    local all_cats=$("$ScriptDir/../src/get-event-category.sh" 2>/dev/null)
    sg_assert_not_null "get-event-category returns data" "$all_cats"

    local cat_count=$(echo "$all_cats" | wc -l)
    sg_assert "Category count is reasonable" test "$cat_count" -ge 5

    local has_obj_history=$(echo "$all_cats" | grep -c "^ObjectHistory$")
    sg_assert_equal "ObjectHistory category exists" "$has_obj_history" "1"

    local has_user_auth_cat=$(echo "$all_cats" | grep -c "^UserAuthentication$")
    sg_assert_equal "UserAuthentication category exists" "$has_user_auth_cat" "1"

    # --- Test: get-event-category.sh filtered by type ---
    local user_cats=$("$ScriptDir/../src/get-event-category.sh" -T User 2>/dev/null)
    sg_assert_not_null "get-event-category -T User returns data" "$user_cats"

    local user_cat_count=$(echo "$user_cats" | wc -l)
    sg_assert "User categories fewer than all" test "$user_cat_count" -le "$cat_count"

    # --- Test: get-event-property.sh ---
    local props=$("$ScriptDir/../src/get-event-property.sh" -n UserCreated 2>/dev/null)
    sg_assert_not_null "get-event-property returns data" "$props"

    local prop_count=$(echo "$props" | jq 'length' 2>/dev/null)
    sg_assert "UserCreated has properties" test "$prop_count" -gt 0

    local has_name_prop=$(echo "$props" | jq '[.[].Name] | map(select(. == "UserName")) | length' 2>/dev/null)
    sg_assert "UserCreated has UserName property" test "$has_name_prop" -ge 1

    # Each property should have Name and Description
    local first_prop_name=$(echo "$props" | jq -r '.[0].Name' 2>/dev/null)
    sg_assert_not_null "Property has Name field" "$first_prop_name"

    # --- Test: find-event.sh (text search) ---
    local search_result=$("$ScriptDir/../src/find-event.sh" -Q "password" 2>/dev/null)
    sg_assert_not_null "find-event -Q password returns data" "$search_result"

    local search_count=$(echo "$search_result" | jq 'length' 2>/dev/null)
    sg_assert "Password search returns results" test "$search_count" -gt 0

    # --- Test: find-event.sh (filter) ---
    local filter_result=$("$ScriptDir/../src/find-event.sh" \
        -q "ObjectType%20eq%20'User'" -f "Name,Category" 2>/dev/null)
    sg_assert_not_null "find-event with filter returns data" "$filter_result"

    local filter_count=$(echo "$filter_result" | jq 'length' 2>/dev/null)
    sg_assert "User filter returns results" test "$filter_count" -gt 0

    local first_filter_name=$(echo "$filter_result" | jq -r '.[0].Name' 2>/dev/null)
    sg_assert_not_null "Filtered result has Name" "$first_filter_name"

    # --- Test: find-event.sh (non-matching) ---
    local nomatch=$("$ScriptDir/../src/find-event.sh" -Q "xyznonexistent99" 2>/dev/null)
    local nomatch_count=$(echo "$nomatch" | jq 'length' 2>/dev/null)
    sg_assert_equal "Non-matching search returns empty" "$nomatch_count" "0"
}

suite_cleanup()
{
    sg_disconnect
}
