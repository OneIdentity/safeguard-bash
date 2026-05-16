---
name: testing-guide
description: >-
  Use when running tests, writing tests, investigating test failures,
  or setting up a test environment against a live Safeguard appliance.
  Covers the test framework API, suite lifecycle, assertion patterns,
  and the test runner.
---

# Testing Guide

## Asking for Appliance Access

**Before running any tests, ask the user for appliance connection details.**

You need these three values:
- **Appliance address** — IP or hostname of a Safeguard appliance
- **Admin username** — typically `Admin`
- **Admin password** — the password for the admin account

Example prompt to the user:

> To run tests I need access to a live Safeguard appliance. Can you provide:
> 1. The appliance network address (IP or hostname)
> 2. An admin username (e.g. Admin)
> 3. The admin password

Do not hardcode credentials anywhere. Pass them only as command-line arguments
to the test runner.

---

## Running Tests

```bash
# Run all test suites
./test/run-tests.sh -a <appliance> -u <user> -p <password>

# Run a specific suite (substring match on filename, may be repeated)
./test/run-tests.sh -a <appliance> -u <user> -p <password> -s connect

# Run multiple specific suites
./test/run-tests.sh -a <appliance> -u <user> -p <password> -s connect -s users

# Run with v3 API
./test/run-tests.sh -a <appliance> -u <user> -p <password> -v 3
```

The test runner:
1. Connects via PKCE (works regardless of appliance grant-type configuration)
2. Checks the Resource Owner Grant (ROG) setting and enables it if needed
3. Disconnects, then runs each suite with a clean session
4. Restores the original ROG setting on exit (via trap)

---

## Test Framework Architecture

The test framework (`test/framework.sh`) is sourced by the test runner and
all suite scripts. It provides:

### Global Context Variables

Set by the test runner and available in all suites:

| Variable | Description |
|----------|-------------|
| `TestAppliance` | Appliance network address |
| `TestUser` | Admin username |
| `TestPassword` | Admin password |
| `TestVersion` | API version (default: 4) |
| `TestPrefix` | Name prefix for test objects: `"SgBashTest"` |
| `TestCABundleArg` | CA bundle argument (default: `"-k"` = skip SSL) |

### Assertion Functions

| Function | Usage | Behavior |
|----------|-------|----------|
| `sg_assert` | `sg_assert "desc" command [args...]` | Runs a command; PASS if exit code 0 |
| `sg_assert_equal` | `sg_assert_equal "desc" "$actual" "expected"` | PASS if strings match exactly |
| `sg_assert_not_null` | `sg_assert_not_null "desc" "$value"` | PASS if value is non-empty |
| `sg_assert_contains` | `sg_assert_contains "desc" "$haystack" "needle"` | PASS if haystack contains needle |
| `sg_skip` | `sg_skip "desc" "reason"` | Record a skipped test |

All assertions increment pass/fail/skip counters automatically and print
colored results. Failed assertions include the actual vs. expected values.

### Connection Helpers

| Function | Description |
|----------|-------------|
| `sg_connect` | Connect via password auth (requires ROG enabled) |
| `sg_connect_pkce` | Connect via PKCE (works regardless of ROG setting) |
| `sg_disconnect` | Disconnect and remove login file |
| `sg_invoke` | Call `invoke-safeguard-method.sh` with the current login file |

`sg_invoke` passes all arguments through, so use it like:
```bash
local result=$(sg_invoke -s core -m GET -U "Me")
local result=$(sg_invoke -s core -m POST -U "Users" -b "$body")
```

### Cleanup Registration

```bash
sg_register_cleanup "description" "shell command to run"
```

Registered cleanups execute in **LIFO order** (last registered runs first)
with a 15-second timeout per action. They run while the login session is
still active, before `suite_cleanup()`.

### ROG Management

| Function | Description |
|----------|-------------|
| `sg_ensure_rog_enabled` | Save current setting, enable ROG if disabled |
| `sg_restore_rog` | Restore original grant-type setting (reconnects via PKCE) |

The test runner calls these automatically — suites don't need to manage ROG.

### SuiteData Associative Array

```bash
declare -A SuiteData
```

An associative array reset between suites. Use it to share state between
`suite_setup` and `suite_execute`:

```bash
suite_setup()
{
    local result=$(sg_invoke -s core -m POST -U "Users" -b "$body")
    SuiteData[UserId]=$(echo "$result" | jq -r '.Id')
    sg_register_cleanup "Delete test user" \
        "$ScriptDir/../src/invoke-safeguard-method.sh -s core -m DELETE -U Users/${SuiteData[UserId]}"
}

suite_execute()
{
    local user=$(sg_invoke -s core -m GET -U "Users/${SuiteData[UserId]}")
    sg_assert_not_null "Can read back created user" "$user"
}
```

---

## Writing a Test Suite

Create a file `test/suites/suite-<name>.sh` that defines these functions:

