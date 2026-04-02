# AGENTS.md — AI Agent Instructions for safeguard-bash

This document provides instructions for AI coding agents working in the
safeguard-bash repository. It covers project structure, conventions, testing
against a live Safeguard appliance, and Safeguard domain knowledge needed to
write correct scripts.

---

## Project Overview

safeguard-bash is a Bash + cURL scripting SDK for the **One Identity Safeguard
for Privileged Passwords (SPP)** REST API. Each script in `src/` is a
self-contained CLI command that wraps one or more Safeguard API operations.

The scripts are designed to run standalone on any system with bash, curl, and
jq, or inside an Alpine-based Docker container.

---

## Project Structure

```
safeguard-bash/
├── src/                    # CLI scripts (the SDK)
│   ├── connect-safeguard.sh
│   ├── disconnect-safeguard.sh
│   ├── invoke-safeguard-method.sh
│   ├── ... (35+ scripts)
│   └── utils/              # Shared libraries sourced by scripts
│       ├── loginfile.sh    # Login file management ($HOME/.safeguard_login)
│       ├── a2a.sh          # A2A (app-to-app) HTTP helpers
│       └── common.sh       # Exponential backoff/retry logic
├── test/                   # Integration test framework
│   ├── run-tests.sh        # Test runner entry point
│   ├── framework.sh        # Test framework library
│   ├── suites/             # Test suite scripts (suite-*.sh)
│   └── README.md
├── samples/                # Example integrations
├── pipeline-templates/     # Azure DevOps CI/CD YAML
├── build.sh                # Docker image + ZIP builder
├── run.sh                  # Docker container launcher
├── install-local.sh        # Install scripts to $HOME/scripts
├── Dockerfile              # Alpine container definition
└── AGENTS.md               # This file
```

---

## Setup and Development Workflow

There is no build step. Scripts are pure bash.

```bash
# Install scripts to $HOME/scripts and add to PATH
./install-local.sh
# Source your profile to pick up the PATH change
. ~/.bash_profile   # or . ~/.profile
```

After editing scripts in `src/`, re-run `./install-local.sh` to copy changes
and test them.

`build.sh` and `run.sh` are for Docker packaging only — not part of the normal
development workflow.

There is no linter or formatter for this project.

---

## Testing Against a Live Appliance

### Asking for Appliance Access

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

### Running Tests

```bash
# Run all test suites
./test/run-tests.sh -a <appliance> -u <user> -p <password>

# Run a specific suite (substring match on filename)
./test/run-tests.sh -a <appliance> -u <user> -p <password> -s connect

# Run with v3 API
./test/run-tests.sh -a <appliance> -u <user> -p <password> -v 3
```

### Test Framework Architecture

The test framework (`test/framework.sh`) provides:

- **Assertions**: `sg_assert`, `sg_assert_equal`, `sg_assert_not_null`,
  `sg_assert_contains`, `sg_skip`
- **Cleanup registration**: `sg_register_cleanup` (LIFO execution order)
- **Suite lifecycle**: Setup → Execute → Cleanup → Registered Cleanups
- **Helpers**: `sg_connect`, `sg_disconnect`, `sg_invoke`

### Writing a Test Suite

Create a file `test/suites/suite-<name>.sh` that defines these functions:

```bash
#!/bin/bash

suite_name()
{
    echo "My Feature"
}

suite_setup()
{
    # Create test objects, register cleanups
    # Return non-zero to skip Execute phase
    sg_connect
    return 0
}

suite_execute()
{
    # Run assertions
    local result=$(sg_invoke -s core -m GET -U "Me")
    sg_assert_not_null "GET Me returns data" "$result"

    local name=$(echo "$result" | jq -r '.UserName' 2>/dev/null)
    sg_assert_equal "Username is correct" "$name" "$TestUser"
}

suite_cleanup()
{
    sg_disconnect
}
```

### Suite Lifecycle Rules

1. **Setup failure** → Execute phase is skipped, Cleanup still runs
2. **Cleanup always runs** — both the `suite_cleanup` function and all
   registered cleanup actions execute regardless of test outcome
3. **Registered cleanups run in LIFO order** — register immediately after
   creating each test object
4. **Suite functions are unloaded** between suites to prevent leakage

