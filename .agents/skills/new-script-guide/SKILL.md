---
name: new-script-guide
description: >-
  Use when creating a new CLI script in src/, adding a new command to
  safeguard-bash, or extending an existing script with new functionality.
  Covers the full script template, flag conventions, login file integration,
  and how to add a corresponding test suite.
---

# New Script Guide

## Step-by-Step Checklist

1. **Name the script** using the naming conventions below
2. **Create `src/<name>.sh`** using the full template
3. **Implement the logic** (API call, error handling, output)
4. **Run `./install-local.sh`** to install to `$HOME/scripts`
5. **Test manually** against a live appliance
6. **Create `test/suites/suite-<name>.sh`** with matching tests
7. **Update the test baseline** in the testing-guide skill

---

## Naming Conventions

| Prefix | Meaning | Examples |
|--------|---------|---------|
| `new-` | Create an object | `new-user.sh`, `new-asset.sh` |
| `remove-` | Delete an object | `remove-user.sh`, `remove-asset.sh` |
| `get-` | Read / list objects | `get-access-request.sh`, `get-platform.sh` |
| `edit-` | Update object properties | `edit-access-request.sh` |
| `set-` | Replace a value (password, key, config) | `set-account-password.sh` |
| `find-` | Search with text query or SCIM filter | `find-event.sh` |
| `connect-` / `disconnect-` | Session lifecycle | `connect-safeguard.sh` |
| `install-` / `uninstall-` | Install/remove appliance resources | `install-trusted-certificate.sh` |
| `enable-` / `disable-` | Toggle a service | `enable-a2a-service.sh` |
| `handle-` / `listen-for-` | Event processing | `handle-event.sh` |

Use lowercase with hyphens. The noun should match the Safeguard API resource
name (e.g., `asset-account` not `account`, `a2a-registration` not `registration`).

---

## Full Script Template

```bash
#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: my-new-script.sh [-h]
       my-new-script.sh [-a appliance] [-B cabundle] [-v version] [-t token]

  -h  Show help and exit
  -a  Network address of the appliance
  -B  CA bundle for SSL validation
  -v  API version (default: 4)
  -t  Access token (from connect-safeguard.sh)

  <describe script-specific flags here>

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Initialize ALL variables before getopts
Appliance=
AccessToken=
CABundle=
CABundleArg=
Version=4

. "$ScriptDir/utils/loginfile.sh"

require_args()
{
    require_login_args
    # Add script-specific validation here, e.g.:
    # if [ -z "$MyRequiredParam" ]; then
    #     read -p "Enter value: " MyRequiredParam
    # fi
}

while getopts ":a:t:B:v:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    t) AccessToken=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    h) print_usage ;;
    esac
done

require_args

# --- Main logic ---
# Make the API call
Result=$(curl -s -k $CABundleArg -X GET \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $AccessToken" \
    "https://$Appliance/service/core/v$Version/MyEndpoint")
if [ $? -ne 0 ]; then
    >&2 echo "Fatal error calling Safeguard API"
    exit 1
fi

# Check for API error response
Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result | jq .
else
    >&2 echo "Error from API:"
    echo $Result | jq .
    exit 1
fi
```

### Template Notes

- **`print_usage()`** is always first, uses heredoc, exits 0
- **`ScriptDir`** uses `${BASH_SOURCE[0]}` (not `$0`) — critical for sourcing
- **Initialize all variables** before the getopts loop
- **Source `loginfile.sh`** to get `require_login_args` and login file helpers
- **`require_args()`** calls `require_login_args` first, then validates
  script-specific parameters
- Leading **`:`** in getopts string suppresses built-in error messages
- **`-h`** always shows help

---

## Using invoke-safeguard-method.sh

Most scripts should delegate the actual HTTP call to
`invoke-safeguard-method.sh` rather than calling curl directly:

```bash
# Instead of raw curl, use:
Result=$(invoke-safeguard-method.sh -s core -m GET -U "MyEndpoint" \
    -a "$Appliance" -t "$AccessToken" -v "$Version")

# Or with the login file (most common):
Result=$("$ScriptDir/invoke-safeguard-method.sh" -s core -m GET -U "MyEndpoint")
```

This handles authentication headers, SSL settings, API versioning, and
error formatting consistently.

For scripts that need the login file's token directly:

```bash
# Modern convention: pass token explicitly
"$ScriptDir/invoke-safeguard-method.sh" -s core -m GET -U "Endpoint" \
    -t "$AccessToken"

# Legacy convention (avoid in new scripts): pipe token via stdin
"$ScriptDir/invoke-safeguard-method.sh" -s core -m GET -U "Endpoint" \
    -T -N <<<$AccessToken
```

---

## Login File Integration

The `require_login_args` function handles the full auth resolution chain:

1. Check for existing login file (`$HOME/.safeguard_login`)
2. If no login file, prompt the user or auto-invoke `connect-safeguard.sh`
3. Set `Appliance`, `AccessToken`, and `CABundleArg` from the login file

Scripts that need authentication should:
1. Initialize `Appliance`, `AccessToken`, `CABundle`, `CABundleArg` variables
2. Source `loginfile.sh`
3. Define `require_args()` that calls `require_login_args`
4. Call `require_args` after the getopts loop

Scripts that do NOT need authentication (e.g., `get-appliance-status.sh`)
can skip `loginfile.sh` and handle parameters directly.

---

## Error Handling Pattern

```bash
# 1. Check curl exit code
Result=$(curl -s -k ...)
if [ $? -ne 0 ]; then
    >&2 echo "Fatal error calling Safeguard API"
    exit 1
fi

# 2. Check for JSON error response
Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result | jq .    # Success — output result
else
    echo $Result | jq .    # Error — output for debugging
    exit 1
fi

# 3. Check for required tools at script start
if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq"
    exit 1
fi
```

---

## Adding a Test Suite

Create `test/suites/suite-<name>.sh`:

```bash
#!/bin/bash

suite_name()
{
    echo "My Feature"
}

suite_setup()
{
    sg_connect
    # Create test objects, register cleanups
    return 0
}

suite_execute()
{
    # Test the new script
    local result=$("$ScriptDir/../src/my-new-script.sh" 2>/dev/null)
    sg_assert_not_null "my-new-script.sh returns data" "$result"

    # Readback via API to verify
    local api_result=$(sg_invoke -s core -m GET -U "MyEndpoint")
    sg_assert_equal "API matches script output" "$api_result" "$result"
}

suite_cleanup()
{
    sg_disconnect
}
```

See the `testing-guide` skill for the full framework API and assertion
patterns.

---

## Consulting safeguard-ps

The [OneIdentity/safeguard-ps](https://github.com/OneIdentity/safeguard-ps)
repository is the PowerShell equivalent and is significantly more
feature-rich. When creating a new script:

1. **Check if safeguard-ps has an equivalent cmdlet** — search the repo for
   the API endpoint or feature name
2. **Study its parameter handling** — what parameters does it accept? What
   validation does it do?
3. **Look at error handling** — what edge cases does it handle?
4. **Check the tests** — safeguard-ps tests often reveal API gotchas

This is especially valuable for less common API endpoints where the bash
SDK may not have existing examples to reference.