```bash
#!/bin/bash

suite_name()
{
    echo "My Feature"
}

suite_setup()
{
    # Connect to the appliance
    sg_connect

    # Create test objects needed by the suite
    local body='{"Name":"'${TestPrefix}'_MyAsset","NetworkAddress":"1.2.3.4","PlatformId":521,"AssetPartitionId":-1}'
    local result=$(sg_invoke -s core -m POST -U "Assets" -b "$body")
    SuiteData[AssetId]=$(echo "$result" | jq -r '.Id')

    # Register cleanup IMMEDIATELY after creating each object
    sg_register_cleanup "Delete test asset" \
        "$ScriptDir/../src/invoke-safeguard-method.sh -s core -m DELETE -U Assets/${SuiteData[AssetId]}"

    # Return non-zero to skip Execute phase
    return 0
}

suite_execute()
{
    # Run assertions against the API
    local result=$(sg_invoke -s core -m GET -U "Assets/${SuiteData[AssetId]}")
    sg_assert_not_null "GET asset returns data" "$result"

    local name=$(echo "$result" | jq -r '.Name' 2>/dev/null)
    sg_assert_equal "Asset name matches" "$name" "${TestPrefix}_MyAsset"
}

suite_cleanup()
{
    # Registered cleanups already ran (LIFO) while session was active.
    # Disconnect to leave a clean state for the next suite.
    sg_disconnect
}
```

### Suite Lifecycle

```
suite_setup()
    ↓ (if setup returns 0)
suite_execute()
    ↓ (always, regardless of test failures)
Registered cleanups (LIFO order, session still active)
    ↓ (always)
suite_cleanup()
```

### Suite Lifecycle Rules

1. **Setup failure** → Execute phase is skipped, Cleanup still runs
2. **Cleanup always runs** — both registered cleanup actions and the
   `suite_cleanup` function execute regardless of test outcome
3. **Registered cleanups run FIRST, in LIFO order** — they execute while the
   current session is still active (login file exists), then `suite_cleanup`
   runs to restore session state for the next suite
4. **Register cleanup immediately** after creating each test object
5. **Suite functions are unloaded** between suites to prevent leakage
6. **Cannot delete the currently authenticated user** — suites that create
   their own admin user must handle deletion in `suite_cleanup()` by
   reconnecting as the original user first

---

## Writing Strong Assertions

Follow these principles (adapted from safeguard-ps):

1. **Always readback after create** — don't trust the return value alone; fetch
   the object again via API and verify its properties
2. **Always readback after edit** — confirm the change persisted and other
   fields are intact
3. **Always readback after delete** — verify the object is gone (expect empty
   or error response)
4. **Assert specific values, not just existence** — prefer
   `sg_assert_equal "name" "$actual" "expected"` over
   `sg_assert_not_null "exists" "$result"`
5. **Test both return value AND readback** — use two separate assertions
6. **Use the TestPrefix** for all test object names so they can be identified
   and cleaned up:
   ```bash
   TestAssetName="${TestPrefix}_MyAsset"
   ```
7. **Register cleanup immediately** after creating each object:
   ```bash
   sg_register_cleanup "Delete test asset" \
       "$ScriptDir/../src/invoke-safeguard-method.sh -s core -m DELETE -U Assets/$asset_id"
   ```

### Test Philosophy

- **Fix source code, not tests** — if a test fails, the default assumption
  is the code is wrong. Ask before weakening assertions.
- **Don't skip tests without a reason** — use `sg_skip` with a clear reason
  string, not silent omission.
- **Clean up after yourself** — every created object must have a registered
  cleanup. Use `TestPrefix` naming so stale objects are identifiable.

---

## Certificate Utility Scripts

These scripts in `src/utils/` are useful for test setup involving certificates:

| Script | Description |
|--------|-------------|
| `new-test-ca.sh` | Generate a self-signed CA certificate + key |
| `new-test-cert.sh` | Generate a certificate signed by a test CA |
| `convert-pfx-to-pem.sh` | Convert PFX/PKCS12 to separate PEM files |
| `add-pem-password.sh` | Add a password to a PEM private key |
| `remove-pem-password.sh` | Remove a password from a PEM private key |

---

## Test Baseline

The current baseline when all suites pass:

```
Suites: 10 (0 failed)
Tests:  268 passed, 0 failed, 0 skipped
```

| Suite                  | Tests | Description                                       |
|------------------------|-------|---------------------------------------------------|
| A2A Access Req Broker  | 21    | Broker lifecycle: get/set/clear, IP restrictions, cert-auth request |
| A2A                    | 92    | Full A2A workflow: cert, registration, retrieval, credentials, IP restrictions |
| Asset Accounts         | 20    | Account CRUD, passwords, SSH keys, edit, filter    |
| Assets                 | 17    | Asset CRUD, platform validation, edit, filter      |
| Certificates           | 19    | Trusted cert install/uninstall, get, filter, fields |
| Connect & Core         | 16    | Connect, PKCE, login file, API calls, disconnect   |
| Event Discovery        | 25    | Event names, categories, properties, search/filter |
| Event Subscriptions    | 25    | Subscription CRUD, edit, find, SignalR/email types  |
| Platforms              | 17    | Built-in platform validation (Windows, Linux)      |
| Users                  | 16    | User CRUD, roles, edit, filter, delete             |

Update this baseline as you add suites and tests.