### Writing Strong Assertions

Follow these principles (adapted from safeguard-ps):

1. **Always readback after create** — don't trust the return value alone; fetch
   the object again via API and verify its properties
2. **Always readback after edit** — confirm the change persisted and other
   fields are intact
3. **Always readback after delete** — verify the object is gone
4. **Assert specific values, not just existence** — prefer
   `sg_assert_equal "name" "$actual" "expected"` over
   `sg_assert_not_null "exists" "$result"`
5. **Test both return value AND readback** — use two separate assertions
6. **Use the SgBashTest prefix** for all test object names so they can be
   identified and cleaned up:
   ```bash
   TestAssetName="${TestPrefix}_MyAsset"
   ```
7. **Register cleanup immediately** after creating each object:
   ```bash
   sg_register_cleanup "Delete test asset" \
       "$ScriptDir/../src/invoke-safeguard-method.sh -s core -m DELETE -U Assets/$asset_id"
   ```

### Test Baseline

The current baseline when all suites pass:

```
Suites: N (0 failed)
Tests:  N passed, 0 failed, 0 skipped
```

Update this baseline as you add suites and tests.

---

## Script Conventions

### Script Template

Every script in `src/` follows this structure:

```bash
#!/bin/bash

print_usage()
{
    cat <<EOF
USAGE: script-name.sh [-h]
       script-name.sh [-a appliance] [-B cabundle] ...

  -h  Show help and exit
  -a  Network address of the appliance
  ...

EOF
    exit 0
}

ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Initialize ALL variables before getopts
Appliance=
CABundle=
CABundleArg=
Version=4

. "$ScriptDir/utils/loginfile.sh"

while getopts ":a:B:v:h" opt; do
    case $opt in
    a) Appliance=$OPTARG ;;
    B) CABundle=$OPTARG ;;
    v) Version=$OPTARG ;;
    h) print_usage ;;
    esac
done
```

**Key rules:**
- `print_usage()` is always defined first, uses a heredoc, exits 0
- `ScriptDir` is resolved via `${BASH_SOURCE[0]}` (not `$0`) — this is
  critical for scripts that may be sourced
- All variables are initialized before the `getopts` loop
- Utilities are sourced with `. "$ScriptDir/utils/loginfile.sh"`
- Leading `:` in getopts string suppresses built-in error messages
- `-h` always shows help

### Common Option Flags

These flags are consistent across most scripts:

| Flag | Meaning                              |
|------|--------------------------------------|
| `-h` | Show help                           |
| `-a` | Appliance network address           |
| `-B` | CA bundle for SSL validation        |
| `-v` | API version (default: 4)            |
| `-i` | Identity provider                   |
| `-u` | Username                            |
| `-c` | Client certificate file             |
| `-k` | Client private key file             |
| `-t` | Access token                        |
| `-p` | Read password from stdin            |

### Error Handling

```bash
# Write errors to stderr
>&2 echo "Error message"

# Check curl exit codes
if [ $? -ne 0 ]; then
    exit 1
fi

# Detect JSON error responses via jq
Error=$(echo $Result | jq .Code 2> /dev/null)
if [ -z "$Error" -o "$Error" = "null" ]; then
    echo $Result    # Success — no error code
else
    echo $Result | jq .
    exit 1
fi

# Check for required tools at script start
if [ -z "$(which jq 2> /dev/null)" ]; then
    >&2 echo "This script requires jq"
    exit 1
fi
```

### Login File Pattern

Scripts share authentication state through `$HOME/.safeguard_login`, a
key=value file created with `umask 0077` (readable only by owner).

The file stores: `Appliance`, `Provider`, `AccessToken`, `CABundleArg`, and
optionally `Cert`/`PKey` for certificate auth.

Most scripts call `use_login_file()` from `utils/loginfile.sh`, which
auto-invokes `connect-safeguard.sh` if no login file exists.

**Lifecycle:**
1. `connect-safeguard.sh` creates the login file
2. Other scripts read it via `use_login_file()`
3. `disconnect-safeguard.sh` invalidates the token and removes the file

### Sourcing Shared Utilities

Always source relative to `ScriptDir`:

