#!/bin/bash
# Suite: Event Subscriptions
# Tests new-event-subscription.sh, get-event-subscription.sh,
# edit-event-subscription.sh, find-event-subscription.sh, and
# remove-event-subscription.sh against a live Safeguard appliance.

suite_name()
{
    echo "Event Subscriptions"
}

suite_setup()
{
    sg_connect

    # Get current user ID for subscription creation
    local me=$(sg_invoke -s core -m GET -U "Me")
    local user_id=$(echo "$me" | jq -r '.Id' 2>/dev/null)
    if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
        >&2 echo "Failed to get current user ID"
        return 1
    fi
    SuiteData[UserId]="$user_id"

    # Pre-cleanup stale test subscriptions
    local stale=$("$ScriptDir/../src/find-event-subscription.sh" \
        -Q "${TestPrefix}" 2>/dev/null)
    for id in $(echo "$stale" | jq -r '.[].Id' 2>/dev/null); do
        "$ScriptDir/../src/remove-event-subscription.sh" -i "$id" 2>/dev/null
    done

    return 0
}

suite_execute()
{
    local user_id="${SuiteData[UserId]}"

    # --- Test: Create SignalR event subscription ---
    local create_result=$("$ScriptDir/../src/new-event-subscription.sh" \
        -T "SignalR" -D "${TestPrefix}_EventSub" \
        -e "UserCreated,UserDeleted" -U "$user_id" 2>/dev/null)
    sg_assert_not_null "Create SignalR subscription returns data" "$create_result"

    local sub_id=$(echo "$create_result" | jq -r '.Id' 2>/dev/null)
    sg_assert_not_null "Subscription has an Id" "$sub_id"
    SuiteData[SubId]="$sub_id"
    sg_register_cleanup "Delete event subscription" \
        "$ScriptDir/../src/remove-event-subscription.sh -i $sub_id"

    local sub_type=$(echo "$create_result" | jq -r '.Type' 2>/dev/null)
    sg_assert_equal "Subscription type is Signalr" "$sub_type" "Signalr"

    local sub_desc=$(echo "$create_result" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Subscription description matches" "$sub_desc" "${TestPrefix}_EventSub"

    local sub_event_count=$(echo "$create_result" | jq '.Subscriptions | length' 2>/dev/null)
    sg_assert_equal "Subscription has 2 events" "$sub_event_count" "2"

    # --- Test: Readback subscription by ID ---
    local readback=$("$ScriptDir/../src/get-event-subscription.sh" \
        -i "$sub_id" 2>/dev/null)
    sg_assert_not_null "get-event-subscription by ID returns data" "$readback"

    local rb_type=$(echo "$readback" | jq -r '.Type' 2>/dev/null)
    sg_assert_equal "Readback type is Signalr" "$rb_type" "Signalr"

    local rb_desc=$(echo "$readback" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Readback description matches" "$rb_desc" "${TestPrefix}_EventSub"

    # --- Test: List all subscriptions ---
    local all_subs=$("$ScriptDir/../src/get-event-subscription.sh" 2>/dev/null)
    sg_assert_not_null "get-event-subscription list all returns data" "$all_subs"

    local all_count=$(echo "$all_subs" | jq 'length' 2>/dev/null)
    sg_assert "List all returns at least 1 subscription" test "$all_count" -gt 0

    # --- Test: get-event-subscription with fields ---
    local fields_result=$("$ScriptDir/../src/get-event-subscription.sh" \
        -f "Id,Type,Description" 2>/dev/null)
    sg_assert_not_null "get-event-subscription fields returns data" "$fields_result"

    local fields_id=$(echo "$fields_result" | jq -r ".[] | select(.Id == $sub_id) | .Id" 2>/dev/null)
    sg_assert_equal "Fields result includes our subscription" "$fields_id" "$sub_id"

    # --- Test: Edit subscription description ---
    local edit_result=$("$ScriptDir/../src/edit-event-subscription.sh" \
        -i "$sub_id" -D "${TestPrefix}_Edited" 2>/dev/null)
    sg_assert_not_null "edit-event-subscription returns data" "$edit_result"

    local edit_desc=$(echo "$edit_result" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Edit updated description" "$edit_desc" "${TestPrefix}_Edited"

    # Readback to verify
    local edit_rb=$("$ScriptDir/../src/get-event-subscription.sh" \
        -i "$sub_id" 2>/dev/null)
    local edit_rb_desc=$(echo "$edit_rb" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Readback confirms edited description" "$edit_rb_desc" "${TestPrefix}_Edited"

    # Type should be unchanged
    local edit_rb_type=$(echo "$edit_rb" | jq -r '.Type' 2>/dev/null)
    sg_assert_equal "Type unchanged after edit" "$edit_rb_type" "Signalr"

    # --- Test: Edit subscription events ---
    local edit_events=$("$ScriptDir/../src/edit-event-subscription.sh" \
        -i "$sub_id" -e "UserCreated" 2>/dev/null)
    local edit_ev_count=$(echo "$edit_events" | jq '.Subscriptions | length' 2>/dev/null)
    sg_assert_equal "Edit reduced to 1 event" "$edit_ev_count" "1"

    local edit_ev_name=$(echo "$edit_events" | jq -r '.Subscriptions[0].Name' 2>/dev/null)
    sg_assert_equal "Remaining event is UserCreated" "$edit_ev_name" "UserCreated"

    # --- Test: Edit with full JSON body ---
    local current=$("$ScriptDir/../src/get-event-subscription.sh" -i "$sub_id" 2>/dev/null)
    local new_body=$(echo "$current" | jq '.Description = "'"${TestPrefix}_JsonEdit"'"')
    local edit_json=$("$ScriptDir/../src/edit-event-subscription.sh" \
        -i "$sub_id" -b "$new_body" 2>/dev/null)
    local edit_json_desc=$(echo "$edit_json" | jq -r '.Description' 2>/dev/null)
    sg_assert_equal "Edit with JSON body updated description" "$edit_json_desc" "${TestPrefix}_JsonEdit"

    # --- Test: find-event-subscription.sh with search text ---
    local find_result=$("$ScriptDir/../src/find-event-subscription.sh" \
        -Q "${TestPrefix}" 2>/dev/null)
    sg_assert_not_null "find-event-subscription returns data" "$find_result"

    local find_count=$(echo "$find_result" | jq 'length' 2>/dev/null)
    sg_assert "Find returns at least 1 result" test "$find_count" -gt 0

    # --- Test: find-event-subscription.sh with filter ---
    local find_filter=$("$ScriptDir/../src/find-event-subscription.sh" \
        -q "Type eq 'SignalR'" -f "Id,Type,Description" 2>/dev/null)
    sg_assert_not_null "find-event-subscription with filter returns data" "$find_filter"

    # --- Test: find-event-subscription.sh with non-matching search ---
    local find_nomatch=$("$ScriptDir/../src/find-event-subscription.sh" \
        -Q "NonExistent_ZZZ_999_XYZ" 2>/dev/null)
    local find_nomatch_count=$(echo "$find_nomatch" | jq 'length' 2>/dev/null)
    sg_assert_equal "Non-matching search returns empty" "$find_nomatch_count" "0"

    # --- Test: Remove event subscription ---
    "$ScriptDir/../src/remove-event-subscription.sh" -i "$sub_id" 2>/dev/null
    local delete_exit=$?
    sg_assert_equal "remove-event-subscription exits 0" "$delete_exit" "0"

    # Verify it's gone
    local after_delete=$("$ScriptDir/../src/get-event-subscription.sh" \
        -i "$sub_id" 2>/dev/null)
    local after_error=$(echo "$after_delete" | jq .Code 2>/dev/null)
    sg_assert "Subscription gone after remove" test "$after_error" != "null"
}

suite_cleanup()
{
    sg_disconnect
}
