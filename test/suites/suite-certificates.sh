#!/bin/bash
# Suite: Certificates
# Tests install-trusted-certificate.sh, get-trusted-certificate.sh, and
# uninstall-trusted-certificate.sh against a live Safeguard appliance.
# Generates a self-signed certificate for test purposes.

suite_name()
{
    echo "Certificates"
}

suite_setup()
{
    sg_connect

    # Generate a self-signed certificate for testing
    local cert_dir=$(mktemp -d)
    SuiteData[CertDir]="$cert_dir"
    openssl req -x509 -newkey rsa:2048 -keyout "$cert_dir/key.pem" \
        -out "$cert_dir/cert.pem" -days 1 -nodes \
        -subj "/CN=${TestPrefix}_TrustedCert" 2>/dev/null
    if [ ! -f "$cert_dir/cert.pem" ]; then
        >&2 echo "Failed to generate self-signed certificate"
        return 1
    fi
    SuiteData[CertFile]="$cert_dir/cert.pem"

    local thumbprint=$(openssl x509 -noout -fingerprint -sha1 -in "$cert_dir/cert.pem" \
        | cut -d= -f2 | tr -d :)
    SuiteData[Thumbprint]="$thumbprint"

    # Pre-cleanup stale test certificates
    local stale=$("$ScriptDir/../src/get-trusted-certificate.sh" \
        -q "Subject contains '${TestPrefix}_'" 2>/dev/null)
    for tp in $(echo "$stale" | jq -r '.[].Thumbprint' 2>/dev/null); do
        "$ScriptDir/../src/uninstall-trusted-certificate.sh" -s "$tp" 2>/dev/null
    done

    return 0
}

suite_execute()
{
    local cert_file="${SuiteData[CertFile]}"
    local thumbprint="${SuiteData[Thumbprint]}"

    # --- Test: Install trusted certificate ---
    # install-trusted-certificate.sh prints "Uploading..." before JSON, so capture and strip
    local install_result=$("$ScriptDir/../src/install-trusted-certificate.sh" \
        -C "$cert_file" 2>/dev/null)
    sg_assert_not_null "install-trusted-certificate returns data" "$install_result"

    sg_register_cleanup "Remove test certificate" \
        "$ScriptDir/../src/uninstall-trusted-certificate.sh -s $thumbprint"

    # Readback to verify install (more reliable than parsing install output)
    local readback=$("$ScriptDir/../src/get-trusted-certificate.sh" \
        -s "$thumbprint" 2>/dev/null)
    sg_assert_not_null "Readback after install returns data" "$readback"

    local readback_tp=$(echo "$readback" | jq -r '.Thumbprint' 2>/dev/null)
    sg_assert_equal "Installed thumbprint matches" "$readback_tp" "$thumbprint"

    local readback_subject=$(echo "$readback" | jq -r '.Subject' 2>/dev/null)
    sg_assert_contains "Installed cert Subject contains test name" "$readback_subject" "${TestPrefix}_TrustedCert"

    # --- Test: get-trusted-certificate.sh list all ---
    local all_certs=$("$ScriptDir/../src/get-trusted-certificate.sh" 2>/dev/null)
    sg_assert_not_null "get-trusted-certificate list all returns data" "$all_certs"

    local all_count=$(echo "$all_certs" | jq 'length' 2>/dev/null)
    sg_assert "List all returns at least 1 cert" test "$all_count" -gt 0

    # --- Test: get-trusted-certificate.sh by thumbprint ---
    local single=$("$ScriptDir/../src/get-trusted-certificate.sh" \
        -s "$thumbprint" 2>/dev/null)
    sg_assert_not_null "get-trusted-certificate by thumbprint returns data" "$single"

    local single_tp=$(echo "$single" | jq -r '.Thumbprint' 2>/dev/null)
    sg_assert_equal "Single cert thumbprint matches" "$single_tp" "$thumbprint"

    local single_subject=$(echo "$single" | jq -r '.Subject' 2>/dev/null)
    sg_assert_contains "Single cert Subject contains test name" "$single_subject" "${TestPrefix}_TrustedCert"

    # --- Test: get-trusted-certificate.sh with filter ---
    local filtered=$("$ScriptDir/../src/get-trusted-certificate.sh" \
        -q "Subject contains '${TestPrefix}_TrustedCert'" 2>/dev/null)
    sg_assert_not_null "get-trusted-certificate filter returns data" "$filtered"

    local filtered_count=$(echo "$filtered" | jq 'length' 2>/dev/null)
    sg_assert_equal "Filter returns exactly 1 cert" "$filtered_count" "1"

    local filtered_tp=$(echo "$filtered" | jq -r '.[0].Thumbprint' 2>/dev/null)
    sg_assert_equal "Filtered cert thumbprint matches" "$filtered_tp" "$thumbprint"

    # --- Test: get-trusted-certificate.sh with non-matching filter ---
    local nomatch=$("$ScriptDir/../src/get-trusted-certificate.sh" \
        -q "Subject contains 'NonExistent_ZZZ_999'" 2>/dev/null)
    local nomatch_count=$(echo "$nomatch" | jq 'length' 2>/dev/null)
    sg_assert_equal "Non-matching filter returns empty" "$nomatch_count" "0"

    # --- Test: get-trusted-certificate.sh with fields ---
    local fields_result=$("$ScriptDir/../src/get-trusted-certificate.sh" \
        -f "Thumbprint,Subject" 2>/dev/null)
    sg_assert_not_null "get-trusted-certificate fields returns data" "$fields_result"

    local fields_tp=$(echo "$fields_result" | jq -r ".[] | select(.Thumbprint == \"$thumbprint\") | .Thumbprint" 2>/dev/null)
    sg_assert_equal "Fields result includes Thumbprint" "$fields_tp" "$thumbprint"

    # --- Test: get-trusted-certificate.sh by thumbprint with fields ---
    local single_fields=$("$ScriptDir/../src/get-trusted-certificate.sh" \
        -s "$thumbprint" -f "Thumbprint,Subject" 2>/dev/null)
    sg_assert_not_null "Single cert with fields returns data" "$single_fields"

    local sf_tp=$(echo "$single_fields" | jq -r '.Thumbprint' 2>/dev/null)
    sg_assert_equal "Single cert fields Thumbprint matches" "$sf_tp" "$thumbprint"

    # --- Test: uninstall-trusted-certificate.sh ---
    "$ScriptDir/../src/uninstall-trusted-certificate.sh" -s "$thumbprint" 2>/dev/null
    local delete_exit=$?
    sg_assert_equal "uninstall-trusted-certificate exits 0" "$delete_exit" "0"

    # Verify it's gone
    local after_delete=$("$ScriptDir/../src/get-trusted-certificate.sh" \
        -q "Subject contains '${TestPrefix}_TrustedCert'" 2>/dev/null)
    local after_count=$(echo "$after_delete" | jq 'length' 2>/dev/null)
    sg_assert_equal "Certificate gone after uninstall" "$after_count" "0"
}

suite_cleanup()
{
    # Clean up temp directory
    local cert_dir="${SuiteData[CertDir]}"
    if [ -n "$cert_dir" ] && [ -d "$cert_dir" ]; then
        rm -rf "$cert_dir"
    fi
    sg_disconnect
}