```bash
. "$ScriptDir/utils/loginfile.sh"
. "$ScriptDir/utils/common.sh"
. "$ScriptDir/utils/a2a.sh"
```

---

## Safeguard API Patterns

### API Services

Safeguard hosts multiple services:

| Service      | Description                                    |
|-------------|------------------------------------------------|
| `core`       | Main application API (users, assets, policies) |
| `appliance`  | Appliance operations (status, clustering)      |
| `notification` | SignalR event connections                    |
| `a2a`        | Application-to-application credential retrieval|

### API Versioning

The default API version is **v4** (since safeguard-bash 7.0). Pass `-v 3` to
use the v3 API. Both v3 and v4 are hosted simultaneously on Safeguard 7.x
appliances.

### Authentication Methods

1. **Password (Resource Owner Grant)** — username + password to a local or
   directory identity provider
2. **Certificate** — client certificate + private key, provider set to
   `certificate`
3. **PKCE** — browser-based OAuth2 flow (not supported in bash scripts)

For scripting and testing, password authentication with a local admin account
is the standard approach.

### SSL/TLS

By default, safeguard-bash disables SSL verification (`-k` flag to curl).
To validate SSL, pass `-B /path/to/ca-bundle.pem` to scripts.

### Common API Endpoints

```bash
# Get current user info
invoke-safeguard-method.sh -s core -m GET -U "Me"

# Get appliance status (anonymous)
get-appliance-status.sh -a <appliance>

# List assets
invoke-safeguard-method.sh -s core -m GET -U "Assets"

# Create a user
invoke-safeguard-method.sh -s core -m POST -U "Users" \
    -b '{"UserName":"TestUser","PrimaryAuthenticationProvider":{"Id":-1}}'

# Delete a user
invoke-safeguard-method.sh -s core -m DELETE -U "Users/<id>"
```

### User Object Field Names

The v4 API uses `Name` (not `UserName`) for the user's login name. Other key
fields: `DisplayName`, `Id`, `PrimaryAuthenticationProvider`. Always inspect
the actual API response with `jq keys` if unsure about field names.

### Local Provider Usernames

Local provider usernames are **case-insensitive**. The API may return a
different casing than what was provided at login (e.g. you pass `admin` but
`GET Me` returns `Admin`). Always normalize case before comparing usernames
in tests or scripts.

### Built-in Admin Account

The built-in `Admin` account has **Authorizer** and **UserAdmin** roles but
does **not** have **AssetAdmin** or **PolicyAdmin**. These roles cannot be
added to the built-in Admin account (Safeguard returns error 50100).

For tests that need full admin rights, create a temporary user with all roles
and use that for the test run.

### POST-then-PUT Pattern

Some Safeguard API endpoints do not accept all properties during POST (create).
You must create first, then PUT (update) additional properties:

```bash
# Create with minimal properties
Result=$(invoke-safeguard-method.sh -s core -m POST -U "Endpoint" -b "$CreateBody")
Id=$(echo $Result | jq -r '.Id')

# Update with full properties
invoke-safeguard-method.sh -s core -m PUT -U "Endpoint/$Id" -b "$FullBody"
```

### SCIM-style Filtering

Many GET endpoints support server-side filtering via query parameters:

```bash
# Filter platforms by family
invoke-safeguard-method.sh -s core -m GET \
    -U "Platforms?filter=PlatformFamily%20eq%20'Custom'"
```

---

## Dependencies

Scripts require: `bash`, `curl`, `jq` (optional but strongly recommended),
`openssl`, `sed`, `grep`.

The Docker image (Alpine-based) bundles all of these. For local development,
install `jq` separately — it is not installed by default on most systems but
significantly improves the user experience with JSON output.

---

## CI/CD

Azure DevOps Pipelines (`build.yml` + `pipeline-templates/`):

- **PR validation**: builds Docker image
- **Merge to master/release-***: builds, creates GitHub release, pushes to
  Docker Hub

---

## Security Notes

- Never commit secrets, tokens, or credentials
- The login file (`$HOME/.safeguard_login`) contains access tokens — don't
  log or serialize it
- Test credentials are passed only as command-line arguments to the test
  runner, never hardcoded in suites
- `-k` (disable SSL verification) is used by default for development — do not
  recommend for production without explanation
