# Testing safeguard-bash

Integration test framework for verifying scripts against a live Safeguard
appliance. Modeled after the test framework in
[safeguard-ps](https://github.com/OneIdentity/safeguard-ps).

## Prerequisites

- A live Safeguard for Privileged Passwords (SPP) appliance
- An admin account (e.g. `Admin`) with credentials
- `bash`, `curl`, `jq` installed locally (or use the Docker container)

## Running Tests

```bash
# Run all test suites
./test/run-tests.sh -a <appliance> -u <user> -p <password>

# Run a specific suite by name
./test/run-tests.sh -a <appliance> -u <user> -p <password> -s connect

# Use v3 API
./test/run-tests.sh -a <appliance> -u <user> -p <password> -v 3
```

The exit code is the number of failed tests (0 = all passed).

## Directory Structure

```
test/
├── run-tests.sh        # Test runner — discovers and runs suites
├── framework.sh        # Shared test framework (assertions, cleanup, helpers)
├── README.md           # This file
└── suites/             # Test suite scripts
    ├── suite-a2a.sh             # A2A end-to-end workflow
    ├── suite-asset-accounts.sh  # Account CRUD tests
    ├── suite-assets.sh          # Asset CRUD tests
    ├── suite-connect.sh         # Connect & core functionality
    ├── suite-platforms.sh       # Built-in platform validation
    └── suite-users.sh           # User CRUD tests
```

## Writing a Test Suite

Create `test/suites/suite-<name>.sh` and define these functions:

```bash
suite_name()    { echo "My Feature"; }
suite_setup()   { sg_connect; return 0; }
suite_execute() {
    local result=$(sg_invoke -s core -m GET -U "Me")
    sg_assert_not_null "GET Me returns data" "$result"
}
suite_cleanup() { sg_disconnect; }
```

### Available Assertions

| Function | Usage |
|----------|-------|
| `sg_assert` | `sg_assert "description" command [args...]` |
| `sg_assert_equal` | `sg_assert_equal "description" "actual" "expected"` |
| `sg_assert_not_null` | `sg_assert_not_null "description" "value"` |
| `sg_assert_contains` | `sg_assert_contains "description" "haystack" "needle"` |
| `sg_skip` | `sg_skip "description" "reason"` |

### Available Helpers

| Function | Description |
|----------|-------------|
| `sg_connect` | Connect to appliance using test context credentials |
| `sg_disconnect` | Disconnect and remove login file |
| `sg_invoke` | Call `invoke-safeguard-method.sh` (pass same flags) |
| `sg_register_cleanup` | Register a cleanup action (LIFO execution) |

### Suite Lifecycle

1. **Setup** — create test objects, register cleanups. Return non-zero to skip Execute.
2. **Execute** — run assertions.
3. **Registered Cleanups** — run in LIFO order while session is still active.
4. **Suite Cleanup** — `suite_cleanup()` restores session state for the next suite.

Cleanup always runs, even if Setup or Execute fail.

## Test Suites

| Suite | Tests | Description |
|-------|-------|-------------|
| `suite-a2a.sh` | 18 | Full A2A workflow: cert, registration, credential retrieval |
| `suite-asset-accounts.sh` | 17 | Account CRUD, passwords, edit, filter |
| `suite-assets.sh` | 17 | Asset CRUD, platform validation, edit, filter |
| `suite-connect.sh` | 9 | Connect, login file, API calls, disconnect |
| `suite-platforms.sh` | 17 | Built-in platform validation (Windows, Linux) |
| `suite-users.sh` | 16 | User CRUD, roles, edit, filter, delete |

**Total: 94 tests across 6 suites**

See [AGENTS.md](../AGENTS.md) for detailed guidance on writing tests and
assertions.
